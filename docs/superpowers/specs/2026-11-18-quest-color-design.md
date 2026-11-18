# Grade level findings by quest colour

Status: approved in conversation · 2026-11-18.

## Intent

Below-level findings were all "medium-high" whatever the gap, and every one in the user's
Dwarf run was under a level short (e.g. The Haunted Isle, "228 kills", one level at 31). The
user wants findings graded the way players already read the guide: by quest colour, in both
directions. Too hard (red/orange) and too trivial (grey) are both guide problems. Quests with
no combat difficulty are exempt from the too-hard side.

## Rules

**Colour** of a quest for a character, from `quest level − character level` (Classic
`GetQuestDifficultyColor`; **unverified for Forever** until checked in game):

| Colour | Quest level − character level |
|---|---|
| red | ≥ 5 |
| orange | 3 to 4 |
| yellow | −2 to 2 |
| green | below −2, above the grey line |
| grey | quest level ≤ `xp.gray_level(character level)` (the same Classic grey line as mobs; unverified for Forever) |

**Findings, one per accept the run plays,** at the character's level when it accepts:
- red: signal `quest-red`, severity **high**
- orange: `quest-orange`, **medium**
- grey: `quest-grey`, **low** ("little or no XP")
- yellow, green: none

**Too-hard exemption (red, orange only).** A quest is exempt when either test holds:
1. It has **no combat objective**. A combat objective is an NPC objective that's a kill (not
   talk-to, using the harness's existing talk-to rule), or an item objective whose QuestieDB
   item has `npcDrops`.
2. QuestieDB marks it as a **non-combat activity**:
   - it rewards Azeroth Commerce Authority reputation (faction 2586; 149 Forever quests,
     "Crate Return" and the "Craftsman's Writ" series, all listed level 60 and takeable at 1), or
   - it rewards Darkmoon Faire reputation (909), or
   - its `zoneOrSort` is −364 (Darkmoon Faire).

   Test 2 is needed because 9 Craftsman's Writs ask for crafted items QuestieDB also lists as
   rare mob drops.

The grey side applies to every quest.

**Below the required level** (the game refuses the accept; the harness grinds to it and logs it):
- The `below-level` signal stays, worded as levels short, from the real XP shortfall to one
  decimal: `"The Haunted Isle" is offered 0.9 levels below its level`, with the sentence
  `The guide reaches this accept 0.9 levels below level 32, the level the quest requires (the
  client ground 228 kills to get there).`
- Severity is **low** under 2 levels short (my call: within the simulation's missing XP from
  incidental kills and rested XP; the sentence then adds that), and **medium** at 2 or more.

**`L` (reach level) steps.** At a guide level check the character ends at `max(check, actual)`:
it grinds only when below the check point and is never moved back. The `LVL` tag is `level` or
`level;offset`, and WoWPro completes an `L` step at that point (`WoWPro_Broker.lua:2597-2645`):
- **no offset:** when `UnitLevel >= level`
- **negative offset:** when `UnitLevel == level and UnitXPMax - UnitXP <= -offset`, or when `UnitLevel > level`
- **positive offset:** when `UnitLevel == level and UnitXP >= offset`, or when `UnitLevel > level`

So an `L` step grinds to the `level;offset` point (`kills.grind_to_point`), and the update the
level-up needs refreshes the guide. A step that is not an `L` step never hides on an offset tag
(`WoWPro_Broker.lua:2648-2680`): the addon just completes it once the XP point is reached, and
grinding there would invent XP the guide never asks for. So an offset `LVL` tag on a non-`L`
step does not grind; a plain-integer `LVL` on a non-`L` step keeps grinding to that level
(Ruling G). Never patch the addon or the guide.

## Constraints

- All data comes from QuestieDB (quest level, objectives, item `npcDrops`, rewards,
  `zoneOrSort`) and the run. Colour thresholds and the grey line are labelled unverified for
  Forever in code and README.
- Findings format 2; new signals are labelled in `text.lua` with severities in `group.lua`.
  Deterministic.
- Non-goals: per-step level checks against the guide's `N Level …` notes; changing the
  enter/leave guide warnings.
