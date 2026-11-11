-- Reviewed list of addon files the harness does not execute (UI-only or replaced by stubs).
-- Keys are paths relative to the addon checkout root; a trailing "/" marks a directory prefix.
local M = {}

local LIB = "WoWPro/Libraries/"
local ACE = LIB .. "Ace/"

local prefixes = {
  { LIB .. "LibSharedMedia-3.0/", "UI media library; no rendering in the harness" },
  { LIB .. "AceGUI-3.0-SharedMediaWidgets/", "AceGUI widgets; UI only" },
  { LIB .. "LibDataBroker-1.1/", "minimap/broker display library; UI only" },
  { LIB .. "LibDBIcon-1.0/", "minimap icon library; UI only" },
  { LIB .. "HereBeDragons/", "replaced by the HereBeDragons stub" },
  { LIB .. "LibPetJournal-2.0/", "pet journal library; UI only" },
  { ACE .. "AceGUI-3.0/", "Ace UI part; no widgets in the harness" },
  { ACE .. "AceConfig-3.0/", "Ace UI part; options dialogs not rendered" },
  { ACE .. "AceDBOptions-3.0/", "Ace UI part; options dialogs not rendered" },
}

-- Not skipped: WoWPro/WoWPro_Widgets.lua. WoWPro_Frames.lua:1767 (CreateRow) builds each row from its
-- constructors (CreateCheck/CreateStep/CreateNote...), and the row check state is read by WoWPro_RowUpdate.lua.
-- Not skipped: WoWPro/WoWPro_CurrentGuide.lua. It creates WoWPro.CurrentGuideFrame hidden at load (:46-47), and
-- WoWPro_Broker.lua:1880 (UpdateGuideReal) calls WoWPro.CurrentGuideFrame:IsVisible() unconditionally.
local exact = {
  ["WoWPro/WoWPro_Templates.xml"] = "frame templates; UI only",
  ["WoWPro/WoWPro_GuideList.lua"] = "guide list window; UI only",
  ["WoWPro/WoWPro_Tutorial.lua"] = "tutorial UI",
  ["WoWPro/WoWPro_Config.lua"] = "options UI",
  ["WoWPro/WoWPro_Command.lua"] = "slash command UI",
  ["WoWPro/WoWPro_Pets.lua"] = "pet journal UI",
  ["WoWPro_Leveling/WoWPro_Leveling_Config.lua"] = "options UI",
  ["WoWPro_Leveling/WoWPro_Leveling_Frames.lua"] = "leveling frames; UI only",
}

function M.reason(rel)
  if exact[rel] then return exact[rel] end
  for _, p in ipairs(prefixes) do
    if rel:sub(1, #p[1]) == p[1] then return p[2] end
  end
  return nil
end

return M
