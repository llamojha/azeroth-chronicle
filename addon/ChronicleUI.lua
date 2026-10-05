--[[
  Azeroth Chronicle — in-game journal (read-only viewer)

  Shows the current character's captured journey in a tabbed window:
  Overview, Places, Quests, Timeline. Open/close with /chronicle.

  Boundary (see .kiro/steering/architecture.md):
  - This file NEVER writes AzerothChronicleDB. AzerothChronicle.lua stays the
    only writer. The model copies captured values into fresh tables and the
    frames only display those copies.
  - It groups, counts and sorts captured facts; it does not interpret them.
    No AI and no recap — Story So Far lives in the companion.
  - Frames are created lazily on first open, so loading costs nothing.
]]--

local _, ns = ...
ns = type(ns) == "table" and ns or {}

local SCHEMA_VERSION = 1
local RECENT_LIMIT = 8
local TIMELINE_LIMIT = 200

local GOLD, WHITE, GREY, GREEN = "|cffffd100", "|cffffffff", "|cff9d9d9d", "|cff40c040"

-- ---------------------------------------------------------------------------
-- 1. Journal model — pure functions, no frame API
-- ---------------------------------------------------------------------------
local Model = {}
ns.JournalModel = Model

local function Str(v) if type(v) == "string" and v ~= "" then return v end end
local function Num(v) if type(v) == "number" and v == v then return v end end
local function C(color, s) return color .. s .. "|r" end

local formatDate = (type(date) == "function" and date) or (os and os.date)

function Model.FormatTime(ts)
  if not Num(ts) or ts <= 0 or not formatDate then return "unknown time" end
  local ok, s = pcall(formatDate, "%Y-%m-%d %H:%M", ts)
  return ok and s or "unknown time"
end

local function PlaceName(zone, subzone)
  if subzone and zone and subzone ~= zone then return subzone .. ", " .. zone end
  return subzone or zone or "somewhere unknown"
end

local function QuestLabel(id)
  return "Quest #" .. tostring(math.floor(id))
end

-- Returns the character record for guid, or nil when the DB is missing,
-- of another schema version, or malformed. Never repairs anything.
function Model.CurrentCharacter(db, guid)
  if type(db) ~= "table" or db.schemaVersion ~= SCHEMA_VERSION then return nil end
  if type(db.characters) ~= "table" or type(guid) ~= "string" then return nil end
  local rec = db.characters[guid]
  if type(rec) ~= "table" or type(rec.events) ~= "table" then return nil end
  return rec
end

