-- Downloads, verifies and atomically installs a QuestieDB release under the
-- hwc store. `active` only moves after the new version dir is in place.
local lfs = require("lfs")
local json = require("hwc.json")
local home = require("hwc.questie.home")
local release = require("hwc.questie.release")
local tocmeta = require("hwc.questie.tocmeta")
local http = require("hwc.questie.http")

local M = {}

local TOC = "/QuestieDB/QuestieDB_Forever.toc"

local function exists(path) return lfs.attributes(path, "mode") ~= nil end

local function mkdirs(path)
  local cur = path:sub(1, 1) == "/" and "" or nil
  for part in path:gmatch("[^/]+") do
    cur = cur and (cur .. "/" .. part) or part
    lfs.mkdir(cur)
  end
end

local function rm_rf(path)
  os.execute("rm -rf " .. http.quote(path))
end

local function size_error(size, expected)
  return ("hwc: questie: download is %s bytes, expected %s"):format(tostring(size), tostring(expected))
end

-- Checks an unpacked (or installed) version dir. asset_size/zip_path are
-- optional: an already-installed dir has no zip left to compare.
function M.verify(dir, asset_size, zip_path)
  if asset_size and zip_path then
    local size = lfs.attributes(zip_path, "size")
    if size ~= asset_size then return nil, size_error(size, asset_size) end
  end
  if not exists(dir .. TOC) then return nil, "hwc: questie: " .. dir .. TOC .. " is missing" end
  local ok, header = pcall(tocmeta.header, dir .. TOC)
  if not ok then return nil, header end
  if header["X-Flavor"] ~= "Forever" then
    return nil, "hwc: questie: X-Flavor is " .. tostring(header["X-Flavor"]) .. ", expected Forever"
  end
  if header["X-Mode"] ~= "baked" then
    return nil, "hwc: questie: X-Mode is " .. tostring(header["X-Mode"]) .. ", expected baked"
  end
  local range, rerr = release.contract_range(dir)
  if not range then return nil, rerr end
  local fine, msg = release.contract_ok(range)
  if not fine then return nil, "hwc: questie: " .. msg end
  return header
end

local function write_file(path, text)
  local f, err = io.open(path, "wb")
  if not f then return nil, "hwc: cannot write " .. path .. ": " .. tostring(err) end
  f:write(text)
  f:close()
  return true
end

local function stage_name(tag)
  local salt = tostring({}):match("0x(%x+)") or "0"
  return (".stage-%s-%d-%s"):format(tag, os.time(), salt)
end

-- Fills `stage` with a verified, checksummed copy of the release. Returns
-- true or nil, err; the caller removes the stage dir on failure.
local function fill_stage(sel, stage, deps)
  local zip = stage .. "/asset.zip"
  mkdirs(stage)
  local ok, err = deps.download(sel.asset_url, zip)
  if not ok then return nil, err or ("hwc: download " .. sel.asset_url .. " failed") end
  local size = lfs.attributes(zip, "size")
  if size ~= sel.asset_size then return nil, size_error(size, sel.asset_size) end
  ok, err = deps.unzip(zip, stage)
  if not ok then return nil, err or ("hwc: unzip " .. zip .. " failed") end
  local header, verr = M.verify(stage, sel.asset_size, zip)
  if not header then return nil, verr end
  local sha, serr = http.sha256(zip)
  if not sha then return nil, serr end
  ok, err = write_file(stage .. "/.hwc-release.json", json.encode({
    tag = sel.tag,
    asset = sel.asset_name,
    size = size,
    sha256 = sha,
    build = sel.build_commit,
  }))
  if not ok then return nil, err end
  os.remove(zip)
  return true
end

-- Moves the finished stage into place. A broken install may already occupy
-- the target; it is moved aside and restored if the rename fails.
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

function M.sync(root, opts, deps)
  opts = opts or {}
  deps = deps or http
  local sel, err = release.select(deps.get_json, opts)
  if not sel then return nil, err end

  local result = { from = home.active(root), to = sel.tag, build = sel.build_commit, skipped = sel.skipped }
  local target = home.version_dir(root, sel.tag)

  if exists(target) and M.verify(target) then
    local ok, serr = pcall(home.set_active, root, sel.tag)
    if not ok then return nil, serr end
    local rel = home.read_release(root, sel.tag)
    result.build = rel and rel.build or sel.build_commit
    result.already = true
    return result
  end

  mkdirs(root .. "/questie")
  local stage = root .. "/questie/" .. stage_name(sel.tag)
  local ok, installed, ierr = pcall(function()
    local good, e = fill_stage(sel, stage, deps)
    if not good then return nil, e end
    return place(stage, target)
  end)
  if not ok or not installed then
    rm_rf(stage)
    return nil, ok and ierr or tostring(installed)
  end
  local set_ok, serr = pcall(home.set_active, root, sel.tag)
  if not set_ok then return nil, serr end
  result.already = false
  return result
end

function M.init(root, deps)
  if home.active_dir(root) then return { already = true } end
  local res, err = M.sync(root, {}, deps)
  if not res then return nil, err end
  return { already = false, sync_result = res }
end

return M
