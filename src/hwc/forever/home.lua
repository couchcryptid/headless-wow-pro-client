-- The Forever client tables in the hwc store: <root>/forever/<build>/ holds one
-- <Table>.json per table, and <root>/forever/active names the build in use.
local lfs = require("lfs")

local M = {}

M.BUILD_PATTERN = "^%d+%.%d+%.%d+%.%d+$"
M.RELEASE_FILE = ".hwc-release.json"

local function set(v) return type(v) == "string" and v ~= "" and v or nil end

local function exists(path) return lfs.attributes(path, "mode") ~= nil end

function M.check_build(build)
  if type(build) ~= "string" or not build:match(M.BUILD_PATTERN) then
    error("hwc: forever: bad build " .. tostring(build), 0)
  end
end

function M.dir(root, build)
  M.check_build(build)
  return root .. "/forever/" .. build
end

function M.active(root)
  if not root then return nil end
  local f = io.open(root .. "/forever/active", "rb")
  if not f then return nil end
  local text = f:read("*a") or ""
  f:close()
  return set(text:match("^%s*(.-)%s*$"))
end

local function mkdirs(path)
  local cur = path:sub(1, 1) == "/" and "" or nil
  for part in path:gmatch("[^/]+") do
    cur = cur and (cur .. "/" .. part) or part
    lfs.mkdir(cur)
  end
end
M.mkdirs = mkdirs

function M.set_active(root, build)
  M.check_build(build)
  mkdirs(root .. "/forever")
  local target = root .. "/forever/active"
  local tmp = root .. "/forever/active.tmp"
  local function fail(err) error("hwc: cannot write " .. target .. ": " .. tostring(err), 0) end
  local f, err = io.open(tmp, "wb")
  if not f then fail(err) end
  local ok, werr = f:write(build, "\n")
  local closed, cerr = f:close()
  if ok and not closed then ok, werr = nil, cerr end
  if not ok then
    os.remove(tmp)
    fail(werr)
  end
  local renamed, rerr = os.rename(tmp, target)
  if not renamed then
    os.remove(tmp)
    fail(rerr)
  end
end

function M.active_dir(root)
  local build = M.active(root)
  if not build then return nil, "none installed" end
  local ok, dir = pcall(M.dir, root, build)
  if not ok or not exists(dir .. "/" .. M.RELEASE_FILE) then return nil, "broken: " .. build end
  return dir
end

return M
