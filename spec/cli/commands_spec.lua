-- The declaration-driven dispatcher and every command but run (design §4).
local lfs = require("lfs")
local cli = require("hwc.cli")

local ADDON = os.getenv("HOME") .. "/Projects/WoW-Pro-Guides"
local present = lfs.attributes(ADDON .. "/WoWPro/WoWPro.toc", "mode") ~= nil

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

local function capture()
  local buf = {}
  return { write = function(_, ...) for _, s in ipairs({ ... }) do buf[#buf + 1] = s end end },
    function() return table.concat(buf) end
end

local function env_at(dir, home) return { pwd = dir, cwd = dir, home = home or tmpdir(), hwc_home = false } end

-- Runs hwc from an empty folder: code, stdout, stderr.
local function run(args, env)
  local out, text = capture()
  local err, etext = capture()
  local code = cli.main(args, out, err, env or env_at(tmpdir()))
  return code, text(), etext()
end

-- Replaces mod[name] with stub for one call of fn, then restores it.
local function with_stub(mod, name, stub, fn)
  local real = mod[name]
  mod[name] = stub
  local ok, res = pcall(fn)
  mod[name] = real
  assert(ok, res)
  return res
end

local function lines(text)
  local out = {}
  for l in text:gmatch("([^\n]*)\n") do out[#out + 1] = l end
  return out
end

describe("hwc dispatcher", function()
  it("a bare hwc prints the usage to stdout and exits 0, without the stubs", function()
    local code, out, err = run({})
    assert.equal(0, code)
    assert.equal("", err)
    assert.equal("Usage: hwc", out:sub(1, 10))
    assert.is_nil(out:find("boot", 1, true))
    assert.is_nil(out:find("matrix", 1, true))
    assert.truthy(out:find("\n  run ", 1, true))
  end)

  it("--help and help print the same usage", function()
    local _, a = run({ "--help" })
    local _, b = run({ "help" })
    local _, c = run({})
    assert.equal(c, a)
    assert.equal(c, b)
  end)

  for _, args in ipairs({ { "--version" }, { "version" }, { "diff", "--version" } }) do
    it("hwc " .. table.concat(args, " ") .. " prints the version", function()
      local code, out = run(args)
      assert.equal(0, code)
      local ok = out:match("^hwc v?%S+ %(%x+%)") or out:match("^hwc unreleased") or out:match("^hwc unknown version")
      assert.truthy(ok, out)
    end)
  end

  it("help run and run --help print the same command help from any folder", function()
    local code, a, err = run({ "help", "run" })
    assert.equal(0, code)
    assert.equal("", err)
    local code2, b = run({ "run", "--help" })
    assert.equal(0, code2)
    assert.equal(a, b)
    assert.equal("Usage: hwc run", a:sub(1, 14))
  end)

  it("help diff prints diff's options and exit codes", function()
    local code, out = run({ "diff", "-h" })
    assert.equal(0, code)
    assert.equal("Usage: hwc diff", out:sub(1, 15))
    assert.truthy(out:find("--json", 1, true))
  end)

  it("an unknown command suggests the nearest visible one", function()
    local code, out, err = run({ "rnu" })
    assert.equal(2, code)
    assert.equal("", out)
    assert.equal("hwc: unknown command: hwc rnu (did you mean run?)\nsee hwc --help\n", err)
  end)

  it("never suggests a stub", function()
    local code, _, err = run({ "bot" })
    assert.equal(2, code)
    assert.is_nil(err:find("boot", 1, true))
    assert.equal("hwc: unknown command: hwc bot\nsee hwc --help\n", err)
  end)

  it("help of an unknown command is the unknown-command error", function()
    local code, _, err = run({ "help", "rnu" })
    assert.equal(2, code)
    assert.equal("hwc: unknown command: hwc rnu (did you mean run?)\nsee hwc --help\n", err)
  end)

  it("a usage error names the command's help", function()
    local code, _, err = run({ "doctor", "--bogus" })
    assert.equal(2, code)
    assert.equal("hwc: unknown option --bogus for hwc doctor\nsee hwc doctor --help\n", err)
  end)

  local STUBS = {
    { { "boot", "--race", "x" }, "hwc boot was removed; hwc doctor checks that the addon loads\n" },
    { { "matrix", "--races", "Dwarf" }, "hwc matrix was removed; hwc run plays one character \226\128\148 see hwc help run\n" },
    { { "sync", "questie", "--tag", "v1" }, "hwc sync questie is now hwc update\n" },
    { { "boot", "--help" }, "hwc boot was removed; hwc doctor checks that the addon loads\n" },
    { { "help", "sync" }, "hwc sync questie is now hwc update\n" },
  }
  for _, case in ipairs(STUBS) do
    it("hwc " .. table.concat(case[1], " ") .. " is a stub that exits 2", function()
      local code, out, err = run(case[1])
      assert.equal(2, code)
      assert.equal("", out)
      assert.equal(case[2], err)
    end)
  end

  it("a Lua error escaping a handler exits 1 with one hwc: line", function()
    local doctor = require("hwc.doctor")
    local r = with_stub(doctor, "run", function() error("hwc: boom", 0) end,
      function() return { run({ "doctor" }) } end)
    assert.equal(1, r[1])
    assert.equal("hwc: boom\n", r[3])
  end)
end)

describe("hwc version", function()
  local version = require("hwc.cli.version")

  it("formats a tag, an untagged checkout and a non-git folder", function()
    assert.equal("hwc v1.1.0 (45c3198)\n",
      version.text({ git = true, describe = "v1.1.0", commit = "45c3198abc", dirty = false }))
    assert.equal("hwc v1.1.0 (45c3198) (dirty)\n",
      version.text({ git = true, describe = "v1.1.0", commit = "45c3198abc", dirty = true }))
    assert.equal("hwc unreleased (45c3198)\n", version.text({ git = true, commit = "45c3198abc", dirty = false }))
    assert.equal("hwc unknown version\n", version.text({ git = false }))
  end)
end)

describe("hwc list", function()
  it("races: one token per line, sorted", function()
    local code, out = run({ "list", "races" })
    assert.equal(0, code)
    local l = lines(out)
    assert.equal(10, #l)
    assert.equal("Dwarf", l[1])
    assert.equal("Undead", l[#l])
    local sorted = {}
    for i, v in ipairs(l) do sorted[i] = v end
    table.sort(sorted)
    assert.same(sorted, l)
  end)

  it("classes RACE: the race's classes, any case", function()
    local code, out = run({ "list", "classes", "gnome" })
    assert.equal(0, code)
    assert.same({ "MAGE", "PRIEST", "ROGUE", "WARLOCK", "WARRIOR" }, lines(out))
  end)

  it("classes without a race, or a bad race, is a usage error", function()
    local code, _, err = run({ "list", "classes" })
    assert.equal(2, code)
    assert.equal("hwc: hwc list classes needs a race\nsee hwc list --help\n", err)
    code, _, err = run({ "list", "classes", "Goblin" })
    assert.equal(2, code)
    assert.matches("^hwc: Goblin is not a race; races: Dwarf, Gnome", err)
  end)

  it("an unknown form is a usage error", function()
    local code, _, err = run({ "list", "spells" })
    assert.equal(2, code)
    assert.matches("^hwc: [^\n]*spells", err)
    assert.matches("see hwc list %-%-help\n$", err)
  end)

  it("professions: 9 primaries then first-aid and fishing, no cooking", function()
    local code, out = run({ "list", "professions" })
    assert.equal(0, code)
    local l = lines(out)
    assert.equal(11, #l)
    assert.equal("alchemy", l[1])
    assert.equal("first-aid", l[10])
    assert.equal("fishing", l[11])
    assert.is_nil(out:find("cooking", 1, true))
  end)

  it("a bare list prints the table", function()
    local code, out = run({ "list" })
    assert.equal(0, code)
    for _, s in ipairs({ "Dwarf", "Alliance", "herbalism", "first-aid", "Cooking is learned from Camping 101: Cooking" }) do
      assert.truthy(out:find(s, 1, true), s)
    end
  end)
end)

describe("hwc init, doctor and update", function()
  local install = require("hwc.questie.install")
  local doctor = require("hwc.doctor")

  local function store_run(args, env)
    return run(args, env or { home = tmpdir(), hwc_home = false, pwd = "/", cwd = "/" })
  end

  it("rejects bad flags with status 2", function()
    assert.equal(2, (store_run({ "doctor", "--bogus" })))
    assert.equal(2, (store_run({ "update", "--bogus" })))
    local code, _, err = store_run({ "update", "--tag" })
    assert.equal(2, code)
    assert.equal("hwc: --tag needs a value\nsee hwc update --help\n", err)
    assert.equal(2, (store_run({ "init", "x" })))
  end)

  it("exits 2 when HOME and HWC_HOME are both unset", function()
    for _, args in ipairs({ { "init" }, { "doctor" }, { "update" } }) do
      local code, _, err = store_run(args, { home = false, hwc_home = false, pwd = "/", cwd = "/" })
      assert.equal(2, code)
      assert.truthy(err:find("hwc: HOME is not set; set HWC_HOME", 1, true))
    end
  end)

  it("update passes --tag through to the installer", function()
    local seen
    local code = with_stub(install, "sync", function(_, opts)
      seen = opts
      return { to = "v1.1.3", build = "e1652ce0123", skipped = {} }
    end, function() return (store_run({ "update", "--tag", "v1.1.3" })) end)
    assert.equal(0, code)
    assert.equal("v1.1.3", seen.tag)
  end)

  it("update prints the change, the skipped releases and the already line", function()
    local r = with_stub(install, "sync", function()
      return { to = "v1.1.2", build = "e1652ce0123", skipped = { "v1.1.3" } }
    end, function() local c, o = store_run({ "update" }); return { c, o } end)
    assert.equal(0, r[1])
    assert.equal("QuestieDB none \226\134\146 v1.1.2 (build e1652ce)\nskipped v1.1.3: no Forever build\n", r[2])
    r = with_stub(install, "sync", function() return { to = "v1.1.2", already = true, skipped = {} } end,
      function() local c, o = store_run({ "update" }); return { c, o } end)
    assert.equal("QuestieDB v1.1.2 already installed; active\n", r[2])
  end)

  it("update failure exits 1 with the error", function()
    local r = with_stub(install, "sync", function() return nil, "hwc: no network" end,
      function() local c, _, e = store_run({ "update" }); return { c, e } end)
    assert.equal(1, r[1])
    assert.equal("hwc: no network\n", r[2])
  end)

  it("doctor exits 1 when the report failed, 0 otherwise", function()
    local function doctor_with(report, args)
      return with_stub(doctor, "run", function() return report end,
        function() local c, o = store_run(args); return { c, o } end)
    end
    local bad = doctor_with({ checks = { { id = "luajit", status = "fail", detail = "x" } }, failed = true }, { "doctor" })
    assert.equal(1, bad[1])
    assert.truthy(bad[2]:find("FAIL luajit: x", 1, true))
    local good = doctor_with({ checks = { { id = "luajit", status = "ok", detail = "y" } }, failed = false },
      { "doctor", "--json" })
    assert.equal(0, good[1])
    assert.truthy(good[2]:find('"failed":false', 1, true))
  end)

  it("init prints the sync line then the doctor report", function()
    local r = with_stub(install, "init", function()
      return { already = false, sync_result = { to = "v1.1.2", build = "e1652ce0123", skipped = {} } }
    end, function()
      return with_stub(doctor, "run", function()
        return { checks = { { id = "luajit", status = "ok", detail = "fine" } }, failed = false }
      end, function() local c, o = store_run({ "init" }); return { c, o } end)
    end)
    assert.equal(0, r[1])
    assert.equal("QuestieDB none \226\134\146 v1.1.2 (build e1652ce)\nok   luajit: fine\n", r[2])
  end)
end)

describe("hwc quest", function()
  it("requires one numeric id", function()
    local code, _, err = run({ "quest", "abc" })
    assert.equal(2, code)
    assert.equal("hwc: quest needs a numeric id\nsee hwc quest --help\n", err)
    code, _, err = run({ "quest" })
    assert.equal(2, code)
    assert.equal("hwc: quest needs 1 id, got 0\nsee hwc quest --help\n", err)
  end)

  it("takes no --addon", function()
    local code, _, err = run({ "quest", "1", "--addon", "x" })
    assert.equal(2, code)
    assert.matches("unknown option %-%-addon for hwc quest", err)
  end)

  local qhome = require("hwc.questie.home")
  local installed = qhome.active_dir(qhome.root()) ~= nil
  if present and installed then
    it("prints the quest and its sources as sorted JSON", function()
      local code, out = run({ "quest", "282" })
      assert.equal(0, code)
      local d = require("dkjson").decode(out)
      assert.equal(282, d.quest.id)
      assert.same({ 218 }, d.quest.pre_single)
      assert.is_true(d.sources.questie.present)
      assert.matches('"pre_single":%[218%]', out)
    end)

    it("reports an unknown id with status 1", function()
      local code, _, err = run({ "quest", "777777" })
      assert.equal(1, code)
      assert.equal("hwc: quest 777777 is in no catalog source\n", err)
    end)
  else
    pending(installed and "quest command needs the addon checkout" or "no QuestieDB installed: run hwc init")
  end
end)

describe("hwc diff", function()
  local jsonlib = require("hwc.json")
  local DWARF, GNOME = "Dwarf WARRIOR none", "Gnome MAGE none"

  local function doc(findings, header)
    local h = {
      addon = { git = true, branch = "main", commit = "aaaaaaa", dirty = false },
      catalog = { questie = { tag = "v1.1.2", build = "e1652ce" }, supplement = { present = false } },
      client = { commit = "c1" },
      matrix = { combos = { DWARF, GNOME } },
      paths_relative_to = "WoW-Pro-Guides",
    }
    for k, v in pairs(header or {}) do h[k] = v end
    return { format = 2, header = h, findings = findings or {} }
  end

  local function finding(id)
    return {
      id = id, combos = { DWARF }, severity = "high", signal = "never-shown-accept",
      title = id, file = "WoWPro_Leveling/Forever/Alliance/01_12_Dun_Morogh.lua", line = 10,
    }
  end

  local function put(dir, name, d)
    local path = dir .. "/" .. name
    write(path, type(d) == "string" and d or jsonlib.encode(d))
    return path
  end

  it("exits 0 and prints the summary when nothing is new", function()
    local dir = tmpdir()
    local a = put(dir, "a.json", doc({ finding("F-1") }))
    local b = put(dir, "b.json", doc({ finding("F-1") }))
    local code, out = run({ "diff", a, b })
    assert.equal(0, code)
    assert.matches("no changes", out)
  end)

  it("exits 1 when NEW has a new finding", function()
    local dir = tmpdir()
    local a = put(dir, "a.json", doc({}))
    local b = put(dir, "b.json", doc({ finding("F-2") }))
    local code, out = run({ "diff", a, b })
    assert.equal(1, code)
    assert.matches("F%-2", out)
  end)

  it("prints the result as JSON with --json", function()
    local dir = tmpdir()
    local a = put(dir, "a.json", doc({}))
    local b = put(dir, "b.json", doc({}))
    local code, out = run({ "diff", a, b, "--json" })
    assert.equal(0, code)
    local r = require("dkjson").decode(out)
    for _, k in ipairs({ "counts", "warnings", "fixed", "new", "partly_fixed", "spread" }) do
      assert.is_not_nil(r[k], k)
    end
    assert.matches('"new":%[%]', out)
  end)

  it("accepts --json before or after the paths", function()
    local dir = tmpdir()
    local a = put(dir, "a.json", doc({}))
    local b = put(dir, "b.json", doc({}))
    local _, after = run({ "diff", a, b, "--json" })
    local _, before = run({ "diff", "--json", a, b })
    assert.equal(after, before)
    assert.matches('"counts"', before)
  end)

  it("exits 2 naming a missing file", function()
    local dir = tmpdir()
    local a = put(dir, "a.json", doc({}))
    local code, _, err = run({ "diff", a, dir .. "/nope.json" })
    assert.equal(2, code)
    assert.matches("^hwc: cannot read .*/nope.json\nsee hwc diff %-%-help\n$", err)
  end)

  it("exits 2 with cannot read for a directory", function()
    local dir = tmpdir()
    local a = put(dir, "a.json", doc({}))
    local code, _, err = run({ "diff", a, dir })
    assert.equal(2, code)
    assert.equal("hwc: cannot read " .. dir .. "\nsee hwc diff --help\n", err)
  end)

  it("exits 2 for a .html path, any case, with a hint", function()
    local dir = tmpdir()
    local a = put(dir, "a.json", doc({}))
    for _, name in ipairs({ "b.html", "x.HTML" }) do
      local h = put(dir, name, "<html></html>")
      local code, _, err = run({ "diff", a, h })
      assert.equal(2, code)
      assert.matches("use the %.json beside it", err)
    end
  end)

  it("exits 2 for invalid JSON and for no shared characters", function()
    local dir = tmpdir()
    local a = put(dir, "a.json", doc({}))
    local bad = put(dir, "bad.json", "{not json")
    local code, _, err = run({ "diff", a, bad })
    assert.equal(2, code)
    assert.matches("not valid JSON", err)
    local scalar = put(dir, "scalar.json", "42")
    code, _, err = run({ "diff", a, scalar })
    assert.equal(2, code)
    assert.matches("not valid JSON", err)
    local other = put(dir, "other.json", doc({}, { matrix = { combos = { "Human PRIEST none" } } }))
    code, _, err = run({ "diff", a, other })
    assert.equal(2, code)
    assert.matches("^hwc: ", err)
    assert.matches("no shared characters", err)
  end)

  it("exits 2 with fewer or more than two paths", function()
    local dir = tmpdir()
    local a = put(dir, "a.json", doc({}))
    local code, _, err = run({ "diff", a })
    assert.equal(2, code)
    assert.equal("hwc: diff needs 2 files, got 1\nsee hwc diff --help\n", err)
    code, _, err = run({ "diff", a, a, a })
    assert.equal(2, code)
    assert.equal("hwc: diff needs 2 files, got 3\nsee hwc diff --help\n", err)
  end)

  it("rejects an unknown flag rather than reading it as a path", function()
    local dir = tmpdir()
    local a = put(dir, "a.json", doc({}))
    local b = put(dir, "b.json", doc({}))
    local code, _, err = run({ "diff", a, b, "--bogus" })
    assert.equal(2, code)
    assert.equal("hwc: unknown option --bogus for hwc diff\nsee hwc diff --help\n", err)
  end)

  it("exits 2 for a format-2 file with a malformed body", function()
    local dir = tmpdir()
    local bad = put(dir, "bad.json", '{"format":2,"header":{"matrix":{"combos":["A"]}},"findings":5}')
    for _, args in ipairs({ { "diff", bad, bad }, { "diff", bad, bad, "--json" } }) do
      local code, out, err = run(args)
      assert.equal(2, code)
      assert.equal("", out)
      assert.matches("^hwc: [^\n]*is not a valid findings file[^\n]*\nsee hwc diff %-%-help\n$", err)
    end
  end)

  it("words an internal error separately, exit 2", function()
    local dir = tmpdir()
    local a = put(dir, "a.json", doc({}))
    local fdiff = require("hwc.findings.diff")
    local r = with_stub(fdiff, "compare", function() error("boom\nsecond line") end,
      function() return { run({ "diff", a, a }) } end)
    assert.equal(2, r[1])
    assert.equal("", r[2])
    assert.equal("hwc: internal error: boom (please report it)\n", r[3])
  end)

  it("warns when the QuestieDB sha256 differs under the same tag and build", function()
    local dir = tmpdir()
    local q = function(sha)
      return { catalog = { questie = { tag = "v1.1.2", build = "e1652ce", sha256 = sha }, supplement = { present = false } } }
    end
    local a = put(dir, "a.json", doc({}, q("1111111aaaa")))
    local b = put(dir, "b.json", doc({}, q("2222222bbbb")))
    local code, out = run({ "diff", a, b })
    assert.equal(0, code)
    assert.truthy(out:find("warning: different QuestieDB", 1, true), out)
    assert.truthy(out:find("2222222", 1, true), out)
  end)

  it("needs no WoW-Pro folder", function()
    local dir = tmpdir()
    local a = put(dir, "a.json", doc({}))
    assert.equal(0, (run({ "diff", a, a }, env_at(tmpdir()))))
  end)

  it("handles a non-git side and the same file twice", function()
    local dir = tmpdir()
    local a = put(dir, "a.json", doc({ finding("F-1") }))
    local code, out = run({ "diff", a, a })
    assert.equal(0, code)
    assert.matches("no changes", out)
    assert.matches("same addon commit", out)
    local nogit = put(dir, "nogit.json", doc({}, { addon = { git = false, version = "2026.11.12.A" } }))
    local out2
    code, out2 = run({ "diff", nogit, nogit })
    assert.equal(0, code)
    assert.matches("2026.11.12.A (not a git folder)", out2, 1, true)
  end)
end)
