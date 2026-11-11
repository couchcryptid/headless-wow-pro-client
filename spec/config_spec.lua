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

  it("defaults the catalog paths and resolves relative ones against the repo root", function()
    local dir = fake_addon()
    local c = config.load({ addon_path = dir }).catalog
    local home = os.getenv("HOME")
    local root = config.repo_root()
    assert.are.equal("/", root:sub(1, 1))
    assert.are.equal(root .. "/local/questie/d57637f490c9dfcdbbc967dab47a8b0d8fe1b3cc", c.questie_dir)
    assert.are.equal(root .. "/local/catalog/supplement.json", c.supplement)
    assert.are.equal(home .. "/Projects/wow-pro-leveling/sim/data/wh.json", c.wh_json)
    assert.are.equal(home .. "/Projects/wow-pro-leveling/sim/data/objs.json", c.objs_json)
    assert.are.equal(home .. "/Projects/wow-pro-leveling/sim/data/rate_overrides.json", c.rate_overrides)
    os.execute("rm -rf '" .. dir .. "'")
  end)

  it("keeps absolute catalog paths and resolves relative overrides against the repo root", function()
    local dir = fake_addon()
    local c = config.load({ addon_path = dir, catalog = { wh_json = "/abs/wh.json", supplement = "x/s.json" } }).catalog
    assert.are.equal("/abs/wh.json", c.wh_json)
    assert.are.equal(config.repo_root() .. "/x/s.json", c.supplement)
    os.execute("rm -rf '" .. dir .. "'")
  end)

  it("missing addon path errors", function()
    assert.has_error(function()
      config.load { addon_path = "/nonexistent" }
    end, "hwc: addon path not found: /nonexistent")
  end)
end)
