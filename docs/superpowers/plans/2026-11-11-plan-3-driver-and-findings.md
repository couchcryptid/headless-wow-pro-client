# Plan 3: Driver and findings

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Play the real WoW-Pro engine's Forever Alliance guides from level 1 to 25 as a simulated player who does every shown step. Record every place the guide breaks as a signal, and write one canonical findings markdown per invocation for the Dwarf/Gnome race, class and profession matrix.

**Architecture:**
- **Engine adapter** (`src/hwc/driver/engine.lua`): wraps a booted sandbox. It reads only engine state: the current step, the visible rows, the step tag arrays, `why[]`, completion and the guide registry. It fires client events, settles the clock and performs the two player-equivalent calls the spec allows, a right-click completion and the forced update after a level-up. It never writes `WoWPro.*` state.
- **Step actions** (`src/hwc/driver/actions.lua`): turn a step record into world changes plus the client event sequence (spec §5.2). They return an outcome record. Refusals are reported, never hidden.
- **Driver loop** (`src/hwc/driver/run.lua`): spec §4.4. It records a JSON-able run log of step snapshots and signals, follows the engine's own next-guide autoload and stops at the stop conditions.
- **Findings** (`src/hwc/findings/`): group the signals from all of a matrix's run logs into findings, with stable ids, severities and root-cause links, and render sorted, byte-identical markdown.

**Tech Stack:** LuaJIT 2.1 (`/opt/homebrew/bin/luajit`), busted 2.3.0 (`~/.luarocks/bin/busted`), dkjson through `hwc.json`, LuaJIT `bit` for the id hash. `git` only inside `tools/addon-worktree.sh`.

**Spec:** `docs/superpowers/specs/2026-11-11-headless-client-design.md` (§3 scope and professions, §4.4 driver loop, §5.2 step actions, §5.5 kill XP, §7 findings, §10 anchors, §11–12 builder calls). **Carry-over:** `docs/superpowers/plans/2026-11-11-plan-2-carryover.md` (read first) and `docs/superpowers/plans/2026-11-11-plan-1-carryover.md` (the canonicalisation ruling). This is plan 3 of 4.

## Global Constraints

- **Runtime and tests:** LuaJIT/Lua 5.1 only. Specs run with `~/.luarocks/bin/busted`. Homebrew `lua` (5.5) is never used.
- **The addon is read-only input.** Its code is never modified, vendored or patched.
- **Fidelity:** addon behaviour, bugs included, is reproduced, never corrected.
  - The harness never writes engine state (`WoWPro.*` decisions, `ActiveStep`, `completion`, `GuideLoaded`, `LockdownTimer`, `currentguide`).
  - The only engine calls the driver makes are the player-equivalents `WoWPro.CompleteStep(idx, "Right-Click")` and `WoWPro:UpdateGuide("sim:level")`.
- **World facts come from the catalog, never from guide lines.** Two exceptions:
  - the placeholder path (`catalog:placeholder`, `QO` count only, flagged "unverified quest data");
  - a step's own `Z`/`M` and item tags, which say where the player *goes* and what they *buy or loot* (spec §5.2), never what a quest *is*.
- **Data storage:** no QuestieDB, Wowhead or other third-party data is committed. Findings markdown may be committed by the user. Run logs (JSON) and worktrees are git-ignored.
- **No GPL code copied. No LICENSE file.**
- **Determinism:**
  - identical inputs (addon commit, catalog hashes, config, seed, `--date`) give byte-identical findings markdown;
  - no wall-clock time inside the sandbox;
  - every serialised table is key-sorted, and every list built from `pairs` is sorted before output.
- **Commits:** imperative subject; body ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Quest log size:** 40. **Rank:** the single default rank 2, guarded. **Stop:** level 25, or the chain loads a guide with `startlevel >= 25`, or no next guide, or a watchdog fires.
- **Severities (spec §7.2):** high for hidden/unreachable quests and `lua-error`; medium-high for `below-level`; medium for `did-not-advance`/`stuck`; low for `leftover-quests` and `missing-global`.

## Review Focus

1. **A guide whose last step completes while the engine's autoload switches `currentguide` inside the same settle.** The driver must notice the guide change by reading `WoWProDB.char.currentguide` after every settle, close the old guide (`never-shown-accept`, `leftover-quests`) and never act on a stale step index from the old guide. Test in Task 6.
2. **The engine advancing a different step than the one acted on.** For example, a turn-in also completes a sticky row, or an accept completes two `A` lines for the same QID. "Advanced" means the acted-on index is now complete or no longer current. It does not mean "the current index changed". Test in Task 6.
3. **The same step coming back after a manual completion** (the engine clears completion on loot-backed `C` steps, `WoWPro_Broker.lua:1997`). The stuck watchdog must fire after the limit instead of looping forever. Test in Task 6.
4. **Re-running the same matrix after the guide file moves lines** (a fix branch adds lines above a finding). Finding ids must not change, because ids key on guide, action, step text, QID and signal, not on the line number. Test in Task 7.
5. **A step whose QID tag lists several quests (`QID|179^180` or `179;180`).** Actions use the first id the engine itself tests (builder checks `WoWPro:QIDsInTable`/`QIDsInTableLogical` usage). Every listed id is checked for `orphan-turnin` and `wrong-race-class`. Test in Task 4.

---

## File structure

