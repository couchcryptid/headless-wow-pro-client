-- Stand-ins for addon UI/config entry points the harness does not run
-- (no renderer, no options UI). Each logs its name to sb.standin_calls and
-- returns nil. Installed after the WoWPro global exists; never overwrites a
-- function the addon defined itself.
local M = {}

local NAMES = {
  "RefreshConfig", "SetDefaults", "InitializeTutorial", "QueueTutorial",
  "CreateConfig", "CreateMiniMapButton",
}

function M.install(sb)
  local wowpro = sb.env.WoWPro
  for _, name in ipairs(NAMES) do
    if wowpro[name] == nil then
      wowpro[name] = function()
        sb.standin_calls[#sb.standin_calls + 1] = name
        return nil
      end
    end
  end
end

return M
