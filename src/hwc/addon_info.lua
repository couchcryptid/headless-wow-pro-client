-- Reads git checkout identity of the (read-only) addon directory.
local M = {}

local function git(path, args)
  local p = assert(io.popen("git -C '" .. path .. "' " .. args .. " 2>/dev/null", "r"))
  local out = p:read("*a")
  p:close()
  return out
end

function M.read(path)
  return {
    branch = git(path, "rev-parse --abbrev-ref HEAD"):gsub("%s+$", ""),
    commit = git(path, "rev-parse HEAD"):gsub("%s+$", ""),
    dirty = git(path, "status --porcelain") ~= "",
  }
end

return M
