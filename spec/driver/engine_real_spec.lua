-- The adapter against the real engine and addon (pending without the checkout).
local flow = dofile("spec/helpers/world_engine_flow.lua")
local Engine = require("hwc.driver.engine")

describe("driver.engine against the real addon", function()
  local absent = flow.absent()
  if absent then
    it("is pending", function() pending(absent) end)
    return
  end

  it("reads the first step, its source line and the guide without writing engine state", function()
    local r = flow.boot("Dwarf", "WARRIOR")
    local W = r.sb.env.WoWPro
    local before = {}
    for k, v in pairs(W) do before[k] = v end
    local E = Engine.new(r)
    local cur = E:current()
    assert.equal("A", cur.action)
    assert.equal("Dwarven Outfitters", cur.name)
    assert.same({ 179 }, cur.qids)
    assert.is_number(cur.line)
    local g = E:guide()
    assert.equal("WoWPro_Leveling/Forever/Alliance/01_12_Dun_Morogh.lua", g.file)
    assert.equal(1, g.startlevel)
    assert.equal("ClassicEasternKingdom1220", g.next_gid)
    assert.equal(2, E:rank())
    assert.is_true(E:num_steps() > 10)
    assert.is_false(E:completed(cur.index))
    local after = {}
    for k, v in pairs(W) do after[k] = v end
    assert.same(before, after)
  end)
end)
