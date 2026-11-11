-- Command line entry point. Requirable: main(args, out, err) returns an exit
-- status; bin/hwc performs the exit.
local USAGE = [[
Usage: hwc [-h|--help]
       hwc boot [--race RACE] [--class CLASS] [--addon PATH] [--json]

Headless WoW-Pro client: loads the real WoW-Pro addon under LuaJIT.

Commands:
  boot          Boot the addon to the first shown steps and print them

Options:
  -h, --help    Show this help
  --race RACE   Player race (default Human)
  --class CLASS Player class token, e.g. WARRIOR (default WARRIOR)
  --addon PATH  WoW-Pro checkout (default ~/Projects/WoW-Pro-Guides)
  --json        Print the boot result as JSON
]]

local M = {}

local function parse_boot(args, i)
  local opts = {}
  while i <= #args do
    local a = args[i]
    if a == "--json" then
      opts.json = true
      i = i + 1
    elseif (a == "--race" or a == "--class" or a == "--addon") and args[i + 1] then
      opts[a:sub(3)] = args[i + 1]
      i = i + 2
    else
      return nil, "unknown or incomplete option: " .. a
    end
  end
  return opts
end

-- "a, b x2, c" in first-seen order
local function tally(list)
  local seen, order = {}, {}
  for _, v in ipairs(list) do
    if not seen[v] then seen[v] = 0; order[#order + 1] = v end
    seen[v] = seen[v] + 1
  end
  local parts = {}
  for _, v in ipairs(order) do parts[#parts + 1] = seen[v] > 1 and (v .. " x" .. seen[v]) or v end
  return table.concat(parts, ", ")
end

local function json_result(r, boot)
  local errors = {}
  for i, e in ipairs(r.errors) do
    errors[i] = { msg = e.msg, where = e.where, stack = e.stack, harness = boot.is_harness_error(e) }
  end
  local skipped = {}
  for rel, reason in pairs(r.skipped) do skipped[#skipped + 1] = { rel = rel, reason = reason } end
  table.sort(skipped, function(a, b) return a.rel < b.rel end)
  return {
    addon = r.addon, files_loaded = r.files_loaded, files_failed = r.files_failed,
    skipped = skipped, errors = errors, missing_order = r.missing_order,
    standin_calls = r.standin_calls, guide = r.guide, steps = r.steps, settle = r.settle,
  }
end

local function print_text(out, r, boot)
  local a = r.addon
  out:write("addon: ", a.path, "\n")
  out:write("branch: ", a.branch, "  commit: ", a.commit, a.dirty and "  (dirty)" or "", "\n")
  out:write("files: ", r.files_loaded, " loaded, ", #r.files_failed, " failed\n")
  out:write(string.format("settle: %d timers run, now %.3f%s\n", r.settle.ran, r.settle.now,
    r.settle.hit_limit and ", HIT LIMIT" or ""))
  out:write("guide: ", tostring(r.guide.gid), "  loaded: ", tostring(r.guide.loaded),
    "  active step: ", tostring(r.guide.active_step), "\n")
  out:write("steps:\n")
  for _, s in ipairs(r.steps) do
    out:write(string.format("  %3d  %s %s%s\n", s.index, tostring(s.action), tostring(s.step),
      s.qid and ("  [QID " .. s.qid .. "]") or ""))
  end
  local harness = #boot.harness_errors(r)
  out:write("errors: ", #r.errors, " (", harness, " harness, ", #r.errors - harness, " addon)\n")
  for _, e in ipairs(r.errors) do out:write("  ", e.msg, "\n") end
  out:write("missing globals: ", #r.missing_order, "\n")
  out:write("stand-ins called: ", #r.standin_calls > 0 and tally(r.standin_calls) or "none", "\n")
end

local function run_boot(opts, out)
  local config = require("hwc.config")
  local boot = require("hwc.boot")
  local cfg = config.load({ addon_path = opts.addon, race = opts.race, class = opts.class })
  local r = boot.run(cfg)
  if opts.json then
    out:write(require("hwc.json").encode(json_result(r, boot), { indent = true }), "\n")
  else
    print_text(out, r, boot)
  end
  return 0
end

function M.main(args, out, err)
  out, err = out or io.stdout, err or io.stderr
  args = args or {}
  for _, a in ipairs(args) do
    if a == "-h" or a == "--help" then
      out:write(USAGE)
      return 0
    end
  end
  if args[1] == "boot" then
    local opts, perr = parse_boot(args, 2)
    if not opts then
      err:write("hwc: ", perr, "\n", USAGE)
      return 2
    end
    local ok, res = pcall(run_boot, opts, out)
    if not ok then
      err:write(tostring(res), "\n")
      return 1
    end
    return res
  end
  err:write(USAGE)
  return 2
end

return M
