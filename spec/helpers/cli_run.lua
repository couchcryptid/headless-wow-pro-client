-- Spec helper for `hwc run`: a small WoW-Pro folder, output capture, finders for
-- hashed findings files and a fake runner.character. Load with dofile.
local lfs = require("lfs")

local M = {}

function M.tmpdir()
  local dir = os.tmpname()
  os.remove(dir)
  assert(lfs.mkdir(dir))
  return dir
end

function M.write(path, text)
  os.execute("mkdir -p '" .. path:match("^(.*)/[^/]*$") .. "'")
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end

-- A small WoW-Pro folder: two Forever guides, GA (a.lua) then GB (b.lua).
function M.fixture()
  local root = M.tmpdir()
  M.write(root .. "/WoWPro/WoWPro.toc", "## Interface: 11500\n")
  M.write(root .. "/WoWPro_Leveling/WoWPro_Leveling.toc", "## Title: x\nForever/Alliance/a.lua\nForever/Alliance/b.lua\n")
  M.write(root .. "/WoWPro_Leveling/Forever/Alliance/a.lua", "WoWPro:RegisterGuide('GA', 'Leveling')\n")
  M.write(root .. "/WoWPro_Leveling/Forever/Alliance/b.lua", "WoWPro:RegisterGuide('GB', 'Leveling')\n")
  return root
end

-- Findings file names end in a content hash; these find them without knowing it.
function M.files(dir, pattern)
  local found = {}
  for name in lfs.dir(dir) do
    if name:match(pattern) then found[#found + 1] = dir .. "/" .. name end
  end
  table.sort(found)
  return found
end

-- The one findings file for `scope` on the test date; ext is "json" or "html".
function M.only(dir, scope, ext)
  ext = ext or "json"
  local pattern = "^2026%-11%-17%-" .. scope:gsub("%-", "%%-") .. "%-%x%x%x%x%x%x%x%x%." .. ext .. "$"
  local found = M.files(dir, pattern)
  -- Plain error: busted's assert.* is not in a dofile'd helper's environment.
  if #found ~= 1 then error("expected one " .. ext .. " for " .. scope .. " in " .. dir .. ", found " .. #found, 2) end
  return found[1]
end

function M.env_at(dir, home) return { pwd = dir, cwd = dir, home = home or M.tmpdir() } end

-- Replaces runner.character for one call of fn; each log plays `played(cfg)`
-- (default { "GB" }) and records one jump over GA. The fake reports progress
-- through opts.on_progress like the driver: the jump, a level, then each guide.
function M.with_runner(fn, played, jumps)
  local runner = require("hwc.driver.run")
  local real = runner.character
  local calls = {}
  runner.character = function(cfg, opts)
    calls[#calls + 1] = { cfg = cfg, opts = opts }
    local guides = played and played(cfg) or { "GB" }
    jumps = jumps or { { from = "GA", passed = { "GA" }, to = "GB", level_before = 1, level_after = 1 } }
    local emit = opts.on_progress or function() end
    for _, j in ipairs(jumps) do emit({ kind = "jump", from = j.from, to = j.to, passed = j.passed }) end
    emit({ kind = "level", level = 5 })
    for i, gid in ipairs(guides) do
      local file = cfg.addon_path .. "/WoWPro_Leveling/Forever/Alliance/" .. gid:sub(2):lower() .. ".lua"
      emit({ kind = "guide", gid = gid, file = file, index = i })
    end
    local names = {}
    for i, p in ipairs(cfg.professions or {}) do names[i] = p.name end
    return { character = { race = cfg.race, class = cfg.class, professions = names }, rank = 2, steps = {},
      signals = {}, guides = guides, jumps = jumps,
      guide_levels = { { gid = "GB", file = cfg.addon_path .. "/WoWPro_Leveling/b.lua", start_level = 5,
        end_level = 10, enter = 1, leave = 4, finished = false, last_line = 12 } },
      stop = cfg.race == "Gnome" and { reason = "iterations", level = 4, gid = "GB" }
        or { reason = "no-next-guide", level = 4, gid = "GB" },
      addon = { path = cfg.addon_path, git = false, version = "1.0" } }
  end
  local ok, res = pcall(fn, calls)
  runner.character = real
  assert(ok, res)
  return res
end

function M.read_json(path)
  local f = assert(io.open(path, "r"))
  local s = f:read("*a")
  f:close()
  return require("dkjson").decode(s)
end

function M.capture()
  local buf = {}
  return { write = function(_, ...) for _, s in ipairs({ ... }) do buf[#buf + 1] = s end end },
    function() return table.concat(buf) end
end

return M
