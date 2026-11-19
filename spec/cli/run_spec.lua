-- hwc run (design §4.3, §4.4, §5.1-§5.3): one character per run, its
-- professions, progress on stderr and the summary on stdout.
local lfs = require("lfs")
local h = dofile("spec/helpers/cli_run.lua")
local tmpdir, fixture, files, only, env_at = h.tmpdir, h.fixture, h.files, h.only, h.env_at
local with_runner, read_json, capture = h.with_runner, h.read_json, h.capture

local cli = require("hwc.cli")

-- A clock that advances one second per read, so elapsed times are known.
local function ticking(start)
  local t = start or 1000
  return function() t = t + 1; return t end
end

-- Runs cli.main against the fixture folder with the fake runner; returns the
-- exit code, stdout, stderr and the runner calls.
local function play(args, opts)
  opts = opts or {}
  local outdir = opts.outdir or tmpdir()
  local argv = {}
  for _, a in ipairs(args) do argv[#argv + 1] = a end
  if not opts.no_out then
    for _, a in ipairs({ "--date", "2026-11-17", "--out", outdir }) do argv[#argv + 1] = a end
  end
  local env = opts.env or env_at(opts.root or fixture())
  env.clock = env.clock or ticking()
  local code, o, e
  local calls = with_runner(function(calls)
    local out, otext = capture()
    local err, etext = capture()
    code = cli.main(argv, out, err, env)
    o, e = otext(), etext()
    return calls
  end, opts.played, opts.jumps)
  return code, o, e, calls, outdir
end

-- Usage errors are checked before any folder is needed, so these need no runner.
local function usage(args, env)
  local out, otext = capture()
  local err, etext = capture()
  local code = cli.main(args, out, err, env or env_at(fixture()))
  return code, otext(), etext()
end

local DW = { "run", "--race", "dwarf", "--class", "warrior" }
local function dw(...)
  local args = {}
  for _, a in ipairs(DW) do args[#args + 1] = a end
  for _, a in ipairs({ ... }) do args[#args + 1] = a end
  return args
end

describe("hwc run: the character", function()
  it("plays Dwarf WARRIOR with no professions from lower-case flags", function()
    local code, _, err, calls, outdir = play(dw())
    assert.equal(0, code, err)
    assert.equal("Dwarf", calls[1].cfg.race)
    assert.equal("WARRIOR", calls[1].cfg.class)
    assert.same({}, calls[1].cfg.professions)
    assert.equal("file", lfs.attributes(only(outdir, "Dwarf-WARRIOR"), "mode"))
  end)

  it("plays the professions given, sorted, into the config and the file names", function()
    local code, _, err, calls, outdir = play(dw("--professions", "skinning,herbalism"))
    assert.equal(0, code, err)
    local professions = require("hwc.world.professions")
    assert.same(professions.skills({ "Herbalism", "Skinning" }), calls[1].cfg.professions)
    local path = only(outdir, "Dwarf-WARRIOR-herbalism-skinning")
    local stem = path:gsub("%.json$", "")
    assert.equal("file", lfs.attributes(stem .. "/Dwarf-WARRIOR-herbalism-skinning.json", "mode"))
    assert.same({ "Dwarf WARRIOR herbalism,skinning" }, read_json(path).header.matrix.combos)
  end)

  it("names a character with no professions without a professions part", function()
    local code, _, err, _, outdir = play(dw())
    assert.equal(0, code, err)
    local path = only(outdir, "Dwarf-WARRIOR")
    local stem = path:gsub("%.json$", "")
    assert.equal("file", lfs.attributes(stem .. "/Dwarf-WARRIOR.json", "mode"))
    assert.same({ "Dwarf WARRIOR none" }, read_json(path).header.matrix.combos)
  end)
end)

describe("hwc run: usage errors", function()
  it("refuses cooking with a hint", function()
    local code, out, err = usage(dw("--professions", "cooking"))
    assert.equal(2, code)
    assert.equal("", out)
    assert.equal("hwc: cooking is learned from Camping 101: Cooking; leave it out of --professions\n"
      .. "see hwc run --help\n", err)
  end)

  it("needs --race", function()
    local code, _, err = usage({ "run", "--class", "WARRIOR" })
    assert.equal(2, code)
    assert.equal("hwc: missing --race\nsee hwc run --help\n", err)
  end)

  it("needs --class", function()
    local code, _, err = usage({ "run", "--race", "Dwarf" })
    assert.equal(2, code)
    assert.equal("hwc: missing --class\nsee hwc run --help\n", err)
  end)

  it("names the race's classes when it can't play the class", function()
    local code, _, err = usage({ "run", "--race", "Gnome", "--class", "PALADIN" })
    assert.equal(2, code)
    assert.equal("hwc: Gnome can't be a PALADIN in Forever; Gnome classes: MAGE, PRIEST, ROGUE, WARLOCK, WARRIOR\n"
      .. "see hwc run --help\n", err)
  end)

  it("lists the races for a race outside the scope", function()
    local code, _, err = usage({ "run", "--race", "Goblin", "--class", "WARRIOR" })
    assert.equal(2, code)
    assert.matches("^hwc: %-%-race Goblin is not a race; races: ", err)
  end)

  it("rejects --variant as an unknown option, naming --professions", function()
    local code, _, err = usage(dw("--variant", "alch-herb"))
    assert.equal(2, code)
    assert.equal("hwc: unknown option --variant for hwc run; use --professions\nsee hwc run --help\n", err)
  end)

  it("rejects an unknown single-dash option", function()
    local code, _, err = usage(dw("-c"))
    assert.equal(2, code)
    assert.equal("hwc: unknown option -c for hwc run\nsee hwc run --help\n", err)
  end)

  for _, opt in ipairs({ "--out", "--relative-to" }) do
    it("rejects an empty " .. opt, function()
      for _, args in ipairs({ dw(opt, ""), dw(opt .. "=") }) do
        local code, _, err = usage(args)
        assert.equal(2, code)
        assert.equal("hwc: " .. opt .. " needs a value\nsee hwc run --help\n", err)
      end
    end)
  end

  for _, opt in ipairs({ "--addon", "--stop-level" }) do
    it(opt .. " is rejected as unknown", function()
      local code, _, err = usage(dw(opt, "/x"))
      assert.equal(2, code)
      assert.matches("unknown option " .. opt:gsub("%-", "%%-") .. " for hwc run", err)
    end)
  end

  -- Final review minor 8: a --date like ../x would change the write path.
  it("rejects a --date that is not YYYY-MM-DD", function()
    for _, d in ipairs({ "../x", "2026-11-1" }) do
      local code, _, err = usage(dw("--date", d))
      assert.equal(2, code)
      assert.equal("hwc: --date needs YYYY-MM-DD\nsee hwc run --help\n", err)
    end
  end)

  it("from a folder with no WoW-Pro folder exits 2", function()
    local code, _, err = usage(dw(), env_at(tmpdir()))
    assert.equal(2, code)
    assert.matches("no WoW%-Pro folder", err)
    assert.matches("see hwc run %-%-help\n$", err)
  end)

  it("an --include matching no guide exits 2", function()
    local code, _, err = usage(dw("--include", "*nope*"))
    assert.equal(2, code)
    assert.matches("%-%-include \"%*nope%*\" matches no guide", err)
  end)

  it("filters leaving no guide exit 2", function()
    local code, _, err = usage(dw("--exclude", "*"))
    assert.equal(2, code)
    assert.matches("no guide left after filters", err)
  end)

  it("a pattern outside the WoW-Pro folder exits 2", function()
    local code, _, err = usage(dw("--include", "/elsewhere/x.lua"))
    assert.equal(2, code)
    assert.matches("outside the WoW%-Pro folder", err)
  end)

  it("an unset HOME without --out exits 2", function()
    local root = fixture()
    local code, _, err = usage(dw(), { pwd = root, cwd = root, home = false })
    assert.equal(2, code)
    assert.equal("hwc: HOME is not set; pass --out DIR\nsee hwc run --help\n", err)
  end)
end)

describe("hwc run: progress and output", function()
  it("reports progress on stderr off a terminal and keeps it off stdout", function()
    local code, out, err = play(dw(), { played = function() return { "GA" } end, jumps = {} })
    assert.equal(0, code, err)
    assert.truthy(err:find("Dwarf Warrior · a (guide 1)\n", 1, true), err)
    assert.is_nil(out:find("guide 1", 1, true))
  end)

  it("off a terminal prints one progress line per guide, without level or time", function()
    local env = env_at(fixture())
    env.tty = false
    local code, _, err = play(dw(), { env = env, played = function() return { "GA", "GB" } end, jumps = {} })
    assert.equal(0, code, err)
    assert.truthy(err:find("^Dwarf Warrior · a %(guide 1%)\nDwarf Warrior · b %(guide 2%)\n"), err)
    assert.is_nil(err:find("level 5", 1, true), err)
  end)

  it("on a terminal redraws the progress line and clears it before the warnings", function()
    local env = env_at(fixture())
    env.tty = true
    env.width = 200
    local code, out, err = play(dw(), { env = env })
    assert.equal(0, code, err)
    assert.truthy(err:find("Dwarf Warrior · b %(guide 1%) · level 5 · 0:0%d\r\27%[Kwarning: "), err)
    -- Redrawn in place, never ended with a newline.
    assert.is_nil(err:find("0:0%d\n"))
    assert.is_nil(out:find("\27", 1, true))
  end)

  it("shows elapsed time from env.clock as M:SS on a terminal", function()
    local t = 0
    local env = env_at(fixture())
    env.tty = true
    env.width = 200
    -- 75 seconds pass between the start and every later read.
    env.clock = function() local now = t; t = 75; return now end
    local code, _, err = play(dw(), { env = env, played = function() return { "GA" } end, jumps = {} })
    assert.equal(0, code, err)
    assert.truthy(err:find("Dwarf Warrior · a (guide 1) · level 5 · 1:15\r", 1, true), err)
  end)

  it("labels progress with the professions", function()
    local code, _, err = play(dw("--professions", "herbalism,skinning"))
    assert.equal(0, code, err)
    assert.truthy(err:find("Dwarf Warrior (Herbalism, Skinning) · b (guide 1)\n", 1, true), err)
  end)

  it("-q prints only the wrote line on stdout and nothing on stderr", function()
    local code, out, err = play(dw("-q"))
    assert.equal(0, code)
    assert.equal("", err)
    assert.matches("^hwc: wrote [^\n]+%.html and [^\n]+%.json\n$", out)
  end)

  it("prints the summary and then the wrote line on stdout by default", function()
    local code, out, err, _, outdir = play(dw())
    assert.equal(0, code, err)
    local stem = only(outdir, "Dwarf-WARRIOR"):gsub("%.json$", "")
    local doc = read_json(stem .. ".json")
    local lines = require("hwc.cli.summary").lines(doc)
    assert.equal(table.concat(lines, "\n") .. "\nhwc: wrote " .. stem .. ".html and " .. stem .. ".json\n", out)
  end)

  it("routes the catalog's warnings through ui, so -q silences them", function()
    local function played(cfg)
      cfg.warn("no QuestieDB installed (absent); run hwc init")
      return { "GB" }
    end
    local code, _, err = play(dw(), { played = played })
    assert.equal(0, code, err)
    assert.truthy(err:find("warning: no QuestieDB installed (absent); run hwc init\n", 1, true), err)
    code, _, err = play(dw("-q"), { played = played })
    assert.equal(0, code)
    assert.equal("", err)
  end)

  it("prints the report's warnings on stderr", function()
    local code, _, err = play(dw())
    assert.equal(0, code, err)
    assert.truthy(err:find("warning: 1 guide entered under-levelled\n", 1, true), err)
  end)

  it("--verbose reports jumps, catalog sources and wall times on stderr", function()
    local code, out, err = play(dw("--verbose", "--exclude", "*/a.lua"))
    assert.equal(0, code, err)
    assert.truthy(err:find("jumped over GA (excluded)\n", 1, true), err)
    assert.truthy(err:find("catalog counts: ", 1, true), err)
    assert.truthy(err:find("wall time: 0:0%d total\n"), err)
    assert.truthy(err:find("wall time: 0:0%d b %(guide 1%)\n"), err)
    assert.is_nil(out:find("jumped", 1, true))
  end)

  it("leaves jumps out without --verbose", function()
    local code, _, err = play(dw("--exclude", "*/a.lua"))
    assert.equal(0, code, err)
    assert.is_nil(err:find("jumped", 1, true))
    assert.is_nil(err:find("wall time", 1, true))
  end)

  it("a harness failure is one line and exit 1", function()
    local html = require("hwc.findings.html")
    local real = html.template
    html.template = function() error("hwc: findings: cannot read the report template x", 0) end
    local ok, code, out, err = pcall(play, dw())
    html.template = real
    assert.is_true(ok, tostring(code))
    assert.equal(1, code)
    assert.equal("", out)
    assert.equal("hwc: findings: cannot read the report template x\n", err)
  end)
end)

describe("hwc run: filters and paths", function()
  it("--include and --exclude keep every occurrence in order", function()
    local root = fixture()
    local code, _, err, calls, outdir = play(dw("--exclude", "*", "--include", "*a.lua",
      "--exclude", "*/a.lua", "--include", "*b.lua"), { root = root })
    assert.equal(0, code, err)
    assert.same({ GB = true }, calls[1].opts.included)
    assert.equal(root, calls[1].cfg.addon_path)
    local hd = read_json(only(outdir, "Dwarf-WARRIOR-filtered")).header
    assert.same({
      { kind = "exclude", pattern = "*" }, { kind = "include", pattern = "*a.lua" },
      { kind = "exclude", pattern = "*/a.lua" }, { kind = "include", pattern = "*b.lua" },
    }, hd.filters)
    assert.same({ "GA" }, hd.jumped)
    assert.is_nil(hd.unreached)
  end)

  it("jumped leaves out guides passed after the last included guide", function()
    local code, _, err, _, outdir = play(dw("--exclude", "*/a.lua"), { jumps = {
      { from = "GA", passed = { "GA" }, to = "GB", level_before = 1, level_after = 1 },
      { from = "GB", passed = { "GC" }, to = nil, level_before = 1, level_after = 1 },
    } })
    assert.equal(0, code, err)
    assert.same({ "GA" }, read_json(only(outdir, "Dwarf-WARRIOR-filtered")).header.jumped)
  end)

  it("a run with no filters passes no included set and has no filter, unreached or played header", function()
    local code, _, err, calls, outdir = play(dw())
    assert.equal(0, code, err)
    assert.is_nil(calls[1].opts.included)
    local hd = read_json(only(outdir, "Dwarf-WARRIOR")).header
    assert.is_nil(hd.filters)
    assert.is_nil(hd.unreached)
    assert.is_nil(hd.played)
  end)

  it("header names included guides an --include matched that no log played", function()
    local code, _, err, _, outdir = play(dw("--include", "*a.lua", "--include", "*b.lua"))
    assert.equal(0, code, err)
    assert.same({ "GA" }, read_json(only(outdir, "Dwarf-WARRIOR-filtered")).header.unreached)
  end)

  it("a ./ pattern resolves from the starting folder", function()
    local root = fixture()
    local code, _, err, calls = play(dw("--exclude", "*", "--include", "./b.lua"),
      { env = env_at(root .. "/WoWPro_Leveling/Forever/Alliance") })
    assert.equal(0, code, err)
    assert.same({ GB = true }, calls[1].opts.included)
    assert.equal(root, calls[1].cfg.addon_path)
  end)

  -- Guide-filters final review 2: from a symlinked folder, paths are relative to
  -- the logical $PWD and the header's addon path is rewritten exactly once.
  it("a symlinked $PWD gives a clean relative WoW-Pro path in the header", function()
    local root, links = fixture(), tmpdir()
    local link = links .. "/AddOns"
    assert(os.execute("ln -s '" .. root .. "' '" .. link .. "'"))
    local env = { pwd = link .. "/WoWPro_Leveling", cwd = root .. "/WoWPro_Leveling", home = tmpdir() }
    local code, _, err, calls, outdir = play(dw(), { env = env })
    assert.equal(0, code, err)
    assert.equal(link, calls[1].cfg.addon_path)
    local hd = read_json(only(outdir, "Dwarf-WARRIOR")).header
    assert.equal("..", hd.addon.path)
    assert.equal("WoWPro_Leveling", hd.paths_relative_to)
  end)

  it("a relative --relative-to resolves from the logical $PWD", function()
    local root, links = fixture(), tmpdir()
    local link = links .. "/AddOns"
    assert(os.execute("ln -s '" .. root .. "' '" .. link .. "'"))
    local env = { pwd = link .. "/WoWPro_Leveling", cwd = root .. "/WoWPro_Leveling", home = tmpdir() }
    local code, _, err, _, outdir = play(dw("--relative-to", ".."), { env = env })
    assert.equal(0, code, err)
    local hd = read_json(only(outdir, "Dwarf-WARRIOR")).header
    assert.equal(".", hd.addon.path)
    assert.equal("AddOns", hd.paths_relative_to)
  end)

  -- Guide-filters final review 3: a run that plays no guide is a usage error,
  -- not an empty report.
  it("a filtered run reaching no included guide exits 2 and writes nothing", function()
    local outdir = tmpdir() .. "/x"
    local code, _, err = play(dw("--exclude", "*/a.lua"), { outdir = outdir, played = function() return {} end })
    assert.equal(2, code)
    assert.equal("hwc: Dwarf Warrior reaches no included guide\nsee hwc run --help\n", err:match("hwc: .*$"))
    assert.is_nil(lfs.attributes(outdir, "mode"))
  end)

  it("keeps both runs when the findings differ", function()
    local outdir = tmpdir()
    for _, g in ipairs({ "GB", "GC" }) do
      local code = play(dw(), { outdir = outdir, played = function() return { g } end })
      assert.equal(0, code)
    end
    assert.equal(2, #files(outdir, "%.json$"))
    assert.equal(2, #files(outdir, "%.html$"))
  end)

  it("--out defaults to $HOME/.hwc/findings", function()
    local home = tmpdir()
    local code, _, err = play(dw("--date", "2026-11-17"), { no_out = true, env = env_at(fixture(), home) })
    assert.equal(0, code, err)
    assert.equal("file", lfs.attributes(only(home .. "/.hwc/findings", "Dwarf-WARRIOR"), "mode"))
  end)

  it("writes format 2 JSON with guide levels and no markdown report", function()
    local code, _, err, _, outdir = play(dw())
    assert.equal(0, code, err)
    assert.same({}, files(outdir, "%.md$"))
    local doc = read_json(only(outdir, "Dwarf-WARRIOR"))
    local page = io.open(only(outdir, "Dwarf-WARRIOR", "html"), "rb"):read("*a")
    assert.same(doc, require("dkjson").decode(page:match('id="report">(.-)</script>')))
    assert.equal(2, doc.format)
    assert.equal(1, #doc.header.guides)
    local g = doc.header.guides[1]
    assert.equal("GB", g.gid)
    assert.equal("WoWPro_Leveling/b.lua", g.file)
    assert.same({ enter = 1, leave = 4, finished = false }, g.levels["Dwarf WARRIOR none"])
    assert.same({ { combo = "Dwarf WARRIOR none", rule = "enter-under" } }, g.flags)
    assert.is_nil(doc.header.stop)
    assert.equal("Dwarf-WARRIOR", doc.header.scope)
    assert.equal("Dwarf Warrior", doc.labels.combos["Dwarf WARRIOR none"])
    -- The client checkout's own state may add a line first: the level flag is the last.
    assert.equal("1 guide entered under-levelled", doc.header.warnings[#doc.header.warnings])
  end)

  it("writes neither file when the report template can't be read", function()
    local outdir = tmpdir()
    local html = require("hwc.findings.html")
    local real = html.template
    html.template = function() error("findings: cannot read the report template x", 0) end
    local ok, code, _, err = pcall(play, dw(), { outdir = outdir })
    html.template = real
    assert.is_true(ok, tostring(code))
    assert.equal(1, code)
    assert.matches("cannot read the report template", err)
    assert.same({}, files(outdir, "%.json$"))
    assert.same({}, files(outdir, "%.html$"))
  end)

  it("a filtered run's scope ends in -filtered", function()
    local code, out = play(dw("--exclude", "*/a.lua"))
    assert.equal(0, code)
    assert.matches("2026%-11%-17%-Dwarf%-WARRIOR%-filtered%-%x%x%x%x%x%x%x%x%.html", out)
  end)
end)

describe("cli output names", function()
  it("the wrote line names both files", function()
    assert.equal("hwc: wrote out/s.html and out/s.json\n", cli.wrote_line("out/s"))
  end)

  it("names the stem by date, scope and the findings hash", function()
    local group = require("hwc.findings.group")
    assert.equal("2026-11-17-s-" .. group.fnv1a32("{}\n"), cli.stem_name("2026-11-17", "s", "{}\n"))
  end)
end)
