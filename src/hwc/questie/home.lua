-- The hwc store: ~/.hwc (or $HWC_HOME) holds downloaded QuestieDB versions at
-- questie/<tag>/ and a questie/active file naming the one in use.
local lfs = require("lfs")
local store = require("hwc.store")
local dkjson = require("dkjson")

local M = {}

local TOC = "QuestieDB/QuestieDB_Forever.toc"
local TAG_PATTERN = "^v%d+%.%d+%.%d+$"

local function set(v) return type(v) == "string" and v ~= "" and v or nil end

-- env = {hwc_home?, home?}; nil reads the process environment instead.
function M.root(env)
  local hwc_home, home
  if env == nil then
    hwc_home, home = set(os.getenv("HWC_HOME")), set(os.getenv("HOME"))
  else
    hwc_home, home = set(env.hwc_home), set(env.home)
  end
  if hwc_home then return hwc_home end
  if home then return home .. "/.hwc" end
  return nil, "hwc: HOME is not set; set HWC_HOME"
end

local function check_tag(tag)
  if type(tag) ~= "string" or not tag:match(TAG_PATTERN) then
    error("hwc: questie: bad tag " .. tostring(tag), 0)
  end
end

function M.version_dir(root, tag)
  check_tag(tag)
  return root .. "/questie/" .. tag
end

local function exists(path) return lfs.attributes(path, "mode") ~= nil end

function M.active(root)
  if not root then return nil end
  local f = io.open(root .. "/questie/active", "rb")
  if not f then return nil end
  local text = f:read("*a") or ""
  f:close()
  return set(text:match("^%s*(.-)%s*$"))
end

function M.set_active(root, tag)
  check_tag(tag)
  store.mkdirs(root .. "/questie")
  store.write_active(root .. "/questie/active", tag)
end

function M.active_dir(root)
  local tag = M.active(root)
  if not tag then return nil, "none installed" end
  local ok, dir = pcall(M.version_dir, root, tag)
  if not ok or not exists(dir .. "/" .. TOC) then return nil, "broken: " .. tag end
  return dir
end

local function parts(tag)
  local a, b, c = tag:match("^v(%d+)%.(%d+)%.(%d+)$")
  return tonumber(a), tonumber(b), tonumber(c)
end

function M.installed(root)
  local tags = {}
  local base = root .. "/questie"
  if not exists(base) then return tags end
  for name in lfs.dir(base) do
    if name:match(TAG_PATTERN) and exists(base .. "/" .. name .. "/" .. TOC) then
      tags[#tags + 1] = name
    end
  end
  table.sort(tags, function(x, y)
    local x1, x2, x3 = parts(x)
    local y1, y2, y3 = parts(y)
    if x1 ~= y1 then return x1 < y1 end
    if x2 ~= y2 then return x2 < y2 end
    return x3 < y3
  end)
  return tags
end

function M.read_release(root, tag)
  local f = io.open(M.version_dir(root, tag) .. "/.hwc-release.json", "rb")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  local rel = dkjson.decode(text)
  if type(rel) ~= "table" then return nil end
  return rel
end

return M
