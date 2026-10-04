--[[
  Azeroth Chronicle — journey capture addon (WoW: Forever)

  Responsibilities: OBSERVE, NORMALIZE, STORE. Nothing else.
  Persistence is only via the account-level SavedVariable AzerothChronicleDB,
  flushed by the client on /reload, logout, or clean exit.

  See .kiro/specs/journey-capture/ for requirements, design, and tasks.

  Interface 16001 confirmed by in-game GetBuildInfo on 2026-10-02:
  WoW: Forever 1.60.1, build 70170. Live capture proof remains task 12.
  Some API calls below are guarded/fallback because availability varies by
  client build; never assume an API exists — verify against the live client.
]]--

local SCHEMA_VERSION = 1

-- ---------------------------------------------------------------------------
-- 1. DB bootstrap (R6, R8) — idempotent
-- ---------------------------------------------------------------------------
local function EnsureDB()
  if AzerothChronicleDB == nil then
    AzerothChronicleDB = { schemaVersion = SCHEMA_VERSION, characters = {} }
  end
  -- Preserve unknown/malformed history verbatim; do not silently repair it.
  if type(AzerothChronicleDB) ~= "table"
      or AzerothChronicleDB.schemaVersion ~= SCHEMA_VERSION
      or type(AzerothChronicleDB.characters) ~= "table" then
    return nil
  end
  return AzerothChronicleDB
end

-- ---------------------------------------------------------------------------
-- 2. Identity (R1) — guarded reads
-- ---------------------------------------------------------------------------
local function GetIdentity()
  local guid  = UnitGUID and UnitGUID("player") or nil
  local name  = UnitName and UnitName("player") or "Unknown"
  local realm = GetRealmName and GetRealmName() or "Unknown"
  local race  = UnitRace and select(1, UnitRace("player")) or nil
  local class = UnitClass and select(1, UnitClass("player")) or nil
  local level = UnitLevel and UnitLevel("player") or nil
  -- Wait for a real GUID; a name-based fallback would split one history.
  if type(guid) ~= "string" or guid == "" then return nil end
  return guid, name, realm, race, class, level
end

local function GetOrCreateCharacter(db, guid, name, realm, race, class, level)
  local rec = db.characters[guid]
  if rec == nil then
    rec = { name = name, realm = realm, race = race, class = class,
            level = level, events = {} }
    db.characters[guid] = rec
  else
    if type(rec) ~= "table" or type(rec.events) ~= "table" then return nil end
    -- Update mutable metadata without destroying events (R1.3).
    rec.name, rec.realm, rec.race, rec.class = name, realm, race, class
    if level then rec.level = level end
  end
  return rec
end

-- ---------------------------------------------------------------------------
-- 3. Normalizer (R5, R2)
-- ---------------------------------------------------------------------------
local function MakeEventId(guid, etype, key, ts)
  return table.concat({ guid, etype, tostring(key or "?"), tostring(ts) }, ":")
end

