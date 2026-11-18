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
