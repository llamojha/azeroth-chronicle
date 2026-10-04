local stubs = require("addon.tests.wow_stubs")
describe("Classic quest metadata adapter", function()
  local names = { "GetQuestLogIndexByID", "GetQuestLogTitle", "GetQuestLogSelection",
    "SelectQuestLogEntry", "GetQuestLogQuestText", "C_QuestLog",
    "GetQuestID", "GetTitleText", "GetQuestText", "GetObjectiveText" }
  local saved, selected, ready, failText, nested
  before_each(function()
    saved = {}
    for _, name in ipairs(names) do saved[name] = _G[name]; _G[name] = nil end
    stubs.install()
    selected, ready, failText, nested = 7, true, false, false
    _G.GetQuestLogIndexByID = function(id) if id == 64 then return 2 end end
    _G.GetQuestLogTitle = function(index)
      assert.are.equal(2, index)
      return "Heirloom", 10, nil, false, false, false, nil, 64
    end
    _G.GetQuestLogSelection = function() return selected end
    _G.SelectQuestLogEntry = function(index)
      selected = index
      if nested then stubs.frame:Fire("QUEST_LOG_UPDATE") end
    end
    _G.GetQuestLogQuestText = function()
      assert.are.equal(2, selected)
      if failText then error("not available") end
      if ready then return "Recover the heirloom.", "Find the heirloom." end
    end
    stubs.loadAddon("addon/AzerothChronicle.lua")
    stubs.frame:Fire("PLAYER_LOGIN")
  end)
  after_each(function()
    for _, name in ipairs(names) do _G[name] = saved[name] end
  end)
  local function events()
    return _G.AzerothChronicleDB.characters[stubs.env.guid].events
  end
  it("captures an offer without any quest-log APIs", function()
    for _, name in ipairs(names) do _G[name] = nil end
    _G.GetQuestID = function() return 64 end
    _G.GetTitleText = function() return "Offer title" end
    _G.GetQuestText = function() return "Offer description" end
    _G.GetObjectiveText = function() return "Offer objectives" end
    stubs.frame:Fire("QUEST_DETAIL")
    assert.are.equal(2, #events()) -- viewing is not accepting
    _G.GetQuestText = nil -- dialog can close before acceptance notification
    stubs.frame:Fire("QUEST_ACCEPTED", 2, 64)
    assert.are.equal("Offer title", events()[3].title)
    assert.are.equal("Offer description", events()[3].description)
    assert.are.equal("Offer objectives", events()[3].objectivesText)
  end)
  it("never attaches another quest's offer text", function()
    _G.GetQuestID = function() return 99 end
    _G.GetTitleText = function() return "Wrong quest" end
    _G.GetQuestText = function() return "Wrong description" end
    stubs.frame:Fire("QUEST_DETAIL")
    stubs.frame:Fire("QUEST_ACCEPTED", 2, 64)
    assert.are.equal("Heirloom", events()[3].title)
  end)
  it("clears an old offer when a new dialog has no valid identity", function()
    _G.GetQuestID = function() return 64 end
    _G.GetTitleText = function() return "Stale title" end
    stubs.frame:Fire("QUEST_DETAIL")
    _G.GetQuestID = function() return nil end
    stubs.frame:Fire("QUEST_DETAIL")
    stubs.frame:Fire("QUEST_ACCEPTED", 2, 64)
    assert.are.equal("Heirloom", events()[3].title)
  end)
  it("preserves partial offer text through failed log reads and logout", function()
    _G.GetQuestID = function() return 64 end
    _G.GetQuestText = function() return "Dialog description" end
    _G.GetObjectiveText = function() error("Unavailable") end
    failText = true
    stubs.frame:Fire("QUEST_DETAIL")
    stubs.frame:Fire("QUEST_ACCEPTED", 2, 64)
    stubs.frame:Fire("PLAYER_LOGOUT")
    assert.are.equal("Dialog description", events()[3].description)
    assert.are.equal("Heirloom", events()[3].title)
    assert.is_nil(events()[3].objectivesText)
  end)
  it("captures text immediately and restores selection", function()
    stubs.frame:Fire("QUEST_ACCEPTED", 2, 64)
    assert.are.equal("Heirloom", events()[3].title)
    assert.are.equal("Recover the heirloom.", events()[3].description)
    assert.are.equal("Find the heirloom.", events()[3].objectivesText)
    assert.are.equal(7, selected)
  end)
  it("retries incomplete text and leaves stored snapshots immutable", function()
    ready = false
    stubs.frame:Fire("QUEST_ACCEPTED", 2, 64)
    assert.are.equal(2, #events())
    ready = true
    stubs.frame:Fire("QUEST_LOG_UPDATE")
    assert.are.equal("Recover the heirloom.", events()[3].description)
    _G.GetQuestLogQuestText = function() return "Changed", "Changed" end
    stubs.frame:Fire("QUEST_LOG_UPDATE")
    assert.are.equal("Recover the heirloom.", events()[3].description)
  end)
  it("restores selection when text throws and preserves partial metadata", function()
    failText = true
    stubs.frame:Fire("QUEST_ACCEPTED", 2, 64)
    stubs.frame:Fire("PLAYER_LOGOUT")
    assert.are.equal(7, selected)
    assert.are.equal("Heirloom", events()[3].title)
    assert.is_nil(events()[3].description)
  end)
  it("rejects a stale index pointing at another quest", function()
    _G.GetQuestLogTitle = function() return "Wrong", 1, nil, false, nil, nil, nil, 99 end
    stubs.frame:Fire("QUEST_ACCEPTED", 2, 64)
    stubs.frame:Fire("QUEST_LOG_UPDATE")
    assert.is_nil(events()[3].title)
    assert.is_nil(events()[3].description)
    assert.are.equal(7, selected)
  end)
  it("does not recurse when selection emits a log update", function()
    nested = true
    stubs.frame:Fire("QUEST_ACCEPTED", 2, 64)
    assert.are.equal(3, #events())
    assert.are.equal(7, selected)
  end)
  it("uses the guarded Classic title API when the log reader is absent", function()
    _G.GetQuestLogIndexByID = nil
    _G.C_QuestLog = { GetQuestInfo = function(id)
      assert.are.equal(64, id)
      return "Fallback title"
    end }
    stubs.frame:Fire("QUEST_ACCEPTED", 2, 64)
    stubs.frame:Fire("QUEST_LOG_UPDATE")
    assert.are.equal("Fallback title", events()[3].title)
    assert.is_nil(events()[3].description)
  end)
end)
