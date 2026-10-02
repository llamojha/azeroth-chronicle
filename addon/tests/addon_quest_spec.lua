local stubs = require("addon.tests.wow_stubs")

describe("Pending quest capture", function()
  local savedTime, savedZone, savedSubzone
  local clock
  before_each(function()
    savedTime = _G.time
    savedZone, savedSubzone = stubs.env.zone, stubs.env.subzone
    clock = 100
    stubs.install()
    _G.time = function() return clock end
    stubs.env.zone, stubs.env.subzone = "Elwynn Forest", "Goldshire"
    stubs.loadAddon("addon/AzerothChronicle.lua")
    stubs.frame:Fire("PLAYER_LOGIN")
  end)
  after_each(function()
    _G.time = savedTime
    stubs.env.zone, stubs.env.subzone = savedZone, savedSubzone
  end)
  local function quests()
    local result = {}
    for _, event in ipairs(_G.AzerothChronicleDB.characters[stubs.env.guid].events) do
      if event.questId then result[#result + 1] = event end
    end
    return result
  end

  it("keeps acceptance time and location when metadata is delayed", function()
    stubs.frame:Fire("QUEST_ACCEPTED", 1, 64)
    assert.are.equal(0, #quests())
    clock = 200
    stubs.env.zone, stubs.env.subzone = "Westfall", "Sentinel Hill"
    stubs.frame:Fire("QUEST_LOG_UPDATE")
    local event = quests()[1]
    assert.are.equal(100, event.timestamp)
    assert.are.equal("Goldshire", event.subzone)
    assert.are.equal("Elwynn Forest", event.zone)
    assert.are.equal(64, event.questId)
    assert.is_nil(event.title)
  end)

  it("suppresses repeated accept and update notifications", function()
    stubs.frame:Fire("QUEST_ACCEPTED", 1, 64)
    stubs.frame:Fire("QUEST_ACCEPTED", 1, 64)
    stubs.frame:Fire("QUEST_LOG_UPDATE")
    local id = quests()[1].id
    clock = 200
    stubs.frame:Fire("QUEST_ACCEPTED", 1, 64)
    stubs.frame:Fire("QUEST_LOG_UPDATE")
    assert.are.equal(1, #quests())
    assert.are.equal(id, quests()[1].id)
  end)

  it("flushes all pending acceptances at logout", function()
    stubs.frame:Fire("QUEST_ACCEPTED", 1, 64)
    stubs.frame:Fire("QUEST_ACCEPTED", 2, 65)
    stubs.frame:Fire("PLAYER_LOGOUT")
    assert.are.equal(2, #quests())
    stubs.frame:Fire("PLAYER_LOGOUT")
    assert.are.equal(2, #quests())
  end)

  it("flushes acceptance before completion and deduplicates identical turn-ins", function()
    stubs.frame:Fire("QUEST_ACCEPTED", 1, 64)
    stubs.frame:Fire("QUEST_TURNED_IN", 64)
    stubs.frame:Fire("QUEST_TURNED_IN", 64)
    assert.are.equal(2, #quests())
    assert.are.equal("quest_accepted", quests()[1].type)
    assert.are.equal("quest_completed", quests()[2].type)
  end)

  it("keeps a new acceptance after turn-in even within the same second", function()
    stubs.frame:Fire("QUEST_ACCEPTED", 1, 64)
    stubs.frame:Fire("QUEST_TURNED_IN", 64)
    stubs.frame:Fire("QUEST_ACCEPTED", 1, 64)
    stubs.frame:Fire("QUEST_LOG_UPDATE")
    assert.are.equal(3, #quests())
    assert.are_not.equal(quests()[1].id, quests()[3].id)
  end)

  it("allows acceptance after abandonment without fabricating completion", function()
    stubs.frame:Fire("QUEST_ACCEPTED", 1, 64)
    stubs.frame:Fire("QUEST_REMOVED", 64)
    stubs.frame:Fire("QUEST_ACCEPTED", 1, 64)
    stubs.frame:Fire("QUEST_LOG_UPDATE")
    assert.are.equal(2, #quests())
    assert.are.equal("quest_accepted", quests()[2].type)
    assert.are_not.equal(quests()[1].id, quests()[2].id)
  end)

  it("suppresses delayed duplicate turn-ins after removal", function()
    stubs.frame:Fire("QUEST_TURNED_IN", 64)
    stubs.frame:Fire("QUEST_REMOVED", 64)
    clock = 200
    stubs.frame:Fire("QUEST_TURNED_IN", 64)
    assert.are.equal(1, #quests())
  end)

  it("retains two full repeatable cycles in the same second", function()
    for _ = 1, 2 do
      stubs.frame:Fire("QUEST_ACCEPTED", 1, 64)
      stubs.frame:Fire("QUEST_TURNED_IN", 64)
    end
    assert.are.equal(4, #quests())
    assert.are_not.equal(quests()[2].id, quests()[4].id)
  end)

  it("ignores invalid quest identities", function()
    for _, id in ipairs({ 0, -1, 1.5, "64", {}, math.huge }) do
      stubs.frame:Fire("QUEST_ACCEPTED", id)
      stubs.frame:Fire("QUEST_TURNED_IN", id)
    end
    stubs.frame:Fire("QUEST_LOG_UPDATE")
    assert.are.equal(0, #quests())
  end)
end)