-- Chronological order; ties keep capture order.
local function SortedEvents(rec)
  local list = {}
  for i, ev in ipairs(rec.events) do
    if type(ev) == "table" and Str(ev.type) then
      list[#list + 1] = { ev = ev, i = i, ts = Num(ev.timestamp) or 0 }
    end
  end
  table.sort(list, function(a, b)
    if a.ts ~= b.ts then return a.ts < b.ts end
    return a.i < b.i
  end)
  return list
end

local function EventText(ev, quests)
  local t = ev.type
  if t == "session_started" then
    local level = Num(ev.level)
    return level and ("Started playing at level " .. level) or "Started playing"
  elseif t == "location_changed" then
    local zone, subzone = Str(ev.zone), Str(ev.subzone)
    if not zone and not subzone then return nil end
    return "Arrived in " .. PlaceName(zone, subzone)
  elseif t == "quest_accepted" or t == "quest_completed" then
    local id = Num(ev.questId)
    if not id then return nil end
    local q = quests[id]
    local title = (q and q.title) or Str(ev.title) or QuestLabel(id)
    return (t == "quest_accepted" and "Took on " or "Completed ") .. title
  end
end

-- Builds a read-only view model from one character record.
function Model.Build(rec)
  local m = {
    character = {
      name = Str(rec.name) or "Unknown", realm = Str(rec.realm),
      race = Str(rec.race), class = Str(rec.class), level = Num(rec.level),
    },
  }
  local quests, questOrder = {}, {}
  local zones, zoneOrder = {}, {}
  local sessions, startLevel = 0, nil
  local events = SortedEvents(rec)

  local function Quest(id)
    local q = quests[id]
    if not q then
      q = { questId = id, status = "in_progress", order = #questOrder + 1 }
      quests[id] = q
      questOrder[#questOrder + 1] = q
    end
    return q
  end

  local function Zone(name)
    local z = zones[name]
    if not z then
      z = { name = name, visits = 0, subzones = {}, quests = {},
            subzoneIndex = {}, order = #zoneOrder + 1 }
      zones[name] = z
      zoneOrder[#zoneOrder + 1] = z
    end
    return z
  end

  for _, item in ipairs(events) do
    local ev, ts, t = item.ev, item.ts, item.ev.type
    if t == "session_started" then
      sessions = sessions + 1
      startLevel = startLevel or Num(ev.level)
    elseif t == "location_changed" and Str(ev.zone) then
      local z = Zone(ev.zone)
      z.visits = z.visits + 1
      z.firstVisited = z.firstVisited or ts
      z.lastVisited = ts
      local sub = Str(ev.subzone)
      if sub and sub ~= ev.zone then
        local s = z.subzoneIndex[sub]
        if not s then
          s = { name = sub, visits = 0, firstVisited = ts }
          z.subzoneIndex[sub] = s
          z.subzones[#z.subzones + 1] = s
        end
        s.visits = s.visits + 1
      end
    elseif (t == "quest_accepted" or t == "quest_completed") and Num(ev.questId) then
      local q = Quest(ev.questId)
      q.title = Str(ev.title) or q.title
      q.description = Str(ev.description) or q.description
      q.objectivesText = Str(ev.objectivesText) or q.objectivesText
      if not q.zone then q.zone, q.subzone = Str(ev.zone), Str(ev.subzone) end
      q.lastActivity = ts
      if t == "quest_accepted" then
        q.status, q.acceptedAt, q.completedAt = "in_progress", ts, nil
        if ev.zone then q.zone, q.subzone = Str(ev.zone), Str(ev.subzone) end
      else
        q.status, q.completedAt, q.everCompleted = "completed", ts, true
      end
    end
  end

  -- Quests
  local completed, inProgress = 0, 0
  for _, q in ipairs(questOrder) do
    q.title = q.title or QuestLabel(q.questId)
    if q.everCompleted then completed = completed + 1 end
    if q.status == "in_progress" then inProgress = inProgress + 1 end
    if q.zone then
      local z = Zone(q.zone)
      z.quests[#z.quests + 1] = q
    end
  end
  table.sort(questOrder, function(a, b)
    if a.status ~= b.status then return a.status == "in_progress" end
    if (a.lastActivity or 0) ~= (b.lastActivity or 0) then
      return (a.lastActivity or 0) > (b.lastActivity or 0)
    end
    return a.order < b.order
  end)
  m.quests = questOrder

  -- Places, in the order the character first reached them
  local zonesExplored, areasExplored = 0, 0
  for _, z in ipairs(zoneOrder) do
    if z.visits > 0 then zonesExplored = zonesExplored + 1 end
    areasExplored = areasExplored + #z.subzones
    z.subzoneIndex = nil
  end
  table.sort(zoneOrder, function(a, b)
    local fa, fb = a.firstVisited or math.huge, b.firstVisited or math.huge
    if fa ~= fb then return fa < fb end
    return a.order < b.order
  end)
  m.places = zoneOrder

  -- Timeline, newest first
  local timeline = {}
  for i = #events, 1, -1 do
    local text = EventText(events[i].ev, quests)
    if text then
      timeline[#timeline + 1] = { timestamp = events[i].ts, kind = events[i].ev.type, text = text }
    end
  end
  m.timeline = timeline

  local recent = {}
  for i = 1, math.min(RECENT_LIMIT, #timeline) do recent[i] = timeline[i] end
  m.overview = {
    sessions = sessions,
    questsCompleted = completed,
    questsInProgress = inProgress,
    zonesExplored = zonesExplored,
    areasExplored = areasExplored,
    startLevel = startLevel,
    firstEntry = events[1] and events[1].ts or nil,
    lastEntry = events[#events] and events[#events].ts or nil,
    recent = recent,
  }
  return m
end

-- Display text -------------------------------------------------------------

Model.EMPTY_TEXT = "Your chronicle is empty so far.\n\n"
  .. "Go explore — the places you visit and the quests you take on will appear here."

local function Join(lines) return table.concat(lines, "\n") end

local function TimelineLine(entry)
  return C(GREY, Model.FormatTime(entry.timestamp)) .. "   " .. entry.text
end

function Model.OverviewText(m)
  if not m then return Model.EMPTY_TEXT end
  local c, o = m.character, m.overview
  local who = {}
  if c.level then who[#who + 1] = "Level " .. c.level end
  if c.race then who[#who + 1] = c.race end
  if c.class then who[#who + 1] = c.class end
  local lines = { C(GOLD, c.name) }
  local sub = table.concat(who, " ")
  if c.realm then sub = (sub ~= "" and (sub .. " — ") or "") .. c.realm end
  if sub ~= "" then lines[#lines + 1] = sub end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Play sessions: " .. C(WHITE, o.sessions)
  lines[#lines + 1] = "Quests completed: " .. C(WHITE, o.questsCompleted)
  lines[#lines + 1] = "Quests in progress: " .. C(WHITE, o.questsInProgress)
  lines[#lines + 1] = "Zones explored: " .. C(WHITE, o.zonesExplored)
    .. "   Areas explored: " .. C(WHITE, o.areasExplored)
  if o.startLevel and c.level and c.level > o.startLevel then
    lines[#lines + 1] = "Grew from level " .. o.startLevel .. " to " .. c.level
  end
  if o.firstEntry then
    lines[#lines + 1] = "Chronicle began: " .. Model.FormatTime(o.firstEntry)
    lines[#lines + 1] = "Latest entry: " .. Model.FormatTime(o.lastEntry)
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = C(GOLD, "Recent moments")
  if #o.recent == 0 then lines[#lines + 1] = C(GREY, "Nothing recorded yet.") end
  for _, entry in ipairs(o.recent) do lines[#lines + 1] = TimelineLine(entry) end
  return Join(lines)
end

function Model.PlaceText(place)
  if not place then return C(GREY, "No places recorded yet.") end
  local lines = { C(GOLD, place.name) }
  if place.firstVisited then
    lines[#lines + 1] = "First visited " .. Model.FormatTime(place.firstVisited)
    lines[#lines + 1] = "Last visited " .. Model.FormatTime(place.lastVisited)
      .. "  ·  " .. place.visits .. (place.visits == 1 and " visit" or " visits")
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = C(GOLD, "Areas explored")
  if #place.subzones == 0 then lines[#lines + 1] = C(GREY, "None recorded.") end
  for _, s in ipairs(place.subzones) do
    lines[#lines + 1] = "  " .. s.name .. C(GREY, "  — first " .. Model.FormatTime(s.firstVisited))
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = C(GOLD, "Quests here")
  if #place.quests == 0 then lines[#lines + 1] = C(GREY, "None recorded.") end
  for _, q in ipairs(place.quests) do
    local status = q.status == "completed" and C(GREEN, "Completed") or C(GOLD, "In progress")
    lines[#lines + 1] = "  " .. q.title .. "  " .. status
  end
  return Join(lines)
end

function Model.QuestText(q)
  if not q then return C(GREY, "No quests recorded yet.") end
  local lines = { C(GOLD, q.title) }
  lines[#lines + 1] = q.status == "completed" and C(GREEN, "Completed") or C(GOLD, "In progress")
  if q.zone then lines[#lines + 1] = "Where: " .. PlaceName(q.zone, q.subzone) end
  if q.acceptedAt then lines[#lines + 1] = "Taken on: " .. Model.FormatTime(q.acceptedAt) end
  if q.completedAt then lines[#lines + 1] = "Completed: " .. Model.FormatTime(q.completedAt) end
  if q.objectivesText then
    lines[#lines + 1] = ""
    lines[#lines + 1] = C(GOLD, "Objectives")
    lines[#lines + 1] = q.objectivesText
  end
  if q.description then
    lines[#lines + 1] = ""
    lines[#lines + 1] = C(GOLD, "Description")
    lines[#lines + 1] = q.description
  end
  if not q.objectivesText and not q.description then
    lines[#lines + 1] = ""
    lines[#lines + 1] = C(GREY, "No quest text was recorded for this quest.")
  end
  return Join(lines)
end

function Model.TimelineText(m)
  if not m or #m.timeline == 0 then return Model.EMPTY_TEXT end
  local lines = {}
  for i = 1, math.min(TIMELINE_LIMIT, #m.timeline) do
    lines[i] = TimelineLine(m.timeline[i])
  end
  if #m.timeline > TIMELINE_LIMIT then
    lines[#lines + 1] = ""
    lines[#lines + 1] = C(GREY, "… and " .. (#m.timeline - TIMELINE_LIMIT) .. " earlier moments")
  end
  return Join(lines)
end

-- List rows for the left-hand panes.
function Model.PlaceItems(m)
  local items = {}
  for _, p in ipairs(m and m.places or {}) do
    local count = #p.quests > 0 and C(GREY, "  (" .. #p.quests .. ")") or ""
    items[#items + 1] = { label = p.name .. count, place = p }
  end
  return items
end

function Model.QuestItems(m)
  local items, active, done = {}, {}, {}
  for _, q in ipairs(m and m.quests or {}) do
    if q.status == "in_progress" then active[#active + 1] = q else done[#done + 1] = q end
  end
  if #active > 0 then
    items[#items + 1] = { label = C(GOLD, "In progress (" .. #active .. ")"), header = true }
    for _, q in ipairs(active) do items[#items + 1] = { label = q.title, quest = q } end
  end
  if #done > 0 then
    items[#items + 1] = { label = C(GOLD, "Completed (" .. #done .. ")"), header = true }
    for _, q in ipairs(done) do items[#items + 1] = { label = C(GREY, q.title), quest = q } end
  end
  return items
end

-- ---------------------------------------------------------------------------
-- 2. Window — WoW frame API, built on first open
-- ---------------------------------------------------------------------------
local UI = {}
ns.JournalUI = UI

local W, H = 680, 460
local PAD_X, TOP, BOTTOM = 14, 30, 40
local CONTENT_W, CONTENT_H = W - 2 * PAD_X, H - TOP - BOTTOM
local BAR = 26 -- room for the template scroll bar
local LIST_W = 210
local ROW_H = 18
local TABS = { "Overview", "Places", "Quests", "Timeline" }
local scrollCount = 0

-- Templates vary by client build: fall back to a plain frame if one is missing.
local function TryCreate(kind, name, parent, template)
  local ok, f = pcall(CreateFrame, kind, name, parent, template)
  if ok and f then return f, true end
  return CreateFrame(kind, name, parent), false
end

local function Fill(tex, r, g, b, a)
  if tex.SetColorTexture then tex:SetColorTexture(r, g, b, a) else tex:SetTexture(r, g, b, a) end
end

local function CreateScroll(parent, x, width)
  scrollCount = scrollCount + 1
  local scroll, templated = TryCreate("ScrollFrame", "AzerothChronicleScroll" .. scrollCount,
    parent, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", x, 0)
  scroll:SetSize(width, CONTENT_H)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(width, 1)
  scroll:SetScrollChild(child)
  if not templated then
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
      local max = self:GetVerticalScrollRange() or 0
      local v = (self:GetVerticalScroll() or 0) - delta * 40
      if v < 0 then v = 0 elseif v > max then v = max end
      self:SetVerticalScroll(v)
    end)
  end
  return scroll, child
end

local function CreateTextPanel(parent, x, width)
  local scroll, child = CreateScroll(parent, x, width)
  local text = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -4)
  text:SetWidth(width - 8)
  text:SetJustifyH("LEFT")
  text:SetJustifyV("TOP")
  local panel = {}
  function panel.SetText(s)
    text:SetText(s)
    child:SetHeight(math.max(1, (text:GetStringHeight() or 0) + 8))
    if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
    scroll:SetVerticalScroll(0)
  end
  return panel
end

local function CreateList(parent, onSelect)
  local _, child = CreateScroll(parent, 0, LIST_W)
  local list = { buttons = {}, items = {} }

  local function Row(i)
    local b = list.buttons[i]
    if b then return b end
    b = CreateFrame("Button", nil, child)
    b:SetSize(LIST_W, ROW_H)
    b:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * ROW_H)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("LEFT", b, "LEFT", 4, 0)
    b.label:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    b.label:SetJustifyH("LEFT")
    b.selected = b:CreateTexture(nil, "BACKGROUND")
    b.selected:SetAllPoints(b)
    Fill(b.selected, 1, 0.82, 0, 0.18)
    b.selected:Hide()
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b:SetScript("OnClick", function(self) list.Select(self.index) end)
    list.buttons[i] = b
    return b
  end

  function list.Select(index)
    local item = index and list.items[index]
    if item and item.header then return end
    for j, b in ipairs(list.buttons) do
      if j == index then b.selected:Show() else b.selected:Hide() end
    end
    onSelect(item)
  end

  function list.SetItems(items)
    list.items = items
    local first
    for i, item in ipairs(items) do
      local b = Row(i)
      b.index = i
      b.label:SetText(item.label)
      if item.header then b:Disable() else b:Enable() end
      b:Show()
      if not first and not item.header then first = i end
    end
    for i = #items + 1, #list.buttons do list.buttons[i]:Hide() end
    child:SetHeight(math.max(1, #items * ROW_H))
    list.Select(first)
  end
  return list
end

local function CreateSplitPanel(parent, describe)
  local detail = CreateTextPanel(parent, LIST_W + BAR + 6, CONTENT_W - LIST_W - 2 * BAR - 6)
  local list = CreateList(parent, function(item) detail.SetText(describe(item)) end)
  return list
end

function UI.Build()
  local f, templated = TryCreate("Frame", "AzerothChronicleJournalFrame", UIParent,
    "BasicFrameTemplateWithInset")
  f:SetSize(W, H)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  f:Hide()
  if not templated then
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    Fill(bg, 0, 0, 0, 0.85)
    local close = TryCreate("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() f:Hide() end)
  end
  -- Escape closes the window like other game panels.
  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "AzerothChronicleJournalFrame")
  end

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOP", f, "TOP", 0, -6)
  UI.title = title

  local content = CreateFrame("Frame", nil, f)
  content:SetPoint("TOPLEFT", f, "TOPLEFT", PAD_X, -TOP)
  content:SetSize(CONTENT_W, CONTENT_H)

  UI.panels, UI.tabs = {}, {}
  for i, name in ipairs(TABS) do
    local panel = CreateFrame("Frame", nil, content)
    panel:SetAllPoints(content)
    panel:Hide()
    UI.panels[i] = panel

    local tab, tabTemplated = TryCreate("Button", "AzerothChronicleTab" .. i, f, "UIPanelButtonTemplate")
    tab:SetSize(100, 22)
    tab:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD_X + (i - 1) * 104, 10)
    if not tabTemplated and GameFontNormal then tab:SetNormalFontObject(GameFontNormal) end
    tab:SetText(name)
    tab:SetScript("OnClick", function() UI.SelectTab(i) end)
    UI.tabs[i] = tab
  end

  UI.overview = CreateTextPanel(UI.panels[1], 0, CONTENT_W - BAR)
  UI.places = CreateSplitPanel(UI.panels[2], function(item) return Model.PlaceText(item and item.place) end)
  UI.quests = CreateSplitPanel(UI.panels[3], function(item) return Model.QuestText(item and item.quest) end)
  UI.timeline = CreateTextPanel(UI.panels[4], 0, CONTENT_W - BAR)

  UI.frame = f
  return f
end

function UI.SelectTab(index)
  UI.tab = index
  for i, panel in ipairs(UI.panels) do
    if i == index then panel:Show(); UI.tabs[i]:LockHighlight()
    else panel:Hide(); UI.tabs[i]:UnlockHighlight() end
  end
end

-- Re-reads the captured history. Called on every open, so the window always
-- reflects what has been recorded so far this session.
function UI.Refresh()
  local guid = UnitGUID and UnitGUID("player") or nil
  local rec = Model.CurrentCharacter(AzerothChronicleDB, guid)
  local m = rec and Model.Build(rec) or nil
  UI.model = m
  UI.title:SetText(m and (m.character.name .. "'s Chronicle") or "Azeroth Chronicle")
  UI.overview.SetText(Model.OverviewText(m))
  UI.places.SetItems(Model.PlaceItems(m))
  UI.quests.SetItems(Model.QuestItems(m))
  UI.timeline.SetText(Model.TimelineText(m))
  UI.SelectTab(UI.tab or 1)
end

function UI.Open()
  if not UI.frame then UI.Build() end
  UI.Refresh()
  UI.frame:Show()
end

function UI.Toggle()
  if UI.frame and UI.frame:IsShown() then UI.frame:Hide() else UI.Open() end
end

-- ---------------------------------------------------------------------------
-- 3. Slash command
-- ---------------------------------------------------------------------------
SLASH_AZEROTHCHRONICLE1 = "/chronicle"
if type(SlashCmdList) == "table" then
  SlashCmdList["AZEROTHCHRONICLE"] = function() UI.Toggle() end
end

return ns
