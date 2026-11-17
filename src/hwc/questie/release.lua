-- Picks which QuestieDB release to install and decides whether its data
-- contract is one this hwc understands.
local tocmeta = require("hwc.questie.tocmeta")

local M = {}

M.API = "https://api.github.com/repos/Questie/QuestieDB"
-- The QuestieDB data contract version hwc's reader is built for.
M.SUPPORTED_CONTRACT = 4

local function read_text(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

-- First non-nolib Forever entry in a release.json, or nil.
local function forever_entry(manifest)
  if type(manifest) ~= "table" or type(manifest.releases) ~= "table" then return nil end
  for _, entry in ipairs(manifest.releases) do
    if type(entry) == "table" and entry.nolib ~= true and type(entry.metadata) == "table" then
      for _, meta in ipairs(entry.metadata) do
        if type(meta) == "table" and type(meta.flavor) == "string" and meta.flavor:lower() == "forever" then
          return entry
        end
      end
    end
  end
  return nil
end

local function is_version_tag(tag)
  return type(tag) == "string" and tag:match("^v%d+%.%d+%.%d+$") ~= nil
end

local function find_asset(rel, name)
  for _, asset in ipairs(rel.assets or {}) do
    if asset.name == name then return asset end
  end
end

-- Returns the selection for a release with a Forever build, nil when it has
-- none, or nil, err when release.json could not be fetched.
local function candidate(get_json, rel)
  local manifest_asset = find_asset(rel, "release.json")
  if not manifest_asset then return nil end
  local manifest, err = get_json(manifest_asset.browser_download_url)
  if not manifest then return nil, err or "hwc: questie: release.json unavailable" end
  local entry = forever_entry(manifest)
  if not entry then return nil end
  local asset = find_asset(rel, entry.filename)
  if not asset then return nil end
  return {
    tag = rel.tag_name,
    asset_name = asset.name,
    asset_url = asset.browser_download_url,
    asset_size = asset.size,
    build_commit = rel.target_commitish,
  }
end

function M.select(get_json, opts)
  opts = opts or {}
  if opts.tag then
    if not is_version_tag(opts.tag) then
      return nil, "hwc: questie: " .. tostring(opts.tag) .. " is not a version tag (vX.Y.Z)"
    end
    local rel, err = get_json(M.API .. "/releases/tags/" .. opts.tag)
    if not rel then return nil, err end
    local found, cerr = candidate(get_json, rel)
    if cerr then return nil, cerr end
    if not found then return nil, "hwc: questie: " .. opts.tag .. " has no Forever build" end
    found.skipped = {}
    return found
  end
  local list, err = get_json(M.API .. "/releases?per_page=30")
  if not list then return nil, err end
  local skipped = {}
  for _, rel in ipairs(list) do
    if not rel.draft and not rel.prerelease and is_version_tag(rel.tag_name) then
      local found, cerr = candidate(get_json, rel)
      if cerr then return nil, cerr end
      if found then
        found.skipped = skipped
        return found
      end
      skipped[#skipped + 1] = rel.tag_name
    end
  end
  return nil, "hwc: questie: no release with a Forever build found"
end

function M.contract_range(version_dir)
  local text = read_text(version_dir .. "/QuestieDB/src/config.lua")
  if text then
    local max = tonumber(text:match("config%.contractVersion%s*=%s*(%d+)"))
    if max then
      local min = tonumber(text:match("config%.minSupportedContract%s*=%s*(%d+)")) or max
      return { min = min, max = max }
    end
  end
  local ok, header = pcall(tocmeta.header, version_dir .. "/QuestieDB/QuestieDB_Forever.toc")
  local v = ok and tonumber(header["X-Contract-Version"])
  if v then return { min = v, max = v } end
  return nil, "hwc: questie: cannot determine the contract version in " .. version_dir
end

function M.contract_ok(range)
  if range.min <= M.SUPPORTED_CONTRACT and M.SUPPORTED_CONTRACT <= range.max then return true end
  return false,
    ("QuestieDB contract %d-%d does not include %d (hwc is built for %d)"):format(
      range.min, range.max, M.SUPPORTED_CONTRACT, M.SUPPORTED_CONTRACT)
end

return M
