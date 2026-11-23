-- File-system helpers shared by the QuestieDB and Forever-table installers:
-- directories, atomic file writes, staged installs and the `active` pointer.
local lfs = require("lfs")
local http = require("hwc.questie.http")

local M = {}

function M.exists(path) return lfs.attributes(path, "mode") ~= nil end

function M.mkdirs(path)
  local cur = path:sub(1, 1) == "/" and "" or nil
  for part in path:gmatch("[^/]+") do
    cur = cur and (cur .. "/" .. part) or part
    lfs.mkdir(cur)
  end
end

function M.rm_rf(path)
  os.execute("rm -rf " .. http.quote(path))
end

-- Returns true, or nil, "hwc: cannot write <path>: <err>".
function M.write_file(path, text)
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

-- Writes value + newline to path through path .. ".tmp" and a rename; raises
-- "hwc: cannot write <path>: <err>" (level 0) on failure.
function M.write_active(path, value)
  local tmp = path .. ".tmp"
  local function fail(err) error("hwc: cannot write " .. path .. ": " .. tostring(err), 0) end
  local f, err = io.open(tmp, "wb")
  if not f then fail(err) end
  local ok, werr = f:write(value, "\n")
  local closed, cerr = f:close()
  if ok and not closed then ok, werr = nil, cerr end
  if not ok then
    os.remove(tmp)
    fail(werr)
  end
  local renamed, rerr = os.rename(tmp, path)
  if not renamed then
    os.remove(tmp)
    fail(rerr)
  end
end

function M.stage_name(tag)
  local salt = tostring({}):match("0x(%x+)") or "0"
  return (".stage-%s-%d-%s"):format(tag, os.time(), salt)
end

-- Moves the finished stage into place. A broken install may already occupy
-- the target; it is moved aside and restored if the rename fails.
function M.place(stage, target)
  local aside
  if M.exists(target) then
    aside = stage .. ".old"
    local moved, merr = os.rename(target, aside)
    if not moved then return nil, "hwc: cannot replace " .. target .. ": " .. tostring(merr) end
  end
  local renamed, rerr = os.rename(stage, target)
  if not renamed then
    if aside then os.rename(aside, target) end
    return nil, "hwc: cannot install " .. target .. ": " .. tostring(rerr)
  end
  if aside then M.rm_rf(aside) end
  return true
end

return M
