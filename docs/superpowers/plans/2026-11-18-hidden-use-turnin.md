# Hidden Use Step at a Refused Turn-in Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a turn-in is refused for a missing item that a hidden L-gated U step of the same quest produces, the driver performs that U step off-guide and retries the turn-in once, keeping the `hidden-use-step` finding.

**Architecture:** A small helper in `src/hwc/driver/run.lua` runs from `Driver:act` after a refused `T`. It finds the matching hidden U step in the current guide's `info.uses`, performs it with the existing `actions.perform`, logs it in `log.offguide` and retries the turn-in.

**Tech Stack:** LuaJIT 2.1, busted 2.3, luacheck 1.2.

**Spec:** `docs/superpowers/specs/2026-11-18-hidden-use-turnin-design.md`

## Global Constraints

- Emulate the engine and game; never correct the guide or the quest data.
- Trigger only when **all** of these hold:
  - `T` refused with `incomplete`
  - a required item objective of the quest is short
  - a U step in the loaded guide for the same quest is unseen (`not info.seen[i]`), has `why` containing `run.HIDDEN_USE_WHY`, and has an `L` item equal to the short objective item
- `hidden-use-step` must still be recorded at guide close. Performing the step off-guide must not set `info.seen`.
- Retry the turn-in at most once per T step.
- Determinism holds. LuaJIT 2.1; `~/.luarocks/bin/luacheck .` 0 warnings. Conventional Commits ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A quest with two hidden U steps:** use the lowest index whose L item matches. Test it.
2. **A U step whose L item isn't the missing item:** no off-guide action, and today's findings stay. Test it.
3. **A retry that's still refused** (e.g. another objective missing): one attempt only, then today's `did-not-advance`. Test it.
4. **A U step that was shown earlier and performed:** never re-performed, because `info.seen` is true. Test it.
5. **The off-guide use adds levels or items:** `out.levels` and the bag events from the U action are applied (`after_settle`/`after_levels` as for any action), so XP stays consistent. Test that the U action's events are fired.

---

### Task 1: Perform the hidden U step at a refused turn-in

**Files:**
- Modify: `src/hwc/driver/run.lua` (`Driver:act`, a new local helper, the `log.offguide` init in `run.drive`)
- Test: `spec/driver/run_spec.lua` (scripted engine via `spec/helpers/driver_fixtures.lua`)

**Interfaces:**
- Produces:
  - `log.offguide`: an array of `{ gid, file, line, qid, action = "U", for_line = <T line> }`. Always present, so `[]` when empty.
  - `Driver:hidden_use_for(step, out, info) -> index | nil`: returns the U step index, or nil.

- [ ] **Step 1: Failing specs:**
  - A guide with `l` (loot 12220), a hidden `U|5456|L|5455` for qid 1016 whose why is `run.HIDDEN_USE_WHY`, and `T` 1016. The quest's objective is item 5455 ×1. Expected:
    - the T turns in successfully
    - `log.offguide` has one entry with `qid == 1016`, `action == "U"`, and the U step's line
    - no `did-not-advance` and no `leftover-quests` for 1016
    - one `hidden-use-step` for the U line
  - Review Focus 1-5, each as its own `it`.
