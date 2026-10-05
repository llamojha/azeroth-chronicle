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
-- The client passes (addonName, addonNamespace) as the file's varargs.
function M.loadAddon(path, ns)
  local chunk = assert(loadfile(path))
  return chunk("AzerothChronicle", ns or {})
end

-- ---------------------------------------------------------------------------
-- Frame widgets for the journal UI. Records only what tests inspect (shown
-- state, text, scripts). Methods are an explicit list so a probe like
-- `frame.CloseButton` stays nil, as it would on a real untemplated frame.
-- ---------------------------------------------------------------------------
local NOOP_METHODS = {
  "SetSize", "SetPoint", "SetAllPoints", "SetFrameStrata", "SetClampedToScreen",
  "SetMovable", "EnableMouse", "EnableMouseWheel", "RegisterForDrag",
  "StartMoving", "StopMovingOrSizing", "SetWidth", "SetJustifyH", "SetJustifyV",
  "SetScrollChild", "UpdateScrollChildRect", "SetVerticalScroll",
  "SetColorTexture", "SetTexture", "SetHighlightTexture", "SetNormalFontObject",
  "LockHighlight", "UnlockHighlight", "Enable", "Disable",
}

local function Widget(kind, name, template)
  local w = { _kind = kind, _name = name, _template = template, _shown = true,
              _scripts = {}, _height = 1 }
  for _, m in ipairs(NOOP_METHODS) do w[m] = function() end end
  function w:Show() self._shown = true end
  function w:Hide() self._shown = false end
  function w:IsShown() return self._shown end
  function w:SetText(t) self._text = t end
  function w:GetText() return self._text end
  function w:SetHeight(h) self._height = h end
  function w:GetStringHeight() return 12 end
  function w:GetVerticalScroll() return 0 end
  function w:GetVerticalScrollRange() return 0 end
  function w:SetScript(kind_, fn) self._scripts[kind_] = fn end
  function w:GetScript(kind_) return self._scripts[kind_] end
  function w:Click() local fn = self._scripts.OnClick; if fn then fn(self) end end
  function w:CreateFontString() return Widget("FontString") end
  function w:CreateTexture() return Widget("Texture") end
  return w
end

-- Installs CreateFrame + UI globals for the journal. `opts.noTemplates`
-- makes every templated CreateFrame fail, exercising the plain fallbacks.
function M.installUI(opts)
  opts = opts or {}
  M.ui = { created = {}, byName = {} }
  _G.CreateFrame = function(kind, name, _parent, template)
    if template and opts.noTemplates then error("unknown template " .. template) end
    local w = Widget(kind, name, template)
    M.ui.created[#M.ui.created + 1] = w
    if name then M.ui.byName[name] = w end
    return w
  end
  _G.UIParent = Widget("Frame", "UIParent")
  _G.UISpecialFrames = {}
  _G.SlashCmdList = {}
  _G.GameFontNormal = {}
end

return M
