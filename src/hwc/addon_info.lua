-- Reads git checkout identity of the (read-only) addon directory.
local M = {}

local function git(path, args)
  local p = assert(io.popen("git -C '" .. path .. "' " .. args .. " 2>/dev/null", "r"))
  local out = p:read("*a")
  p:close()
  return out
end

-- opts.tracked_only: dirty only for changes to tracked files. The client's own
-- tree uses it: the findings markdown a run writes under findings/ is untracked
-- until the user commits it, and must not make the next run's header differ.
function M.read(path, opts)
  local status = (opts and opts.tracked_only) and "status --porcelain --untracked-files=no" or "status --porcelain"
  return {
    branch = git(path, "rev-parse --abbrev-ref HEAD"):gsub("%s+$", ""),
    commit = git(path, "rev-parse HEAD"):gsub("%s+$", ""),
    dirty = git(path, status) ~= "",
  }
end

return M
