-- Profession name -> { spell, primary }. `spell` teaches the profession: learning it at a
-- trainer teaches a "Learn Skill (<profession>)" effect. The guides' SPELL tags test these
-- ids with IsPlayerSpell (WoWPro_Broker.lua:3330-3366), e.g. the Camping 101 accepts'
-- "SPELL|First Aid; 3273; Flip" shows the step only once the spell is known. `primary`
-- marks the nine professions a character is limited to two of; the rest are secondary.
return {
  Alchemy = { spell = 2259, primary = true },
  Blacksmithing = { spell = 2018, primary = true },
  Cooking = { spell = 2550, primary = false },
  Enchanting = { spell = 7411, primary = true },
  Engineering = { spell = 4036, primary = true },
  ["First Aid"] = { spell = 3273, primary = false },
  Fishing = { spell = 7620, primary = false },
  Herbalism = { spell = 2366, primary = true },
  Leatherworking = { spell = 2108, primary = true },
  Mining = { spell = 2575, primary = true },
  Skinning = { spell = 8613, primary = true },
  Tailoring = { spell = 3908, primary = true },
}
