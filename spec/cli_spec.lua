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
