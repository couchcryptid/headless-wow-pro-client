-- The Forever client tables in the hwc store: <root>/forever/<build>/ holds one
-- <Table>.json per table, and <root>/forever/active names the build in use.
local store = require("hwc.store")

local M = {}

M.BUILD_PATTERN = "^%d+%.%d+%.%d+%.%d+$"
M.RELEASE_FILE = ".hwc-release.json"

local function set(v) return type(v) == "string" and v ~= "" and v or nil end

local exists = store.exists

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

M.mkdirs = store.mkdirs

function M.set_active(root, build)
  M.check_build(build)
  store.mkdirs(root .. "/forever")
  store.write_active(root .. "/forever/active", build)
end

function M.active_dir(root)
  local build = M.active(root)
  if not build then return nil, "none installed" end
  local ok, dir = pcall(M.dir, root, build)
  if not ok or not exists(dir .. "/" .. M.RELEASE_FILE) then return nil, "broken: " .. build end
  return dir
end

return M
