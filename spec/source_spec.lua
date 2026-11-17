-- Locating the WoW-Pro folder from where hwc is run (guide-filters design).
local lfs = require("lfs")
local source = require("hwc.source")

local function write(path, text)
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end

local function mkdirs(path)
  local cur = ""
  for part in path:gmatch("[^/]+") do
    cur = cur .. "/" .. part
    lfs.mkdir(cur)
  end
end

describe("hwc.source", function()
  local tmp, addons, link

  setup(function()
    tmp = os.tmpname()
    os.remove(tmp)
    addons = tmp .. "/AddOns"
    mkdirs(addons .. "/WoWPro")
    mkdirs(addons .. "/WoWPro_Leveling/Forever/Alliance")
    write(addons .. "/WoWPro/WoWPro.toc", "## Title: WoWPro\n")
    link = tmp .. "/link"
    os.execute("ln -s '" .. addons .. "' '" .. link .. "'")
  end)

  teardown(function()
    os.execute("rm -rf '" .. tmp .. "'")
  end)

  describe("find", function()
    it("finds the folder when started in it", function()
      assert.equal(addons, source.find(addons))
    end)

    it("walks up from a nested guide folder", function()
      assert.equal(addons, source.find(addons .. "/WoWPro_Leveling/Forever/Alliance"))
    end)

    it("returns nil and an error when no folder is above", function()
      local root, err = source.find(tmp)
      assert.is_nil(root)
      assert.matches("no WoW%-Pro folder at or above", err)
    end)
  end)

  describe("start_dir", function()
    it("keeps a logical PWD that is the same directory as cwd", function()
      assert.equal(link, source.start_dir({ pwd = link, cwd = addons }))
    end)

    it("uses cwd when PWD is unset", function()
      assert.equal("/x", source.start_dir({ pwd = nil, cwd = "/x" }))
    end)

    it("uses cwd when PWD does not exist", function()
      assert.equal(tmp, source.start_dir({ pwd = "/nonexistent", cwd = tmp }))
    end)
  end)
end)
