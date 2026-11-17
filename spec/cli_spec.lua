local lfs = require("lfs")

local ADDON = os.getenv("HOME") .. "/Projects/WoW-Pro-Guides"
local present = lfs.attributes(ADDON .. "/WoWPro/WoWPro.toc", "mode") ~= nil

local REPO = lfs.currentdir()

local function tmpdir()
  local dir = os.tmpname()
  os.remove(dir)
  assert(lfs.mkdir(dir))
  return dir
end

local function write(path, text)
  os.execute("mkdir -p '" .. path:match("^(.*)/[^/]*$") .. "'")
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end

-- A small WoW-Pro folder: two Forever guides, GA (a.lua) then GB (b.lua).
local function fixture()
  local root = tmpdir()
  write(root .. "/WoWPro/WoWPro.toc", "## Interface: 11500\n")
  write(root .. "/WoWPro_Leveling/WoWPro_Leveling.toc", "## Title: x\nForever/Alliance/a.lua\nForever/Alliance/b.lua\n")
  write(root .. "/WoWPro_Leveling/Forever/Alliance/a.lua", "WoWPro:RegisterGuide('GA', 'Leveling')\n")
  write(root .. "/WoWPro_Leveling/Forever/Alliance/b.lua", "WoWPro:RegisterGuide('GB', 'Leveling')\n")
  return root
end

local function env_at(dir, home) return { pwd = dir, cwd = dir, home = home or tmpdir() } end

