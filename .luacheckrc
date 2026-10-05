-- luacheck configuration for the WoW addon.
-- NOTE: luacheck currently fails to load under Lua 5.5; the test runner
-- treats it as optional. This config is ready for a compatible luacheck
-- (run under Lua 5.1/5.4).

std = "lua51" -- WoW addons run a Lua 5.1-based environment.

-- WoW client globals the addon reads/uses; declared so luacheck does not
-- flag them as undefined. This is not the full WoW API, only what we touch.
read_globals = {
  "CreateFrame", "time", "select",
  "UnitGUID", "UnitName", "GetRealmName", "UnitRace", "UnitClass", "UnitLevel",
  "GetZoneText", "GetSubZoneText", "C_Map", "C_Timer",
  -- In-game journal (ChronicleUI.lua)
  "date", "UIParent", "UISpecialFrames", "SlashCmdList", "GameFontNormal",
}

-- The account-level SavedVariable is a global the client owns; the slash
-- command name is a global the client reads.
globals = { "AzerothChronicleDB", "SLASH_AZEROTHCHRONICLE1" }

exclude_files = { "companion/**" }