-- Read the current meaningful location. Coordinates are NOT captured (R4.2).
local function GetLocation()
  local zone    = GetZoneText and GetZoneText() or nil
  local subzone = GetSubZoneText and GetSubZoneText() or nil
  local mapId   = (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")) or nil
  if subzone == "" then subzone = nil end
  if zone == "" then zone = nil end
  return zone, subzone, mapId
end

-- ---------------------------------------------------------------------------
-- 4. Store with dedup (R5.2)
-- ---------------------------------------------------------------------------
local function HasEvent(charRec, id)
  for i = 1, #charRec.events do
    if charRec.events[i].id == id then return true end
  end
  return false
end

local function AppendEvent(charRec, event)
  if not event or not event.id then return false end
  if HasEvent(charRec, event.id) then return false end
  charRec.events[#charRec.events + 1] = event
  return true
end

-- ---------------------------------------------------------------------------
-- Runtime state (in-memory only; not persisted)
-- ---------------------------------------------------------------------------
local state = {
  guid = nil,
  char = nil,          -- current character record
  lastZone = nil,
  lastSubzone = nil,
  questOffer = nil,    -- one bounded dialog snapshot, keyed by quest ID
  pendingQuests = {},  -- questId -> acceptance snapshot awaiting metadata
  acceptedQuests = {}, -- repeated notifications within this addon load
  completedQuests = {}, -- reset only by a new acceptance
  resolvingQuest = false, -- selection APIs can trigger nested notifications
}

local function CurrentChar()
  return state.char
end

-- Copy captured fields and allocate a stable ID once. Existing IDs are opaque
-- strings to importers; suffixes distinguish genuine same-second occurrences.
local function MakeEvent(etype, key, fields)
  local event = {}
  for name, value in pairs(fields) do event[name] = value end
  event.type = etype
  event.timestamp = event.timestamp or time()
  local base = MakeEventId(state.guid, etype, key, event.timestamp)
  event.id = base
  local suffix = 2
  while HasEvent(state.char, event.id) do
    event.id = base .. ":" .. suffix
    suffix = suffix + 1
  end
  return event
end

-- ---------------------------------------------------------------------------
-- Event capture
-- ---------------------------------------------------------------------------

-- session_started (R2.1)
local function CaptureSessionStarted()
  local rec = CurrentChar(); if not rec then return end
  local ev = MakeEvent("session_started", "session", {
    characterId = state.guid,
    level = rec.level,
  })
  AppendEvent(rec, ev)
end

-- location_changed (R2.4, R4) — meaningful transitions only
local function CaptureLocationIfChanged()
  local rec = CurrentChar(); if not rec then return end
  local zone, subzone, mapId = GetLocation()
  if not zone and not subzone then return end
  if zone == state.lastZone and subzone == state.lastSubzone then
    return -- no meaningful change (R4.2)
  end
  local ev = MakeEvent("location_changed", subzone or zone, {
    zone = zone, subzone = subzone, mapId = mapId,
  })
  if AppendEvent(rec, ev) then
    state.lastZone, state.lastSubzone = zone, subzone
  end
end

-- Classic UI contracts: GetQuestLogIndexByID, GetQuestLogTitle (ID at
-- return 8), and selected-entry GetQuestLogQuestText. Restore the user's
-- selection even when reading fails. Live Forever validation is still required.
local function ReadAPI(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
end

local function Text(value)
  if type(value) == "string" and value ~= "" then return value end
end

local function CaptureQuestOffer()
  state.questOffer = nil
  local id = ReadAPI(GetQuestID)
  if type(id) ~= "number" or id <= 0 or id >= math.huge
      or id ~= math.floor(id) then return end
  state.questOffer = {
    questId = id,
    title = Text(ReadAPI(GetTitleText)),
    description = Text(ReadAPI(GetQuestText)),
    objectivesText = Text(ReadAPI(GetObjectiveText)),
  }
end

local function TryResolveQuest(questId)
  local snap = { questId = questId }
  local offer = state.questOffer
  if offer and offer.questId == questId then
    snap.title = offer.title
    snap.description = offer.description
    snap.objectivesText = offer.objectivesText
    if snap.title and snap.description and snap.objectivesText then
      return snap, true
    end
  end
  local index = ReadAPI(GetQuestLogIndexByID, questId)
  if type(index) == "number" and index > 0
      and type(GetQuestLogTitle) == "function" then
    local ok, title, _, _, header, _, _, _, actualId = pcall(GetQuestLogTitle, index)
    if ok and not header and actualId == questId then
      snap.title = snap.title or Text(title)
      local selected = ReadAPI(GetQuestLogSelection)
      if type(selected) == "number" and type(SelectQuestLogEntry) == "function"
          and type(GetQuestLogQuestText) == "function" then
        state.resolvingQuest = true
        local selectedOK = pcall(SelectQuestLogEntry, index)
        if selectedOK and ReadAPI(GetQuestLogSelection) == index then
          local textOK, description, objectives = pcall(GetQuestLogQuestText)
          if textOK then
            snap.description = snap.description or Text(description)
            snap.objectivesText = snap.objectivesText or Text(objectives)
          end
        end
        pcall(SelectQuestLogEntry, selected)
        state.resolvingQuest = false
      end
    end
  end
  if not snap.title and type(C_QuestLog) == "table" then
    snap.title = Text(ReadAPI(C_QuestLog.GetQuestInfo, questId))
  end
  return snap, snap.title ~= nil and snap.description ~= nil
    and snap.objectivesText ~= nil
end

-- Preserve the occurrence context while metadata is pending. Never rewrite a
-- stored event; after one retry, missing optional metadata is accepted (R3.4).
local function PersistPendingQuest(questId, force)
  local pending = state.pendingQuests[questId]
  if not pending then return end
  local snap, complete = TryResolveQuest(questId)
  for _, field in ipairs({ "title", "description", "objectivesText" }) do
    if snap[field] ~= nil then pending[field] = snap[field] end
  end
  if complete or force then
    if AppendEvent(state.char, MakeEvent("quest_accepted", questId, pending)) then
      state.pendingQuests[questId] = nil
    end
  end
end

local function ValidQuestId(questId)
  return type(questId) == "number" and questId > 0
    and questId < math.huge and questId == math.floor(questId)
end

-- quest_accepted (R2.2, R3)
local function CaptureQuestAccepted(questId)
  if not CurrentChar() or not ValidQuestId(questId) then return end
  if state.acceptedQuests[questId] then return end
  state.acceptedQuests[questId] = true
  state.completedQuests[questId] = nil
  local zone, subzone, mapId = GetLocation()
  state.pendingQuests[questId] = {
    questId = questId, timestamp = time(),
    zone = zone, subzone = subzone, mapId = mapId,
  }
  PersistPendingQuest(questId, false)
  if state.questOffer and state.questOffer.questId == questId then
    state.questOffer = nil
  end
end

local function ResolvePendingQuests()
  if not CurrentChar() or state.resolvingQuest then return end
  for questId in pairs(state.pendingQuests) do
    PersistPendingQuest(questId, true)
  end
end

-- quest_completed (R2.3)
local function CaptureQuestCompleted(questId)
  local rec = CurrentChar(); if not rec or not ValidQuestId(questId) then return end
  if state.completedQuests[questId] then return end
  PersistPendingQuest(questId, true)
  local zone, subzone = GetLocation()
  local ev = MakeEvent("quest_completed", questId, {
    questId = questId, zone = zone, subzone = subzone,
  })
  if AppendEvent(rec, ev) then
    state.completedQuests[questId] = true
    state.acceptedQuests[questId] = nil
  end
end

-- ---------------------------------------------------------------------------
-- 5. Dispatch (R7)
-- ---------------------------------------------------------------------------
local function OnPlayerLogin()
  if state.char then return end
  local guid, name, realm, race, class, level = GetIdentity()
  if not guid then return end
  local db = EnsureDB()
  if not db then return end
  state.guid = guid
  state.char = GetOrCreateCharacter(db, guid, name, realm, race, class, level)
  if not state.char then return end
  -- Restore the last emitted location across reloads, ignoring session/quest rows.
  for i = #state.char.events, 1, -1 do
    local event = state.char.events[i]
    if type(event) == "table" and event.type == "location_changed" then
      state.lastZone, state.lastSubzone = event.zone, event.subzone
      break
    end
  end
  CaptureSessionStarted()
  CaptureLocationIfChanged()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("QUEST_ACCEPTED")
frame:RegisterEvent("QUEST_DETAIL")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("QUEST_TURNED_IN")
frame:RegisterEvent("QUEST_REMOVED")
frame:RegisterEvent("ZONE_CHANGED")
frame:RegisterEvent("ZONE_CHANGED_INDOORS")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

frame:SetScript("OnEvent", function(_, event, arg1, arg2)
  if event == "PLAYER_LOGIN" then
    OnPlayerLogin()
  elseif event == "PLAYER_ENTERING_WORLD" then
    if not state.char then OnPlayerLogin() end
    CaptureLocationIfChanged()
  elseif event == "QUEST_DETAIL" then
    CaptureQuestOffer()
  elseif event == "QUEST_ACCEPTED" then
    -- Signature varies by build: questLogIndex, questID may arrive as arg1/arg2.
    local questId = arg2 or arg1
    CaptureQuestAccepted(questId)
  elseif event == "QUEST_LOG_UPDATE" or event == "PLAYER_LOGOUT" then
    ResolvePendingQuests()
  elseif event == "QUEST_REMOVED" then
    if CurrentChar() and ValidQuestId(arg1) then
      PersistPendingQuest(arg1, true)
      state.acceptedQuests[arg1] = nil
    end
  elseif event == "QUEST_TURNED_IN" then
    local questId = arg1
    CaptureQuestCompleted(questId)
  elseif event == "ZONE_CHANGED"
      or event == "ZONE_CHANGED_INDOORS"
      or event == "ZONE_CHANGED_NEW_AREA" then
    CaptureLocationIfChanged()
  end
end)
