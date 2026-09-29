--[[
  addon_smoke_spec.lua — scaffolding smoke test for the harness itself.

  Confirms the stubs + loader work and the addon bootstraps without errors.
  This is NOT the journey-capture normalization suite (see tasks.md #11) —
  those property/unit tests are implemented as part of Spec 1's work.
]]--

local stubs = require("addon.tests.wow_stubs")
local ADDON_PATH = "addon/AzerothChronicle.lua"

describe("Azeroth Chronicle addon (smoke)", function()
  before_each(function()
    stubs.install()
  end)

  it("loads and registers events without error", function()
    assert.has_no.errors(function()
      stubs.loadAddon(ADDON_PATH)
    end)
    assert.is_table(stubs.frame)
    assert.is_true(stubs.frame._events["PLAYER_LOGIN"])
  end)

  it("bootstraps AzerothChronicleDB on PLAYER_LOGIN", function()
    stubs.loadAddon(ADDON_PATH)
    stubs.frame:Fire("PLAYER_LOGIN")

    assert.is_table(_G.AzerothChronicleDB)
    assert.are.equal(1, _G.AzerothChronicleDB.schemaVersion)
    assert.is_table(_G.AzerothChronicleDB.characters)

    local rec = _G.AzerothChronicleDB.characters[stubs.env.guid]
    assert.is_table(rec)
    assert.are.equal("Testchar", rec.name)
    assert.is_table(rec.events)
  end)
end)
