# Reputation from Quest Rewards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Characters gain reputation from quest rewards, WoWPro's `REP|` steps evaluate against real standings through a `C_Reputation` stub, reputation-gated accepts are enforced, and unmet-faction `REP` steps become findings.

**Architecture:**
- `src/hwc/world/reputation.lua` is a pure rules module, like `xp.lua`: bands, standings, start tables and met-at values.
- A world-side reputation state, created in `World.new`, holds points per faction. `QuestLog:turn_in` credits it and `QuestLog:refusal` gates on it.
- A `C_Reputation` stub reads the state and records the lookups it was asked for. The driver turns a lookup for an unmet faction into a `rep-faction-unmet` finding.

**Tech Stack:** LuaJIT 2.1, busted 2.3, luacheck 1.2.

**Spec:** `docs/superpowers/specs/2026-11-18-reputation-design.md`

## Global Constraints

- Every rule cites its evidence. Forever-verified facts carry the date and how they were checked. Classic-only or inferred facts are labelled "unverified for Forever" in code comments and README. No Diplomacy and no racial bonus.
- Forever API: `C_Reputation.GetFactionDataByID(id)` returns a table, or nil for an unmet faction. `GetFactionInfoByID` stays undefined.
- Scale: points are cumulative and Neutral starts at 0.
  - Verified in Forever: Neutral [0, 3000), Friendly [3000, 9000), Honored [9000, 21000).
  - Unverified: Hated [−42000, −6000), Hostile [−6000, −3000), Unfriendly [−3000, 0), Revered [21000, 42000), Exalted [42000, 42999].
  - `reaction`: 1 Hated … 8 Exalted.
- Dwarf start (Forever, fresh level 1, 2026-11-18): {47 = 4000, 54 = 3100, 69 = 3100, 72 = 3100}.
- Met at (Forever, 2026-11-18): {92 = 2000, 93 = 2000}. Any other faction is met at 0, which is an assumption.
- Gains: only on a successful turn-in, from `reputationReward`, at full value (scaling is unverified), clamped to [−42000, 42999].
- Findings:
  - A reputation refusal is `accept-refused`, reason `reputation`, confidence `unverified`.
  - An unmet-faction `REP` step is the new signal `rep-faction-unmet`, confidence `unverified`.
  - Both sentences say that reputation from kills, item turn-ins and encounters isn't modelled.
