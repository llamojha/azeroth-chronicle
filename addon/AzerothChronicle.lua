--[[
  Azeroth Chronicle — journey capture addon (WoW: Forever)

  Responsibilities: OBSERVE, NORMALIZE, STORE. Nothing else.
  Persistence is only via the account-level SavedVariable AzerothChronicleDB,
  flushed by the client on /reload, logout, or clean exit.

  See .kiro/specs/journey-capture/ for requirements, design, and tasks.

  NOTE: `## Interface:` in the .toc is a PLACEHOLDER — confirm the exact
  WoW: Forever build interface number before loading (see tasks.md #12).
  Some API calls below are guarded/fallback because availability varies by
  client build; never assume an API exists — verify against the live client.
]]--

local ADDON_NAME = ...
local SCHEMA_VERSION = 1

-- ---------------------------------------------------------------------------
-- 1. DB bootstrap (R6, R8) — idempotent
-- ---------------------------------------------------------------------------
local function EnsureDB()
  if type(AzerothChronicleDB) ~= "table" then
    AzerothChronicleDB = {}
  end
  AzerothChronicleDB.schemaVersion = AzerothChronicleDB.schemaVersion or SCHEMA_VERSION
  if type(AzerothChronicleDB.characters) ~= "table" then
    AzerothChronicleDB.characters = {}
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
  -- Fallback id if GUID is unavailable on this client build.
  guid = guid or (name .. "-" .. realm)
  return guid, name, realm, race, class, level
end

local function GetOrCreateCharacter(db, guid, name, realm, race, class, level)
  local rec = db.characters[guid]
  if type(rec) ~= "table" then
    rec = { name = name, realm = realm, race = race, class = class,
            level = level, events = {} }
    db.characters[guid] = rec
  else
    -- Update mutable metadata without destroying events (R1.3).
    rec.name, rec.realm, rec.race, rec.class = name, realm, race, class
    if level then rec.level = level end
    if type(rec.events) ~= "table" then rec.events = {} end
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
  pendingQuests = {},  -- questId -> true (awaiting metadata resolution)
}

local function CurrentChar()
  return state.char
end

-- ---------------------------------------------------------------------------
-- Event capture
-- ---------------------------------------------------------------------------

-- session_started (R2.1)
local function CaptureSessionStarted()
  local rec = CurrentChar(); if not rec then return end
  local ts = time()
  local ev = {
    id = MakeEventId(state.guid, "session_started", "session", ts),
    type = "session_started",
    timestamp = ts,
    level = rec.level,
  }
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
  state.lastZone, state.lastSubzone = zone, subzone
  local ts = time()
  local ev = {
    id = MakeEventId(state.guid, "location_changed", subzone or zone, ts),
    type = "location_changed",
    timestamp = ts,
    zone = zone, subzone = subzone, mapId = mapId,
  }
  AppendEvent(rec, ev)
end

-- Resolve a quest snapshot with guarded reads. Any field may be nil (R3.4).
-- TODO(wow-addon-developer): flesh out against the live client's quest APIs.
-- The exact API set differs by build (classic GetQuestLogTitle vs C_QuestLog);
-- verify before finalizing. Returns (snapshot, complete).
local function TryResolveQuest(questId)
  local snap = { questId = questId }
  -- Placeholder guarded resolution — replace with verified APIs (tasks.md #9).
  -- Example shape only:
  --   snap.title           = <verified title API>
  --   snap.description      = <verified description API>
  --   snap.objectivesText   = <verified objectives API>
  local complete = snap.title ~= nil
  return snap, complete
end

-- quest_accepted (R2.2, R3)
local function CaptureQuestAccepted(questId)
  local rec = CurrentChar(); if not rec or not questId then return end
  local snap, complete = TryResolveQuest(questId)
  if complete then
    local zone, subzone, mapId = GetLocation()
    local ts = time()
    local ev = {
      id = MakeEventId(state.guid, "quest_accepted", questId, ts),
      type = "quest_accepted",
      timestamp = ts,
      questId = questId,
      title = snap.title,
      description = snap.description,
      objectivesText = snap.objectivesText,
      zone = zone, subzone = subzone, mapId = mapId,
    }
    AppendEvent(rec, ev)
  else
    state.pendingQuests[questId] = true -- resolve on QUEST_LOG_UPDATE (R3.2)
  end
end

local function ResolvePendingQuests()
  local rec = CurrentChar(); if not rec then return end
  for questId in pairs(state.pendingQuests) do
    local snap, complete = TryResolveQuest(questId)
    if complete then
      local zone, subzone, mapId = GetLocation()
      local ts = time()
      local ev = {
        id = MakeEventId(state.guid, "quest_accepted", questId, ts),
        type = "quest_accepted",
        timestamp = ts,
        questId = questId,
        title = snap.title,
        description = snap.description,
        objectivesText = snap.objectivesText,
        zone = zone, subzone = subzone, mapId = mapId,
      }
      AppendEvent(rec, ev)
      state.pendingQuests[questId] = nil
    end
  end
end

-- quest_completed (R2.3)
local function CaptureQuestCompleted(questId)
  local rec = CurrentChar(); if not rec or not questId then return end
  local zone, subzone = GetLocation()
  local ts = time()
  local ev = {
    id = MakeEventId(state.guid, "quest_completed", questId, ts),
    type = "quest_completed",
    timestamp = ts,
    questId = questId,
    zone = zone, subzone = subzone,
  }
  AppendEvent(rec, ev)
end

-- ---------------------------------------------------------------------------
-- 5. Dispatch (R7)
-- ---------------------------------------------------------------------------
local function OnPlayerLogin()
  local db = EnsureDB()
  local guid, name, realm, race, class, level = GetIdentity()
  state.guid = guid
  state.char = GetOrCreateCharacter(db, guid, name, realm, race, class, level)
  CaptureSessionStarted()
  CaptureLocationIfChanged()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("QUEST_ACCEPTED")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:RegisterEvent("QUEST_TURNED_IN")
frame:RegisterEvent("ZONE_CHANGED")
frame:RegisterEvent("ZONE_CHANGED_INDOORS")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

frame:SetScript("OnEvent", function(_, event, arg1, arg2)
  if event == "PLAYER_LOGIN" then
    OnPlayerLogin()
  elseif event == "PLAYER_ENTERING_WORLD" then
    if not state.char then OnPlayerLogin() end
    CaptureLocationIfChanged()
  elseif event == "QUEST_ACCEPTED" then
    -- Signature varies by build: questLogIndex, questID may arrive as arg1/arg2.
    local questId = arg2 or arg1
    CaptureQuestAccepted(questId)
  elseif event == "QUEST_LOG_UPDATE" then
    ResolvePendingQuests()
  elseif event == "QUEST_TURNED_IN" then
    local questId = arg1
    CaptureQuestCompleted(questId)
  elseif event == "ZONE_CHANGED"
      or event == "ZONE_CHANGED_INDOORS"
      or event == "ZONE_CHANGED_NEW_AREA" then
    CaptureLocationIfChanged()
  end
end)
