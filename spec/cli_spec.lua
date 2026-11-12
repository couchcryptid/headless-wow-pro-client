local lfs = require("lfs")

local ADDON = os.getenv("HOME") .. "/Projects/WoW-Pro-Guides"
local present = lfs.attributes(ADDON .. "/WoWPro/WoWPro.toc", "mode") ~= nil

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
      assert.equal(0, cli.main({ "quest", "282", "--addon", ADDON }, out))
      local d = require("dkjson").decode(text())
      assert.equal(282, d.quest.id)
      assert.same({ 218 }, d.quest.pre_single)
      assert.is_true(d.sources.questie.present)
      assert.matches('"pre_single":%[218%]', text())
    end)

    it("quest reports an unknown id with status 1", function()
      local out, _ = capture()
      local err, etext = capture()
      assert.equal(1, cli.main({ "quest", "777777", "--addon", ADDON }, out, err))
      assert.matches("777777", etext())
    end)
  else
    pending("quest command needs the addon checkout and pinned QuestieDB")
  end

  it("quest requires a numeric id", function()
    local out, _ = capture()
    local err, etext = capture()
    assert.equal(2, cli.main({ "quest", "abc" }, out, err))
    assert.matches("Usage", etext())
  end)

  if present then
    it("boot prints the addon identity, guide and first steps", function()
      local out, text = capture()
      assert.equal(0, cli.main({ "boot", "--race", "Dwarf", "--class", "WARRIOR", "--addon", ADDON }, out))
      local t = text()
      assert.matches("commit: %x+", t)
      assert.matches("ClassicDunMorogh0112", t)
      assert.matches("A Dwarven Outfitters", t)
    end)

    it("boot --json emits a decodable result", function()
      local out, text = capture()
      assert.equal(0, cli.main({ "boot", "--race", "Gnome", "--class", "MAGE", "--json" }, out))
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
      local p = assert(io.popen("bin/hwc boot --race Dwarf --class WARRIOR --json 2>&1"))
      local s = p:read("*a")
      p:close()
      return s
    end
    local a, b = run(), run()
    assert.is_true(#a > 100)
    assert.equal(a, b)
  end)
end)
