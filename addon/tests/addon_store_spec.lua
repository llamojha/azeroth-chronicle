local stubs = require("addon.tests.wow_stubs")

-- Inspect private closures in tests only; no debug API or test exports in addon.
local function findClosure(fn, wanted, seen)
  seen = seen or {}
  if seen[fn] then return end
  seen[fn] = true
  for i = 1, math.huge do
    local name, value = debug.getupvalue(fn, i)
    if not name then break end
    if name == wanted then return value end
    if type(value) == "function" then
      local found = findClosure(value, wanted, seen)
      if found then return found end
    end
  end
end

describe("Event store and normalizer contracts", function()
  local append, make, record
  before_each(function()
    stubs.install()
    stubs.loadAddon("addon/AzerothChronicle.lua")
    stubs.frame:Fire("PLAYER_LOGIN")
    append = assert(findClosure(stubs.frame._script, "AppendEvent"))
    make = assert(findClosure(stubs.frame._script, "MakeEvent"))
    record = _G.AzerothChronicleDB.characters[stubs.env.guid]
  end)
  it("rejects duplicate IDs without replacing the original event", function()
    local event = { id = "fixture-id", title = "Original" }
    assert.is_true(append(record, event))
    local count = #record.events
    for _ = 1, 100 do
      assert.is_false(append(record, { id = event.id, title = "Replacement" }))
    end
    assert.are.equal(count, #record.events)
    assert.are.equal(event, record.events[count])
    assert.are.equal("Original", record.events[count].title)
  end)
  it("rejects absent events and absent IDs", function()
    local count = #record.events
    assert.is_false(append(record, nil))
    assert.is_false(append(record, {}))
    assert.are.equal(count, #record.events)
  end)
  it("copies fields and allocates collision suffixes without mutating input", function()
    local fields = { timestamp = 100, questId = 64, title = "Snapshot" }
    local first = make("quest_accepted", 64, fields)
    assert.are.equal(stubs.env.guid .. ":quest_accepted:64:100", first.id)
    append(record, first)
    local second = make("quest_accepted", 64, fields)
    assert.are.equal(first.id .. ":2", second.id)
    fields.title = "Changed"
    assert.are.equal("Snapshot", first.title)
    assert.is_nil(fields.id)
    assert.is_nil(fields.type)
  end)
end)
