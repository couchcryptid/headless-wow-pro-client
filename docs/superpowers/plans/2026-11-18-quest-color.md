# Quest Colour Grading Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Level findings graded by quest colour (red high, orange medium, grey low), non-combat quests exempt from the too-hard side, below-required-level worded as levels short, and `L` steps completing as the game completes them.

**Superseded in part:** Task 6 supersedes this Goal and the Global Constraints below: quest-colour grading was removed, and the client grades only whether the character can accept a quest plus the guide's own level checks.

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

### Task 4: One gap scale at every level check

User request (2026-11-18): every point where the harness compares the character's level with what the guide or quest expects reports the size of the gap, in levels, on one scale.

**The scale.** The gap is fractional levels from real XP: `level + xp / xp.to_next(level)`, rounded to one decimal, using the existing "less than 0.1" wording below 0.05.
- `< 2`: **low**. Add the sentence ` Gaps under 2 levels are within what the simulation's missing XP explains (no incidental kills or rested XP).`
- `2 to < 4`: **medium**
- `>= 4`: **high**

**The checks:**

| Check | Signal | When | Gap |
|---|---|---|---|
| Guide level check (`L` step, or the `LVL` tag on any step) | new `level-check` | the character arrived below the check point (a grind happened) | check point − level before the grind |
| Accept below the required level | `below-level` (existing) | as today | levels short (existing); the scale adds **high** at ≥ 4 |
| Quest above the character | `quest-red` / `quest-orange` (existing names) | judged at the **do step**: the first `C` or `K` step for the qid after its accept, or the `T` step if there is none. The colour band (Task 1, integer levels) decides whether a finding exists | `quest level − fractional character level` at the do step; severity comes from the scale, not the band |

- **Not changed:** the non-combat exemption, grey (low, judged at the accept as today), and one colour finding per guide line, now keyed on the do-step line.
- **Older logs** without the new data keep today's severities and wording.

**Files:**
- Create: `src/hwc/findings/gap.lua` with `gap.severity(g)`, `gap.text(g)` ("N.N" or "less than 0.1") and `gap.MARGIN_SENTENCE`. `below-level` uses it too, replacing its private rounding and wording helpers.
- Modify:
  - `src/hwc/driver/actions.lua`: record `out.grind.short` for level-check grinds as well (the point minus the fractional level before)
  - `src/hwc/driver/run.lua`: emit `level-check`; move the colour judgement to the do step and carry `gap`, `do_action` and `accept_gap`
  - `src/hwc/findings/group.lua`
  - `src/hwc/findings/text.lua`
  - `README.md` ("Level findings": the scale and the three checks)
  - the report label fixtures if they change
- Test: `spec/findings/gap_spec.lua`, `spec/driver/run_spec.lua`, `spec/driver/actions_other_spec.lua`, `spec/findings/group_spec.lua`, `spec/findings/text_spec.lua`

**Wording:**
- **level-check title:** `The guide's level check "<step name>" is reached N.N levels short`
- **level-check sentence:** `The client ground K kills to reach the point the guide checks (level L<point>).` `<point>` is one of:
  - `, within X XP of level L+1` (negative offset)
  - `, with at least X XP` (positive offset)
  - nothing (no offset)

  Then the margin sentence when the gap is under 2.
- **quest-red / quest-orange title:** `"<name>" is N.N levels above the character when the guide has you do it (<colour>)`
- **quest-red / quest-orange sentence:** `The guide has a level C.C character do a level Q quest with combat objectives at this step; it was A.A levels above at the accept.` (The second clause appears only when `accept_gap` is known.)

**Review Focus:**
1. A quest accepted but never done (no C, K or T step played) gives no colour finding.
2. A do step whose qid list holds several quests judges each quest.
3. A level check that needs no grind gives no `level-check`.
4. An older log without `gap` keeps the old severity.

- [ ] **Step 1: Failing specs:**
  - `gap.severity(1.9)=='low'`, `(2)=='medium'`, `(3.9)=='medium'`, `(4)=='high'`; `gap.text(0.04)=='less than 0.1'`.
  - `level-check` emitted with gap 0.5 for a `LVL|2;-650` grind from level 1.81 (check point 2 + 250/900 ≈ 2.28).
  - Colour judged at the C step, not the accept: accepted at char 20 (quest 26 is red there), done at 23.7, so the gap is 2.3, severity medium, signal `quest-orange`.
  - `below-level` gap 4.5 is high.
  - Review Focus 1-4.
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: GREEN.**
  - Run the full suite, the slow suite and luacheck, plus `web/report` `npm test` if the fixtures change.
  - Do the real Dwarf run.
  - Paste the counts per signal and severity, and the high findings with their gaps.
- [ ] **Step 5: Commit** `feat: Report the level gap at every check on one scale`.

### Task 5: Low quests graded by how soon they lead to a quest at your level

User request (2026-11-18): lessen or increase the severity of a low-level quest by the number of hops to a follow-up at the character's level, never exceeding the severity its gap alone gives.

**Rules:**
- **A low quest** is one judged green or grey at its accept (`quest_color.of`). Both now give a finding.
  - Grey keeps the signal `quest-grey`.
  - Green gets the new signal `quest-green`.
  - The gap is `fractional character level − quest level` at the accept.
  - Its base severity is `gap.severity(gap)`, from Task 4.