-- Replaces runner.character for one call of fn; each log plays `played(cfg)`
-- (default { "GB" }) and records one jump over GA.
local function with_runner(fn, played, jumps)
  local runner = require("hwc.driver.run")
  local real = runner.character
  local calls = {}
  runner.character = function(cfg, opts)
    calls[#calls + 1] = { cfg = cfg, opts = opts }
    return { character = { race = cfg.race, class = cfg.class, professions = {} }, rank = 2, steps = {},
      signals = {}, guides = played and played(cfg) or { "GB" },
      jumps = jumps or { { from = "GA", passed = { "GA" }, to = "GB", level_before = 1, level_after = 1 } },
      addon = { path = cfg.addon_path, git = false, version = "1.0" } }
  end
  local ok, res = pcall(fn, calls)
  runner.character = real
  assert(ok, res)
  return res
end

-- Replaces matrix.combos for one call of fn.
local function with_combos(combos, fn)
  local matrix = require("hwc.driver.matrix")
  local real = matrix.combos
  matrix.combos = function() return combos end
  local ok, res = pcall(fn)
  matrix.combos = real
  assert(ok, res)
  return res
end

local function read_json(path)
  local f = assert(io.open(path, "r"))
  local s = f:read("*a")
  f:close()
  return require("dkjson").decode(s)
end

local function capture()
  local buf = {}
  return { write = function(_, ...) for _, s in ipairs({ ... }) do buf[#buf + 1] = s end end },
    function() return table.concat(buf) end
end

describe("cli", function()
  local cli = require("hwc.cli")

  it("is requirable and prints help with status 0", function()
    local out, text = capture()
    assert.equal(0, cli.main({ "--help" }, out))
    assert.matches("boot", text())
  end)

  it("rejects unknown commands with status 2", function()
    local out, _ = capture()
    local err, etext = capture()
    assert.equal(2, cli.main({ "nope" }, out, err))
    assert.matches("Usage", etext())
  end)

  it("run without --class exits 2 with usage", function()
    local out, _ = capture()
    local err, etext = capture()
    assert.equal(2, cli.main({ "run", "--race", "Dwarf" }, out, err))
    assert.matches("Usage", etext())
    assert.matches("%-%-class", etext())
  end)

  it("run with an unknown variant exits 2", function()
    local out, _ = capture()
    local err, etext = capture()
    assert.equal(2, cli.main({ "run", "--class", "WARRIOR", "--variant", "nope" }, out, err))
    assert.matches("variant", etext())
  end)

  it("run with a race outside the scope exits 2", function()
    local out, _ = capture()
    local err, etext = capture()
    assert.equal(2, cli.main({ "run", "--race", "Orc", "--class", "WARRIOR" }, out, err))
    assert.matches("race not in scope", etext())
  end)

  -- Final review minor 8: a --date like ../x would change the write path.
  it("run and matrix reject a --date that is not YYYY-MM-DD with status 2", function()
    for _, args in ipairs({
      { "run", "--class", "WARRIOR", "--date", "../x" },
      { "matrix", "--date", "2026-11-1" },
    }) do
      local out, _ = capture()
      local err, etext = capture()
      assert.equal(2, cli.main(args, out, err))
      assert.matches("%-%-date", etext())
    end
  end)

  -- Final review minor 6: each command states its race default.
  it("USAGE states the per-command race defaults", function()
    local out, text = capture()
    cli.main({ "--help" }, out)
    assert.matches("boot default Human", text())
    assert.matches("run default Dwarf", text())
  end)

  it("run and matrix accept --relative-to (parsed as an option, so the race check is what fails)", function()
    for _, args in ipairs({
      { "run", "--class", "WARRIOR", "--race", "Orc", "--relative-to", "/x" },
      { "matrix", "--races", "Orc", "--relative-to", "/x" },
    }) do
      local out, _ = capture()
      local err, etext = capture()
      assert.equal(2, cli.main(args, out, err))
      assert.matches("race not in scope", etext())
      assert.is_nil(etext():match("unknown or incomplete"))
    end
  end)

  it("the wrote line names both files and pluralises the character count", function()
    assert.equal("hwc: wrote out/s.md and out/s.json (1 character)\n", cli.wrote_line("out/s", 1))
    assert.equal("hwc: wrote out/s.md and out/s.json (2 characters)\n", cli.wrote_line("out/s", 2))
  end)

  it("USAGE documents --relative-to", function()
    local out, text = capture()
    cli.main({ "--help" }, out)
    assert.matches("%-%-relative%-to DIR", text())
  end)

  -- Final review minor 7: no combos means no findings file, not an "Addon: nil" header.
  it("matrix with no combos exits 2 with a message and writes nothing", function()
    local matrix = require("hwc.driver.matrix")
    local real = matrix.combos
    matrix.combos = function() return {} end
    local out, _ = capture()
    local err, etext = capture()
    local dir = os.tmpname()
    os.remove(dir)
    local ok, status = pcall(cli.main, { "matrix", "--races", "Dwarf", "--out", dir }, out, err, env_at(fixture()))
    matrix.combos = real
    assert.is_true(ok, tostring(status))
    assert.equal(2, status)
    assert.matches("no combos", etext())
    assert.is_nil(lfs.attributes(dir, "mode"))
  end)

  it("matrix --races Orc exits 2 (race not in scope)", function()
    local out, _ = capture()
    local err, etext = capture()
    assert.equal(2, cli.main({ "matrix", "--races", "Orc" }, out, err))
    assert.matches("race not in scope", etext())
  end)

  local PIN_DIR = "local/questie/d57637f490c9dfcdbbc967dab47a8b0d8fe1b3cc"
  if present and lfs.attributes(PIN_DIR, "mode") == "directory" then
    it("quest prints the quest and its sources as sorted JSON", function()
      local out, text = capture()
      assert.equal(0, cli.main({ "quest", "282" }, out))
      local d = require("dkjson").decode(text())
      assert.equal(282, d.quest.id)
      assert.same({ 218 }, d.quest.pre_single)
      assert.is_true(d.sources.questie.present)
      assert.matches('"pre_single":%[218%]', text())
    end)

    it("quest reports an unknown id with status 1", function()
      local out, _ = capture()
      local err, etext = capture()
      assert.equal(1, cli.main({ "quest", "777777" }, out, err))
      assert.matches("777777", etext())
    end)
  else
    pending("quest command needs the addon checkout and pinned QuestieDB")
  end

  it("quest takes no --addon", function()
    local out, _ = capture()
    local err, _ = capture()
    assert.equal(2, cli.main({ "quest", "1", "--addon", "x" }, out, err))
  end)

  it("boot rejects --addon", function()
    local out, _ = capture()
    local err, etext = capture()
    assert.equal(2, cli.main({ "boot", "--addon", "/x" }, out, err))
    assert.matches("unknown or incomplete option: %-%-addon", etext())
  end)

  it("run from a folder with no WoW-Pro folder exits 2", function()
    local out, _ = capture()
    local err, etext = capture()
    local dir = tmpdir()
    assert.equal(2, cli.main({ "run", "--class", "WARRIOR" }, out, err, env_at(dir)))
    assert.matches("no WoW%-Pro folder", etext())
  end)

  for _, opt in ipairs({ "--addon", "--stop-level" }) do
    it(opt .. " is rejected as unknown", function()
      local out, _ = capture()
      local err, etext = capture()
      assert.equal(2, cli.main({ "run", "--class", "WARRIOR", opt, "/x" }, out, err))
      assert.matches("unknown or incomplete option: " .. opt:gsub("%-", "%%-"), etext())
    end)
  end

  it("an --include matching no guide exits 2", function()
    local out, _ = capture()
    local err, etext = capture()
    assert.equal(2, cli.main({ "run", "--class", "WARRIOR", "--include", "*nope*" }, out, err, env_at(fixture())))
    assert.matches("%-%-include \"%*nope%*\" matches no guide", etext())
  end)

  it("filters leaving no guide exit 2", function()
    local out, _ = capture()
    local err, etext = capture()
    assert.equal(2, cli.main({ "run", "--class", "WARRIOR", "--exclude", "*" }, out, err, env_at(fixture())))
    assert.matches("no guide left after filters", etext())
  end)

  it("a pattern outside the WoW-Pro folder exits 2", function()
    local out, _ = capture()
    local err, etext = capture()
    assert.equal(2, cli.main({ "run", "--class", "WARRIOR", "--include", "/elsewhere/x.lua" }, out, err,
      env_at(fixture())))
    assert.matches("outside the WoW%-Pro folder", etext())
  end)

  it("--include and --exclude keep every occurrence in order", function()
    local root, outdir = fixture(), tmpdir()
    local calls = with_runner(function(calls)
      local out, _ = capture()
      local err, etext = capture()
      assert.equal(0, cli.main({ "run", "--class", "WARRIOR", "--exclude", "*", "--include", "*a.lua",
        "--exclude", "*/a.lua", "--include", "*b.lua", "--date", "2026-11-17", "--out", outdir },
        out, err, env_at(root)), etext())
      return calls
    end)
    assert.same({ GB = true }, calls[1].opts.included)
    assert.equal(root, calls[1].cfg.addon_path)
    local h = read_json(outdir .. "/2026-11-17-Dwarf-WARRIOR-baseline-filtered.json").header
    assert.same({
      { kind = "exclude", pattern = "*" }, { kind = "include", pattern = "*a.lua" },
      { kind = "exclude", pattern = "*/a.lua" }, { kind = "include", pattern = "*b.lua" },
    }, h.filters)
    assert.same({ "GA" }, h.jumped)
    assert.is_nil(h.unreached)
  end)

  it("jumped leaves out guides passed after the last included guide", function()
    local outdir = tmpdir()
    with_runner(function()
      local out, _ = capture()
      assert.equal(0, cli.main({ "run", "--class", "WARRIOR", "--exclude", "*/a.lua", "--date", "2026-11-17",
        "--out", outdir }, out, nil, env_at(fixture())))
    end, nil, {
      { from = "GA", passed = { "GA" }, to = "GB", level_before = 1, level_after = 1 },
      { from = "GB", passed = { "GC" }, to = nil, level_before = 1, level_after = 1 },
    })
    local h = read_json(outdir .. "/2026-11-17-Dwarf-WARRIOR-baseline-filtered.json").header
    assert.same({ "GA" }, h.jumped)
  end)

  it("an unset HOME without --out exits 2", function()
    local root = fixture()
    local out, _ = capture()
    local err, etext = capture()
    assert.equal(2, cli.main({ "run", "--class", "WARRIOR" }, out, err, { pwd = root, cwd = root, home = false }))
    assert.matches("hwc: HOME is not set; pass %-%-out DIR", etext())
  end)

  it("a run with no filters passes no included set and no filter header", function()
    local outdir = tmpdir()
    local calls = with_runner(function(calls)
      local out, _ = capture()
      assert.equal(0, cli.main({ "run", "--class", "WARRIOR", "--date", "2026-11-17", "--out", outdir },
        out, nil, env_at(fixture())))
      return calls
    end)
    assert.is_nil(calls[1].opts.included)
    local h = read_json(outdir .. "/2026-11-17-Dwarf-WARRIOR-baseline.json").header
    assert.is_nil(h.filters)
    assert.is_nil(h.unreached)
  end)

  it("header names included guides an --include matched that no log played", function()
    local outdir = tmpdir()
    with_runner(function()
      local out, _ = capture()
      assert.equal(0, cli.main({ "run", "--class", "WARRIOR", "--include", "*a.lua", "--include", "*b.lua",
        "--date", "2026-11-17", "--out", outdir }, out, nil, env_at(fixture())))
    end)
    local h = read_json(outdir .. "/2026-11-17-Dwarf-WARRIOR-baseline-filtered.json").header
    assert.same({ "GA" }, h.unreached)
  end)

  it("a ./ pattern resolves from the starting folder", function()
    local root, outdir = fixture(), tmpdir()
    local start = root .. "/WoWPro_Leveling/Forever/Alliance"
    local calls = with_runner(function(calls)
      local out, _ = capture()
      local err, etext = capture()
      assert.equal(0, cli.main({ "run", "--class", "WARRIOR", "--exclude", "*", "--include", "./b.lua",
        "--date", "2026-11-17", "--out", outdir }, out, err, env_at(start)), etext())
      return calls
    end)
    assert.same({ GB = true }, calls[1].opts.included)
    assert.equal(root, calls[1].cfg.addon_path)
  end)

  -- Guide-filters final review 2: from a symlinked folder, paths are relative to
  -- the logical $PWD and the header's addon path is rewritten exactly once.
  it("a symlinked $PWD gives a clean relative WoW-Pro path in the header", function()
    local root, outdir, links = fixture(), tmpdir(), tmpdir()
    local link = links .. "/AddOns"
    assert(os.execute("ln -s '" .. root .. "' '" .. link .. "'"))
    local env = { pwd = link .. "/WoWPro_Leveling", cwd = root .. "/WoWPro_Leveling", home = tmpdir() }
    local calls = with_runner(function(calls)
      local out, _ = capture()
      local err, etext = capture()
      assert.equal(0, cli.main({ "run", "--class", "WARRIOR", "--date", "2026-11-17", "--out", outdir },
        out, err, env), etext())
      return calls
    end)
    assert.equal(link, calls[1].cfg.addon_path)
    local h = read_json(outdir .. "/2026-11-17-Dwarf-WARRIOR-baseline.json").header
    assert.equal("..", h.addon.path)
    assert.equal("WoWPro_Leveling", h.paths_relative_to)
  end)

  it("a relative --relative-to resolves from the logical $PWD", function()
    local root, outdir, links = fixture(), tmpdir(), tmpdir()
    local link = links .. "/AddOns"
    assert(os.execute("ln -s '" .. root .. "' '" .. link .. "'"))
    local env = { pwd = link .. "/WoWPro_Leveling", cwd = root .. "/WoWPro_Leveling", home = tmpdir() }
    with_runner(function()
      local out, _ = capture()
      local err, etext = capture()
      assert.equal(0, cli.main({ "run", "--class", "WARRIOR", "--date", "2026-11-17", "--out", outdir,
        "--relative-to", ".." }, out, err, env), etext())
    end)
    local h = read_json(outdir .. "/2026-11-17-Dwarf-WARRIOR-baseline.json").header
    assert.equal(".", h.addon.path)
    assert.equal("AddOns", h.paths_relative_to)
  end)

  -- Guide-filters final review 3: a single run that plays no guide is a usage
  -- error (matrix's rule), not an empty report.
  it("a filtered run reaching no included guide exits 2 and writes nothing", function()
    local outdir = tmpdir() .. "/x"
    with_runner(function()
      local out, _ = capture()
      local err, etext = capture()
      assert.equal(2, cli.main({ "run", "--class", "WARRIOR", "--exclude", "*/a.lua", "--date", "2026-11-17",
        "--out", outdir }, out, err, env_at(fixture())))
      assert.matches("hwc: Dwarf reaches no included guide", etext())
    end, function() return {} end)
    assert.is_nil(lfs.attributes(outdir, "mode"))
  end)

  -- Guide-filters final review 4: the header lists the guides played, first-seen order.
  it("header lists the guides played across logs in first-seen order", function()
    local outdir = tmpdir()
    with_combos({ { race = "Dwarf", class = "WARRIOR", variant = "baseline" },
      { race = "Gnome", class = "MAGE", variant = "baseline" } }, function()
      with_runner(function()
        local out, _ = capture()
        assert.equal(0, cli.main({ "matrix", "--races", "Dwarf,Gnome", "--exclude", "*/zz.lua", "--include",
          "*", "--date", "2026-11-17", "--out", outdir }, out, nil, env_at(fixture())))
      end, function(cfg) return cfg.race == "Gnome" and { "GA", "GB" } or { "GB" } end)
    end)
    local h = read_json(outdir .. "/2026-11-17-forever-alliance-dwarf-gnome-filtered.json").header
    assert.same({ "GB", "GA" }, h.played)
  end)

  it("a run with no filters has no played list", function()
    local outdir = tmpdir()
    with_runner(function()
      local out, _ = capture()
      assert.equal(0, cli.main({ "run", "--class", "WARRIOR", "--date", "2026-11-17", "--out", outdir },
        out, nil, env_at(fixture())))
    end)
    assert.is_nil(read_json(outdir .. "/2026-11-17-Dwarf-WARRIOR-baseline.json").header.played)
  end)

  it("matrix accepts repeated --race and merges --races, first-seen order", function()
    local matrix = require("hwc.driver.matrix")
    local real = matrix.combos
    local got, got_path
    matrix.combos = function(path, races) got_path, got = path, races; return {} end
    local root = fixture()
    local out, _ = capture()
    local err, _ = capture()
    local ok, status = pcall(cli.main, { "matrix", "--race", "Dwarf", "--races", "Gnome,Dwarf" }, out, err,
      env_at(root))
    matrix.combos = real
    assert.is_true(ok, tostring(status))
    assert.same({ "Dwarf", "Gnome" }, got)
    assert.equal(root, got_path)
  end)

  it("--out defaults to $HOME/.hwc/findings", function()
    local home = tmpdir()
    with_runner(function()
      local out, _ = capture()
      assert.equal(0, cli.main({ "run", "--class", "WARRIOR", "--date", "2026-11-17" }, out, nil,
        env_at(fixture(), home)))
    end)
    assert.equal("file", lfs.attributes(home .. "/.hwc/findings/2026-11-17-Dwarf-WARRIOR-baseline.md", "mode"))
  end)

  it("a filtered run's scope ends in -filtered and drops -1-25", function()
    local outdir = tmpdir()
    local text = with_runner(function()
      local out, text = capture()
      assert.equal(0, cli.main({ "run", "--class", "WARRIOR", "--exclude", "*/a.lua", "--date", "2026-11-17",
        "--out", outdir }, out, nil, env_at(fixture())))
      return text()
    end)
    assert.matches("2026%-11%-17%-Dwarf%-WARRIOR%-baseline%-filtered%.md", text)
  end)

  it("a filtered matrix scope is forever-alliance-<races>-filtered", function()
    local outdir = tmpdir()
    local text = with_combos({ { race = "Dwarf", class = "WARRIOR", variant = "baseline" } }, function()
      return with_runner(function()
        local out, text = capture()
        assert.equal(0, cli.main({ "matrix", "--race", "Dwarf", "--exclude", "*/a.lua", "--date", "2026-11-17",
          "--out", outdir }, out, nil, env_at(fixture())))
        return text()
      end)
    end)
    assert.matches("2026%-11%-17%-forever%-alliance%-dwarf%-filtered%.md", text)
    assert.is_nil(text:match("1%-25"))
  end)

  it("matrix names races that reach no included guide and skips their combos", function()
    local outdir = tmpdir()
    with_combos({ { race = "Dwarf", class = "WARRIOR", variant = "baseline" },
      { race = "Gnome", class = "MAGE", variant = "baseline" } }, function()
      with_runner(function()
        local out, _ = capture()
        assert.equal(0, cli.main({ "matrix", "--races", "Dwarf,Gnome", "--exclude", "*/a.lua", "--date",
          "2026-11-17", "--out", outdir }, out, nil, env_at(fixture())))
      end, function(cfg) return cfg.race == "Gnome" and {} or { "GB" } end)
    end)
    local h = read_json(outdir .. "/2026-11-17-forever-alliance-dwarf-gnome-filtered.json").header
    assert.same({ "Gnome" }, h.skipped_races)
    assert.same({ "Dwarf WARRIOR baseline" }, h.matrix.combos)
    assert.is_nil(lfs.attributes(outdir .. "/2026-11-17-forever-alliance-dwarf-gnome-filtered/Gnome-MAGE-baseline.json"))
  end)

  it("matrix exits 2 when no race reaches an included guide", function()
    local outdir = tmpdir() .. "/x"
    with_combos({ { race = "Gnome", class = "MAGE", variant = "baseline" } }, function()
      with_runner(function()
        local out, _ = capture()
        local err, etext = capture()
        assert.equal(2, cli.main({ "matrix", "--races", "Gnome", "--exclude", "*/a.lua", "--date", "2026-11-17",
          "--out", outdir }, out, err, env_at(fixture())))
        assert.matches("hwc: matrix: no race reaches an included guide", etext())
      end, function() return {} end)
    end)
    assert.is_nil(lfs.attributes(outdir, "mode"))
  end)

  it("USAGE lists the filter options and drops --addon and --stop-level", function()
    local out, text = capture()
    cli.main({ "--help" }, out)
    assert.matches("%-%-include P / %-%-exclude P", text())
    assert.matches('README "Choosing guides"', text())
    assert.is_nil(text():match("%-%-addon"))
    assert.is_nil(text():match("%-%-stop%-level"))
  end)

  it("quest requires a numeric id", function()
    local out, _ = capture()
    local err, etext = capture()
    assert.equal(2, cli.main({ "quest", "abc" }, out, err))
    assert.matches("Usage", etext())
  end)

  if present then
    it("boot prints the addon identity, guide and first steps", function()
      local out, text = capture()
      assert.equal(0, cli.main({ "boot", "--race", "Dwarf", "--class", "WARRIOR" }, out, nil, env_at(ADDON)))
      local t = text()
      assert.matches("commit: %x+", t)
      assert.matches("ClassicDunMorogh0112", t)
      assert.matches("A Dwarven Outfitters", t)
    end)

    it("boot --json emits a decodable result", function()
      local out, text = capture()
      assert.equal(0, cli.main({ "boot", "--race", "Gnome", "--class", "MAGE", "--json" }, out, nil, env_at(ADDON)))
      local r = require("dkjson").decode(text())
      assert.equal("ClassicDunMorogh0112", r.guide.gid)
      assert.equal(40, #r.addon.commit)
    end)
  else
    pending("addon checkout absent at " .. ADDON)
  end
end)

describe("cli determinism", function()
  if not present then
    pending("addon checkout absent at " .. ADDON)
    return
  end
  it("boot --json is byte-identical across separate processes", function()
    local function run()
      local p = assert(io.popen("cd '" .. ADDON .. "' && '" .. REPO .. "/bin/hwc' boot --race Dwarf --class WARRIOR --json 2>&1"))
      local s = p:read("*a")
      p:close()
      return s
    end
    local a, b = run(), run()
    assert.is_true(#a > 100)
    assert.equal(a, b)
  end)
end)

describe("cli JSON output for a folder without git", function()
  local json = require("hwc.json")
  local cli = require("hwc.cli")
  local addon = { git = false, version = "9.9.9", path = "AddOns", dirty = false }

  it("boot --json encodes branch and commit as null and keeps memory nil", function()
    local boot = { is_harness_error = function() return false end }
    local r = { addon = addon, errors = {}, skipped = {}, files_failed = {}, missing_order = {},
      standin_calls = {}, guide = {}, steps = {}, settle = {} }
    local text = json.encode(cli._json_result(r, boot))
    assert.truthy(text:find('"branch":null', 1, true))
    assert.truthy(text:find('"commit":null', 1, true))
    assert.truthy(text:find('"version":"9.9.9"', 1, true))
    assert.is_nil(addon.branch)
    assert.is_nil(addon.commit)
  end)

  it("report JSON encodes branch and commit as null and keeps memory nil", function()
    local rep = { header = { addon = addon }, findings = {} }
    local text = json.encode(cli._report_json(rep))
    assert.truthy(text:find('"branch":null', 1, true))
    assert.truthy(text:find('"commit":null', 1, true))
    assert.is_nil(addon.branch)
    assert.is_nil(addon.commit)
  end)
end)
