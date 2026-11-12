-- Command line entry point. Requirable: main(args, out, err) returns an exit
-- status; bin/hwc performs the exit.
local USAGE = [[
Usage: hwc [-h|--help]
       hwc boot [--race RACE] [--class CLASS] [--addon PATH] [--json]
       hwc quest <id> [--addon PATH]
       hwc run --class CLASS [--race RACE] [--variant V] [--addon PATH] [--stop-level N]
               [--date D] [--out DIR] [--relative-to DIR]
       hwc matrix [--races Dwarf,Gnome] [--addon PATH] [--date D] [--out DIR] [--relative-to DIR]

Headless WoW-Pro client: loads the real WoW-Pro addon under LuaJIT.

Commands:
  boot          Boot the addon to the first shown steps and print them
  quest         Print a quest from the catalog, with its sources, as JSON
  run           Play one character through the 1-25 chain; write findings and a run log
  matrix        Play every race x class (and profession variant); write findings and run logs

Options:
  -h, --help    Show this help
  --race RACE   Player race (boot default Human; run default Dwarf)
  --class CLASS Player class token, e.g. WARRIOR (default WARRIOR)
  --addon PATH  WoW-Pro checkout (default ~/Projects/WoW-Pro-Guides)
  --json        Print the boot result as JSON
  --variant V   Profession variant: baseline, secondary, alch-herb, bs-mining, lw-skin,
                eng-ench, tailoring (default baseline)
  --races LIST  Comma list of races for matrix (default Dwarf,Gnome)
  --stop-level N  Level at which a run stops (default 25)
  --date D      Findings date, YYYY-MM-DD (default today, host clock)
  --out DIR     Findings directory (default findings/)
  --relative-to DIR  Every path in the output is written relative to DIR (default: current directory)
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

local function run_quest(id, addon, out, err)
  local config = require("hwc.config")
  local catalog = require("hwc.catalog")
  local cfg = config.load({ addon_path = addon })
  local cat = catalog.load(cfg)
  local quest = cat:quest(id)
  if not quest then
    err:write("hwc: quest ", id, " is in no catalog source\n")
    return 1
  end
  out:write(require("hwc.json").encode({ quest = quest, sources = cat.sources }, { indent = true }), "\n")
  return 0
end

-- Options for run/matrix: name -> value, every option takes a value.
local function parse_values(args, allowed)
  local opts = {}
  local i = 2
  while i <= #args do
    local name = args[i]:match("^%-%-(.+)$")
    if not (name and allowed[name] and args[i + 1]) then
      return nil, "unknown or incomplete option: " .. args[i]
    end
    opts[name] = args[i + 1]
    i = i + 2
  end
  return opts
end

local function mkdirs(path)
  local lfs = require("lfs")
  local cur = path:sub(1, 1) == "/" and "" or nil
  for part in path:gmatch("[^/]+") do
    cur = cur and (cur .. "/" .. part) or part
    if lfs.attributes(cur, "mode") == nil then assert(lfs.mkdir(cur)) end
  end
end

-- The CLI's closing line: both files and the character count.
function M.wrote_line(stem, n)
  return "hwc: wrote " .. stem .. ".md and " .. stem .. ".json (" .. n .. (n == 1 and " character" or " characters") .. ")\n"
end

local function write_file(path, text)
  local f = assert(io.open(path, "wb"))
  f:write(text)
  f:close()
end

-- Plays every combo, then writes DIR/<date>-<scope>.md and .json and one run
-- log per character under DIR/<date>-<scope>/. Every path in the output is
-- rewritten relative to --relative-to (default: the current directory).
local function play(combos, scope, opts, out)
  local config = require("hwc.config")
  local runner = require("hwc.driver.run")
  local matrix = require("hwc.driver.matrix")
  local group = require("hwc.findings.group")
  local render = require("hwc.findings.render")
  local json = require("hwc.json")
  local addon_info = require("hwc.addon_info")
  local date = opts.date or os.date("%Y-%m-%d")
  local outdir = opts.out or "findings"
  local logdir = outdir .. "/" .. date .. "-" .. scope
  mkdirs(logdir)
  local paths = require("hwc.paths")
  local report = require("hwc.findings.report")
  local cwd = paths.cwd()
  local base = paths.resolve(opts["relative-to"] or cwd, cwd)
  -- Absolute, so addon paths and chunk names enter the logs in a form
  -- paths.rewrite can match.
  if opts.addon then opts.addon = paths.resolve(opts.addon, cwd) end
  local raw, labels = {}, {}
  for _, c in ipairs(combos) do
    local cfg = config.load({
      addon_path = opts.addon, race = c.race, class = c.class,
      professions = matrix.professions(c.variant),
    })
    cfg.variant = c.variant
    local log = runner.character(cfg, { stop_level = opts.stop_level })
    log.variant = c.variant
    raw[#raw + 1] = log
    labels[#labels + 1] = string.format("%s %s %s", c.race, c.class, c.variant)
  end
  local first = raw[1] or {}
  -- Roots come from the first log: every combo shares one config.
  local roots = { base }
  if first.addon and first.addon.path then roots[#roots + 1] = first.addon.path end
  local sources = (first.catalog or {}).sources or {}
  local names = {}
  for name in pairs(sources) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    if sources[name].path then roots[#roots + 1] = sources[name].path end
  end
  local logs = {}
  for i, c in ipairs(combos) do
    logs[i] = paths.rewrite(raw[i], roots, base, cwd)
    write_file(string.format("%s/%s-%s-%s.json", logdir, c.race, c.class, c.variant),
      json.encode(logs[i], { indent = true }) .. "\n")
  end
  local rfirst = logs[1] or {}
  local client = addon_info.read(config.repo_root(), { tracked_only = true })
  local header = {
    scope = scope, date = date, addon = rfirst.addon, catalog = (rfirst.catalog or {}).sources,
    client = { commit = client.commit, dirty = client.dirty },
    matrix = { combos = labels }, rank = rfirst.rank,
  }
  header = paths.rewrite(header, roots, base, cwd)
  header.paths_relative_to = base:match("([^/]+)$") or "/"
  local findings = group.findings(logs)
  local stem = outdir .. "/" .. date .. "-" .. scope
  local md = render.markdown(findings, header)
  write_file(stem .. ".md", md)
  write_file(stem .. ".json", json.encode(report.build(findings, header), { indent = true }) .. "\n")
  out:write(M.wrote_line(stem, #logs))
  return 0
end

-- Usage-level validation shared by run and matrix: nil, or a message for exit 2.
local function check_race(race)
  if not require("hwc.world.player").RACES[race] then return "race not in scope: " .. tostring(race) end
end

local function run_run(opts, out)
  local combo = { race = opts.race or "Dwarf", class = opts.class:upper(), variant = opts.variant or "baseline" }
  return play({ combo }, string.format("%s-%s-%s", combo.race, combo.class, combo.variant), opts, out)
end

local function run_matrix(races, opts, out, err)
  local combos = require("hwc.driver.matrix").combos(
    opts.addon or (os.getenv("HOME") .. "/Projects/WoW-Pro-Guides"), races)
  -- Nothing to play: no findings file (it would carry an "Addon: nil" header).
  if #combos == 0 then
    err:write("hwc: matrix: no combos for ", table.concat(races, ","),
      " (the start guide names no class for these races)\n")
    return 2
  end
  local names = {}
  for i, r in ipairs(races) do names[i] = r:lower() end
  return play(combos, "forever-alliance-" .. table.concat(names, "-") .. "-1-25", opts, out)
end

local function command(args, out, err, allowed, prepare, fn)
  local opts, perr = parse_values(args, allowed)
  if opts and opts["stop-level"] then
    opts.stop_level = tonumber(opts["stop-level"])
    if not opts.stop_level then opts, perr = nil, "--stop-level needs a number" end
  end
  -- The date names the output files: anything but YYYY-MM-DD (e.g. ../x) would
  -- change the write path.
  if opts and opts.date and not opts.date:match("^%d%d%d%d%-%d%d%-%d%d$") then
    opts, perr = nil, "--date needs YYYY-MM-DD"
  end
  local arg
  if opts then opts, arg, perr = prepare(opts) end
  if not opts then
    err:write("hwc: ", perr, "\n", USAGE)
    return 2
  end
  local ok, res = pcall(fn, arg, opts, out)
  if not ok then
    local msg = tostring(res)
    -- config.load's scope errors are usage errors
    if msg:match("race not in scope") then
      err:write(msg, "\n", USAGE)
      return 2
    end
    err:write(msg, "\n")
    return 1
  end
  return res
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
  if args[1] == "quest" then
    local id = tonumber(args[2] or "")
    local addon
    local i = 3
    while id and i <= #args do
      if args[i] == "--addon" and args[i + 1] then
        addon = args[i + 1]
        i = i + 2
      else
        id = nil
      end
    end
    if not id then
      err:write("hwc: quest needs a numeric id\n", USAGE)
      return 2
    end
    local ok, res = pcall(run_quest, id, addon, out, err)
    if not ok then
      err:write(tostring(res), "\n")
      return 1
    end
    return res
  end
  if args[1] == "run" then
    return command(args, out, err,
      { race = true, class = true, variant = true, addon = true, ["stop-level"] = true, date = true, out = true, ["relative-to"] = true },
      function(o)
        if not o.class then return nil, nil, "run needs --class" end
        if not require("hwc.driver.matrix").professions(o.variant or "baseline") then
          return nil, nil, "unknown variant: " .. o.variant
        end
        local bad = check_race(o.race or "Dwarf")
        if bad then return nil, nil, bad end
        return o
      end,
      function(_, o, w) return run_run(o, w) end)
  end
  if args[1] == "matrix" then
    return command(args, out, err, { races = true, addon = true, date = true, out = true, ["relative-to"] = true },
      function(o)
        local races = {}
        for r in (o.races or "Dwarf,Gnome"):gmatch("[^,]+") do
          local bad = check_race(r)
          if bad then return nil, nil, bad end
          races[#races + 1] = r
        end
        if #races == 0 then return nil, nil, "--races is empty" end
        return o, races
      end,
      function(races, o, w) return run_matrix(races, o, w, err) end)
  end
  err:write(USAGE)
  return 2
end

return M
