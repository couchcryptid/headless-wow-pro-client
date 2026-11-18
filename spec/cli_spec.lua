local lfs = require("lfs")

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

-- Findings file names end in a content hash; these find them without knowing it.
local function files(dir, pattern)
  local found = {}
  for name in lfs.dir(dir) do
    if name:match(pattern) then found[#found + 1] = dir .. "/" .. name end
  end
  table.sort(found)
  return found
end

-- The one findings file for `scope` on the test date; ext is "json" or "html".
local function only(dir, scope, ext)
  ext = ext or "json"
  local pattern = "^2026%-11%-17%-" .. scope:gsub("%-", "%%-") .. "%-%x%x%x%x%x%x%x%x%." .. ext .. "$"
  local found = files(dir, pattern)
  assert.equal(1, #found, "expected one " .. ext .. " for " .. scope .. " in " .. dir)
  return found[1]
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
    assert.equal(2, cli.main({ "run", "--race", "Goblin", "--class", "WARRIOR" }, out, err))
    assert.matches("race not in scope", etext())
  end)

  -- Final review minor 8: a --date like ../x would change the write path.
  it("run rejects a --date that is not YYYY-MM-DD with status 2", function()
    for _, args in ipairs({
      { "run", "--class", "WARRIOR", "--date", "../x" },
      { "run", "--class", "WARRIOR", "--date", "2026-11-1" },
    }) do
      local out, _ = capture()
      local err, etext = capture()
      assert.equal(2, cli.main(args, out, err))
      assert.matches("%-%-date", etext())
    end
  end)

  it("run accepts --relative-to (parsed as an option, so the race check is what fails)", function()
    for _, args in ipairs({
      { "run", "--class", "WARRIOR", "--race", "Goblin", "--relative-to", "/x" },
    }) do
      local out, _ = capture()
      local err, etext = capture()
      assert.equal(2, cli.main(args, out, err))
      assert.matches("race not in scope", etext())
      assert.is_nil(etext():match("unknown or incomplete"))
    end
  end)

  it("the wrote line names both files and pluralises the character count", function()
    assert.equal("hwc: wrote out/s.html and out/s.json (1 character)\n", cli.wrote_line("out/s", 1))
    assert.equal("hwc: wrote out/s.html and out/s.json (2 characters)\n", cli.wrote_line("out/s", 2))
  end)

  it("run exits 2 for a class the race can't play in Forever", function()
    local out, _ = capture()
    local err, etext = capture()
    assert.equal(2, cli.main({ "run", "--race", "Tauren", "--class", "MAGE" }, out, err))
    assert.matches("Tauren can't be a MAGE in Forever", etext())
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
    local h = read_json(only(outdir, "Dwarf-WARRIOR-baseline-filtered")).header
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
    local h = read_json(only(outdir, "Dwarf-WARRIOR-baseline-filtered")).header
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
    local h = read_json(only(outdir, "Dwarf-WARRIOR-baseline")).header
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
    local h = read_json(only(outdir, "Dwarf-WARRIOR-baseline-filtered")).header
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
    local h = read_json(only(outdir, "Dwarf-WARRIOR-baseline")).header
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
    local h = read_json(only(outdir, "Dwarf-WARRIOR-baseline")).header
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

  it("a run with no filters has no played list", function()
    local outdir = tmpdir()
    with_runner(function()
      local out, _ = capture()
      assert.equal(0, cli.main({ "run", "--class", "WARRIOR", "--date", "2026-11-17", "--out", outdir },
        out, nil, env_at(fixture())))
    end)
    assert.is_nil(read_json(only(outdir, "Dwarf-WARRIOR-baseline")).header.played)
  end)

  it("names the stem by date, scope and the findings hash", function()
    local group = require("hwc.findings.group")
    assert.equal("2026-11-17-s-" .. group.fnv1a32("{}\n"), cli.stem_name("2026-11-17", "s", "{}\n"))
  end)

  it("keeps both runs when the findings differ", function()
    local outdir = tmpdir()
    for _, g in ipairs({ "GB", "GC" }) do
      with_runner(function()
        local out, _ = capture()
        assert.equal(0, cli.main({ "run", "--class", "WARRIOR", "--date", "2026-11-17", "--out", outdir }, out, nil,
          env_at(fixture())))
      end, function() return { g } end)
    end
    assert.equal(2, #files(outdir, "%.json$"))
    assert.equal(2, #files(outdir, "%.html$"))
  end)

  it("writes run logs under the hashed stem", function()
    local outdir = tmpdir()
    local text = with_runner(function()
      local out, text = capture()
      assert.equal(0, cli.main({ "run", "--class", "WARRIOR", "--date", "2026-11-17", "--out", outdir }, out, nil,
        env_at(fixture())))
      return text()
    end)
    local stem = only(outdir, "Dwarf-WARRIOR-baseline"):gsub("%.json$", "")
    assert.matches(stem .. ".html", text, 1, true)
    assert.equal("file", lfs.attributes(stem .. "/Dwarf-WARRIOR-baseline.json", "mode"))
  end)

  it("--out defaults to $HOME/.hwc/findings", function()
    local home = tmpdir()
    with_runner(function()
      local out, _ = capture()
      assert.equal(0, cli.main({ "run", "--class", "WARRIOR", "--date", "2026-11-17" }, out, nil,
        env_at(fixture(), home)))
    end)
    assert.equal("file", lfs.attributes(only(home .. "/.hwc/findings", "Dwarf-WARRIOR-baseline"), "mode"))
  end)

  it("writes format 2 JSON with guide levels and no markdown report", function()
    local outdir = tmpdir()
    with_runner(function()
      local out, _ = capture()
      assert.equal(0, cli.main({ "run", "--class", "WARRIOR", "--date", "2026-11-17", "--out", outdir }, out, nil,
        env_at(fixture())))
    end)
    assert.same({}, files(outdir, "%.md$"))
    local doc = read_json(only(outdir, "Dwarf-WARRIOR-baseline"))
    local page = io.open(only(outdir, "Dwarf-WARRIOR-baseline", "html"), "rb"):read("*a")
    assert.same(doc, require("dkjson").decode(page:match('id="report">(.-)</script>')))
    assert.equal(2, doc.format)
    assert.equal(1, #doc.header.guides)
    local g = doc.header.guides[1]
    assert.equal("GB", g.gid)
    assert.equal("WoWPro_Leveling/b.lua", g.file)
    assert.same({ enter = 1, leave = 4, finished = false }, g.levels["Dwarf WARRIOR none"])
    assert.same({ { combo = "Dwarf WARRIOR none", rule = "enter-under" } }, g.flags)
    assert.is_nil(doc.header.stop)
    assert.equal("Dwarf Warrior", doc.labels.combos["Dwarf WARRIOR none"])
    -- The client checkout's own state may add a line first: the level flag is the last.
    assert.equal("1 guide entered under-levelled", doc.header.warnings[#doc.header.warnings])
  end)

  it("writes neither file when the report template can't be read", function()
    local outdir = tmpdir()
    local html = require("hwc.findings.html")
    local real = html.template
    html.template = function() error("findings: cannot read the report template x", 0) end
    local status, etext
    local ok, perr = pcall(with_runner, function()
      local out, _ = capture()
      local err, text = capture()
      status = cli.main({ "run", "--class", "WARRIOR", "--date", "2026-11-17", "--out", outdir }, out, err,
        env_at(fixture()))
      etext = text()
    end)
    html.template = real
    assert.is_true(ok, tostring(perr))
    assert.equal(1, status)
    assert.matches("cannot read the report template", etext)
    assert.same({}, files(outdir, "%.json$"))
    assert.same({}, files(outdir, "%.html$"))
  end)

  it("a filtered run's scope ends in -filtered and drops -1-25", function()
    local outdir = tmpdir()
    local text = with_runner(function()
      local out, text = capture()
      assert.equal(0, cli.main({ "run", "--class", "WARRIOR", "--exclude", "*/a.lua", "--date", "2026-11-17",
        "--out", outdir }, out, nil, env_at(fixture())))
      return text()
    end)
    assert.matches("2026%-11%-17%-Dwarf%-WARRIOR%-baseline%-filtered%-%x%x%x%x%x%x%x%x%.html", text)
  end)
end)
