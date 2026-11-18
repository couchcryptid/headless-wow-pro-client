-- Finds the WoW-Pro folder (the one holding WoWPro/WoWPro.toc) from where hwc
-- is run, so the CLI works without an explicit addon path.
local lfs = require("lfs")
local paths = require("hwc.paths")

local M = {}

-- The logical working directory. $PWD keeps symlinked paths intact, but is
-- only trusted when it is absolute and names the same directory as the real
-- cwd (same inode and device); a stale or foreign $PWD falls back to cwd.
function M.start_dir(env)
  env = env or { pwd = os.getenv("PWD"), cwd = lfs.currentdir() }
  local pwd = env.pwd
  if type(pwd) == "string" and pwd:sub(1, 1) == "/" then
    local a, b = lfs.attributes(pwd), lfs.attributes(env.cwd)
    if a and b and a.ino == b.ino and a.dev == b.dev then return pwd end
  end
  return env.cwd
end

-- Walks start and its lexical parents; returns the first folder containing
-- WoWPro/WoWPro.toc.
function M.find(start)
  local dir = paths.normalize(start)
  while true do
    if lfs.attributes(dir .. "/WoWPro/WoWPro.toc", "mode") == "file" then
      return dir
    end
    if dir == "/" then break end
    dir = paths.normalize(dir .. "/..")
  end
  return nil, "hwc: no WoW-Pro folder at or above " .. start
    .. " (looked for WoWPro/WoWPro.toc)"
end

return M
