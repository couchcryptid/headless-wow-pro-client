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

  it("puts the Honored, Revered and Exalted lower bounds in their own bands", function()
    assert.same({ 6, 9000, 21000 }, { reputation.standing(9000) })
    assert.same({ 7, 21000, 42000 }, { reputation.standing(21000) })
    assert.same({ 8, 42000, 42999 }, { reputation.standing(42000) })
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
  -- Forever, in game, fresh level-1 characters, 2026-11-18.
  it("is the captured Dwarf table, Alliance header included, not inferred", function()
    local pts, inferred = reputation.start("Dwarf")
    assert.same({ [47] = 4000, [54] = 3100, [69] = 3100, [72] = 3100, [469] = 3300 }, pts)
    assert.is_false(inferred)
  end)

  it("is the captured Orc table, Horde header included, not inferred", function()
    local pts, inferred = reputation.start("Orc")
    assert.same({ [76] = 4000, [81] = 3100, [530] = 3100, [68] = 500, [67] = 3500 }, pts)
    assert.is_false(inferred)
  end)

  it("is the captured Undead table, Horde header included, not inferred", function()
    local pts, inferred = reputation.start("Undead")
    assert.same({ [68] = 4000, [76] = 2000, [530] = 2000, [81] = 500, [67] = 3500 }, pts)
    assert.is_false(inferred)
  end)

  it("infers the other Alliance races from the Dwarf table", function()
    for race, home in pairs({ Human = 72, Gnome = 54, NightElf = 69 }) do
      local pts, inferred = reputation.start(race)
      local want = { [47] = 3100, [54] = 3100, [69] = 3100, [72] = 3100, [469] = 3300 }
      want[home] = 4000
      assert.same(want, pts, race)
      assert.is_true(inferred, race)
    end
  end)

  it("is the captured Tauren table, not inferred", function()
    local pts, inferred = reputation.start("Tauren")
    assert.same({ [81] = 4000, [76] = 3100, [530] = 3100, [68] = 500, [67] = 3500 }, pts)
    assert.is_false(inferred)
  end)

  it("infers Troll from the Orc table", function()
    local pts, inferred = reputation.start("Troll")
    assert.same({ [530] = 4000, [76] = 3100, [81] = 3100, [68] = 500, [67] = 3500 }, pts)
    assert.is_true(inferred)
  end)

  it("infers Skyborne from its side's capitals with no home", function()
    local a, ia = reputation.start("SkyborneAlliance")
    assert.same({ [72] = 3100, [47] = 3100, [54] = 3100, [69] = 3100, [469] = 3300 }, a)
    assert.is_true(ia)
    local h, ih = reputation.start("SkyborneHorde")
    assert.same({ [76] = 3100, [81] = 3100, [530] = 3100, [68] = 500, [67] = 3500 }, h)
    assert.is_true(ih)
  end)

  it("raises for a race out of scope", function()
    assert.has_error(function() reputation.start("Nope") end)
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
