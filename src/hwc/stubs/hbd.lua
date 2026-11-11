-- HereBeDragons stub. Values are placeholders: this pass has no time/travel
-- model, so zone size and distance are constants.
local M = {}

function M.register(sb)
  local libstub = sb.env.LibStub
  if not libstub then error("hwc: LibStub must load before the HBD stub", 0) end

  -- WoWPro_Mapping.lua:11 (WoWPro.HBD); :275/:302 GetZoneDistance, :621 and WoWPro_Zones.lua:338 GetZoneSize
  local hbd = libstub:NewLibrary("HereBeDragons-2.0", 999)
  if hbd then
    function hbd:GetZoneSize() return 1000, 1000 end
    function hbd:GetZoneDistance() return 0, 0, 0 end
  end

  -- WoWPro_ZoneDataLegacy.lua:10 (hbdm:GetUIMapIDFromMapAreaId)
  local migrate = libstub:NewLibrary("HereBeDragons-Migrate", 999)
  if migrate then
    function migrate:GetUIMapIDFromMapAreaId(id) return id end
  end
end

return M
