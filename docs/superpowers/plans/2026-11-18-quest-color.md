# Quest Colour Grading Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Level findings graded by quest colour (red high, orange medium, grey low), non-combat quests exempt from the too-hard side, below-required-level worded as levels short, and `L` steps completing as the game completes them.

**Architecture:**
- A pure `src/hwc/world/quest_color.lua` computes the colour.
- The catalog exposes the quest's `zone_or_sort` and a `Catalog:noncombat(qid)` test.
- The driver emits `quest-red` / `quest-orange` / `quest-grey` on each played accept, and the levels-short data on `below-level`.
- `group.lua` and `text.lua` grade and word them.

**Tech Stack:** LuaJIT 2.1, busted 2.3, luacheck 1.2.

**Spec:** `docs/superpowers/specs/2026-11-18-quest-color-design.md`

## Global Constraints

- Colour thresholds (`quest − character`): ≥5 red; 3-4 orange; −2..2 yellow; below that green, unless `quest level ≤ xp.gray_level(char)` (grey). All labelled "unverified for Forever (Classic)".
- Severities: `quest-red` high, `quest-orange` medium, `quest-grey` low. `below-level`: low when < 2 levels short, medium at ≥ 2.
- Exempt from red/orange: no combat objective (an NPC kill objective, or an item objective whose QuestieDB item has `npcDrops`), OR the quest rewards faction 2586 or 909 reputation, OR `zoneOrSort == -364`.
- Data from QuestieDB and the run only; never patch the guide or addon. Findings format 2. Deterministic. luacheck 0. Conventional Commits ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A quest with no level in the catalog** (a placeholder): no colour finding, no error. Test it.
2. **A repeatable accept played twice:** at most one colour finding per guide line (grouping dedupes by key). Make sure the key is stable.
3. **The character's level changes during the accept** (e.g. a grind to the required level): colour uses the level after any grind, the level at which the quest is actually taken. Test it.
4. **A quest with both a talk-to objective and a kill objective:** combat. Test it.
5. **A Craftsman's Writ (rewards 2586) whose item has `npcDrops`:** exempt. Test it with a fixture.

---

### Task 1: Colour rules and the non-combat test

**Files:**
- Create: `src/hwc/world/quest_color.lua`, `spec/world/quest_color_spec.lua`
- Modify: `src/hwc/catalog/init.lua` (`quest.zone_or_sort` from `zoneOrSort`; `Catalog:noncombat(qid) -> bool, reason`), `spec/catalog/catalog_spec.lua` and its fixture source