| Path | Responsibility |
|---|---|
| `src/hwc/catalog/questie.lua`, `src/hwc/catalog/init.lua` (modify) | carry-over fixes; Camping 101 skill rules |
| `src/hwc/world/questlog.lua`, `src/hwc/stubs/core.lua` (modify) | carry-over fixes (negative progress, `GetTitleText`) |
| `src/hwc/driver/engine.lua` | read-only engine adapter: steps, rows, completion, `why`, guide info, `fire`/`settle`, the two allowed calls |
| `src/hwc/driver/guide_source.lua` | maps a GID to its guide file and a step to its source line, by reading the addon's guide files |
| `src/hwc/world/kills.lua` | kill counts and XP for kill/drop objectives and generic grinding (pure, plus `grind_to`) |
| `src/hwc/driver/actions.lua` | step action → world change → client events; outcome records |
| `src/hwc/driver/run.lua` | the loop, watchdogs, guide chain, stop conditions, run log, signals |
| `src/hwc/driver/matrix.lua` | race → class list from the start guide's own `C`/`R` tags; profession variants |
| `src/hwc/findings/group.lua` | signals → findings: grouping key, ids, severity, root-cause links |
| `src/hwc/findings/render.lua` | findings → canonical markdown |
| `src/hwc/cli.lua` (modify) | `hwc run`, `hwc matrix` |
| `tools/addon-worktree.sh` | creates a detached addon worktree at `local/addon/<slug>` for Red/Green |
| `spec/helpers/world_engine_flow.lua` (modify) | re-pointed at `hwc.driver.engine` (no duplicate fire/settle/current code) |

---

### Task 1: Fix the Plan 2 carry-over first

**Files:** Modify `src/hwc/catalog/questie.lua`, `src/hwc/catalog/init.lua`, `src/hwc/world/questlog.lua`, `src/hwc/stubs/core.lua`, `README.md`. Tests: `spec/catalog/questie_spec.lua`, `spec/catalog/catalog_spec.lua`, `spec/world/questlog_spec.lua`, `spec/stubs_spec.lua`.

**Interfaces:**
- Produces:
  - `catalog.sources.questie.present` is `true`, `false` or `"partial"`, with `missing = { <file names> }` when partial; boot no longer errors.
  - `QuestLog:progress(qid, index, amount)` returns `false, "bad-amount"` for `amount < 0` or a non-number.
  - Objectives whose count was assumed carry `count_assumed = true`. Such a quest has `confidence = "unverified"` and a note.
  - `world.dialog` is `{ qid = n, kind = "detail"|"progress"|"complete" }` or nil; `GetTitleText()` returns the dialog quest's catalog name, or `""` with no dialog open.

- [ ] **Step 1: Write the failing specs:**
  - "partial questie dir records present = 'partial'": copy the fixture dir minus `foreverItemDB.lua` to a temp dir. `Catalog.load` returns `present == "partial"` and `missing == {"foreverItemDB.lua"}`, quests still load, and items come back nil.
  - "progress rejects negative amounts": `progress(179, 1, -3)` gives `false, "bad-amount"`, and `have[1]` is unchanged.
  - "supplement objective without count": a supplement objective `{kind="item", ids={750}}` becomes `count = 1`, `count_assumed = true`, `confidence = "unverified"`, plus a note naming the objective.
  - "QuestieDB objective with no count is assumed": the same flags on the fixture quest whose Questie row has no count (catalog/init.lua:184,296).
  - "GetTitleText follows the open dialog": `""` by default. After `world.dialog = {qid=179, kind="detail"}` it returns `"Dwarven Outfitters"`; after `world.dialog = nil`, `""`.
- [ ] **Step 2:** Run `~/.luarocks/bin/busted`. Expect those specs to FAIL.
- [ ] **Step 3:** Implement. Soften nothing in the README except the partial-source sentence: "a partial QuestieDB copy is recorded as `present: "partial"` with the missing files listed".
- [ ] **Step 4:** Run the full suite. Expect PASS.
- [ ] **Step 5:** Record in this plan's carry-over (created at branch end) as `needs-human`: the turn-in event order against the live client (QUEST_TURNED_IN with the quest still in the log, plus QUEST_REMOVED). The harness keeps its current order until the user confirms it in game.
- [ ] **Step 6:** Commit: "Close Plan 2 carry-over: partial catalog, progress guard, dialog title, assumed counts".

### Task 2: Read-only engine adapter and guide source map

**Files:** Create `src/hwc/driver/engine.lua`, `src/hwc/driver/guide_source.lua`. Modify `spec/helpers/world_engine_flow.lua` to use them. Tests: `spec/driver/engine_spec.lua` (fake env), `spec/driver/guide_source_spec.lua` (fixture guide), `spec/integration/world_engine_spec.lua` (unchanged assertions, still PASS).

