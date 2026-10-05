--[[
  journal_model_spec.lua — the in-game journal's pure view model.
  Builds from hand-written character records; no frame API involved.
]]--

local stubs = require("addon.tests.wow_stubs")

local function loadModel()
  local ns = {}
  stubs.loadAddon("addon/ChronicleUI.lua", ns)
  return ns.JournalModel
end

local GUID = "Player-1-DEADBEEF"

local function record(events)
  return { name = "Willpala", realm = "Forever", race = "Human", class = "Paladin",
           level = 9, events = events }
end

local function sample()
  return record({
    { type = "session_started", timestamp = 100, level = 6 },
    { type = "location_changed", timestamp = 110, zone = "Elwynn Forest", subzone = "Northshire Valley" },
    { type = "quest_accepted", timestamp = 120, questId = 783, title = "A Threat Within",
      description = "I have heard troubling news.", objectivesText = "Speak with Marshal McBride.",
      zone = "Elwynn Forest", subzone = "Northshire Valley" },
    { type = "quest_completed", timestamp = 130, questId = 783, zone = "Elwynn Forest" },
    { type = "quest_accepted", timestamp = 140, questId = 7, title = "Kobold Camp Cleanup",
      zone = "Elwynn Forest" },
    { type = "location_changed", timestamp = 150, zone = "Elwynn Forest", subzone = "Goldshire" },
    { type = "location_changed", timestamp = 160, zone = "Westfall" },
    { type = "quest_completed", timestamp = 170, questId = 999, zone = "Westfall" },
  })
end

