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

  -- Classes come from Player.RACES (Blizzard's Forever table), never from guide tags:
  -- the guide is what's under test.
  it("is the race's Forever class list from Player.RACES", function()
    assert.same(Player.RACES.Undead.classes, Player.classes_for("Undead"))
  end)
end)

-- The README's "Covering professions" list (design §6): together the characters
-- reach every Camping 101 quest in the 1-25 Alliance guides. Reads the real
-- guides and pends without the addon checkout.
describe("covering professions", function()
  local lfs = require("lfs")
  local ADDON = os.getenv("HOME") .. "/Projects/WoW-Pro-Guides"
  local COVERING = { "alchemy,herbalism", "blacksmithing,mining", "leatherworking,skinning",
    "enchanting,engineering", "tailoring", "first-aid,fishing" }

  it("each parses as a valid --professions list", function()
    for _, list in ipairs(COVERING) do assert.is_table(professions.parse(list), list) end
  end)

  if lfs.attributes(ADDON .. "/WoWPro/WoWPro.toc", "mode") == nil then
    pending("addon checkout absent at " .. ADDON)
    return
  end

  it("cover exactly the Camping 101 professions in the 1-25 Alliance guides", function()
    local found = {}
    local dir = ADDON .. "/WoWPro_Leveling/Forever/Alliance"
    for f in lfs.dir(dir) do
      local lo = f:match("^(%d+)_%d+_.*%.lua$")
      if lo and tonumber(lo) < 25 then
        for line in io.lines(dir .. "/" .. f) do
          local p = line:match("^A Camping 101: ([%a ]+)|")
          if p then found[p] = true end
        end
      end
    end
    -- Cooking needs no covering character: every run learns it from the guide.
    assert.is_true(found.Cooking)
    found.Cooking = nil
    local want, got = {}, {}
    for p in pairs(found) do want[#want + 1] = p end
    for _, list in ipairs(COVERING) do
      for _, p in ipairs(professions.parse(list)) do got[#got + 1] = p end
    end
    table.sort(want); table.sort(got)
    assert.same(want, got)
    assert.equal(11, #got)
  end)
end)
