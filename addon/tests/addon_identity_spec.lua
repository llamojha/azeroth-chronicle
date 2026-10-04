local stubs = require("addon.tests.wow_stubs")
local path = "addon/AzerothChronicle.lua"

describe("Journey capture identity and persistence", function()
  before_each(function()
    stubs.env.guid = "Player-1-DEADBEEF"
    stubs.env.level = 17
    stubs.install()
  end)

  after_each(function()
    stubs.env.guid = "Player-1-DEADBEEF"
    stubs.env.level = 17
  end)

  local function login()
    stubs.loadAddon(path)
    stubs.frame:Fire("PLAYER_LOGIN")
  end

  it("records authoritative character identity in the session", function()
    login()
    local rec = _G.AzerothChronicleDB.characters[stubs.env.guid]
    assert.are.equal("Testchar", rec.name)
    assert.are.equal("TestRealm", rec.realm)
    assert.are.equal("Human", rec.race)
    assert.are.equal("Mage", rec.class)
    assert.are.equal(17, rec.level)
    assert.are.equal(stubs.env.guid, rec.events[1].characterId)
  end)

  it("initializes once when login and entering-world repeat", function()
    login()
    local rec = _G.AzerothChronicleDB.characters[stubs.env.guid]
    local count = #rec.events
    stubs.frame:Fire("PLAYER_LOGIN")
    stubs.frame:Fire("PLAYER_ENTERING_WORLD")
    stubs.frame:Fire("PLAYER_ENTERING_WORLD")
    assert.are.equal(count, #rec.events)
  end)

  it("waits for a GUID and retries when entering the world", function()
    stubs.env.guid = nil
    login()
    assert.is_nil(_G.AzerothChronicleDB)
    stubs.env.guid = "Player-1-DEADBEEF"
    stubs.frame:Fire("PLAYER_ENTERING_WORLD")
    assert.is_table(_G.AzerothChronicleDB.characters[stubs.env.guid])
    assert.is_nil(_G.AzerothChronicleDB.characters["Testchar-TestRealm"])
  end)

  it("updates metadata without changing existing events or other characters", function()
    local event = { id = "historical", title = "Original snapshot" }
    local other = { events = { { id = "other" } } }
    local rec = { level = 1, events = { event } }
    _G.AzerothChronicleDB = {
      schemaVersion = 1,
      characters = { [stubs.env.guid] = rec, other = other },
    }
    login()
    assert.are.equal(17, rec.level)
    assert.are.equal(event, rec.events[1])
    assert.are.equal("Original snapshot", event.title)
    assert.are.equal(other, _G.AzerothChronicleDB.characters.other)
  end)

  it("preserves unsupported and malformed databases without capturing", function()
    local cases = {
      "invalid",
      { schemaVersion = 2, characters = {} },
      { schemaVersion = 1, characters = "invalid" },
      { characters = {} },
    }
    for _, db in ipairs(cases) do
      local original = type(db) == "table" and {
        schemaVersion = db.schemaVersion, characters = db.characters,
      } or db
      _G.AzerothChronicleDB = db
      assert.has_no.errors(login)
      stubs.frame:Fire("ZONE_CHANGED")
      stubs.frame:Fire("QUEST_ACCEPTED", 64)
      assert.are.equal(db, _G.AzerothChronicleDB)
      assert.same(original, _G.AzerothChronicleDB)
    end
  end)

  it("preserves malformed character history without replacing it", function()
    local rec = { name = "Preserved", events = "invalid" }
    _G.AzerothChronicleDB = {
      schemaVersion = 1, characters = { [stubs.env.guid] = rec },
    }
    assert.has_no.errors(login)
    assert.are.equal("Preserved", rec.name)
    assert.are.equal("invalid", rec.events)
  end)
end)
