describe("questie addon.load", function()
  local addon = require("hwc.questie.addon")
  local lfs = require("lfs")
  local dir

  local function write(rel, text)
    local f = assert(io.open(dir .. "/" .. rel, "wb"))
    f:write(text)
    f:close()
  end

  -- A stand-in release: one TOC and a single hwc-written file that plays
  -- QuestieDB's part (records what it saw, publishes RequireContract).
  local function release(body, extra_toc_line)
    write("QuestieDB/QuestieDB_Forever.toc",
      "## X-Flavor: Forever\n## X-Probe: hello\n\nmain.lua\n" .. (extra_toc_line or ""))
    write("QuestieDB/main.lua", "local name, lib = ...\n" .. body)
  end

  local OK_CONTRACT = "function lib.RequireContract(n) return n == 4 end\n"
    .. "lib.Support = { Get = function(m) return m == 'QuestXP' and { db = { [7] = { 2, 170 } } } or nil end }\n"

  before_each(function()
    dir = os.tmpname()
    os.remove(dir)
    assert(lfs.mkdir(dir))
    assert(lfs.mkdir(dir .. "/QuestieDB"))
  end)
  after_each(function() os.execute("rm -rf '" .. dir .. "'") end)

  it("answers as the character and serves only QuestieDB's TOC metadata", function()
    release(OK_CONTRACT .. [[
lib.seen = { name = name, class = { UnitClassBase("player") }, faction = UnitFactionGroup("Player"),
  probe = C_AddOns.GetAddOnMetadata("QuestieDB", "X-Probe"),
  other = C_AddOns.GetAddOnMetadata("WoWPro", "X-Probe"),
  season = C_Seasons.GetActiveSeason(), locale = GetLocale() }
]])
    local lib, sb = addon.load(dir, { class = "MAGE", faction = "Horde" })
    assert.are.same({ name = "QuestieDB", class = { "MAGE", 8 }, faction = "Horde", probe = "hello",
      season = 0, locale = "enUS" }, lib.seen)
    assert.are.same({}, sb.errors)
    assert.are.same({ [7] = { 2, 170 } }, lib.xp_db)
  end)

  it("raises when the release has no QuestXP data", function()
    release("function lib.RequireContract(n) return n == 4 end\n")
    assert.has_error(function() addon.load(dir, { class = "MAGE", faction = "Horde" }) end,
      "hwc: questie: no QuestXP data")
  end)

  it("gives every call its own sandbox", function()
    release(OK_CONTRACT .. "Shared = (rawget(_G, 'Shared') or 0) + 1\nlib.count = Shared\n")
    local a, sa = addon.load(dir, { class = "MAGE", faction = "Horde" })
    local b, sb = addon.load(dir, { class = "MAGE", faction = "Horde" })
    assert.are.equal(1, a.count); assert.are.equal(1, b.count)
    assert.are_not.equal(sa, sb)
  end)

  it("raises on the first file error, naming the file", function()
    release("error('boom', 0)\n")
    assert.has_error(function() addon.load(dir, { class = "MAGE", faction = "Horde" }) end,
      "hwc: questie: QuestieDB/main.lua: boom")
  end)

  it("raises on a TOC entry it cannot run", function()
    release(OK_CONTRACT, "gone.lua\n")
    assert.has_error(function() addon.load(dir, { class = "MAGE", faction = "Horde" }) end,
      "hwc: questie: QuestieDB/gone.lua: skipped (missing on disk)")
  end)

  it("raises on a missing global", function()
    release(OK_CONTRACT .. "local x = NotAWowApi\n")
    assert.has_error(function() addon.load(dir, { class = "MAGE", faction = "Horde" }) end,
      "hwc: questie: missing global NotAWowApi")
  end)

  it("raises when the contract check returns false", function()
    release("function lib.RequireContract(n) return false, 'contract mismatch' end\n")
    assert.has_error(function() addon.load(dir, { class = "MAGE", faction = "Horde" }) end,
      "hwc: questie: contract mismatch; installed " .. dir:match("([^/]+)$")
      .. "; run hwc update --tag <a compatible tag>")
  end)
end)
