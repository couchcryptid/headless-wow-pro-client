-- Reads git checkout identity of the (read-only) addon directory.
local M = {}

local function git(path, args)
  local p = assert(io.popen("git -C '" .. path .. "' " .. args .. " 2>/dev/null", "r"))
  local out = p:read("*a")
  p:close()
  return out
end

-- Trimmed "## Version:" value of <path>/WoWPro/WoWPro.toc, or nil.
function M.toc_version(path)
  local f = io.open(path .. "/WoWPro/WoWPro.toc", "r")
  if not f then return nil end
  local v
  for line in f:lines() do
    v = line:match("^##%s*Version:%s*(.-)%s*$")
    if v then break end
  end
  f:close()
  return v
end

-- opts.tracked_only: dirty only for changes to tracked files. The client's own
-- tree uses it: the findings markdown a run writes under findings/ is untracked
-- until the user commits it, and must not make the next run's header differ.
function M.read(path, opts)
  local version = M.toc_version(path)
  if git(path, "rev-parse --is-inside-work-tree"):gsub("%s+$", "") ~= "true" then
    return { git = false, branch = nil, commit = nil, dirty = false, version = version }
  end
  local status = (opts and opts.tracked_only) and "status --porcelain --untracked-files=no" or "status --porcelain"
  return {
    git = true,
    branch = git(path, "rev-parse --abbrev-ref HEAD"):gsub("%s+$", ""),
    commit = git(path, "rev-parse HEAD"):gsub("%s+$", ""),
    dirty = git(path, status) ~= "",
    version = version,
  }
end

-- Copy of an addon identity for JSON output. A folder without git has no
-- branch or commit and states that as null instead of dropping the keys; an
-- unreadable version is null too. In-memory values stay nil.
function M.json_view(a)
  local null = require("hwc.json").null
  local copy = {}
  for k, v in pairs(a) do copy[k] = v end
  if a.git == false then
    copy.branch, copy.commit = null, null
  end
  if copy.version == nil then copy.version = null end
  return copy
end

return M
