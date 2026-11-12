local gs = require("hwc.driver.guide_source")

local ROOT = "spec/fixtures/addon"

describe("guide_source", function()
  it("indexes guides by the GID in RegisterGuide, relative to the addon root", function()
    local idx = gs.index(ROOT, "Fix/forever")
    assert.equal("Fix/forever/G1.lua", idx.FixG1)
  end)

  it("accepts double-quoted GIDs and returns {} for a missing directory", function()
    assert.same({}, gs.index(ROOT, "nope"))
  end)

  it("maps the n-th identical step to its n-th source line", function()
    local file = "Fix/forever/G1.lua"
    local step = { action = "C", name = "Foo", qids = { 5 } }
    assert.equal(7, gs.line_of(ROOT, file, step, 1))
    assert.equal(8, gs.line_of(ROOT, file, step, 2))
    assert.is_nil(gs.line_of(ROOT, file, step, 3))
  end)

  it("matches on the first QID of a multi-QID step", function()
    assert.equal(9, gs.line_of(ROOT, "Fix/forever/G1.lua", { action = "T", name = "Bar", qids = { 7, 8 } }, 1))
  end)

  it("matches an ACTIVE-only step (no QID in the source line) on action and name", function()
    -- the engine fills QID from ACTIVE, so the step carries qid 9; the line has no |QID|
    assert.equal(10, gs.line_of(ROOT, "Fix/forever/G1.lua", { action = "K", name = "Baz", qids = { 9 } }, 1))
  end)

  it("returns nil for an unknown step or file", function()
    assert.is_nil(gs.line_of(ROOT, "Fix/forever/G1.lua", { action = "A", name = "Nope", qids = { 5 } }, 1))
    assert.is_nil(gs.line_of(ROOT, "Fix/forever/Missing.lua", { action = "A", name = "Foo", qids = { 5 } }, 1))
  end)

  it("indexes the real addon when present", function()
    local home = os.getenv("HOME") .. "/Projects/WoW-Pro-Guides"
    if not require("lfs").attributes(home .. "/WoWPro_Leveling", "mode") then return pending("addon absent") end
    assert.equal("WoWPro_Leveling/Forever/Alliance/01_12_Dun_Morogh.lua", gs.index(home).ClassicDunMorogh0112)
  end)
end)