**Interfaces:**
- Consumes: `boot.run(cfg) -> result` with `result.sb`, `result.world` (Plan 2 Task 6).
- Produces:
  - `Engine.new(result) -> E`.
  - `E:fire(event, ...)`.
  - `E:settle() -> { ran, now, hit_limit }`, with the same lockdown `busy` predicate as boot and `max_virtual = 60`.
  - `E:gid() -> string|nil`, from `WoWProDB.char.currentguide`.
  - `E:guide(gid) -> { gid, startlevel, endlevel, next_gid, file, done }`. `file` is relative to the addon root; `done` is `WoWProCharDB.Guide[gid].done`.
  - `E:step(i) -> Step`, where Step is `{ index, gid, action, name, qids = {int...}, tags = {...}, line }`.
    - `tags` holds the engine's per-index arrays for `QO` (`questtext`), `U` (`use`), `L` (`lootitem`), `Z` (`zone`), `M` (`map`), `LVL` (`level`), `ELITE`, `NC`, `DUNGEON`, `P` (`prof`), `SPELL`, `N` (`note`), `O`, `S`/`US`, `RANK`, `T` (`target`). Each value is copied as the engine parsed it.
    - `line` comes from `guide_source`, or nil.
  - `E:current() -> Step|nil`: the row after the active sticky rows (the addon's own lookup, as in the Plan 2 helper).
  - `E:rows() -> { Step... }`: the visible rows, each with `sticky = bool`.
  - `E:num_steps() -> int`.
  - `E:completed(i) -> bool`.
  - `E:why(i) -> string|nil`.
  - `E:complete_manual(i)`, which calls `WoWPro.CompleteStep(i, "Right-Click")` through `sb:call`.
  - `E:update_guide()`, which calls `WoWPro:UpdateGuide("sim:level")`.
  - `E:rank() -> number`, from `WoWPro:GuideRank` or the engine's own lookup, so the rank 2 guard can assert it.
  - `guide_source.index(addon_path) -> { [gid] = rel_file }`: scans `WoWPro_Leveling/Forever/**/*.lua` for `RegisterGuide('<gid>'` (single or double quotes).
  - `guide_source.line_of(addon_path, rel_file, step, occurrence) -> int|nil`: the source line of the `occurrence`-th line whose action char, step name and first QID match. `occurrence` counts earlier engine steps with the same triple.

- [ ] **Step 1: Write the failing specs:**
  - The engine spec builds a fake `env` with `WoWPro.action/step/QID/questtext/why/rows` and `WoWProCharDB.Guide.G.completion`. It asserts:
    - `current()` skips 2 sticky rows;
    - `step(3).qids == {179, 180}` for `QID|179^180`, and `{179}` for `"179"`;
    - `completed`/`why` read through;
    - `complete_manual(4)` calls the fake `CompleteStep` with `(4, "Right-Click")`;
    - no key of `env.WoWPro` changes across `current`, `rows`, `step` and `guide` (snapshot the keys and values before and after).
  - The guide_source spec uses the fixture `spec/fixtures/addon/Fix/forever/G1.lua`: `index` finds its GID. A guide with two identical `C Foo|QID|5|` lines maps occurrence 1 and 2 to their two lines, and an unknown step gives nil.
- [ ] **Step 2:** Run. Expect FAIL.
- [ ] **Step 3:** Implement. Re-point `world_engine_flow.lua`'s `fire`, `settle`, `current` and `completion` at the adapter.
- [ ] **Step 4:** Run the full suite. Expect PASS, including `world_engine_spec` unchanged.
- [ ] **Step 5:** Commit: "Add a read-only engine adapter and guide source map".

### Task 3: Kill and grind model

**Files:** Create `src/hwc/world/kills.lua`. Test: `spec/world/kills_spec.lua`.

**Interfaces:**
- Consumes: `xp.mob_xp(c, m, elite, party)`, `Player:add_xp(n) -> levels`, `catalog:npc(id)`, `catalog:item(id)`.
- Produces:
  - `kills.for_drop(rate, needed) -> int`: the smallest n with P(at least `needed` drops in n kills at `rate`) >= 0.90 (binomial). `rate` is a probability 0–1 (catalog rates in percent are divided by 100 by the caller). `rate >= 1` or nil-with-`named_elite` gives `needed`.
  - `kills.mob_level(npc) -> int`: `floor((level_min + level_max) / 2)`.
  - `kills.objective_kills(catalog, objective) -> { npc_id, level, elite, count }|nil`:
    - npc objectives: `count` kills of `ids[1]`;
    - item objectives: the first drop source with a rate, with `for_drop` kills; a named elite (rank 1 or 2 with 2 or fewer spawns) always drops;
    - object objectives and objectives without a source: nil, no XP.
  - `kills.credit(player, k, party_size) -> xp, levels`: adds `k.count × floor(mob_xp(player.level, k.level, k.elite, party_size))`. The level is recomputed after each kill, because a level-up mid-objective changes the per-kill XP.
  - `kills.grind_to(player, target_level) -> kills, xp, levels`: generic mobs at the player's own level until `player.level >= target_level`. It records a `"grind"` world event `{ to = target_level, kills = n }`.

- [ ] **Step 1: Write the failing specs** (values computed by hand and in the spec comments):
  - `for_drop(1, 8) == 8`; `for_drop(0.5, 1) == 4` (1-0.5^4 = 0.9375 ≥ 0.9, 1-0.5^3 = 0.875); `for_drop(0.35, 8)` checked against the binomial sum computed in the spec.
  - `mob_level{level_min=5, level_max=7} == 6`.
  - `credit` at level 1, 10 kills of level-1 mobs: 10 × 50 = 500 XP, 1 level gained, xp = 100.
  - `grind_to(level-1 player, 3)` reaches level 3 with xp carried exactly. Each kill uses `mob_xp(c, c)`, and the kill count is the minimal one.
  - An object objective gives nil.
  - An elite at party size 1 counts ×2 (`mob_xp` rule).
- [ ] **Step 2:** Run. Expect FAIL.
- [ ] **Step 3:** Implement. Cite spec §5.5 and `sim.py`'s 90%-confidence rule in the header comment.
- [ ] **Step 4:** Run. Expect PASS.
- [ ] **Step 5:** Commit: "Model kill counts, drop-objective XP and grinding".

### Task 4: Quest step actions: A, C, K, T, refusals, grind and Camping 101

**Files:** Create `src/hwc/driver/actions.lua`. Modify `src/hwc/catalog/init.lua` (Camping 101 rules). Tests: `spec/driver/actions_quest_spec.lua` (a fake engine recording fired events plus a real `World` with the fixture catalog), `spec/catalog/catalog_spec.lua`.

**Interfaces:**
- Consumes: Task 2 `E:fire/settle/update_guide/step/num_steps`, Task 3 `kills.*`, `world.log:*`, `world.player:*`.
- Produces:
  - `actions.perform(ctx, step) -> Outcome`, where `ctx = { engine = E, world = W, cfg = cfg }`. Outcome is `{ kind = "acted"|"refused"|"noop", reason = string|nil, qid = int|nil, events = {names...}, levels = int, grind = {kills, to}|nil, elite = bool }`.
  - `refused` reasons: `log-full`, `race`, `class`, `prerequisite`, `already-completed`, `unknown-quest`, `not-in-log`, `incomplete`, `requires-skill`.
  - After any outcome with `levels > 0`, `perform` has called `E:update_guide()`.
  - Catalog: a quest named `Camping 101: <Prof>` gets `requires_skill = "<Prof>"`, except Cooking, which gets `completed_by_training = "Cooking"`. The supplement may override both. The citation is spec §3 (user, in game 2026-11-11; Wowhead progress text).
- **Action rules** (spec §5.2; event order as in Plan 2 Task 6's helper, cited there):
  - **`A`:**
    - Accept the step's first QID (opts `placeholder_qo = #QO` when the catalog lacks it). While the accept runs, `world.dialog = {qid, "detail"}`.
    - On `below-level`: `kills.grind_to(required_level)`, fire nothing until the ding, `E:update_guide()`, then accept. The outcome carries `grind`.
    - Any other refusal leaves the world unchanged.
    - Events: `QUEST_ACCEPTED(logIdx, qid)`, `QUEST_LOG_UPDATE`.
    - **Camping 101:** if the accepted quest's name starts with `Camping 101` and no `T` step in the current guide has that QID, complete its objectives and turn it in at once (when `requires_skill` is known or absent). Record a world event `abstracted-turnin`, and fire the turn-in sequence. Otherwise leave it in the log.
  - **`C` / `K`:**
    - Complete the `QO` objectives (1-based indices from the engine's `questtext`, matched to catalog objectives by order), or all of them without `QO`.
    - Credit kill XP through `kills.objective_kills` and `kills.credit`, and add the items for item objectives.
    - For a Camping 101 quest with `completed_by_training`, learn that skill first and fire `SKILL_LINES_CHANGED`.
    - Events: `QUEST_LOG_UPDATE`, plus `BAG_UPDATE(0)` when items changed.
    - Quest not in log: `refused, not-in-log`.
  - **`T`:** `world.dialog = {qid, "complete"}` while it runs; `turn_in(qid)`. Events: `QUEST_TURNED_IN(qid, xp, 0)`, `QUEST_LOG_UPDATE`. On refusal: no events; the reason comes back.
  - **Every action** settles once at the end, then sets `world.dialog = nil`.

- [ ] **Step 1: Write the failing specs:**
  - accept fires exactly `{"QUEST_ACCEPTED", "QUEST_LOG_UPDATE"}`, with args `(1, 179)`;
  - log full: 40 accepted, then the 41st gives `refused/log-full`, no events, `#log == 40`;
  - race refusal on a fixture quest limited to `Human` for a Dwarf;
  - below-level: a fixture quest with `required_level = 3` at level 1 gives an `acted` outcome with `grind.to == 3`, `player.level == 3`, the quest in the log, and `update_guide` called at least once;
  - `C` with `QO|2|` completes only objective 2;
  - `C` on an item objective adds the items, credits XP, and fires `BAG_UPDATE`;
  - `T` refused `incomplete` fires nothing;
  - a `T` gaining a level calls `update_guide`;
  - **Camping:**
    - accepting `Camping 101: First Aid` without First Aid leaves it in the log;
    - with First Aid it's turned in at once, with an `abstracted-turnin` event;
    - with a `T` step for its QID in the guide it isn't auto-turned-in;
    - `C` on `Camping 101: Cooking` learns Cooking and completes it;
  - **Multi-QID (Review Focus 5):** `QID|179^180` acts on 179 (or the id the engine's own test picks, per the builder's check, cited).
  - catalog: `quest(<fixture Camping 101: Fishing>).requires_skill == "Fishing"`; Cooking gives `completed_by_training == "Cooking"` and no `requires_skill`.
- [ ] **Step 2:** Run. Expect FAIL.
- [ ] **Step 3:** Implement. Check every event sequence against `WoWPro_Events.lua:752–940` and `WoWPro_AutoComplete.lua:317–399`, and cite the lines in comments.
- [ ] **Step 4:** Run the full suite. Expect PASS.
- [ ] **Step 5:** Commit: "Perform quest steps with refusals, grinding and Camping 101 turn-ins".

### Task 5: Travel, item, training and note actions

**Files:** Modify `src/hwc/driver/actions.lua`. Test: `spec/driver/actions_other_spec.lua`.

**Interfaces:**
- Produces: `actions.perform` also handles the rules below. `actions.EXPECTED_MANUAL` is the set of actions whose completion is expected to need a right-click: `N`, `D`, `=`, `r`, and any step whose note contains "Manually check this step off". Task 6 uses it to split `manual-completion` into expected and unexpected.
- **Rules** (spec §5.2):
  - **`R`, `F`, `b`, `P`, `H`:**
    - Parse `Z` (`"1426; Dun Morogh"`, `"1426"` or a zone name) and `M` (`"46.74,53.87"`, first coordinate, ÷100).
    - `player:set_zone(zone, subzone, map_id, x, y)`. For `R` the subzone is the step name.
    - Events: `ZONE_CHANGED_NEW_AREA`, `ZONE_CHANGED`. For `F`, `TAXIMAP_OPENED` first.
    - For `H` the bind location is used for the zone.
  - **`f`:** `player:learn_flight_point(step name)`, then `UI_INFO_MESSAGE(0, ERR_NEWTAXIPATH)` (builder checks the arg shape against the handler).
  - **`h`:** `player:set_bind(step name, map_id)`, then `HEARTHSTONE_BOUND`.
  - **`B` / `l` / any step with an `L` tag:** add the `L` item (`"id count"`, count default 1), then `BAG_UPDATE(0)`.
  - **`U`:**
    - Ensure the `U` item is in the bags (add 1 if missing), fire `BAG_UPDATE(0)`.
    - If the step has a QID in the log, apply the `C` objective rule, then remove one `U` item unless it's also the `L` item.
    - Events: `BAG_UPDATE(0)`, `QUEST_LOG_UPDATE`.
  - **`L`** (level step) and any step with `LVL|n` while `player.level < n`: `kills.grind_to(n)`, then `E:update_guide()`.
  - **`=`** (train), or a step with `P` or `SPELL` whose skill or spell is unknown: learn the skill or spell named by the tag. Events: `SKILL_LINES_CHANGED`, `SPELLS_CHANGED`. The no-profession baseline trains only here (spec §12).
  - **Everything else** (`N`, `D`, `r`, `t`, unknown actions): `noop`.

- [ ] **Step 1: Write the failing specs:**
  - `R` with `Z|1426; Dun Morogh|M|46.74,53.87` gives `UnitPosition`-backing fields `zone == "Dun Morogh"`, `map_id == 1426`, `x == 0.4674`, `y == 0.5387`, and events in order;
  - `R` with no `M` keeps the previous x/y;
  - `f` adds the flight point;
  - `h` sets the bind;
  - `l` with `L|2894 2|` gives `item_count(2894) == 2`;
  - `U` consumes the use item and completes `QO`;
  - `L` with `LVL|4` grinds to 4;
  - `=` trains;
  - `N` gives `noop`, and `EXPECTED_MANUAL["N"]` is true.
- [ ] **Step 2:** Run. Expect FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expect PASS.
- [ ] **Step 5:** Commit: "Perform travel, item, use, level and training steps".

### Task 6: Driver loop, run log and signals

**Files:** Create `src/hwc/driver/run.lua`. Modify `.gitignore` (`findings/**/*.json`), `.busted` (`default.exclude_tags = { "slow" }`; tag the existing cross-process determinism spec `#slow`). Tests: `spec/driver/run_spec.lua` (a scripted fake engine), `spec/integration/run_dun_morogh_spec.lua` (real engine, pending without addon or catalog).

**Interfaces:**
- Consumes: Tasks 2, 4 and 5.
- Produces:
  - `run.character(cfg, opts) -> RunLog`. It boots, then loops. `opts = { max_iterations = 20000, stuck_limit = 5, max_addon_errors = 200, stop_level = 25 }`.
  - RunLog fields:
    - `character = {race, class, professions = {names...}}`, plus `variant`;
    - `addon = {path, branch, commit, dirty}`, `catalog = {sources}`, `rank`;
    - `steps = { Snapshot... }`, `signals = { Signal... }`;
    - `stop = {reason, level, gid}`, `guides = {gid...}` in load order.
  - A Snapshot is `{ n, gid, index, action, name, qids, line, why, rows = {indices}, outcome, level, xp, log = {qids} }`.
  - A Signal is `{ signal, gid, file, line, action, name, qid, why, level, log = {qids}, before = {name}, after = {name}, reason, outcome, expected = bool|nil, confidence }`. `confidence` is `"unverified"` when the quest is a placeholder or has `confidence = "unverified"`. `before`/`after` are the names of the steps acted on just before and just after.
  - `run.STOP` reasons: `level`, `chain-range`, `no-next-guide`, `stuck`, `iterations`, `errors`, `no-step`.
- **Loop** (spec §4.4):
  - Read `E:gid()` after every settle. If it changed, close the old guide (below) and append the new GID. If `guide(gid).startlevel >= 25`, stop with `chain-range`.
  - `cur = E:current()`. If there's none, the guide isn't done and nothing advances, so stop with `no-step` (a `stuck` signal).
  - Check `wrong-race-class` for every QID on the shown step (catalog races and classes).
  - `outcome = actions.perform(ctx, cur)`, then append a snapshot.
  - **Refusals become signals:**
    - `log-full` gives `log-full`;
    - `race`, `class` and `prerequisite` give `accept-refused`;
    - a `below-level` grind gives `below-level`, which is acted, not refused;
    - `not-in-log` on `T`/`C` gives `orphan-turnin`;
    - `incomplete` and `requires-skill` are kept as the `reason` of the `did-not-advance` that follows.
  - **Advanced** means `E:completed(cur.index)` is true, or `E:gid()` changed, or `E:current().index ~= cur.index`.
  - If the step didn't advance:
    - for `EXPECTED_MANUAL`, record `manual-completion` with `expected = true`;
    - otherwise record `did-not-advance` (and `manual-completion` with `expected = false`);
    - then `E:complete_manual(cur.index)` and settle.
  - **Watchdogs:**
    - the same `(gid, index)` acted on more than `stuck_limit` times in a row records `stuck` and stops;
    - `max_iterations` stops with `iterations`, plus a `stuck` signal;
    - addon `lua-error`s past `max_addon_errors` stop with `errors`;
    - every settle with `hit_limit` records `stuck` with the reason `settle-limit`.
  - Stop at `player.level >= stop_level`, or when the engine has no next guide (the current guide is `done` and `E:gid()` is nil or unchanged after settling).
- **Closing a guide**, and at the end of the run for the current guide:
  - every `A` index never seen as current or in rows gives `never-shown-accept`, with `E:why(i)`;
  - an `A` index with the `DUNGEON` tag that the engine completed without being shown also gets `reason = "engine-dungeon-skip"`;
  - each quest left in the log gives one `leftover-quests` signal (qid, gid).
- **Errors at the end:**
  - each addon error (not `boot.is_harness_error`) gives `lua-error` with the message and the first stack line;
  - each harness error gives `lua-error` with `reason = "harness"`;
  - each `sb.missing_order` name gives `missing-global`.

- [ ] **Step 1: Write the failing fake-engine specs.** The scripted engine is a table of steps plus a script of which index each event completes. Specs:
  - a step that completes on its action records no signal;
  - an `N` step records an expected `manual-completion`;
  - a `C` that doesn't complete records `did-not-advance` and calls `complete_manual` once;
  - **Review Focus 2:** acting on index 4 completes 4 and a sticky 2. That counts as advanced, with no signal.
  - **Review Focus 3:** index 5 is un-completed after every manual completion, so `stuck` fires after 5 and the stop reason is `stuck`.
  - **Review Focus 1:** the action on the last step of guide G1 also switches `gid` to G2 within the settle. G1 closes: an unshown `A` gives `never-shown-accept` and a log entry gives `leftover-quests`. The next action is taken on G2's current step, never on G1's index.
  - a G2 with `startlevel = 25` stops with `chain-range`;
  - `player.level` reaching 25 stops with `level`.
- [ ] **Step 2:** Run. Expect FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4: Write the integration spec** "Dwarf Warrior plays Dun Morogh to the next guide":
  - **guide chain:** `guides[1] == "ClassicDunMorogh0112"`, and `guides[2]` is that guide's `nextGID` as the engine resolves it;
  - **rank:** `rank == 2`;
  - **Rhapsody Malt:** a `did-not-advance` signal exists for QID 384 at the `C Beer Basted Boar Ribs` step (spec §10);
  - **harness errors:** zero `lua-error` signals with `reason = "harness"`;
  - **slow tag:** tagged `#slow`, run with `opts.stop_level = 12` and stopped after the first guide change via an `opts.max_guides = 2` option.

  Run it. If the engine doesn't advance where a player would, use `superpowers:systematic-debugging` and fix only harness fidelity, with citations. A legitimate engine or guide failure is a finding: report it, never patch it.
- [ ] **Step 5:** Run the full suite. Expect PASS.
- [ ] **Step 6:** Commit: "Drive the real engine through the guide chain and record signals".

### Task 7: Findings: grouping, ids, links and canonical markdown

**Files:** Create `src/hwc/findings/group.lua`, `src/hwc/findings/render.lua`. Tests: `spec/findings/group_spec.lua`, `spec/findings/render_spec.lua`, `spec/integration/findings_determinism_spec.lua` (`#slow`, two processes).

**Interfaces:**
- Consumes: RunLogs from Task 6.
- Produces:
  - `group.findings(runlogs) -> { Finding... }`, sorted by `(file, line or 0, signal, id)`. A Finding is `{ id, signal, severity, file, line, gid, action, name, qid, why, combos = {"Dwarf WARRIOR baseline", ...}, before, after, level, log, confidence, caused_by = id|nil, causes = {ids}, reasons = {sorted unique} }`.
  - **Grouping key:** `gid .. "\0" .. action .. "\0" .. name .. "\0" .. (qid or "") .. "\0" .. signal`. One finding per key across all characters. `combos` is sorted.
    - `before`/`after`/`level`/`log`/`why` come from the first combo in sorted order.
    - `lua-error` and `missing-global` group on the message or name instead.
  - **Id:** `"F-" .. 8 lowercase hex` of FNV-1a 32 (LuaJIT `bit`) over the grouping key. No line number goes into it (Review Focus 4).
  - **Severity:** the Global Constraints map. `never-shown-accept`, `orphan-turnin`, `accept-refused`, `wrong-race-class` and `log-full` are high. Expected `manual-completion` findings go in a separate "Expected manual completions" list with no severity.
  - **Root-cause links:**
    - an `orphan-turnin`, `did-not-advance` or `leftover-quests` finding on quest Q links `caused_by` the `accept-refused`/`log-full` finding on Q;
    - a `never-shown-accept` whose `why` names quest Q (pattern `%d+` within a `PRE`/`prereq` reason) links to the refusal or `never-shown-accept` finding on Q;
    - all `engine-dungeon-skip` findings link under one root finding `{signal = "engine-dungeon-skip", severity = "high", name = "EnableDungeons auto-completes DUNGEON accepts", file = "WoWPro/WoWPro_Broker.lua", line = 2588}`.

    The root lists `causes`, sorted.
  - `render.markdown(findings, header) -> string`.
    - `header = { scope, date, addon = {path, branch, commit, dirty}, catalog = sources, client = {commit}, matrix = {combos}, rank = 2, gaps = {...} }`.
    - `gaps` is exactly: rested XP, Forever Boosted Rest from campfires, party XP for non-elites (spec §5.5), dungeon runs and instance XP (spec §3).
    - The output is a title, the header, a summary table (count per signal and per severity), each finding with every §7.2 field and an empty `Triage:` block, and the expected manual completions list.
    - Tables are sorted and lines use `\n`, ending in one trailing newline.
- [ ] **Step 1: Write the failing specs:**
  - two RunLogs (Dwarf WARRIOR, Gnome MAGE) with the same `did-not-advance` group into one finding whose `combos` lists both;
  - a finding's id stays the same when its `line` changes (Review Focus 4);
  - `accept-refused` on 96629 and a `never-shown-accept` whose `why` is `"PRE&(...): A mandatory prereq was not met: 96629"` are linked both ways;
  - three dungeon skips link under one `engine-dungeon-skip` root;
  - render is identical for the same input with the RunLog arrays shuffled;
  - the render contains `Triage:` once per finding and the header line `Rank: 2`;
  - **determinism (`#slow`):** two `bin/hwc run` processes, Dwarf WARRIOR, `--stop-level 6 --date 2026-11-12`, give byte-identical markdown. Stderr is captured and asserted empty of harness errors, not discarded (carry-over minor).
- [ ] **Step 2:** Run. Expect FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expect PASS.
- [ ] **Step 5:** Commit: "Group signals into linked findings and render canonical markdown".

### Task 8: `hwc run`, `hwc matrix` and the character matrix

**Files:** Create `src/hwc/driver/matrix.lua`. Modify `src/hwc/cli.lua`, `README.md`. Tests: `spec/driver/matrix_spec.lua`, `spec/cli_spec.lua`.

**Interfaces:**
- Consumes: Tasks 6–7, `config.load`.
- Produces:
  - `matrix.classes_for(addon_path, race) -> {CLASS_TOKEN...}` (sorted). These are the classes the race's start guide (`ForeverStartGuides[race]`, read from `WoWPro_Leveling/WoWPro_Leveling.lua` source text) names in `C|` tags on lines whose `R|` tag includes the race, or that have no `R|` tag. This is the spec §3 rule that the class list comes from the guides' own `C|` tags, never from memory. The tokens are upper-case, with "Priest" becoming `PRIEST`.
  - `matrix.VARIANTS` holds the spec §11 profession variants, chosen so that every Camping 101 quest in the 1–25 guides (12 professions) is covered:
    - `baseline` (none);
    - `secondary` (Cooking, First Aid, Fishing);
    - `alch-herb` (Alchemy, Herbalism);
    - `bs-mining` (Blacksmithing, Mining);
    - `lw-skin` (Leatherworking, Skinning);
    - `eng-ench` (Engineering, Enchanting);
    - `tailoring` (Tailoring).

    Every variant starts with its skills known at rank 1/max 75 (spec §12). The secondaries ride the `secondary` variant only, so the primaries stay at two each, as in the client.
  - `matrix.combos(addon_path, races) -> { {race, class, variant}... }`: every class × `baseline`, plus every non-baseline variant on the race's first class in sorted order. Camping 101 quests aren't class-gated, so one class per race covers them.
  - **CLI:**
    - `hwc run --race R --class C [--variant V] [--addon P] [--stop-level N] [--date D] [--out DIR]`.
    - `hwc matrix [--races Dwarf,Gnome] [--addon P] [--date D] [--out DIR]`.
    - Both write `DIR/<date>-<scope>.md` (default `findings/`) and per-character run logs `DIR/<date>-<scope>/<race>-<class>-<variant>.json`.
    - The scope is `forever-alliance-<races lower, joined by '-'>-1-25`, or `<race>-<class>-<variant>` for `run`.
    - `--date` defaults to the host date, read outside the sandbox. It's an input, so a fixed `--date` makes reruns byte-identical.
    - Exit 0 when the findings were written, whatever they contain. Exit 1 on a harness failure, with the message on stderr.
- [ ] **Step 1: Write the failing specs:**
  - `classes_for(<real addon>, "Dwarf")` contains `PRIEST` and `PALADIN`, and `"Gnome"` contains `PRIEST` (`01_12_Dun_Morogh.lua:193`, `C|Priest|R|Dwarf,Gnome`); pending without the addon;
  - with a fixture start guide, a `C|Mage|R|Gnome` line doesn't add `MAGE` to Dwarf;
  - the union of `VARIANTS` profession names equals the 12 Camping 101 professions found by scanning the 1–25 Alliance guides' `A Camping 101: <Prof>` lines;
  - `combos` has `#classes + 6` entries per race;
  - CLI: `hwc run` without `--class` exits 2 with usage, and `hwc matrix --races Orc` exits 2 ("race not in scope").
- [ ] **Step 2:** Run. Expect FAIL.
- [ ] **Step 3:** Implement. Document `run`, `matrix`, the findings layout and the variants in `README.md`.
- [ ] **Step 4:** Run the full suite. Expect PASS.
- [ ] **Step 5:** Commit: "Add hwc run and hwc matrix over the Dwarf/Gnome matrix".

### Task 9: Anchors, Red/Green worktrees and the first full matrix

**Files:** Create `tools/addon-worktree.sh`, `spec/integration/anchors_spec.lua` (`#slow`; each anchor pending when its worktree is absent). Modify `README.md`.

**Interfaces:**
- Consumes: `hwc run` and `hwc matrix` (Task 8).
- Produces:
  - **`tools/addon-worktree.sh <ref> [addon_path]`:** runs `git -C <addon> worktree add --detach <hwc>/local/addon/<slug> <ref>`, where `<slug>` is the ref with `/` replaced by `-`.
    - It refuses to touch an existing path, and never checks out a branch in the user's main checkout, whose branch the game's AddOns folder follows (spec §9).
    - It prints the worktree path and commit.
  - Anchor specs read `local/addon/main`, `local/addon/fix-forever-prereq-gates` and `local/addon/fix-u-step-loot-result`. They never use `~/Projects/WoW-Pro-Guides` itself, because that checkout is currently on `fix/forever-prereq-gates`.
- **Anchors** (spec §10):
  - **#3535 Red:** on `main`, a Dwarf Warrior baseline has `never-shown-accept` findings for Tools for Steelgrill, Flintfire's Shipment and Farsen's Watch (QIDs looked up in the catalog by name and cited in the spec file). Each one's `why` contains `96629`.
  - **#3535 Green:** on `fix/forever-prereq-gates` those three are absent.
    - The spec prints the total count of `never-shown-accept` findings on both branches; the issue-03 Python model expected 46 and 0.
    - It doesn't assert 46. A difference is written into this plan's carry-over as a question for triage, not a failure.
  - **#3554:** on `main` the Divining Scroll `U` step is `never-shown` (or never in rows); on `fix/u-step-loot-result` it's shown. The builder finds the step by `grep -n "Divining Scroll"` in the 1–25 guides and cites file:line.
  - **Dungeons:** on `main`, the findings contain one `engine-dungeon-skip` root whose `causes` include the `DUNGEON` accepts of `19_25_Alliance.lua` reached in the run. The count is printed. The spec expects 9 in that guide, and a mismatch is noted, not asserted.
  - **Harness completeness:** a full Dwarf Warrior baseline run on `main` to level 25 or chain end has zero harness `lua-error` findings. The `missing-global` list is printed for review.
- [ ] **Step 1:** Write `tools/addon-worktree.sh`, then run it for the three refs. Expect three paths under `local/addon/`, and `git -C ~/Projects/WoW-Pro-Guides branch --show-current` unchanged.
- [ ] **Step 2:** Write the anchor specs. Run `~/.luarocks/bin/busted --tags=slow spec/integration/anchors_spec.lua`. Expect PASS, or a FAIL that's root-caused with `superpowers:systematic-debugging`: harness fidelity gets fixed, and engine or guide behaviour gets reported, not patched.
- [ ] **Step 3:** Run `bin/hwc matrix --races Dwarf,Gnome --addon local/addon/main --date <today>`. Expect exit 0 and `findings/<today>-forever-alliance-dwarf-gnome-1-25.md`. Report the summary table and every `stop` reason other than `level`/`chain-range`/`no-next-guide` to the user. Don't commit the findings file unless the user asks.
- [ ] **Step 4:** Run the full suite (`busted`, then `busted --tags=slow`). Expect PASS.
- [ ] **Step 5:** Document worktrees, anchors and `--tags=slow` in `README.md`. Commit: "Add Red/Green anchors and addon worktrees".

---

## Rulings recorded in writing this plan (check these)

- `engine-dungeon-skip` is a signal name added to §7.1's list, so that spec §3's "one engine-bug finding with the hidden accepts linked under it" has a key. Its children are `never-shown-accept` findings.
- A `T` refused as `incomplete` or `requires-skill` isn't a new signal. It's carried as the `reason` of the `did-not-advance` that follows.
- Finding ids don't contain the line number, so Red/Green findings files can be diffed by id. Two identical step lines in one guide share an id and are told apart by `line`.
- Profession variants run on one class per race. Camping 101 quests aren't class-gated, and this keeps the matrix at classes + 6 runs per race instead of classes × 7.
- `--date` is an explicit input to keep findings byte-identical. It defaults to the host date outside the sandbox.
- Slow specs (full runs, the cross-process determinism specs, anchors) are tagged `slow`. Per the Plan 2 carry-over, they're excluded from the default run by adding `exclude_tags = { "slow" }` to `.busted`'s `default` in Task 6.

## Follow-on plans

- **Plan 4: `/triage` skill** (spec §8), fed by this plan's findings files.
- **Later:** Human and Night Elf start guides, CI with catalog-dependent specs skipped, and the in-game confirmation of turn-in event order.