- **A follow-up** is a quest reached through QuestieDB's `nextQuestInChain`, or a quest whose `preQuestSingle` or `preQuestGroup` lists this one.
  - Hop 1 is a direct follow-up; hop 2 is a follow-up of a follow-up. Search no further.
  - A follow-up counts only if its quest level is at least `character level at the accept − 2` (yellow or higher) **and** the run accepts it. A payoff the guide skips doesn't excuse the low quest.
- **The cap by nearest hop:**

  | Nearest qualifying follow-up | Severity cap |
  |---|---|
  | hop 1 | low |
  | hop 2 | medium |
  | none within 2 hops | the base severity |

  Final severity is `min(base, cap)`, which can never exceed the base.
- **Wording:**
  - title: `"<name>" is N.N levels below the character (<green|grey>)`
  - sentence: the base sentence (grey keeps its XP-rate clause), then one of:
    - ` It leads to "<follow-up name>" (level Q), at your level, H hop(s) on.`
    - ` Nothing at your level follows within two quests.`
- **Expected on the Dwarf run** (the controller's offline estimate): 41 low quests; base 15 high and 26 medium; after the cap, 7 high, 17 medium and 17 low.

**Files:**
- Modify:
  - `src/hwc/catalog/init.lua`: `Catalog:follow_ups(qid) -> { {qid, level, name, hop}, ... }` up to hop 2, deterministic order
  - `src/hwc/driver/run.lua`: emit `quest-green` and `quest-grey` with `gap`, plus `follow_up = {qid, name, level, hop}` or nil, decided at `Driver:finish` once the run's accepts are known
  - `src/hwc/findings/group.lua`
  - `src/hwc/findings/text.lua`
  - `README.md`
  - the report label fixtures
- Test: `spec/catalog/catalog_spec.lua`, `spec/driver/run_spec.lua`, `spec/findings/group_spec.lua`, `spec/findings/text_spec.lua`

**Review Focus:**
1. A follow-up the run never accepts doesn't lower the severity.
2. Chain cycles terminate.
3. A quest with several hop-1 follow-ups picks the nearest qualifying one, deterministically: lowest hop, then the one accepted first in the run, then the lowest qid.
4. Older logs keep today's grey wording and low severity.

- [ ] **Step 1: Failing specs** for the hop search, the cap table (base high with hop 1 → low, hop 2 → medium, none → high; base medium with hop 2 → medium) and Review Focus 1-4.
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: GREEN.**
  - Run the full suite, the slow suite, luacheck and npm test.
  - Do the real Dwarf run.
  - Paste the per-severity counts for quest-green and quest-grey, and each high one with its gap.
- [ ] **Step 5: Commit** `feat: Grade low quests by how soon they lead to a quest at your level`.

### Task 6: Grade only whether the character can accept the quest

User decision (2026-11-18): the line is "can this character accept this quest", and the gap gauges how far off they are from being able to. Quest colour (red/orange: too hard; green/grey: too easy) is a routing decision that belongs to the guide, not to this client.

**Remove:**
- The signals `quest-red`, `quest-orange`, `quest-green` and `quest-grey`: their emission in `run.lua` (accept- and do-step judging, `awaiting_do`, `pre_step`, follow-up attachment), and their severities, titles and sentences in `group.lua`/`text.lua`.
- The code only they use:
  - `src/hwc/world/quest_color.lua`
  - `Catalog:noncombat`, `Catalog:follow_ups` and the reverse prerequisite index (with `Source:quest_ids` if nothing else uses it)
  - `kills.talk_to`'s export, if nothing else uses it
  - their specs, fixtures and README text
- Before deleting anything, `grep` for other users.

**Keep:**
- `below-level` (accept below the required level), graded on the gap scale: low < 2, medium < 4, high ≥ 4. Its levels-short wording stays, as does the "less than 0.1" case and the margin sentence.
- `level-check` (the guide's own level checks) on the same scale.
- `gap.lua`, `Player:fractional_level`, and the Task 3 grind-to-point behaviour, including non-L offset tags not grinding.
- Older findings files that contain colour signals must still load in the report and in `hwc diff` without errors. Keep a label for each removed signal if the report or diff needs one, and say so in the README.

**README "Level findings":** describe the two checks and the scale. Add one line saying the client doesn't grade quest difficulty or colour, because those are routing decisions for the guide.

- [ ] **Step 1: Failing specs:**
  - A played accept 5+ levels below the quest's level, at or above its required level, emits no finding.
  - `below-level` with a gap of 4.5 is high.
  - An older findings file with a `quest-red` finding still groups and renders without error.
- [ ] **Step 2: RED.**
- [ ] **Step 3: Remove and implement.**
- [ ] **Step 4: GREEN.**
  - Full suite, slow suite, luacheck and npm test (regenerate the label fixtures).
  - Real Dwarf run: paste the per-signal and per-severity counts. The `quest-*` signals should be gone; `below-level` and `level-check` are kept.
- [ ] **Step 5: Commit** `feat!: Grade only whether the character can accept a quest`. The body explains that the quest colour findings were removed.