**Interfaces:**
- Produces:
  - `quest_color.of(char_level, quest_level) -> "red"|"orange"|"yellow"|"green"|"grey"|nil` (nil when either level is missing).
  - `Catalog:noncombat(qid) -> true, "no-combat-objective"|"commerce"|"darkmoon" | false`.
  - Reuse the existing talk-to rule from `src/hwc/world/kills.lua` (`talk_to`, exposing it if it's local) for NPC objectives.

- [ ] **Step 1: Failing specs:**
  - `of(32, 37) == "red"`; `of(32, 35) == "orange"`; `of(32, 34) == "yellow"`; `of(32, 30) == "yellow"`; `of(32, 29) == "green"`; `of(32, xp.gray_level(32)) == "grey"`; `of(nil, 5) == nil`.
  - `noncombat`:
    - no objectives → true, `no-combat-objective`
    - talk-to NPC → true
    - kill NPC → false
    - item with `npcDrops` → false
    - item without → true
    - rewards 2586 with an `npcDrops` item → true, `commerce`
    - rewards 909 → `darkmoon`
    - `zoneOrSort -364` → `darkmoon`
    - talk-to + kill → false
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement.** The header comment cites `GetQuestDifficultyColor` (Classic) and marks the values unverified for Forever.
- [ ] **Step 4: GREEN.** Full suite plus luacheck.
- [ ] **Step 5: Commit** `feat: Add quest colour rules and a non-combat quest test`.

### Task 2: Colour findings and levels-short wording

**Files:**
- Modify:
  - `src/hwc/driver/run.lua` (after an accept is acted, emit `quest-red`/`quest-orange`/`quest-grey` with `quest_level`, `char_level`, `color`, `exempt`; on `below-level`, record `levels_short` from the real XP shortfall: `required − (level_before + xp_before / xp_max_before)`, to one decimal)
  - `src/hwc/findings/group.lua` (severities; `below-level` severity by `levels_short` per the Global Constraints, keeping every other signal's fixed severity)
  - `src/hwc/findings/text.lua` (labels, titles, sentences)
  - `README.md` (a short "Level findings" note with the table and the unverified label)
- Test: `spec/driver/run_spec.lua`, `spec/findings/group_spec.lua`, `spec/findings/text_spec.lua`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - **Titles:**
    - `"<name>" is red for this character (quest level Q, character level C)`; orange the same way
    - `"<name>" is grey for this character (quest level Q, character level C)`
    - `below-level`: `"<name>" is offered N.N levels below its level`
  - **Sentences:**
    - red/orange: `The guide sends a level C character to a level Q quest with combat objectives.`
    - grey: `The quest is grey at level C, so it gives little or no XP.`
    - below-level: `The guide reaches this accept N.N levels below level R, the level the quest requires (the client ground K kills to get there).` When N.N < 2, it adds: ` Gaps under 2 levels are within what the simulation's missing XP explains (no incidental kills or rested XP).`

- [ ] **Step 1: Failing specs** (run_spec, group_spec, text_spec) for each colour, the exemption, each sentence, and `below-level` severity at 0.9 → low and 2.5 → medium. Review Focus 1-4.
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: GREEN.** Full suite, slow suite (21 + 1 known pending; anchors unchanged), luacheck; `web/report` `npm test` if fixture JSON changes.
- [ ] **Step 5: Real check.** From `~/Projects/WoW-Pro-Guides`, run `<worktree>/bin/hwc run --race Dwarf --class WARRIOR --date 2026-11-18 --out "$TMPDIR/qc"`.
  - Paste the counts per new signal.
  - Paste The Haunted Isle's findings: below-level about 0.9 levels, low; and no red finding, because it's a delivery.
  - Paste any red or orange findings with their quest.
- [ ] **Step 6: Commit** `feat: Grade level findings by quest colour`.

### Task 3: Level checks grind to exactly the point the guide checks

User rule (2026-11-18): at a guide level check the character ends at `max(check, actual)`. It grinds only when below the check point and is never moved back.

Cause of today's `did-not-advance` on `L Level 3/4/6/10` (`01_12_Dun_Morogh.lua:44,60,108,219-220`): their `LVL` tag carries an XP offset (`LVL|2;-1234`). WoWPro completes an `L` step at `level;offset` like this (`WoWPro_Broker.lua:2597-2645`):
- **no offset:** when `UnitLevel >= level`
- **negative offset:** when `UnitLevel == level and UnitXPMax - UnitXP <= -offset`, or when `UnitLevel > level`
- **positive offset:** when `UnitLevel == level and UnitXP >= offset`, or when `UnitLevel > level`

`perform_level` (`src/hwc/driver/actions.lua:704`) reads only the integer, so it stops short.

**Files:**
- Modify:
  - `src/hwc/driver/actions.lua` (`perform_level`: parse `level;offset`, and grind to the check point when the character is below it)
  - `src/hwc/world/kills.lua` (a grind-to-XP-point helper, if `grind_to` can't express it)
- Test: `spec/driver/actions_spec.lua` (or wherever `perform_level` is tested), `spec/world/kills_spec.lua`

**Interfaces:**
- Produces: `kills.grind_to_point(player, level, xp) -> kills, xp_gained, levels`, which grinds until `player.level > level` or (`player.level == level` and `player.xp >= xp`). Reuse `grind_to`'s same-level mob model.

- [ ] **Step 1: Failing specs:**
  - `LVL|2;-650` at level 2 with 900 XP to go: grinds, and ends with `max - xp <= 650` at level 2 (or level 3 if one kill overshoots).
  - At level 2 with 400 to go: no grind, and `out.grind` is nil.
  - At level 3: no grind.
  - `LVL|5;300` at level 5 with 100 XP: grinds to at least 300 XP.
  - `LVL|10` with no offset: unchanged (grinds to 10 only when below).
  - The check applies the same way for non-`L` steps that carry `LVL` (today's Ruling G).
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement.** For a negative offset the target is `xp >= xp_max(level) + offset`.
- [ ] **Step 4: GREEN.** Full and slow suites plus luacheck. Real Dwarf run (same command as Task 2): the four Dun Morogh `L` `did-not-advance` findings are gone. Paste the new per-signal counts, including quest-red, quest-orange and below-level.
- [ ] **Step 5: Commit** `fix: Grind level checks to the XP point the guide checks`.
