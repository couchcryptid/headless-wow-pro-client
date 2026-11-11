-- Stand-ins for addon UI/config entry points the harness does not run
-- (no renderer, no options UI). Each logs its name to sb.standin_calls and
-- returns nil.
--   install(sb):  after WoWPro.lua runs; fills names the skipped UI files would
--                 define, and never overwrites a function the addon defined.
--   override(sb): after all addon files load; replaces addon-defined UI calls
--                 that cannot run headless. Each entry cites why.
local M = {}

local NAMES = {
  -- WoWPro.lua:456-458 registers AceDB callbacks to these (CallbackHandler-1.0.lua:101-102 errors if absent); defined in skipped WoWPro_Config.lua
  "RefreshConfig", "SetDefaults",
  -- WoWPro.lua:454 and :720; defined in skipped WoWPro_Tutorial.lua
  "InitializeTutorial", "QueueTutorial",
  -- WoWPro.lua:582; defined in skipped WoWPro_Config.lua
  "CreateConfig",
  -- WoWPro_Frames.lua:2452 (CreateFrames); guide list window, defined in skipped WoWPro_GuideList.lua:196
  "CreateGuideList",
}

local OVERRIDES = {
  -- WoWPro.lua:695 -> WoWPro_Frames.lua:1922 needs LibDataBroker-1.1 (skipped: minimap UI only)
  "CreateMiniMapButton",
  -- WoWPro_Frames.lua:836 (CustomizeFrames) -> :142 needs LibDBIcon-1.0 (skipped), and without a Minimap
  -- frame :145-146 re-arms a 1 s timer forever
  "MinimapSet",
}

local function standin(sb, name)
  return function()
    sb.standin_calls[#sb.standin_calls + 1] = name
    return nil
  end
end

function M.install(sb)
  local wowpro = sb.env.WoWPro
  for _, name in ipairs(NAMES) do
    if wowpro[name] == nil then wowpro[name] = standin(sb, name) end
  end
end

function M.override(sb)
  local wowpro = sb.env.WoWPro
  for _, name in ipairs(OVERRIDES) do wowpro[name] = standin(sb, name) end
end

return M
