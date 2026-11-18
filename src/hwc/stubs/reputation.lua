-- C_Reputation for the Forever flavor, backed by sb.world.reputation.
-- WoWPro_CompatUtil.lua:240-270 and WoWPro_Broker.lua ~2882-2895 read reaction,
-- currentStanding, the two thresholds, name and hasBonusRepGain. The legacy
-- GetFactionInfoByID is absent in Forever, so it stays undefined. Reads
-- sb.world on each call, never a captured copy.
local reputation = require("hwc.world.reputation")

local M = {}

function M.install(sb, trap)
  sb.env.C_Reputation = trap(sb, "C_Reputation", {
    GetFactionDataByID = function(id)
      id = tonumber(id)
      if not id then return nil end
      local rep = sb.world.reputation
      rep.lookups[id] = true
      local points = rep:points(id)
      if points == nil then return nil end
      local reaction, lower, upper = reputation.standing(points)
      return {
        factionID = id, name = rep:name(id), reaction = reaction,
        currentStanding = points, currentReactionThreshold = lower, nextReactionThreshold = upper,
        hasBonusRepGain = false, isHeader = false, isHeaderWithRep = false, isWatched = false,
        isChild = false, atWarWith = false, canToggleAtWar = false, isCollapsed = false,
        canSetInactive = false, description = "",
      }
    end,
  })
end

return M
