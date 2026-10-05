--[[
  journal_ui_spec.lua — the in-game journal window against stubbed frames.
  Proves /chronicle opens and toggles, every tab renders, the capture addon
  and the viewer coexist, and opening never writes AzerothChronicleDB.
]]--

local stubs = require("addon.tests.wow_stubs")

local function deepcopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = deepcopy(x) end
  return out
end

local function captureSomeHistory()
  stubs.loadAddon("addon/AzerothChronicle.lua")
  stubs.frame:Fire("PLAYER_LOGIN")
  stubs.env.quests[64] = { title = "The Fargodeep Mine" }
  _G.GetQuestID = function() return 64 end
  _G.GetTitleText = function() return "The Fargodeep Mine" end
  _G.GetQuestText = function() return "Kobolds have overrun the mine." end
  _G.GetObjectiveText = function() return "Explore the Fargodeep Mine." end
  stubs.frame:Fire("QUEST_DETAIL")
  stubs.frame:Fire("QUEST_ACCEPTED", 1, 64)
end

local function openJournal(opts)
  stubs.installUI(opts)
  local ns = {}
  stubs.loadAddon("addon/ChronicleUI.lua", ns)
  _G.SlashCmdList.AZEROTHCHRONICLE("")
  return ns.JournalUI
end

describe("Journal window", function()
  before_each(function()
    stubs.install()
    _G.GetQuestID, _G.GetTitleText, _G.GetQuestText, _G.GetObjectiveText = nil, nil, nil, nil
  end)

  it("registers /chronicle and creates no frames until opened", function()
    stubs.installUI()
    stubs.loadAddon("addon/ChronicleUI.lua", {})
    assert.are.equal("/chronicle", _G.SLASH_AZEROTHCHRONICLE1)
    assert.is_function(_G.SlashCmdList.AZEROTHCHRONICLE)
    assert.are.equal(0, #stubs.ui.created)
  end)

  it("opens on the overview with the character's history and toggles closed", function()
    captureSomeHistory()
    local UI = openJournal()
    local frame = stubs.ui.byName.AzerothChronicleJournalFrame
    assert.is_true(frame:IsShown())
    assert.are.equal("Testchar's Chronicle", UI.title:GetText())
    assert.are.equal(1, UI.tab)
    assert.is_true(UI.panels[1]:IsShown())
    assert.is_false(UI.panels[2]:IsShown())
    assert.are.equal("AzerothChronicleJournalFrame", _G.UISpecialFrames[1])
    _G.SlashCmdList.AZEROTHCHRONICLE("")
    assert.is_false(frame:IsShown())
  end)

  it("switches tabs and fills the quest detail from captured text", function()
    captureSomeHistory()
    local UI = openJournal()
    stubs.ui.byName.AzerothChronicleTab3:Click()
    assert.are.equal(3, UI.tab)
    assert.is_true(UI.panels[3]:IsShown())
    assert.is_false(UI.panels[1]:IsShown())
    local q = UI.model.quests[1]
    assert.are.equal("The Fargodeep Mine", q.title)
    assert.are.equal("Kobolds have overrun the mine.", q.description)
  end)

  it("never writes the SavedVariable", function()
    captureSomeHistory()
    local before = deepcopy(_G.AzerothChronicleDB)
    local UI = openJournal()
    for i = 1, 4 do UI.SelectTab(i) end
    UI.Refresh()
    assert.are.same(before, _G.AzerothChronicleDB)
  end)

  it("shows the empty state when nothing has been captured", function()
    local UI = openJournal()
    assert.is_nil(UI.model)
    assert.are.equal("Azeroth Chronicle", UI.title:GetText())
    assert.is_nil(_G.AzerothChronicleDB)
  end)

  it("still opens when the client lacks the frame templates", function()
    captureSomeHistory()
    local UI = openJournal({ noTemplates = true })
    assert.is_true(UI.frame:IsShown())
    assert.is_nil(UI.frame._template)
  end)
end)