- [ ] **Step 2: RED.** `~/.luarocks/bin/busted spec/driver/run_spec.lua`.
- [ ] **Step 3: Implement.** Get the U step's full tags from `self.E:step(i)`, because `info.steps` has only the parsed fields. Perform it through `self.perform(self.ctx, ustep)`. Then re-perform the T step and replace `out` with the retry's outcome before `snapshot`/`refusals`, so the snapshot and refusal reflect the final result. Fire and settle as other actions do.
- [ ] **Step 4: GREEN.** Run the full suite, `~/.luarocks/bin/busted --tags=slow` (21 + 1 known pending; #3554 and #3535 anchors unchanged) and luacheck.
- [ ] **Step 5: Real check.** From `~/Projects/WoW-Pro-Guides`, run `<worktree>/bin/hwc run --race Dwarf --class WARRIOR --date 2026-11-18 --out "$TMPDIR/hut"`. Expected:
  - `hidden-use-step` at `19_25_Alliance.lua:449` (qid 1016) still present
  - no `did-not-advance` at :450 for 1016
  - no `leftover-quests` for 1016
  - `log.offguide` names it

  Paste the summary and these checks.
- [ ] **Step 6: Commit** `fix: Combine a hidden use step's item when a turn-in needs it`.

---

### Task 2: Credit a run-to step's named objective; name missing prerequisites

**Files:**
- Modify:
  - `src/hwc/driver/actions.lua` (`perform_travel` for `R`)
  - `src/hwc/world/questlog.lua` (`refusal` returns the missing prerequisite ids)
  - `src/hwc/driver/run.lua` (carry `missing` on the `accept-refused` signal)
  - `src/hwc/findings/group.lua` (link a prerequisite refusal under the missing quest's failure)
  - `src/hwc/findings/text.lua` (sentence)
- Test: `spec/driver/actions_quest_spec.lua` (or `actions_other_spec.lua`, whichever covers `R`), `spec/world/questlog_spec.lua`, `spec/findings/group_spec.lua`, `spec/findings/text_spec.lua`, `spec/driver/run_spec.lua`

**Interfaces:**
- Produces:
  - **`R` steps:** when `step.tags.questtext` (QO) is set and the step's qid (`ACTIVE` or `QID`) is in the log, add progress to each QO-named objective up to what the QO part asks. This uses the same QO parsing as `perform_objectives`, but **without** `credit_objective`'s kill XP: `world.log:progress(qid, index, delta)` for non-item objectives, and `add_item` for item objectives. Fire `QUEST_LOG_UPDATE`.
  - **`QuestLog:refusal(qid, opts) -> reason, quest_or_missing`:** for `"prerequisite"`, the second value is a sorted array of the missing ids. For `pre_single`, all of them, since none is done; for `pre_group`, the undone ones. Callers that only use the reason are unaffected; check every caller.
  - **Signal:** `accept-refused` with reason `prerequisite` carries `missing = { ids… }`.
  - **Text:** the `prerequisite` sentence for an accept becomes "The guide shows this accept, but the quest data says it needs quest <id> (<name>)[ and …], which isn't done yet." Names come from the catalog, with "quest <id>" when unknown.
  - **Linker:** an `accept-refused`/`prerequisite` with `missing` links (`caused_by`) to the first missing id's failure. In preference order: a refusal of that id, a hidden-use-step, an incomplete turn-in, a never-shown-accept, the same order `never-shown-accept` uses (`group.lua` `link_roots`).

- [ ] **Step 1: Failing specs:**
  - An `R` step with `ACTIVE|98319|QO|1` and an NPC objective → progress 1/1, `is_complete(98319)`, and **no XP gained**.
  - An `R` step with no QO → no progress.
  - An `R` step whose qid isn't in the log → no progress and no error.
  - `refusal` for a `pre_group = {287, 98323}` quest with only 287 done → `"prerequisite", {98323}`.
  - The sentence names "quest 98323 (Secure the Mountain)".
  - group_spec: a prerequisite refusal of 291 with `missing = {98323}` links under a `never-shown-accept` for 98323.
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: GREEN.** Full suite, slow suite (21 + 1 known pending; #3535 and #3554 unchanged; if #3535's Red expectations change because 98323 or 291 now play, stop and report rather than editing the anchor), and luacheck.
- [ ] **Step 5: Real check.** Dwarf Warrior run as in Task 1. Expected:
  - no `did-not-advance` at `01_12_Dun_Morogh.lua:161`
  - no `never-shown-accept` for 98323 at :162
  - no `accept-refused` for 291 at :291

  Paste the summary and the `hwc diff` against the Task 1 run.
- [ ] **Step 6: Commit** `fix: Credit a run-to step's quest objective and name missing prerequisites`.
