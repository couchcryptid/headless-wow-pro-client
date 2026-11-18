-- Command line entry point. Requirable: main(args, out, err) returns an exit
-- status; bin/hwc performs the exit.
local USAGE = [[
Usage: hwc [-h|--help]
       hwc boot   [--race RACE] [--class CLASS] [--json]
       hwc quest  <id>
       hwc run    --class CLASS [--race RACE] [--variant V]
                  [--include PATTERN]... [--exclude PATTERN]...
                  [--date D] [--out DIR] [--relative-to DIR]
       hwc matrix [--race RACE]... [--races LIST]
                  [--include PATTERN]... [--exclude PATTERN]...
                  [--date D] [--out DIR] [--relative-to DIR]
       hwc init
       hwc doctor [--json]
       hwc sync questie [--tag TAG]

Headless WoW-Pro client: loads the real WoW-Pro addon under LuaJIT. Run it from
the WoW-Pro folder (the one holding WoWPro/WoWPro.toc) or any folder below it.
init, doctor and sync run from any folder.

Commands:
  boot          Boot the addon to the first shown steps and print them
  quest         Print a quest from the catalog, with its sources, as JSON
  run           Play one character along the guide chain; write findings and a run log
  matrix        Play every race x class (and profession variant); write findings and run logs
  init          Download QuestieDB (latest Forever release) into ~/.hwc and check the setup
  doctor        Check LuaJIT, rocks, tools, the WoW-Pro folder, QuestieDB and the supplement
  sync questie  Install the newest QuestieDB Forever release (or --tag TAG) and make it active

Options:
  -h, --help    Show this help
  --race RACE   Player race (boot default Human; run default Dwarf; repeatable for matrix)
  --class CLASS Player class token, e.g. WARRIOR (default WARRIOR)
  --json        Print the boot result as JSON
  --variant V   Profession variant: baseline, secondary, alch-herb, bs-mining, lw-skin,
                eng-ench, tailoring (default baseline)
  --races LIST  Comma list of races for matrix, merged with --race (default Dwarf,Gnome)
  --include P / --exclude P  Glob filters on guide paths (repeatable; last match wins; default: all guides)
                See README "Choosing guides" for the rules.
  --date D      Findings date, YYYY-MM-DD (default today, host clock)
  --out DIR     Findings directory (default ~/.hwc/findings)
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
    elseif (a == "--race" or a == "--class") and args[i + 1] then
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
  local addon = require("hwc.addon_info").json_view(r.addon)
  return {
    addon = addon, files_loaded = r.files_loaded, files_failed = r.files_failed,
    skipped = skipped, errors = errors, missing_order = r.missing_order,
    standin_calls = r.standin_calls, guide = r.guide, steps = r.steps, settle = r.settle,
  }
end

local function print_text(out, r, boot)
  local a = r.addon
  out:write("addon: ", a.path, "\n")
  if a.git == false then
    out:write("version: ", a.version or "unknown", "  (not a git folder)\n")
  else
    out:write("branch: ", a.branch, "  commit: ", a.commit, a.dirty and "  (dirty)" or "", "\n")
  end
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

local function run_boot(opts, root, out)
  local config = require("hwc.config")
  local boot = require("hwc.boot")
  local cfg = config.load({ addon_path = root, race = opts.race, class = opts.class })
  local r = boot.run(cfg)
  if opts.json then
    out:write(require("hwc.json").encode(json_result(r, boot), { indent = true }), "\n")
  else
    print_text(out, r, boot)
  end
  return 0
end

local function run_quest(id, out, err)
  local config = require("hwc.config")
  local catalog = require("hwc.catalog")
  local cfg = config.load({})
  local cat = catalog.load(cfg)
  local quest = cat:quest(id)
  if not quest then
    err:write("hwc: quest ", id, " is in no catalog source\n")
    return 1
  end
  out:write(require("hwc.json").encode({ quest = quest, sources = cat.sources }, { indent = true }), "\n")
  return 0
end

-- Options for run/matrix: every option takes a value. allowed[name] is true for
-- a single value (the last one wins) or "list" for a repeatable option, kept as an
-- array in order. --include and --exclude also go into opts.filters, one ordered
-- list of { kind, raw }, since their relative order decides (last match wins).
local function parse_values(args, allowed)
  local opts = { filters = {} }
  local i = 2
  while i <= #args do
    local name = args[i]:match("^%-%-(.+)$")
    if not (name and allowed[name] and args[i + 1]) then
      return nil, "unknown or incomplete option: " .. args[i]
    end
    local value = args[i + 1]
    if allowed[name] == "list" then
      opts[name] = opts[name] or {}
      table.insert(opts[name], value)
    else
      opts[name] = value
    end
    if name == "include" or name == "exclude" then
      opts.filters[#opts.filters + 1] = { kind = name, raw = value }
    end
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
  return "hwc: wrote " .. stem .. ".html and " .. stem .. ".json (" .. n .. (n == 1 and " character" or " characters") .. ")\n"
end

local function write_file(path, text)
  local f = assert(io.open(path, "wb"))
  f:write(text)
  f:close()
end

-- The report JSON carries the addon identity through addon_info.json_view.
local function report_json(rep)
  local a = rep.header and rep.header.addon
  if a then rep.header.addon = require("hwc.addon_info").json_view(a) end
  return rep
end

-- Distinct passed gids across the logs' jumps, first-seen order; nil when none.
-- Only jumps that land on an included guide count: guides passed after the last
-- included one (to == nil) end the run, so no finding can follow from skipping them.
local function jumped_gids(logs)
  local seen, out = {}, {}
  for _, l in ipairs(logs) do
    for _, j in ipairs(l.jumps or {}) do
      if j.to ~= nil then
        for _, gid in ipairs(j.passed or {}) do
          if not seen[gid] then seen[gid] = true; out[#out + 1] = gid end
        end
      end
    end
  end
  return #out > 0 and out or nil
end

-- Included guides an --include matched that no log played, in TOC order
-- (controller Ruling 1). nil when no --include was given or every one was reached.
local function unreached_gids(opts, logs)
  local includes = {}
  for _, f in ipairs(opts.filters) do
    if f.kind == "include" then includes[#includes + 1] = require("hwc.filters").compile(f.pattern) end
  end
  if #includes == 0 then return nil end
  local played = {}
  for _, l in ipairs(logs) do
    for _, gid in ipairs(l.guides or {}) do played[gid] = true end
  end
  local seen, out = {}, {}
  for _, g in ipairs(opts.guides) do
    if opts.included[g.gid] and not played[g.gid] and not seen[g.gid] then
      for _, match in ipairs(includes) do
        if match(g.rel) then seen[g.gid] = true; out[#out + 1] = g.gid; break end
      end
    end
  end
  return #out > 0 and out or nil
end

-- Distinct gids the logs played, first-seen order; nil when none.
local function played_gids(logs)
  local seen, out = {}, {}
  for _, l in ipairs(logs) do
    for _, gid in ipairs(l.guides or {}) do
      if not seen[gid] then seen[gid] = true; out[#out + 1] = gid end
    end
  end
  return #out > 0 and out or nil
end

-- Each played character's guide levels, labelled, for report.guides.
local function guide_entries(logs, labels)
  local entries = {}
  for i, l in ipairs(logs) do entries[i] = { combo = labels[i], guide_levels = l.guide_levels or {} } end
  return entries
end

-- Each character whose run stopped before the end of the chain; nil when none did.
local function early_stops(logs, labels)
  local out = {}
  for i, l in ipairs(logs) do
    local reason = l.stop and l.stop.reason
    if reason and reason ~= "no-next-guide" then out[#out + 1] = { combo = labels[i], reason = reason } end
  end
  return #out > 0 and out or nil
end

-- Plays every combo, then writes DIR/<date>-<scope>.json and one run
-- log per character under DIR/<date>-<scope>/. Every path in the output is
-- rewritten relative to --relative-to (default: the logical start folder, so a
-- symlinked $PWD such as Interface/AddOns stays the base its paths are named from).
-- With filters, a combo whose log played no guide is skipped: a matrix names its
-- race in the header and writes nothing when every combo is skipped; a single run
-- exits 2 and writes nothing.
local function play(combos, scope, opts, out, err)
  local config = require("hwc.config")
  local runner = require("hwc.driver.run")
  local matrix = require("hwc.driver.matrix")
  local group = require("hwc.findings.group")
  local json = require("hwc.json")
  local addon_info = require("hwc.addon_info")
  local date = opts.date or os.date("%Y-%m-%d")
  local outdir = opts.out or (opts.home .. "/.hwc/findings")
  local logdir = outdir .. "/" .. date .. "-" .. scope
  local paths = require("hwc.paths")
  local report = require("hwc.findings.report")
  local cwd = opts.start or paths.cwd()
  local base = paths.resolve(opts["relative-to"] or cwd, cwd)
  local played, raw, labels = {}, {}, {}
  -- Resolved once: a `hwc sync questie` mid-run must not mix QuestieDB versions.
  local questie_dir = config.default_questie_dir()
  local skipped_races, skipped_seen = {}, {}
  for _, c in ipairs(combos) do
    local cfg = config.load({
      addon_path = opts.root, race = c.race, class = c.class,
      professions = matrix.professions(c.variant),
      catalog = { questie_dir = questie_dir },
    })
    cfg.variant = c.variant
    local log = runner.character(cfg, { included = opts.included })
    log.variant = c.variant
    if opts.included and #(log.guides or {}) == 0 then
      if not skipped_seen[c.race] then skipped_seen[c.race] = true; skipped_races[#skipped_races + 1] = c.race end
    else
      played[#played + 1] = c
      raw[#raw + 1] = log
      labels[#labels + 1] = string.format("%s %s %s", c.race, c.class, c.variant)
    end
  end
  if #played == 0 and #combos > 0 and opts.matrix then
    err:write("hwc: matrix: no race reaches an included guide\n")
    return 2
  end
  if not opts.matrix and opts.included and #skipped_races > 0 then
    err:write("hwc: ", skipped_races[1], " reaches no included guide\n")
    return 2
  end
  mkdirs(logdir)
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
  for i, c in ipairs(played) do
    logs[i] = paths.rewrite(raw[i], roots, base, cwd)
    write_file(string.format("%s/%s-%s-%s.json", logdir, c.race, c.class, c.variant),
      json.encode(logs[i], { indent = true }) .. "\n")
  end
  -- The header reads the raw first log: it is rewritten once, below.
  -- Skip Dungeon Quests is per character; a matrix runs every combo with WoWPro's
  -- defaults, so the first RunLog's value stands for the run. skipped counts distinct
  -- guide lines across every RunLog; carried lists each quest carried past the end of
  -- a run once, by id.
  local skipped, nskipped = {}, 0
  local carried, by_qid = {}, {}
  for _, l in ipairs(raw) do
    for _, c in ipairs(l.carried or {}) do
      if not by_qid[c.qid] then by_qid[c.qid] = true; carried[#carried + 1] = c end
    end
    for _, d in ipairs(l.dungeon_skips or {}) do
      local k = tostring(d.file) .. ":" .. tostring(d.line)
      if not skipped[k] then skipped[k] = true; nskipped = nskipped + 1 end
    end
  end
  table.sort(carried, function(a, b) return a.qid < b.qid end)
  local client = addon_info.read(config.repo_root(), { tracked_only = true })
  local filters
  if #opts.filters > 0 then
    filters = {}
    for i, f in ipairs(opts.filters) do filters[i] = { kind = f.kind, pattern = f.pattern } end
  end
  local header = {
    scope = scope, date = date, addon = first.addon, catalog = (first.catalog or {}).sources,
    client = { commit = client.commit, dirty = client.dirty },
    matrix = { combos = labels }, rank = first.rank,
    carried = #carried > 0 and carried or nil,
    dungeons = first.skip_dungeons ~= nil and { skip = first.skip_dungeons, skipped = nskipped } or nil,
    filters = filters,
    played = filters and played_gids(logs) or nil,
    jumped = jumped_gids(logs),
    unreached = opts.included and unreached_gids(opts, logs) or nil,
    skipped_races = #skipped_races > 0 and skipped_races or nil,
    guides = report.guides(guide_entries(logs, labels)),
    stop = early_stops(logs, labels),
  }
  header = paths.rewrite(header, roots, base, cwd)
  header.paths_relative_to = base:match("([^/]+)$") or "/"
  local findings = group.findings(logs)
  local stem = outdir .. "/" .. date .. "-" .. scope
  local doc = json.encode(report_json(report.build(findings, header)), { indent = true }) .. "\n"
  local html = require("hwc.findings.html")
  write_file(stem .. ".json", doc)
  write_file(stem .. ".html", html.render(doc, html.template()))
  out:write(M.wrote_line(stem, #logs))
  return 0
end

-- Usage-level validation shared by run and matrix: nil, or a message for exit 2.
local function check_race(race)
  if not require("hwc.world.player").RACES[race] then return "race not in scope: " .. tostring(race) end
end

-- "-filtered" marks output that played only part of the chain.
local function scoped(name, opts)
  return #opts.filters > 0 and (name .. "-filtered") or name
end

local function run_run(opts, out, err)
  local combo = { race = opts.race or "Dwarf", class = opts.class:upper(), variant = opts.variant or "baseline" }
  return play({ combo }, scoped(string.format("%s-%s-%s", combo.race, combo.class, combo.variant), opts),
    opts, out, err)
end

local function run_matrix(races, opts, out, err)
  local combos = require("hwc.driver.matrix").combos(opts.root, races)
  -- Nothing to play: no findings file (it would carry an "Addon: nil" header).
  if #combos == 0 then
    err:write("hwc: matrix: no combos for ", table.concat(races, ","),
      " (the start guide names no class for these races)\n")
    return 2
  end
  local names = {}
  for i, r in ipairs(races) do names[i] = r:lower() end
  opts.matrix = true
  return play(combos, scoped("forever-alliance-" .. table.concat(names, "-"), opts), opts, out, err)
end

local function strip(msg) return (tostring(msg):gsub("^hwc: ", "")) end

local function print_skipped(out, res)
  for _, tag in ipairs(res.skipped or {}) do out:write("skipped ", tag, ": no Forever build\n") end
end

local function sync_line(res)
  if res.already then return "QuestieDB " .. res.to .. " already installed; active\n" end
  return "QuestieDB " .. (res.from or "none") .. " \226\134\146 " .. res.to .. " (build " .. tostring(res.build):sub(1, 7) .. ")\n"
end

-- hwc init / doctor / sync questie: they work on ~/.hwc, so they need no WoW-Pro
-- folder. Returns an exit status.
local function run_store(cmd, args, out, err, env)
  local home = require("hwc.questie.home")
  local install = require("hwc.questie.install")
  local doctor = require("hwc.doctor")
  local tag, json
  if cmd == "sync" then
    local i = 3
    if args[2] ~= "questie" then
      err:write("hwc: sync needs a source: questie\n", USAGE)
      return 2
    end
    while i <= #args do
      if args[i] == "--tag" and args[i + 1] then
        tag = args[i + 1]
        i = i + 2
      else
        err:write("hwc: unknown or incomplete option: ", args[i], "\n", USAGE)
        return 2
      end
    end
  elseif cmd == "doctor" then
    for i = 2, #args do
      if args[i] == "--json" then
        json = true
      else
        err:write("hwc: unknown option: ", args[i], "\n", USAGE)
        return 2
      end
    end
  elseif #args > 1 then
    err:write("hwc: init takes no options\n", USAGE)
    return 2
  end
  local root, herr = home.root({ hwc_home = env.hwc_home, home = env.home })
  if not root then
    err:write(herr, "\n", USAGE)
    return 2
  end
  if cmd == "sync" then
    local res, serr = install.sync(root, { tag = tag })
    if not res then
      err:write("hwc: ", strip(serr), "\n")
      return 1
    end
    out:write(sync_line(res))
    print_skipped(out, res)
    return 0
  elseif cmd == "init" then
    local res, ierr = install.init(root)
    if not res then
      err:write("hwc: ", strip(ierr), "\n")
      return 1
    end
    if res.already then
      out:write("QuestieDB ", tostring(home.active(root)), " already installed\n")
    else
      out:write(sync_line(res.sync_result))
      print_skipped(out, res.sync_result)
    end
    local report = doctor.run(env)
    out:write(doctor.text(report))
    return 0
  end
  local report = doctor.run(env)
  out:write(json and (doctor.json(report) .. "\n") or doctor.text(report))
  return report.failed and 1 or 0
end

-- The WoW-Pro folder hwc runs in: root and start, or nil and a usage message.
local function locate(env)
  local source = require("hwc.source")
  local start = source.start_dir({ pwd = env.pwd, cwd = env.cwd })
  local root, ferr = source.find(start)
  if not root then return nil, nil, strip(ferr) end
  return root, start
end

-- Resolves opts.filters against the WoW-Pro folder and selects the guides they
-- keep: sets f.pattern on each filter, and opts.guides (the TOC's guides) and
-- opts.included ({ [gid] = true }) when any filter is given. Returns nil and a
-- usage message for a bad pattern, an --include matching no guide, or no guide left.
-- Raises (exit 1) when the Leveling TOC cannot be read.
local function select_guides(opts)
  if #opts.filters == 0 then return true end
  local filters = require("hwc.filters")
  local list = {}
  for i, f in ipairs(opts.filters) do
    local pattern, rerr = filters.resolve(f.raw, opts.root, opts.start)
    if not pattern then return nil, strip(rerr) end
    f.pattern = pattern
    list[i] = { kind = f.kind, pattern = pattern, raw = f.raw }
  end
  local guides = require("hwc.driver.guide_source").toc_guides(opts.root)
  local files, seen = {}, {}
  for _, g in ipairs(guides) do
    if not seen[g.rel] then seen[g.rel] = true; files[#files + 1] = g.rel end
  end
  local set, unmatched = filters.select(files, list)
  if #unmatched > 0 then
    local msgs = {}
    for i, raw in ipairs(unmatched) do msgs[i] = '--include "' .. raw .. '" matches no guide' end
    return nil, table.concat(msgs, "; ")
  end
  local included, any = {}, false
  for _, g in ipairs(guides) do
    if set[g.rel] then included[g.gid] = true; any = true end
  end
  if not any then return nil, "no guide left after filters" end
  opts.guides, opts.included = guides, included
  return true
end

local function command(args, out, err, env, allowed, prepare, fn)
  local opts, perr = parse_values(args, allowed)
  -- The date names the output files: anything but YYYY-MM-DD (e.g. ../x) would
  -- change the write path.
  if opts and opts.date and not opts.date:match("^%d%d%d%d%-%d%d%-%d%d$") then
    opts, perr = nil, "--date needs YYYY-MM-DD"
  end
  local arg
  if opts then opts, arg, perr = prepare(opts) end
  -- --out defaults under $HOME: without one, say so rather than fail on a nil path.
  if opts and not opts.out and not (env.home and env.home ~= "") then
    opts, perr = nil, "HOME is not set; pass --out DIR"
  end
  if opts then
    opts.home = env.home
    opts.root, opts.start, perr = locate(env)
    if not opts.root then opts = nil end
  end
  if opts then
    local ok, sel, serr = pcall(select_guides, opts)
    if not ok then
      err:write(tostring(sel), "\n")
      return 1
    end
    if not sel then opts, perr = nil, serr end
  end
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

-- env = { pwd, cwd, home }: where hwc runs and the user's home, each defaulting
-- to the process's own (specs pass their own).
function M.main(args, out, err, env)
  out, err = out or io.stdout, err or io.stderr
  args = args or {}
  env = env or {}
  env = {
    pwd = env.pwd or os.getenv("PWD"),
    cwd = env.cwd or require("lfs").currentdir(),
    -- false (specs) stands for an unset HOME
    home = env.home == nil and os.getenv("HOME") or env.home,
    hwc_home = env.hwc_home == nil and os.getenv("HWC_HOME") or env.hwc_home,
  }
  for _, a in ipairs(args) do
    if a == "-h" or a == "--help" then
      out:write(USAGE)
      return 0
    end
  end
  if args[1] == "boot" then
    local opts, perr = parse_boot(args, 2)
    local root
    if opts then
      root, _, perr = locate(env)
      if not root then opts = nil end
    end
    if not opts then
      err:write("hwc: ", perr, "\n", USAGE)
      return 2
    end
    local ok, res = pcall(run_boot, opts, root, out)
    if not ok then
      err:write(tostring(res), "\n")
      return 1
    end
    return res
  end
  if args[1] == "init" or args[1] == "doctor" or args[1] == "sync" then
    return run_store(args[1], args, out, err, env)
  end
  if args[1] == "quest" then
    local id = tonumber(args[2] or "")
    if not id or #args > 2 then
      err:write("hwc: quest needs a numeric id and takes no options\n", USAGE)
      return 2
    end
    local ok, res = pcall(run_quest, id, out, err)
    if not ok then
      err:write(tostring(res), "\n")
      return 1
    end
    return res
  end
  if args[1] == "run" then
    return command(args, out, err, env,
      { race = true, class = true, variant = true, include = "list", exclude = "list",
        date = true, out = true, ["relative-to"] = true },
      function(o)
        if not o.class then return nil, nil, "run needs --class" end
        if not require("hwc.driver.matrix").professions(o.variant or "baseline") then
          return nil, nil, "unknown variant: " .. o.variant
        end
        local bad = check_race(o.race or "Dwarf")
        if bad then return nil, nil, bad end
        return o
      end,
      function(_, o, w) return run_run(o, w, err) end)
  end
  if args[1] == "matrix" then
    return command(args, out, err, env,
      { race = "list", races = true, include = "list", exclude = "list",
        date = true, out = true, ["relative-to"] = true },
      function(o)
        -- --race (repeatable) and --races (comma list) merge, first-seen order.
        local given = {}
        for _, r in ipairs(o.race or {}) do given[#given + 1] = r end
        if o.races then
          for r in o.races:gmatch("[^,]+") do given[#given + 1] = r end
          if #given == #(o.race or {}) then return nil, nil, "--races is empty" end
        end
        if #given == 0 then given = { "Dwarf", "Gnome" } end
        local races, seen = {}, {}
        for _, r in ipairs(given) do
          local bad = check_race(r)
          if bad then return nil, nil, bad end
          if not seen[r] then seen[r] = true; races[#races + 1] = r end
        end
        return o, races
      end,
      function(races, o, w) return run_matrix(races, o, w, err) end)
  end
  err:write(USAGE)
  return 2
end

M._json_result, M._report_json = json_result, report_json

return M
