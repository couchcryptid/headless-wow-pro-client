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

### Task 3: `L` steps complete as the game completes them

**Files:**
- Investigate:
  - `~/Projects/WoW-Pro-Guides/WoWPro` (which event makes WoWPro refresh after a level-up; check `WoWPro.lua` event registration lists and `RegisterBucketEvent`)
  - the harness's level-up path (`src/hwc/world/player.lua` `add_xp`, the driver's `after_levels`)
- Modify: the harness's level-up event firing (wherever events are fired after XP), only to fire what the real client fires
- Test: `spec/driver/run_spec.lua` or the stubs/world specs

- [ ] **Step 1: Investigate and write the evidence into the report:** the event(s) WoWPro registers that run `UpdateGuide`/`NextStep` on a level change (e.g. `PLAYER_LEVEL_UP`, `PLAYER_XP_UPDATE`), with file:line, and what the harness fires today after `add_xp` levels up.
  - **If the client fires an event WoWPro listens for and the harness doesn't fire it,** go on to Step 2.
  - **If WoWPro registers nothing that refreshes on a level-up,** stop and report. The finding is then real addon behaviour.
- [ ] **Step 2: Failing spec:** a level-up during a scripted run fires that event, and an `L` step for the new level completes without a manual click.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: GREEN.** Full and slow suites plus luacheck. Real Dwarf run: the `did-not-advance` findings for `L Level 3/4/6/10` in Dun Morogh are gone (or explained, if Step 1 stopped).
- [ ] **Step 5: Commit** `fix: Fire the level-up event the client fires`.
