local config = require("hwc.config")

local function fake_addon()
  local dir = os.tmpname()
  os.remove(dir)
  os.execute("mkdir -p '" .. dir .. "/WoWPro'")
  local f = assert(io.open(dir .. "/WoWPro/WoWPro.toc", "w"))
  f:write("## Interface: 11500\n")
  f:close()
  return dir
end

describe("config.load", function()
  it("defaults apply", function()
    local dir = fake_addon()
    local c = config.load { addon_path = dir }
    assert.are.equal(dir, c.addon_path)
    assert.are.equal("Forever", c.flavor)
    assert.are.equal(16001, c.toc_version)
    assert.are.equal(40, c.quest_log_size)
    assert.are.equal("Alliance", c.faction)
    assert.are.equal(2, c.sex)
    assert.are.equal(1, c.seed)
    assert.are.equal("string", type(c.race))
    assert.are.equal("string", type(c.class))
    os.execute("rm -rf '" .. dir .. "'")
  end)

  it("keeps caller overrides", function()
    local dir = fake_addon()
    local c = config.load { addon_path = dir, race = "NightElf", class = "DRUID", sex = 3, seed = 7 }
    assert.are.equal("NightElf", c.race)
    assert.are.equal("DRUID", c.class)
    assert.are.equal(3, c.sex)
    assert.are.equal(7, c.seed)
    os.execute("rm -rf '" .. dir .. "'")
  end)

  it("defaults to no professions and keeps a professions list", function()
    local dir = fake_addon()
    assert.same({}, config.load({ addon_path = dir }).professions)
    local profs = { { name = "First Aid", rank = 1, max = 75 } }
    assert.same(profs, config.load({ addon_path = dir, professions = profs }).professions)
    os.execute("rm -rf '" .. dir .. "'")
  end)

  it("missing addon path errors", function()
    assert.has_error(function()
      config.load { addon_path = "/nonexistent" }
    end, "hwc: addon path not found: /nonexistent")
  end)
end)
