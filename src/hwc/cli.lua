-- Command line entry point. Requirable: main(args, out, err, env) returns an
-- exit status; bin/hwc performs the exit. Each command is a declaration plus a
-- handler (src/hwc/cli/commands.lua); run still takes the legacy path below
-- until it gets its own declaration.

-- The legacy run path's usage text, printed after its usage errors.
local function usage()
  return require("hwc.cli.help").command(require("hwc.cli.commands").find("run"))
end

local M = {}

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

-- A findings file's stem: date, scope, then the hash of the findings JSON text.
function M.stem_name(date, scope, doc)
  return date .. "-" .. scope .. "-" .. require("hwc.findings.group").fnv1a32(doc)
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

-- Plays every combo, then writes DIR/<date>-<scope>-<hash>.json and one run
-- log per character under DIR/<date>-<scope>-<hash>/. Every path in the output is
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
  local paths = require("hwc.paths")
  local report = require("hwc.findings.report")
  local html = require("hwc.findings.html")
  -- Read before anything is played or written: a missing template must not leave
  -- a .json (or run logs) with no .html beside it.
  local template = html.template()
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
    if opts.included and #(log.guides or {}) == 0 then
      if not skipped_seen[c.race] then skipped_seen[c.race] = true; skipped_races[#skipped_races + 1] = c.race end
    else
      played[#played + 1] = c
      raw[#raw + 1] = log
      labels[#labels + 1] = group.combo(log)
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
  for i = 1, #played do logs[i] = paths.rewrite(raw[i], roots, base, cwd) end
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
  local doc = json.encode(report_json(report.build(findings, header)), { indent = true }) .. "\n"
  -- The hash is of the findings, so it names the run logs too: two runs whose
  -- findings differ never overwrite each other.
  local stem = outdir .. "/" .. M.stem_name(date, scope, doc)
  mkdirs(stem)
  for i, c in ipairs(played) do
    write_file(string.format("%s/%s-%s-%s.json", stem, c.race, c.class, c.variant),
      json.encode(logs[i], { indent = true }) .. "\n")
  end
  write_file(stem .. ".json", doc)
  write_file(stem .. ".html", html.render(doc, template))
  out:write(M.wrote_line(stem, #logs))
  return 0
end

-- Usage-level validation shared by run and matrix: nil, or a message for exit 2.
-- With a class, also that the race can play it in Forever (Player.RACES).
local function check_race(race, class)
  local Player = require("hwc.world.player")
  if not Player.RACES[race] then return "race not in scope: " .. tostring(race) end
  if class and not Player.can_play(race, class:upper()) then
    return race .. " can't be a " .. class:upper() .. " in Forever"
  end
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

local function strip(msg) return (tostring(msg):gsub("^hwc: ", "")) end

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
    err:write("hwc: ", perr, "\n", usage())
    return 2
  end
  local ok, res = pcall(fn, arg, opts, out)
  if not ok then
    local msg = tostring(res)
    -- config.load's scope errors are usage errors
    if msg:match("race not in scope") then
      err:write(msg, "\n", usage())
      return 2
    end
    err:write(msg, "\n")
    return 1
  end
  return res
end

-- Legacy `hwc run` (argv after the command; globals already taken out). Task 7
-- replaces it with a declaration.
local function legacy_run(rest, out, err, env)
  local args = { "run" }
  for _, a in ipairs(rest) do args[#args + 1] = a end
  return command(args, out, err, env,
    { race = true, class = true, variant = true, include = "list", exclude = "list",
      date = true, out = true, ["relative-to"] = true },
    function(o)
      if not o.class then return nil, nil, "run needs --class" end
      if not require("hwc.driver.matrix").professions(o.variant or "baseline") then
        return nil, nil, "unknown variant: " .. o.variant
      end
      local bad = check_race(o.race or "Dwarf", o.class)
      if bad then return nil, nil, bad end
      return o
    end,
    function(_, o, w) return run_run(o, w, err) end)
end

-- Parses rest against decl, finds the WoW-Pro folder when the command needs
-- one, then runs the handler. A Lua error escaping the handler exits 1.
local function dispatch(decl, rest, u, env)
  local commands = require("hwc.cli.commands")
  local ctx = { ui = u, env = env }
  if decl.passthrough then
    ctx.opts = { positionals = rest, filters = {} }
  else
    local opts, perr = require("hwc.cli.args").parse(decl, rest)
    if not opts then return commands.usage_error(u, perr, decl.name) end
    ctx.opts = opts
  end
  if decl.needs_folder then
    local root, start, ferr = locate(env)
    if not root then return commands.usage_error(u, ferr, decl.name) end
    ctx.root, ctx.start = root, start
  end
  local ok, res = pcall(decl.run, ctx)
  if not ok then
    u:error(strip(res))
    return 1
  end
  return res
end

-- env = { pwd, cwd, home, hwc_home, tty, clock }: where hwc runs, the user's
-- home, whether stderr is a terminal and the wall clock, each defaulting to the
-- process's own (specs pass their own; tty defaults to false).
function M.main(argv, out, err, env)
  out, err = out or io.stdout, err or io.stderr
  argv = argv or {}
  env = env or {}
  env = {
    pwd = env.pwd or os.getenv("PWD"),
    cwd = env.cwd or require("lfs").currentdir(),
    -- false (specs) stands for an unset HOME
    home = env.home == nil and os.getenv("HOME") or env.home,
    hwc_home = env.hwc_home == nil and os.getenv("HWC_HOME") or env.hwc_home,
    tty = env.tty or false,
    clock = env.clock or os.time,
  }
  local commands = require("hwc.cli.commands")
  local g = require("hwc.cli.args").globals(argv)
  local u = require("hwc.ui").new({ out = out, err = err, level = g.level, tty = env.tty })
  if g.version or g.command == "version" then return dispatch(commands.find("version"), {}, u, env) end
  if g.help and g.command and g.command ~= "help" then
    return dispatch(commands.find("help"), { g.command }, u, env)
  end
  if not g.command then
    if #g.rest > 0 and not g.help then
      return commands.usage_error(u, "unknown option " .. g.rest[1])
    end
    return dispatch(commands.find("help"), {}, u, env)
  end
  local decl = commands.find(g.command)
  if not decl then return commands.unknown(u, g.command) end
  if decl.name == "run" then return legacy_run(g.rest, out, err, env) end
  return dispatch(decl, g.rest, u, env)
end

M._report_json = report_json

return M
