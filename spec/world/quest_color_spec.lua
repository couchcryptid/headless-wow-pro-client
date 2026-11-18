local quest_color = require("hwc.world.quest_color")
local xp = require("hwc.world.xp")

describe("quest_color.of", function()
  it("grades a quest by its level against the character's", function()
    assert.equal("red", quest_color.of(32, 37))
    assert.equal("orange", quest_color.of(32, 35))
    assert.equal("yellow", quest_color.of(32, 34))
    assert.equal("yellow", quest_color.of(32, 30))
    assert.equal("green", quest_color.of(32, 29))
    assert.equal("grey", quest_color.of(32, xp.gray_level(32)))
  end)

  it("pins the d=4 orange edge, the first non-grey green and the low-level grey floor", function()
    assert.equal("orange", quest_color.of(30, 34))
    -- At 30 the grey line is 22: one above it is 23, 7 below the character, so green.
    assert.equal(22, xp.gray_level(30))
    assert.equal("green", quest_color.of(30, xp.gray_level(30) + 1))
    assert.equal("green", quest_color.of(5, 1))
    for c = 1, 5 do assert.not_equal("grey", quest_color.of(c, 1)) end
  end)

  it("is nil when either level is missing", function()
    assert.is_nil(quest_color.of(nil, 5))
    assert.is_nil(quest_color.of(5, nil))
  end)
end)
