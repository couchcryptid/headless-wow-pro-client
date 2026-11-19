-- Downloads the Forever client tables from wago.tools, converts them to JSON
-- and installs them atomically under the hwc store. `active` only moves after
-- the new build dir is in place.
local lfs = require("lfs")
local dkjson = require("dkjson")
local json = require("hwc.json")
local home = require("hwc.forever.home")
local convert = require("hwc.forever.convert")
local http = require("hwc.questie.http")

local M = {}

M.BUILDS_URL = "https://wago.tools/api/builds"
M.PRODUCT = "wowf"

local function exists(path) return lfs.attributes(path, "mode") ~= nil end

local function rm_rf(path) os.execute("rm -rf " .. http.quote(path)) end

local function table_url(name, build)
  return ("https://wago.tools/db2/%s/csv?build=%s"):format(name, build)
end

local function read_file(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, "hwc: cannot read " .. path .. ": " .. tostring(err) end
  local text = f:read("*a")
  f:close()
  return text
end

local function write_file(path, text)
  local f, err = io.open(path, "wb")
  if not f then return nil, "hwc: cannot write " .. path .. ": " .. tostring(err) end
  local ok, werr = f:write(text)
  local closed, cerr = f:close()
  if ok and not closed then ok, werr = nil, cerr end
  if not ok then
    os.remove(path)
    return nil, "hwc: cannot write " .. path .. ": " .. tostring(werr)
  end
  return true
end

-- Every table's JSON is present and parses, and the release file does.
function M.verify(dir)
  local rel_text = read_file(dir .. "/" .. home.RELEASE_FILE)
  if not rel_text or type(dkjson.decode(rel_text)) ~= "table" then
    return nil, "hwc: forever: " .. dir .. "/" .. home.RELEASE_FILE .. " is missing or invalid"
  end
  for _, spec in ipairs(convert.TABLES) do
    local path = dir .. "/" .. spec.name .. ".json"
    local text = read_file(path)
    if not text then return nil, "hwc: forever: " .. path .. " is missing" end
    local value = dkjson.decode(text)
    if type(value) ~= "table" or type(value.rows) ~= "table" then
      return nil, "hwc: forever: " .. path .. " is not valid table JSON"
    end
  end
  return true
end

-- The newest wowf build string, validated.
local function newest_build(deps)
  local builds, err = deps.get_json(M.BUILDS_URL)
  if not builds then return nil, err end
  local list = builds[M.PRODUCT]
  local first = type(list) == "table" and list[1]
  local version = type(first) == "table" and first.version
  if type(version) ~= "string" then
    return nil, "hwc: forever: " .. M.BUILDS_URL .. " lists no " .. M.PRODUCT .. " build"
  end
  return version
end

local function stage_name(build)
  local salt = tostring({}):match("0x(%x+)") or "0"
  return (".stage-%s-%d-%s"):format(build, os.time(), salt)
end

-- Fills `stage` with the converted tables and the release file. Returns true
-- or nil, err; the caller removes the stage dir on failure.
local function fill_stage(build, stage, deps, mode)
  home.mkdirs(stage)
  local tables = {}
  for _, spec in ipairs(convert.TABLES) do
    local csv_path = stage .. "/" .. spec.name .. ".csv"
    local url = table_url(spec.name, build)
    local ok, err = deps.download(url, csv_path, mode)
    if not ok then return nil, err or ("hwc: download " .. url .. " failed") end
    local sha, serr = deps.sha256(csv_path)
    if not sha then return nil, serr end
    local text, rerr = read_file(csv_path)
    if not text then return nil, rerr end
    local converted = convert.table(spec.name, text)
    ok, err = write_file(stage .. "/" .. spec.name .. ".json", json.encode(converted))
    if not ok then return nil, err end
    os.remove(csv_path)
    tables[spec.name] = { sha256 = sha, rows = #converted.rows }
  end
  local ok, err = write_file(stage .. "/" .. home.RELEASE_FILE, json.encode({
    build = build,
    tables = tables,
    downloaded_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }))
  if not ok then return nil, err end
  return true
end

-- Moves the finished stage into place; a broken install already occupying the
-- target is moved aside and restored if the rename fails.
local function place(stage, target)
  local aside
  if exists(target) then
    aside = stage .. ".old"
    local moved, merr = os.rename(target, aside)
    if not moved then return nil, "hwc: cannot replace " .. target .. ": " .. tostring(merr) end
  end
  local renamed, rerr = os.rename(stage, target)
  if not renamed then
    if aside then os.rename(aside, target) end
    return nil, "hwc: cannot install " .. target .. ": " .. tostring(rerr)
  end
  if aside then rm_rf(aside) end
  return true
end

local function with_defaults(deps)
  deps = deps or {}
  return {
    get_json = deps.get_json or http.get_json,
    download = deps.download or http.download,
    sha256 = deps.sha256 or http.sha256,
  }
end

-- opts = {build?, download_mode?}. Returns {from, to, already} or nil, err.
function M.sync(root, opts, deps)
  opts = opts or {}
  deps = with_defaults(deps)
  local build = opts.build
  if build == nil then
    local err
    build, err = newest_build(deps)
    if not build then return nil, err end
  end
  local has_dir, target = pcall(home.dir, root, build)
  if not has_dir then return nil, target end

  local result = { from = home.active(root), to = build }
  if exists(target) and M.verify(target) then
    local ok, serr = pcall(home.set_active, root, build)
    if not ok then return nil, serr end
    result.already = true
    return result
  end

  home.mkdirs(root .. "/forever")
  local existed = exists(target)
  local stage = root .. "/forever/" .. stage_name(build)
  local ok, installed, ierr = pcall(function()
    local good, e = fill_stage(build, stage, deps, opts.download_mode)
    if not good then return nil, e end
    return place(stage, target)
  end)
  if not ok or not installed then
    rm_rf(stage)
    return nil, ok and ierr or tostring(installed)
  end
  local set_ok, serr = pcall(home.set_active, root, build)
  if not set_ok then
    if not existed then rm_rf(target) end
    return nil, serr
  end
  result.already = false
  return result
end

function M.init(root, deps, opts)
  local dir = home.active_dir(root)
  if dir and M.verify(dir) then return { already = true } end
  local res, err = M.sync(root, { download_mode = opts and opts.download_mode }, deps)
  if not res then return nil, err end
  return { already = false, sync_result = res }
end

return M
