-- Race facts (design spec §3): which races exist, their faction, the token the client
-- returns from UnitRace, the classes Blizzard lists for each in Forever, and where a
-- new character of that race spawns. None of it comes from guide lines.
local Player = require("hwc.world.player")

-- Blizzard, "Create the Hero You Want to Be in World of Warcraft: Forever",
-- https://worldofwarcraft.blizzard.com/news/24304075/ (race/class tables, read 2026-11-18).
local BLIZZARD = {
  Dwarf = { "HUNTER", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARRIOR" },
  Gnome = { "MAGE", "PRIEST", "ROGUE", "WARLOCK", "WARRIOR" },
  Human = { "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "WARLOCK", "WARRIOR" },
  NightElf = { "DRUID", "HUNTER", "PRIEST", "ROGUE", "WARRIOR" },
  Orc = { "HUNTER", "MAGE", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" },
  Tauren = { "DRUID", "HUNTER", "SHAMAN", "WARRIOR" },
  Troll = { "HUNTER", "MAGE", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" },
  Undead = { "MAGE", "PALADIN", "PRIEST", "ROGUE", "WARLOCK", "WARRIOR" },
  SkyborneAlliance = { "DRUID", "HUNTER", "MAGE", "ROGUE", "WARRIOR" },
  SkyborneHorde = { "DRUID", "HUNTER", "ROGUE", "SHAMAN", "WARRIOR" },
}

describe("Player.RACES", function()
  it("has the ten Forever Alliance and Horde races with Blizzard's class lists", function()
    local keys = {}
    for k in pairs(Player.RACES) do keys[#keys + 1] = k end
    table.sort(keys)
    assert.same({ "Dwarf", "Gnome", "Human", "NightElf", "Orc", "SkyborneAlliance", "SkyborneHorde", "Tauren",
      "Troll", "Undead" }, keys)
    for race, classes in pairs(BLIZZARD) do
      assert.same(classes, Player.RACES[race].classes, race)
    end
  end)

  it("includes the Forever-only combos (Gnome Priest, Dwarf Shaman, Undead Paladin, ...)", function()
    local function has(race, class)
      for _, c in ipairs(Player.RACES[race].classes) do if c == class then return true end end
      return false
    end
    assert.is_true(has("Gnome", "PRIEST"))
    assert.is_true(has("Dwarf", "SHAMAN"))
    assert.is_true(has("Human", "HUNTER"))
    assert.is_true(has("Orc", "MAGE"))
    assert.is_true(has("Troll", "WARLOCK"))
    assert.is_true(has("Undead", "PALADIN"))
  end)

  it("puts each race in its faction", function()
    for _, r in ipairs({ "Dwarf", "Gnome", "Human", "NightElf", "SkyborneAlliance" }) do
      assert.equal("Alliance", Player.RACES[r].faction)
    end
    for _, r in ipairs({ "Orc", "Tauren", "Troll", "Undead", "SkyborneHorde" }) do
      assert.equal("Horde", Player.RACES[r].faction)
    end
  end)

  -- UnitRace's second return is the file token; the engine keys ForeverStartGuides by it
  -- (WoWPro_Leveling.lua:55 Scourge = 'Tirisfal Glades') and maps Scourge to Undead
  -- before matching R| tags (WoWPro_Parser.lua:1097-1099).
  it("gives Undead the client token Scourge and the display name Undead", function()
    assert.equal("Scourge", Player.RACES.Undead.token)
    assert.equal("Undead", Player.RACES.Undead.name)
    assert.equal("NightElf", Player.RACES.NightElf.token)
    assert.equal("Night Elf", Player.RACES.NightElf.name)
  end)

  -- ChrRaces 95/96 (QuestieDB src/corrections/enum/expansions.lua:27-28): two races with
  -- one client token. UnitRace in game (user, 2026-11-18): "High Order Skyborne",
  -- "Skyborne", 95 and "Windshaper Skyborne", "Skyborne", 96.
  it("has Skyborne as two races sharing the token Skyborne", function()
    for _, r in ipairs({ "SkyborneAlliance", "SkyborneHorde" }) do
      assert.equal("Skyborne", Player.RACES[r].token)
    end
    assert.equal("High Order Skyborne", Player.RACES.SkyborneAlliance.name)
    assert.equal("Windshaper Skyborne", Player.RACES.SkyborneHorde.name)
    assert.is_true(Player.can_play("SkyborneHorde", "SHAMAN"))
    assert.is_false(Player.can_play("SkyborneAlliance", "SHAMAN"))
    assert.is_true(Player.can_play("SkyborneAlliance", "MAGE"))
    assert.is_false(Player.can_play("SkyborneHorde", "MAGE"))
  end)

  it("spawns each race in its own start zone", function()
    local want = {
      Dwarf = { "Dun Morogh", 1426 }, Gnome = { "Dun Morogh", 1426 },
      Human = { "Elwynn Forest", 1429 }, NightElf = { "Teldrassil", 1438 },
      Orc = { "Durotar", 1411 }, Troll = { "Durotar", 1411 },
      Tauren = { "Mulgore", 1412 }, Undead = { "Tirisfal Glades", 1420 },
      SkyborneAlliance = { "Zephras Isle", 2521 }, SkyborneHorde = { "Zephras Isle", 2521 },
    }
    for race, z in pairs(want) do
      local p = Player.new({ race = race, class = Player.RACES[race].classes[1], faction = Player.RACES[race].faction })
      assert.equal(z[1], p.zone, race)
      assert.equal(z[2], p.map_id, race)
      assert.equal(Player.RACES[race].faction, p.faction, race)
      assert.equal(Player.RACES[race].token, p.race_token, race)
      assert.equal(race, p.race_key, race)
    end
  end)
end)