describe("Journal model", function()
  local Model
  before_each(function()
    stubs.install()
    Model = loadModel()
  end)

  it("finds the current character only in a valid v1 DB", function()
    local rec = sample()
    local db = { schemaVersion = 1, characters = { [GUID] = rec } }
    assert.are.equal(rec, Model.CurrentCharacter(db, GUID))
    assert.is_nil(Model.CurrentCharacter(db, "Player-1-OTHER"))
    assert.is_nil(Model.CurrentCharacter({ schemaVersion = 2, characters = db.characters }, GUID))
    assert.is_nil(Model.CurrentCharacter(nil, GUID))
    assert.is_nil(Model.CurrentCharacter({ schemaVersion = 1, characters = { [GUID] = { events = "x" } } }, GUID))
  end)

  it("summarises the journey for the overview", function()
    local o = Model.Build(sample()).overview
    assert.are.equal(1, o.sessions)
    assert.are.equal(2, o.questsCompleted)
    assert.are.equal(1, o.questsInProgress)
    assert.are.equal(2, o.zonesExplored)
    assert.are.equal(2, o.areasExplored)
    assert.are.equal(6, o.startLevel)
    assert.are.equal(100, o.firstEntry)
    assert.are.equal(170, o.lastEntry)
    assert.are.equal(8, #o.recent)
  end)

  it("groups places in first-visit order with their areas and quests", function()
    local places = Model.Build(sample()).places
    assert.are.equal("Elwynn Forest", places[1].name)
    assert.are.equal("Westfall", places[2].name)
    assert.are.equal(2, places[1].visits)
    assert.are.equal("Northshire Valley", places[1].subzones[1].name)
    assert.are.equal("Goldshire", places[1].subzones[2].name)
    assert.are.equal(2, #places[1].quests)
    assert.are.equal(0, #places[2].subzones)
  end)

  it("lists quests in progress first and keeps captured quest text", function()
    local quests = Model.Build(sample()).quests
    assert.are.equal("Kobold Camp Cleanup", quests[1].title)
    assert.are.equal("in_progress", quests[1].status)
    local threat
    for _, q in ipairs(quests) do if q.questId == 783 then threat = q end end
    assert.are.equal("completed", threat.status)
    assert.are.equal(120, threat.acceptedAt)
    assert.are.equal(130, threat.completedAt)
    assert.are.equal("Speak with Marshal McBride.", threat.objectivesText)
    assert.are.equal("Northshire Valley", threat.subzone)
  end)

  it("names a quest by id when no title was captured", function()
    local quests = Model.Build(sample()).quests
    local unknown
    for _, q in ipairs(quests) do if q.questId == 999 then unknown = q end end
    assert.are.equal("Quest #999", unknown.title)
    assert.are.equal("Westfall", unknown.zone)
  end)

  it("treats a re-accepted quest as in progress again", function()
    local m = Model.Build(record({
      { type = "quest_accepted", timestamp = 1, questId = 5, title = "Again" },
      { type = "quest_completed", timestamp = 2, questId = 5 },
      { type = "quest_accepted", timestamp = 3, questId = 5 },
    }))
    assert.are.equal("in_progress", m.quests[1].status)
    assert.are.equal(1, m.overview.questsCompleted)
  end)

  it("orders the timeline newest first using captured quest titles", function()
    local tl = Model.Build(sample()).timeline
    assert.are.equal(170, tl[1].timestamp)
    assert.are.equal("Completed Quest #999", tl[1].text)
    assert.are.equal("Arrived in Westfall", tl[2].text)
    assert.are.equal("Arrived in Goldshire, Elwynn Forest", tl[3].text)
    assert.are.equal("Completed A Threat Within", tl[5].text)
    assert.are.equal("Started playing at level 6", tl[#tl].text)
  end)

  it("sorts out-of-order events chronologically", function()
    local m = Model.Build(record({
      { type = "location_changed", timestamp = 50, zone = "Westfall" },
      { type = "location_changed", timestamp = 10, zone = "Elwynn Forest" },
    }))
    assert.are.equal("Elwynn Forest", m.places[1].name)
    assert.are.equal(50, m.timeline[1].timestamp)
  end)

  it("ignores malformed and unknown events without failing", function()
    local m = Model.Build(record({
      "not a table",
      { timestamp = 5 },
      { type = "future_event", timestamp = 6 },
      { type = "quest_completed", timestamp = 7, questId = "nope" },
      { type = "location_changed", timestamp = 8 },
      { type = "session_started", timestamp = 9 },
    }))
    assert.are.equal(1, #m.timeline)
    assert.are.equal("Started playing", m.timeline[1].text)
    assert.are.equal(0, #m.quests)
    assert.are.equal(0, #m.places)
  end)

  it("does not modify the captured record", function()
    local rec = sample()
    local before = {}
    for i, ev in ipairs(rec.events) do
      local copy = {}
      for k, v in pairs(ev) do copy[k] = v end
      before[i] = copy
    end
    local m = Model.Build(rec)
    Model.OverviewText(m); Model.TimelineText(m)
    Model.PlaceText(m.places[1]); Model.QuestText(m.quests[1])
    assert.are.same(before, rec.events)
    assert.are.equal(8, #rec.events)
  end)

  it("renders readable text for every tab", function()
    local m = Model.Build(sample())
    assert.truthy(Model.OverviewText(m):find("Willpala", 1, true))
    assert.truthy(Model.OverviewText(m):find("Grew from level 6 to 9", 1, true))
    assert.truthy(Model.PlaceText(m.places[1]):find("Goldshire", 1, true))
    local threat
    for _, q in ipairs(m.quests) do if q.questId == 783 then threat = q end end
    local text = Model.QuestText(threat)
    assert.truthy(text:find("Marshal McBride", 1, true))
    assert.truthy(text:find("troubling news", 1, true))
    assert.truthy(Model.TimelineText(m):find("Took on Kobold Camp Cleanup", 1, true))
  end)

  it("shows a friendly empty state with no history", function()
    assert.are.equal(Model.EMPTY_TEXT, Model.OverviewText(nil))
    assert.are.equal(Model.EMPTY_TEXT, Model.TimelineText(nil))
    assert.are.equal(0, #Model.PlaceItems(nil))
    assert.are.equal(0, #Model.QuestItems(nil))
  end)

  it("builds quest list rows with in-progress and completed headers", function()
    local items = Model.QuestItems(Model.Build(sample()))
    assert.is_true(items[1].header)
    assert.truthy(items[1].label:find("In progress (1)", 1, true))
    assert.are.equal("Kobold Camp Cleanup", items[2].label)
    assert.is_true(items[3].header)
    assert.truthy(items[3].label:find("Completed (2)", 1, true))
  end)
end)
