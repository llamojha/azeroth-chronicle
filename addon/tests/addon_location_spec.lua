local stubs = require("addon.tests.wow_stubs")
local path = "addon/AzerothChronicle.lua"

describe("Journey location capture", function()
  local saved = {}
  before_each(function()
    for _, key in ipairs({ "zone", "subzone", "mapId" }) do
      saved[key] = stubs.env[key]
    end
    saved.time = _G.time
    stubs.install()
    _G.time = function() return 1234567890 end
    stubs.env.zone, stubs.env.subzone = "Elwynn Forest", "Goldshire"
    stubs.loadAddon(path)
    stubs.frame:Fire("PLAYER_LOGIN")
  end)
  after_each(function()
    stubs.env.zone, stubs.env.subzone = saved.zone, saved.subzone
    stubs.env.mapId = saved.mapId
    _G.time = saved.time
  end)

  local function events()
    return _G.AzerothChronicleDB.characters[stubs.env.guid].events
  end

  it("ignores repeated location notifications and map-only changes", function()
    stubs.frame:Fire("ZONE_CHANGED")
    stubs.frame:Fire("ZONE_CHANGED_NEW_AREA")
    stubs.env.mapId = 999
    stubs.frame:Fire("ZONE_CHANGED_INDOORS")
    assert.are.equal(2, #events())
  end)

  it("keeps distinct same-second transitions including a return", function()
    local original = events()[2]
    stubs.env.zone = "Westfall"
    stubs.frame:Fire("ZONE_CHANGED_NEW_AREA")
    stubs.env.zone = "Elwynn Forest"
    stubs.frame:Fire("ZONE_CHANGED_NEW_AREA")
    assert.are.equal(4, #events())
    local ids = {}
    for _, event in ipairs(events()) do
      assert.is_nil(ids[event.id])
      ids[event.id] = true
    end
    assert.are.equal("Elwynn Forest", original.zone)
    assert.are.equal("Westfall", events()[3].zone)
    assert.are.equal("Elwynn Forest", events()[4].zone)
  end)

  it("does not repeat an unchanged location after reload", function()
    local firstId = events()[1].id
    stubs.loadAddon(path)
    stubs.frame:Fire("PLAYER_LOGIN")
    assert.are.equal(3, #events())
    assert.are.equal("session_started", events()[3].type)
    assert.are_not.equal(firstId, events()[3].id)
    assert.are.equal(firstId, events()[1].id)
  end)

  it("records a changed location after reload", function()
    stubs.env.subzone = "Northshire"
    stubs.loadAddon(path)
    stubs.frame:Fire("PLAYER_LOGIN")
    assert.are.equal(4, #events())
    assert.are.equal("Northshire", events()[4].subzone)
  end)

  it("tolerates absent location and normalizes empty subzones", function()
    stubs.env.zone, stubs.env.subzone = nil, nil
    stubs.frame:Fire("ZONE_CHANGED")
    assert.are.equal(2, #events())
    stubs.env.zone, stubs.env.subzone = "Westfall", ""
    stubs.env.mapId = nil
    stubs.frame:Fire("ZONE_CHANGED")
    assert.are.equal(3, #events())
    assert.is_nil(events()[3].subzone)
    assert.is_nil(events()[3].mapId)
    stubs.env.subzone = nil
    stubs.frame:Fire("ZONE_CHANGED")
    assert.are.equal(3, #events())
  end)
end)
