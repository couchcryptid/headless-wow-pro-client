local professions = require("hwc.world.professions")
local Player = require("hwc.world.player")

describe("professions.parse", function()
  it("sorts and canonicalises names, case-insensitively", function()
    assert.same({ "Herbalism", "Skinning" }, professions.parse("Skinning,HERBALISM"))
  end)

  it("leaves secondaries uncapped and accepts first aid with a hyphen or a space", function()
    assert.same({ "Alchemy", "First Aid", "Fishing", "Herbalism" },
      professions.parse("first-aid,fishing,alchemy,herbalism"))
    assert.same({ "First Aid" }, professions.parse("first aid"))
  end)

  it("rejects a third primary", function()
    local list, err = professions.parse("alchemy,herbalism,mining")
    assert.is_nil(list)
    assert.equal("--professions alchemy,herbalism,mining has 3 primary professions; a character can know 2", err)
  end)

  it("rejects a duplicate", function()
    local list, err = professions.parse("herbalism,herbalism")
    assert.is_nil(list)
    assert.matches("herbalism is listed twice", err, 1, true)
  end)

  it("tells the user Cooking is quest-learned", function()
    local list, err = professions.parse("cooking")
    assert.is_nil(list)
    assert.matches("cooking is learned from Camping 101: Cooking; leave it out of --professions", err, 1, true)
  end)

  it("rejects an unknown name and lists the valid ones", function()
    local list, err = professions.parse("herbalizm")
    assert.is_nil(list)
    assert.matches("unknown profession herbalizm; professions: alchemy, ", err, 1, true)
  end)

  it("rejects empty entries", function()
    for _, text in ipairs({ "herbalism,", ",herbalism", "" }) do
      local list, err = professions.parse(text)
      assert.is_nil(list)
      assert.matches("empty profession", err, 1, true)
    end
  end)
end)

describe("professions formatting", function()
  it("token is none for an empty list, else a comma list", function()
    assert.equal("none", professions.token({}))
    assert.equal("first-aid,herbalism", professions.token({ "First Aid", "Herbalism" }))
  end)

  it("label joins with a comma and space, nil when empty", function()
    assert.equal("Herbalism, Skinning", professions.label({ "Herbalism", "Skinning" }))
    assert.is_nil(professions.label({}))
  end)

  it("stem joins with hyphens, nil when empty", function()
    assert.equal("first-aid", professions.stem({ "First Aid" }))
    assert.equal("first-aid-herbalism", professions.stem({ "First Aid", "Herbalism" }))
    assert.is_nil(professions.stem({}))
  end)

  it("skills starts each at rank 1 of 75", function()
    assert.same({ { name = "Alchemy", rank = 1, max = 75 } }, professions.skills({ "Alchemy" }))
    assert.same({}, professions.skills({}))
  end)

  it("token and parse round-trip every sorted pair of accepted names", function()
    local names = {}
    for _, n in ipairs(professions.PRIMARY) do names[#names + 1] = n end
    for _, n in ipairs(professions.SECONDARY) do names[#names + 1] = n end
    for i = 1, #names do
      for j = i + 1, #names do
        local pair = { names[i], names[j] }
        table.sort(pair)
        assert.same(pair, professions.parse(professions.token(pair)))
      end
    end
  end)

  it("PRIMARY is the nine primaries, sorted", function()
    assert.same({ "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism",
      "Leatherworking", "Mining", "Skinning", "Tailoring" }, professions.PRIMARY)
  end)
end)

describe("Player.classes_for", function()
  it("returns the race's classes as a copy", function()
    assert.same({ "MAGE", "PRIEST", "ROGUE", "WARLOCK", "WARRIOR" }, Player.classes_for("Gnome"))
    local a = Player.classes_for("Gnome")
    a[1] = "X"
    assert.equal("MAGE", Player.classes_for("Gnome")[1])
  end)

  it("raises for an unknown race", function()
    assert.has_error(function() Player.classes_for("Goblin") end, "hwc: race not in scope: Goblin")
  end)
end)
