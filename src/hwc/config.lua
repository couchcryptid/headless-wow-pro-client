-- Harness configuration: defaults plus validation of the addon checkout path.
local Player = require("hwc.world.player")
local SKILL_LINES = require("hwc.world.skill_lines")
local home = require("hwc.questie.home")
local lfs = require("lfs")

local M = {}

-- The hwc repo root (the directory containing bin/hwc), derived from where this
-- module was loaded from, so catalog paths do not depend on the process cwd.
function M.repo_root()
  local src = debug.getinfo(1, "S").source:gsub("^@", "")
  local dir = src:match("^(.*)/src/hwc/config%.lua$") or "."
  if dir:sub(1, 1) ~= "/" then dir = lfs.currentdir() .. "/" .. dir end
  return (dir:gsub("/%.$", ""):gsub("/%./", "/"))
end

local function resolve(path)
  if path:sub(1, 1) == "/" then return path end
  return M.repo_root() .. "/" .. path
end

-- The active QuestieDB version dir, even when it is broken, so the catalog
-- can report "broken: <tag>"; nil with no store or no active tag. A tag
-- version_dir rejects is never turned into a path, so nil too.
function M.default_questie_dir()
  local root = home.root()
  local tag = home.active(root)
  if not tag then return nil end
  local ok, dir = pcall(home.version_dir, root, tag)
  return ok and dir or nil
end

-- Catalog sources (design spec §6). All optional; relative paths resolve
-- against the repo root.
local function catalog_config(c)
  c = c or {}
  local sim = (os.getenv("HOME") or "") .. "/Projects/wow-pro-leveling/sim/data/"
  return {
    questie_dir = c.questie_dir and resolve(c.questie_dir) or M.default_questie_dir(),
    wh_json = resolve(c.wh_json or (sim .. "wh.json")),
    objs_json = resolve(c.objs_json or (sim .. "objs.json")),
    rate_overrides = resolve(c.rate_overrides or (sim .. "rate_overrides.json")),
    supplement = resolve(c.supplement or "local/catalog/supplement.json"),
  }
end

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
  -- No default: the CLI finds the WoW-Pro folder (hwc.source). Without one the
  -- config still serves world and catalog code; boot.run refuses it.
  local addon_path = tbl.addon_path
  if addon_path and not file_exists(addon_path .. "/WoWPro/WoWPro.toc") then
    error("hwc: addon path not found: " .. addon_path, 0)
  end
  local race = tbl.race or "Human"
  if not Player.RACES[race] then
    error("hwc: race not in scope: " .. tostring(race), 0)
  end
  for _, p in ipairs(tbl.professions or {}) do
    if not SKILL_LINES[p.name] then
      error("hwc: unknown profession: " .. tostring(p.name), 0)
    end
  end
  return {
    addon_path = addon_path,
    flavor = "Forever",
    toc_version = 16001,
    race = race,
    class = tbl.class or "WARRIOR",
    faction = "Alliance",
    sex = tbl.sex or 2,
    seed = tbl.seed or 1,
    quest_log_size = 40,
    professions = tbl.professions or {},
    catalog = catalog_config(tbl.catalog),
  }
end

return M
