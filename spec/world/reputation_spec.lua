local reputation = require("hwc.world.reputation")

describe("reputation.standing", function()
  it("puts a lower bound in its own band", function()
    assert.same({ 4, 0, 3000 }, { reputation.standing(0) })
    assert.same({ 5, 3000, 9000 }, { reputation.standing(3000) })
  end)

  it("matches the Forever-checked readings", function()
    assert.equals(4, (reputation.standing(2999)))
    assert.same({ 6, 9000, 21000 }, { reputation.standing(9475) })
    assert.equals(6, (reputation.standing(16362)))
  end)

  it("handles the unverified negative and top bands", function()
    assert.equals(3, (reputation.standing(-1)))
    assert.equals(1, (reputation.standing(-42000)))
    assert.equals(8, (reputation.standing(42999)))
  end)
end)

describe("reputation.clamp", function()
  it("bounds points to the scale, so many large negative rewards leave Hated", function()
    assert.equals(-42000, reputation.clamp(-50000))
    assert.equals(42999, reputation.clamp(50000))
    assert.equals(1, (reputation.standing(reputation.clamp(-50000))))
  end)
end)

describe("reputation.start", function()
  it("is the captured Dwarf table, not inferred", function()
    local pts, inferred = reputation.start("Dwarf")
    assert.same({ [47] = 4000, [54] = 3100, [69] = 3100, [72] = 3100 }, pts)
    assert.is_false(inferred)
  end)

  it("infers other races from the Dwarf pattern", function()
    local pts, inferred = reputation.start("Gnome")
    assert.same({ [54] = 4000, [47] = 3100, [69] = 3100, [72] = 3100 }, pts)
    assert.is_true(inferred)
    assert.equals(4000, reputation.start("Orc")[76])
  end)

  it("gives Skyborne the three other capitals of its side and no home", function()
    local pts, inferred = reputation.start("SkyborneHorde")
    assert.same({ [76] = 3100, [81] = 3100, [530] = 3100, [68] = 3100 }, pts)
    assert.is_true(inferred)
  end)

  it("returns a fresh copy each call", function()
    reputation.start("Dwarf")[47] = 1
    assert.equals(4000, reputation.start("Dwarf")[47])
  end)
end)

describe("reputation.met_at", function()
  it("knows the verified centaur values", function()
    assert.same({ 2000, false }, { reputation.met_at(92) })
    assert.same({ 2000, false }, { reputation.met_at(93) })
  end)

  it("assumes 0 for any other faction", function()
    assert.same({ 0, true }, { reputation.met_at(91) })
  end)
end)

describe("reputation.BANDS", function()
  it("marks only Neutral, Friendly and Honored as verified", function()
    assert.equals(8, #reputation.BANDS)
    for _, b in ipairs(reputation.BANDS) do
      local want = b.reaction >= 4 and b.reaction <= 6
      assert.equals(want, b.verified, b.name)
    end
  end)
end)
