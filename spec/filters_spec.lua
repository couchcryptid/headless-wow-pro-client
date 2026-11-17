-- S3-style include/exclude guide selection (guide-filters design).
local lfs = require("lfs")
local filters = require("hwc.filters")

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

local function inc(p) return { kind = "include", pattern = p, raw = p } end
local function exc(p) return { kind = "exclude", pattern = p, raw = p } end

describe("hwc.filters", function()
  local tmp, root, dir
  local dun = "WoWPro_Leveling/Forever/Alliance/01_12_Dun_Morogh.lua"
  local files = {
    dun,
    "WoWPro_Leveling/Forever/Alliance/12_20_Westfall.lua",
    "WoWPro_Leveling/Forever/Horde/01_12_Durotar.lua",
  }

  setup(function()
    tmp = os.tmpname()
    os.remove(tmp)
    root = tmp .. "/AddOns"
    dir = root .. "/WoWPro_Leveling/Forever/Alliance"
    mkdirs(dir)
    write(dir .. "/01_12_Dun_Morogh.lua", "")
    write(dir .. "/Guide [Beta] 1.lua", "")
    write(dir .. "/a-b(c)*.lua", "")
  end)

  teardown(function()
    os.execute("rm -rf '" .. tmp .. "'")
  end)

  describe("compile", function()
    it("star matches across slashes", function()
      assert.is_true(filters.compile("*")("a/b/c.lua"))
    end)
    it("matches a substring glob", function()
      assert.is_true(filters.compile("*Dun_Morogh*")(dun))
    end)
    it("? matches exactly one character", function()
      local m = filters.compile("a?.lua")
      assert.is_true(m("ab.lua"))
      assert.is_false(m("abc.lua"))
    end)
    it("supports classes and negated classes", function()
      assert.is_true(filters.compile("[abc]y")("by"))
      local m = filters.compile("[!x]y")
      assert.is_true(m("ay"))
      assert.is_false(m("xy"))
    end)
    it("escapes Lua magic characters", function()
      local m = filters.compile("a-b(c).lua")
      assert.is_true(m("a-b(c).lua"))
      assert.is_false(m("a-bc.lua"))
      assert.is_true(filters.compile("50%+.lua")("50%+.lua"))
    end)
    it("keeps Lua magic inside a class from changing meaning", function()
      local m = filters.compile("[%a]")
      assert.is_true(m("%"))
      assert.is_true(m("a"))
      assert.is_false(m("b"))
      assert.is_true(filters.compile("[!^]")("a"))
      assert.is_false(filters.compile("[!^]")("^"))
    end)
    it("treats escaped bracket classes literally", function()
      assert.is_true(filters.compile("[[]x[]]")("[x]"))
    end)
    it("treats an unterminated [ literally", function()
      assert.is_true(filters.compile("a[b")("a[b"))
    end)
  end)

  describe("select", function()
    it("applies filters in order: exclude all then include", function()
      local set = filters.select(files, { exc("*"), inc("*Dun_Morogh*") })
      assert.same({ [dun] = true }, set)
    end)
    it("lets a later exclude win", function()
      local set = filters.select(files, { inc("*Dun*"), exc("*") })
      assert.same({}, set)
    end)
    it("keeps everything with no filters", function()
      local set, unmatched = filters.select(files, {})
      for _, f in ipairs(files) do assert.is_true(set[f]) end
      assert.same({}, unmatched)
    end)
    it("reports includes that matched nothing", function()
      local _, unmatched = filters.select(files, { inc("*nope*") })
      assert.same({ "*nope*" }, unmatched)
    end)
    it("does not report unmatched excludes", function()
      local _, unmatched = filters.select(files, { exc("*nope*") })
      assert.same({}, unmatched)
    end)
  end)

  describe("resolve", function()
    it("resolves ./file from the start dir to its rel", function()
      local rel = filters.resolve("./01_12_Dun_Morogh.lua", root, dir)
      assert.is_true(filters.compile(rel)(dun))
      assert.is_false(filters.compile(rel)("WoWPro_Leveling/Forever/Horde/01_12_Durotar.lua"))
    end)
    it("turns a directory into dir/*", function()
      local rel = filters.resolve(".", root, dir) -- not a ./ prefix: unchanged
      assert.equal(".", rel)
      rel = filters.resolve("../Alliance/", root, dir)
      assert.equal("WoWPro_Leveling/Forever/Alliance/*", rel)
    end)
    it("turns the root into *", function()
      assert.equal("*", filters.resolve("../../..", root, dir))
    end)
    it("rejects paths outside root", function()
      local rel, err = filters.resolve("../../../..", root, dir)
      assert.is_nil(rel)
      assert.matches("outside the WoW%-Pro folder", err)
      assert.matches("pattern ../../../..", err, 1, true)
    end)
    it("matches an existing file whose name has glob characters", function()
      local rel = filters.resolve("./Guide [Beta] 1.lua", root, dir)
      local relpath = "WoWPro_Leveling/Forever/Alliance/Guide [Beta] 1.lua"
      assert.is_true(filters.compile(rel)(relpath))
      assert.is_false(filters.compile(rel)("WoWPro_Leveling/Forever/Alliance/Guide B 1.lua"))
    end)
    it("escapes * and ? in an existing file name", function()
      local rel = filters.resolve("./a-b(c)*.lua", root, dir)
      local m = filters.compile(rel)
      assert.is_true(m("WoWPro_Leveling/Forever/Alliance/a-b(c)*.lua"))
      assert.is_false(m("WoWPro_Leveling/Forever/Alliance/a-b(c)xx.lua"))
    end)
    it("returns other patterns unchanged", function()
      assert.equal("*Dun*", filters.resolve("*Dun*", root, dir))
    end)
    it("keeps a glob in a not-yet-existing relative pattern", function()
      assert.equal("WoWPro_Leveling/Forever/Alliance/01*",
        filters.resolve("./01*", root, dir))
    end)
  end)
end)
