local config = require("hwc.config")
local store = require("hwc.questie.home")

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

  it("takes the faction from the race", function()
    assert.are.equal("Alliance", config.load({ race = "Gnome", class = "PRIEST" }).faction)
    assert.are.equal("Horde", config.load({ race = "Orc", class = "WARRIOR" }).faction)
    assert.are.equal("Horde", config.load({ race = "Undead", class = "PALADIN" }).faction)
  end)

  it("rejects a class the race can't play in Forever", function()
    assert.has_error(function() config.load({ race = "Tauren", class = "MAGE" }) end,
      "hwc: Tauren can't be a MAGE in Forever")
    assert.has_error(function() config.load({ race = "Gnome", class = "SHAMAN" }) end,
      "hwc: Gnome can't be a SHAMAN in Forever")
  end)

  it("defaults to no professions and keeps a professions list", function()
    local dir = fake_addon()
    assert.same({}, config.load({ addon_path = dir }).professions)
    local profs = { { name = "First Aid", rank = 1, max = 75 } }
    assert.same(profs, config.load({ addon_path = dir, professions = profs }).professions)
    os.execute("rm -rf '" .. dir .. "'")
  end)

  it("rejects unknown profession names", function()
    local dir = fake_addon()
    local ok, err = pcall(config.load, { addon_path = dir, professions = { { name = "Basketweaving", rank = 1, max = 75 } } })
    assert.is_false(ok)
    assert.equal("hwc: unknown profession: Basketweaving", err)
    os.execute("rm -rf '" .. dir .. "'")
  end)

  it("defaults the catalog paths and resolves relative ones against the repo root", function()
    local dir = fake_addon()
    local c = config.load({ addon_path = dir }).catalog
    local home = os.getenv("HOME")
    local root = config.repo_root()
    assert.are.equal("/", root:sub(1, 1))
    -- The active version dir (even a broken one), else nil.
    local qroot = store.root()
    local tag = store.active(qroot)
    assert.are.equal(tag and store.version_dir(qroot, tag) or nil, c.questie_dir)
    assert.are.equal(root .. "/local/catalog/counts.json", c.counts)
    os.execute("rm -rf '" .. dir .. "'")
  end)

  it("keeps absolute catalog paths and resolves relative overrides against the repo root", function()
    local dir = fake_addon()
    local c = config.load({ addon_path = dir, catalog = { questie_dir = "/abs/questie", counts = "x/c.json" } }).catalog
    assert.are.equal("/abs/questie", c.questie_dir)
    assert.are.equal(config.repo_root() .. "/x/c.json", c.counts)
    os.execute("rm -rf '" .. dir .. "'")
  end)

  describe("default questie_dir", function()
    local real_root = store.root
    local qroot
    before_each(function()
      qroot = os.tmpname()
      os.remove(qroot)
      os.execute("mkdir -p '" .. qroot .. "/questie'")
      store.root = function() return qroot end
    end)
    after_each(function()
      store.root = real_root
      os.execute("rm -rf '" .. qroot .. "'")
    end)
    local function set_active(text)
      local f = assert(io.open(qroot .. "/questie/active", "w"))
      f:write(text)
      f:close()
    end

    it("is nil with no active tag", function()
      assert.is_nil(config.load({}).catalog.questie_dir)
    end)

    -- Review Focus 4: a broken active dir is still passed on, so the catalog says "broken: <tag>".
    it("is the active version dir, even when it has no TOC", function()
      set_active("v9.9.9\n")
      assert.are.equal(qroot .. "/questie/v9.9.9", config.load({}).catalog.questie_dir)
    end)

    it("is nil when the active tag is not a version tag", function()
      set_active("../elsewhere\n")
      assert.is_nil(config.load({}).catalog.questie_dir)
    end)

    it("yields to an explicit catalog.questie_dir, resolved against the repo root", function()
      set_active("v9.9.9\n")
      assert.are.equal(config.repo_root() .. "/q/v1", config.load({ catalog = { questie_dir = "q/v1" } }).catalog.questie_dir)
      assert.are.equal("/abs/v1", config.load({ catalog = { questie_dir = "/abs/v1" } }).catalog.questie_dir)
    end)
  end)

  it("missing addon path errors", function()
    assert.has_error(function()
      config.load { addon_path = "/nonexistent" }
    end, "hwc: addon path not found: /nonexistent")
  end)

  -- The CLI finds the WoW-Pro folder (hwc.source); config has no default path.
  it("has no default addon path and skips the TOC check without one", function()
    local c = config.load({})
    assert.is_nil(c.addon_path)
  end)
end)

describe("boot.run", function()
  it("errors when the config names no WoW-Pro folder", function()
    local cfg = config.load({})
    assert.has_error(function() require("hwc.boot").run(cfg) end, "hwc: no WoW-Pro folder")
  end)

  it("writes one stderr line suggesting hwc init when QuestieDB is absent", function()
    local dir = fake_addon()
    local cfg = config.load({ addon_path = dir, catalog = { questie_dir = "/nonexistent/questie/v9.9.9" } })
    -- The fake addon has no WoW-Pro to load: stop the boot once the catalog is in.
    local sources
    cfg.on_phase = function(_, sb)
      sources = sb.world.catalog.sources
      error("stop", 0)
    end
    local real, lines = io.stderr, {}
    io.stderr = { write = function(_, ...) lines[#lines + 1] = table.concat({ ... }) end }
    local ok, err = pcall(require("hwc.boot").run, cfg)
    io.stderr = real
    os.execute("rm -rf '" .. dir .. "'")
    assert.is_false(ok)
    assert.are.equal("stop", err)
    assert.are.same({ "hwc: no QuestieDB installed (broken: v9.9.9); run hwc init\n" }, lines)
    assert.are.equal("broken: v9.9.9", sources.questie.reason)
  end)
end)
