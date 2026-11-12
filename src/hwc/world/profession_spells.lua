-- Profession name -> the spell that teaches it. Learning a profession at a trainer
-- teaches this spell; each spell's Wowhead Forever page (wowhead.com/forever/spell=<id>,
-- checked 2026-11-12) has a "Learn Skill (<profession>)" effect. The guides' SPELL tags
-- test these ids with IsPlayerSpell (WoWPro_Broker.lua:3330-3366), e.g. the Camping 101
-- accepts' "SPELL|First Aid; 3273; Flip" shows the step only once the spell is known.
return {
  Alchemy = 2259, Blacksmithing = 2018, Cooking = 2550, Enchanting = 7411, Engineering = 4036,
  ["First Aid"] = 3273, Fishing = 7620, Herbalism = 2366, Leatherworking = 2108, Mining = 2575,
  Skinning = 8613, Tailoring = 3908,
}