- No third-party data committed. Faction names come from the installed QuestieDB at run time; an id with no constant shows as "Faction <id>".
- Findings format stays 2. Run-specific assumptions are appended to the header's `gaps` array.
- `reputation.lua` is pure. Determinism holds: anything iterating factions sorts by id.
- Run `~/.luarocks/bin/busted`, `~/.luarocks/bin/busted --tags=slow` (needs the `local` symlink to the main checkout's `local/`, already present in this worktree) and `~/.luarocks/bin/luacheck .` with 0 warnings.
- Conventional Commits, each ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Large negative rewards** (e.g. many Magram −500 turn-ins): points clamp at −42000, `standing` returns Hated, and nothing errors. Test in Task 1.
2. **One quest rewarding a known faction and an unknown one:** both are applied, and the unknown one is created at its met-at value before the reward is added (1382: Gelkis +100 on 2000 → 2100; Magram −500 on 2000 → 1500). Test in Task 2.
3. **A race with no start table and no inferred home** (Skyborne): it starts with the three other capitals of its side and turn-ins still work. Test in Task 2.
4. **WoWPro passing the faction id as a string** (`"92"`): the stub coerces it with `tonumber`, and a non-numeric value returns nil without an error. Test in Task 3.
5. **Run-log determinism:** reputation changes are recorded in turn-in order, and any per-faction listing is sorted by id. Two drives of the same script encode to identical JSON. Test in Task 2.

---

### Task 1: Rules module

**Files:**
- Create: `src/hwc/world/reputation.lua`, `spec/world/reputation_spec.lua`

**Interfaces:**
- Produces (pure; no other hwc requires except `hwc.world.player` for `Player.RACES` factions):
  - `reputation.MIN = -42000` and `reputation.MAX = 42999`.
  - `reputation.BANDS`: an array of `{ reaction, name, lower, upper, verified }`, Hated to Exalted.
  - `reputation.standing(points) -> reaction, lower, upper`.
  - `reputation.clamp(points) -> number`.
  - `reputation.start(race_key) -> { [factionID] = points }, inferred`. `inferred` is a boolean: false for Dwarf, true otherwise. Returns a fresh copy.
  - `reputation.met_at(factionID) -> points, assumed`. `assumed` is a boolean: false for 92 and 93, true (with 0) otherwise.
  - `reputation.CAPITALS = { Alliance = {72, 47, 54, 69}, Horde = {76, 81, 530, 68} }`.
  - `reputation.HOME = { Dwarf = 47, Gnome = 54, Human = 72, NightElf = 69, Orc = 76, Troll = 530, Tauren = 81, Undead = 68 }`. Skyborne races have no entry.

- [ ] **Step 1: Failing tests** in `spec/world/reputation_spec.lua`:
  - `standing(0)` → `4, 0, 3000`; `standing(2999)` → `4`; `standing(3000)` → `5, 3000, 9000`; `standing(9475)` → `6, 9000, 21000`; `standing(16362)` → `6`; `standing(-1)` → `3`; `standing(-42000)` → `1`; `standing(42999)` → `8`.
  - `clamp(-50000) == -42000`; `clamp(50000) == 42999` (Review Focus 1).
  - `start("Dwarf")` equals `{ [47]=4000, [54]=3100, [69]=3100, [72]=3100 }`, with `inferred == false`.
  - `start("Gnome")` equals `{ [54]=4000, [47]=3100, [69]=3100, [72]=3100 }`, with `inferred == true`. `start("Orc")[76] == 4000`.
  - `start("SkyborneHorde")` equals `{ [76]=3100, [81]=3100, [530]=3100, [68]=3100 }`.
  - `met_at(92)` → `2000, false`; `met_at(91)` → `0, true`.
  - Mutating the table `start` returns leaves the next call unchanged.
  - Each `BANDS` entry for Neutral, Friendly and Honored has `verified == true`; every other entry has `false`.
- [ ] **Step 2: RED.** `~/.luarocks/bin/busted spec/world/reputation_spec.lua` → module not found.
- [ ] **Step 3: Implement.** The header comment cites each fact's evidence as in Global Constraints.
- [ ] **Step 4: GREEN**, plus luacheck.
- [ ] **Step 5: Commit** `feat: Add Forever reputation rules`.

---

### Task 2: Catalog fields, world state, turn-in gains and the accept gate

**Files:**
- Modify:
  - `src/hwc/catalog/init.lua` (`build_quest`; add `reputation_reward`, `min_rep`, `max_rep` to `SUPPLEMENT_FIELDS`)
  - `src/hwc/world/init.lua` (`World.new` creates `world.reputation`)
  - `src/hwc/world/questlog.lua` (`refusal`, `turn_in`)
  - `src/hwc/driver/run.lua` (`REFUSAL_SIGNALS`, the refusal's confidence, the run-log `reputation` field)
  - `src/hwc/findings/text.lua` (the `reputation` reason sentence)
- Create: `src/hwc/world/reputation_state.lua`
- Test: `spec/world/reputation_state_spec.lua`, `spec/world/questlog_spec.lua`, `spec/catalog/catalog_spec.lua`, `spec/driver/run_spec.lua`, `spec/findings/text_spec.lua`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - **Catalog quest fields:**
    - `quest.reputation_reward`: an array of `{ faction = id, value = n }`, in QuestieDB order (an empty array when absent).
    - `quest.min_rep` / `quest.max_rep`: `{ faction = id, value = n }` or nil.
  - **`ReputationState.new(race_key, faction_side) -> state`,** stored as `world.reputation`, with:
    - `state:points(id) -> number | nil` (nil when unknown)
    - `state:known(id) -> bool`
    - `state:value_for_gate(id) -> number` (points, or met-at when unknown)
    - `state:gain(id, value) -> new_points`, which creates the faction at met-at first
    - `state:assumptions() -> { string… }`: the start table when inferred, plus "factions first met at an assumed Neutral 0: <sorted names>"
    - `state.changes`: an array of `{ qid, faction, value, total, assumed_start }`
    - `state.lookups`: a set, written by Task 3
  - **`QuestLog:refusal`** returns `"reputation"` (after the prerequisite checks) when `min_rep` is set and `value_for_gate < min_rep.value`, or when `max_rep` is set and `value_for_gate >= max_rep.value`.
  - **`QuestLog:turn_in`** applies `reputation_reward` after XP, appending to `state.changes` with the qid.
  - **Driver:**
    - `REFUSAL_SIGNALS.reputation = "accept-refused"`.
    - A signal whose reason is `reputation` gets `confidence = "unverified"` (overriding `Driver:confidence`).
    - The run log gains `log.reputation = { changes = state.changes, assumptions = state:assumptions() }`.
  - **Text:** the reason `reputation` gets the sentence "The quest data needs <standing> with <faction>; this character has <standing> (<points>). Reputation from kills, item turn-ins and encounters isn't modelled, so a real player may have it." Standing names come from `BANDS`.

- [ ] **Step 1: Failing tests:**
  - catalog_spec: quest 1382 from the fixture source (add the field to `spec/fixtures/catalog/questie_source.lua` if missing) gives `reputation_reward == { {faction=93,value=-500}, {faction=92,value=100} }`.
  - reputation_state_spec:
    - A Dwarf starts with `points(47) == 4000` and `known(92) == false`.
    - `gain(92, 100) == 2100` and `known(92) == true`.
    - Gelkis +100 then Magram −500 gives 2100 and 1500 (Review Focus 2).
    - SkyborneAlliance starts with `points(72) == 3100` and no home (Review Focus 3).
    - `assumptions()` names "Gnome" as inferred for a Gnome, and lists "Faction 91" after `gain(91, 1)` (pass a names table in, so the spec doesn't depend on QuestieDB).
  - questlog_spec:
    - A quest with `min_rep = {faction=72, value=9000}` is refused `"reputation"` for a fresh Dwarf (3100) and accepted after `gain(72, 6000)`.
    - `max_rep = {faction=92, value=3000}` is accepted for an unmet Gelkis (2000) and refused after `gain(92, 1000)`.
    - `turn_in` of a quest with `reputation_reward` appends to `changes` with the qid.
  - run_spec:
    - A scripted accept refused `reputation` yields an `accept-refused` signal with `confidence == "unverified"`.
    - Two drives encode to identical `log.reputation` JSON (Review Focus 5).
  - text_spec: the `reputation` sentence contains "Friendly", "Stormwind" and "isn't modelled".
- [ ] **Step 2: RED.** `~/.luarocks/bin/busted spec/world spec/catalog spec/driver/run_spec.lua spec/findings/text_spec.lua`.
- [ ] **Step 3: Implement.** `World.new` already knows `cfg.race` and the faction; pass the QuestieDB faction names, via the catalog, into the state for `assumptions()`.
- [ ] **Step 4: GREEN.** Full suite plus luacheck.
- [ ] **Step 5: Commit** `feat: Gain reputation from quest rewards and gate accepts on it`.

---

### Task 3: The `C_Reputation` stub

**Files:**
- Modify: `src/hwc/stubs/core.lua` (or a new `src/hwc/stubs/reputation.lua`, installed from `stubs.install`; follow how `questlog.lua` is installed)
- Test: `spec/stubs_spec.lua`

**Interfaces:**
- Consumes: `world.reputation` (Task 2), `reputation.standing` (Task 1).
- Produces:
  - `env.C_Reputation = trap(sb, "C_Reputation", { GetFactionDataByID = fn })`.
  - `fn(id)` does `id = tonumber(id)`, records `world.reputation.lookups[id] = true` when `id` is a number, and returns nil when the faction is unknown. Otherwise it returns the table spec §4.4 specifies: `reaction`, `currentStanding`, `currentReactionThreshold`, `nextReactionThreshold`, `name`, `factionID`, and `hasBonusRepGain = false`, with the other booleans false and `description = ""`.
  - `env.GetFactionInfoByID` stays nil.

- [ ] **Step 1: Failing tests:**
  - For a Dwarf: `GetFactionDataByID(47)` gives `reaction 5`, `currentStanding 4000`, `currentReactionThreshold 3000`, `nextReactionThreshold 9000`.
  - `GetFactionDataByID(92)` is nil, and `lookups[92]` is true.
  - `GetFactionDataByID("47").currentStanding == 4000`; `GetFactionDataByID("x")` is nil and doesn't raise (Review Focus 4).
  - `env.GetFactionInfoByID == nil`.
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: GREEN.** Full suite plus luacheck.
- [ ] **Step 5: Commit** `feat: Stub C_Reputation from the simulated reputation`.

---

### Task 4: `rep-faction-unmet`, run gaps and harness-error classification

**Files:**
- Modify:
  - `src/hwc/driver/engine.lua` (`Engine:step(i)` adds `rep = W.rep and W.rep[i]`)
  - `src/hwc/driver/run.lua` (emit the signal)
  - `src/hwc/findings/group.lua` (severity `rep-faction-unmet = "medium"`)
  - `src/hwc/findings/text.lua` (label "REP faction never met", title, sentence)
  - `src/hwc/findings/report.lua` (static GAPS line; `report.build` appends `header.assumptions`)
  - `src/hwc/cli/run_output.lua` (`header.assumptions = log.reputation.assumptions`)
  - `src/hwc/boot.lua` (`is_harness_error(e, missing)`)
  - callers of `is_harness_error` in `src/hwc/driver/run.lua` and `src/hwc/doctor.lua` (pass `sb.missing` where they have it)
- Test: `spec/driver/run_spec.lua`, `spec/findings/group_spec.lua`, `spec/findings/text_spec.lua`, `spec/findings/report_spec.lua`, `spec/integration/boot_spec.lua` or a unit spec for `boot.is_harness_error`

**Interfaces:**
- Consumes: `state.lookups`, `state:known` (Tasks 2-3).
- Produces:
  - **The signal.** When a guide closes (`Driver:close`), for each captured step with a `rep` tag, take the faction id (the second `;`-separated field, `tonumber`). If `lookups[id]` is set and `known(id)` is false, emit one signal `{ signal = "rep-faction-unmet", gid, file, line, action, name, qid, faction = id, confidence = "unverified" }` per step.
    - The title is `REP step checks <faction name or "Faction <id>">, which this character never met`.
    - The sentence: "WoWPro asks for reputation with faction <id>, but this character has never met that faction, so the step is skipped. Reputation from kills and encounters isn't modelled; if the guide meant another faction, the id is wrong."
  - **Gaps.**
    - Add to `report.GAPS`: `"reputation is gained from quest rewards only (no kills, item turn-ins or encounters)"`.
    - `report.build` sets `h.gaps` to `report.GAPS` followed by `header.assumptions` (when present), without mutating `report.GAPS`.
  - **Harness errors.** `boot.is_harness_error(e, missing)` adds a rule: the message matches `attempt to (index|call) (field|global) '([^']+)' %(a nil value%)` and that bare name is a key of `missing`, or the last part of a `ns.field` key in it.

- [ ] **Step 1: Failing tests:**
  - run_spec: a scripted engine whose guide has a step with `rep = "Gelkis Clan Centaur;91;hated-neutral"`, with `lookups[91] = true` and 91 unknown, yields one `rep-faction-unmet` signal with `faction == 91` and `confidence == "unverified"`. With 91 known, no signal.
  - group_spec: the signal gets severity `medium`.
  - text_spec: the title for faction 91 with no name contains `Faction 91`.
  - report_spec: `build(…, { assumptions = { "x" } }).header.gaps` ends with `"x"`, and `report.GAPS` is unchanged afterwards.
  - is_harness_error:
    - `{ msg = "…/WoWPro_CompatUtil.lua:243: attempt to index field 'C_Reputation' (a nil value)" }` with `missing = { C_Reputation = true }` → true; with `{}` → false.
    - `"… attempt to call global 'GetFactionInfoByID' (a nil value)"` with `{ GetFactionInfoByID = true }` → true.
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement.** The text_spec scan of `run.lua` reasons must still pass, so label every new reason.
- [ ] **Step 4: GREEN.** Full suite plus luacheck.
- [ ] **Step 5: Commit** `feat: Report REP steps for unmet factions and run-specific gaps`.

---

### Task 5: Verify on the real addon, and document

**Files:**
- Modify: `README.md` (World and catalog: a "Reputation" paragraph, plus the evidence table summarised from the spec §2 with the unverified rows marked)
- Test: none new. This is a verification run.

- [ ] **Step 1: Real run.** From `~/Projects/WoW-Pro-Guides`, run `<worktree>/bin/hwc run --race Dwarf --class WARRIOR --date 2026-11-18 --out "$TMPDIR/rep"`. Expected:
  - No `stopped early: Stuck on a step` at `30_41_Alliance.lua:542`.
  - The findings JSON has one `rep-faction-unmet` with `faction == 91` at `30_41_Alliance.lua:544`.
  - No `lua-error` with `C_Reputation` in its message.
  - Paste the summary lines and the stop reason into the commit body. If the run stalls somewhere new, stop and report the step. Don't fix it here.
- [ ] **Step 2: Slow suite.** `~/.luarocks/bin/busted --tags=slow` gives 21 passes and 1 known pending (Farsen's Watch), with #3535 still Red on `main`.
- [ ] **Step 3: README.**
- [ ] **Step 4: Commit** `docs: Describe reputation and its evidence`.
