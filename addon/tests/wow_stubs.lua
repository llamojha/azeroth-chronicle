--[[
  wow_stubs.lua — minimal WoW client API stubs for offline testing.

  The live addon calls WoW globals (UnitGUID, GetZoneText, CreateFrame, ...).
  These do not exist outside the client. This module installs controllable
  fakes into the global environment so the addon's normalization logic can be
  exercised under busted without the game.

  It stubs ONLY what the addon touches. Extend as the addon grows.
  It never emulates game behavior beyond returning the values a test sets.
]]--

local M = {}

-- Mutable table the tests write to; stubs read from here.
M.env = {
  guid = "Player-1-DEADBEEF",
  name = "Testchar",
  realm = "TestRealm",
  race = "Human",
  class = "Mage",
  level = 17,
  zone = "Elwynn Forest",
  subzone = "Goldshire",
  mapId = 1429,
  quests = {}, -- questId -> { title, description, objectivesText }
}

-- Captures RegisterEvent + OnEvent so tests can fire events at the addon.
M.frame = nil

local function installFrame()
  local frame = { _events = {}, _script = nil }
  function frame:RegisterEvent(e) self._events[e] = true end
  function frame:UnregisterEvent(e) self._events[e] = nil end
  function frame:SetScript(kind, fn) if kind == "OnEvent" then self._script = fn end end
  -- Test helper: fire an event into the addon's OnEvent handler.
  function frame:Fire(event, ...)
    if self._events[event] and self._script then
      self._script(self, event, ...)
    end
  end
  M.frame = frame
  return frame
end

-- Install all stubs into the global environment. Call in before_each.
function M.install()
  _G.CreateFrame = function() return installFrame() end
  _G.time = _G.time or function() return 1234567890 end
  _G.select = _G.select or function(i, ...) return (select(i, ...)) end

  _G.UnitGUID = function(_) return M.env.guid end
  _G.UnitName = function(_) return M.env.name end
  _G.GetRealmName = function() return M.env.realm end
  _G.UnitRace = function(_) return M.env.race end
  _G.UnitClass = function(_) return M.env.class end
  _G.UnitLevel = function(_) return M.env.level end

  _G.GetZoneText = function() return M.env.zone end
  _G.GetSubZoneText = function() return M.env.subzone end
  _G.C_Map = { GetBestMapForUnit = function(_) return M.env.mapId end }

  -- Reset the persisted SavedVariable between tests.
  _G.AzerothChronicleDB = nil
end

-- Load the addon file fresh (re-runs its top-level chunk against current stubs).
-- The addon expects the addon name as its vararg (`local ADDON_NAME = ...`).
function M.loadAddon(path)
  local chunk = assert(loadfile(path))
  return chunk("AzerothChronicle")
end

return M
