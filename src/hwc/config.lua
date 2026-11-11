-- Harness configuration: defaults plus validation of the addon checkout path.
local M = {}

local function file_exists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

function M.load(tbl)
  tbl = tbl or {}
  local addon_path = tbl.addon_path or (os.getenv("HOME") .. "/Projects/WoW-Pro-Guides")
  if not file_exists(addon_path .. "/WoWPro/WoWPro.toc") then
    error("hwc: addon path not found: " .. addon_path, 0)
  end
  return {
    addon_path = addon_path,
    flavor = "Forever",
    toc_version = 16001,
    race = tbl.race or "Human",
    class = tbl.class or "WARRIOR",
    faction = "Alliance",
    sex = tbl.sex or 2,
    seed = tbl.seed or 1,
    quest_log_size = 40,
  }
end

return M
