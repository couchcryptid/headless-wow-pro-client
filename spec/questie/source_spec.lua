describe("questie source adapter", function()
  local source = require("hwc.questie.source")

  -- A stand-in for QuestieDB's private addon table: entity objects live at
  -- lib.<Entity> (QuestieDB src/api.lua:26, the same tables as the QuestDB/...
  -- globals) and addon.load hangs the QuestXP db off lib.xp_db.
  local function fake_lib()
    return {
      Meta = { Quest = { keys = { name = 1, questLevel = 5 } } },
      Quest = {
        GetAll = function(id) return id == 7 and { "Fake", nil, nil, nil, 12 } or nil end,
      },
      Item = { GetAllIds = function() return { 9, 3 } end },
      xp_db = { [7] = { 2, 170 } },
    }
  end

  local info = { path = "/x", tag = "v1.0.0", build = "abc", sha256 = "def" }

  it("builds a record keyed by QuestieDB's own field names", function()
    local s = source.from_lib(fake_lib(), info)
    assert.are.same({ id = 7, name = "Fake", questLevel = 12 }, s:quest(7))
  end)

  it("returns nil for an unknown id", function()
    assert.is_nil(source.from_lib(fake_lib(), info):quest(8))
  end)

  it("lists item ids sorted, without reordering QuestieDB's list", function()
    local lib = fake_lib()
    local ids = { 9, 3 }
    lib.Item.GetAllIds = function() return ids end
    assert.are.same({ 3, 9 }, source.from_lib(lib, info):item_ids())
    assert.are.same({ 9, 3 }, ids)
  end)

  it("serves quest xp from the QuestXP db", function()
    local s = source.from_lib(fake_lib(), info)
    assert.are.same({ 2, 170 }, s:xp(7))
    assert.is_nil(s:xp(8))
  end)

  it("carries info", function()
    assert.are.same(info, source.from_lib(fake_lib(), info).info)
  end)

  it("open reports none installed for a nil dir and broken for a dir without the TOC", function()
    local s, why = source.open(nil, { class = "WARRIOR", faction = "Alliance" })
    assert.is_nil(s); assert.are.equal("none installed", why)
    s, why = source.open("/nonexistent/questie/v9.9.9", { class = "WARRIOR", faction = "Alliance" })
    assert.is_nil(s); assert.are.equal("broken: v9.9.9", why)
  end)
end)
