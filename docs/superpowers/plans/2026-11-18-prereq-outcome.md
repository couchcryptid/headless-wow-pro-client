# Missing-Prerequisite Outcome Wording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prerequisite refusals say whether each missing quest was never accepted, never completed, or done only later in the run.

**Architecture:**
1. The driver records when each quest was accepted and turned in (the step counter `n`).
2. At `Driver:finish`, it annotates each `accept-refused`/`prerequisite` signal's `missing` ids with an outcome.
3. `group.lua` carries `missing_outcome`.
4. `text.lua` renders the endings.

**Tech Stack:** LuaJIT 2.1, busted 2.3, luacheck 1.2.

**Spec:** `docs/superpowers/specs/2026-11-18-prereq-outcome-design.md`

## Global Constraints

- The exact endings: `which is never accepted`, `which is never completed`, `which isn't done until later in the run`; any-of with a shared outcome: `none of which is ever accepted` / `none of which is ever completed`.
- Outcomes come from the run's quest log only. Findings format 2 with additive fields. Finding ids unchanged. Deterministic. luacheck 0. Conventional Commits ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Without `missing_outcome`, today's wording, so existing specs and fixtures pass unchanged.

## Review Focus

1. **The missing quest is accepted after the refusal but never completed:** `never-completed`, not `never-accepted`. Test it.
2. **The missing quest was completed before the refusal:** impossible, because refusal requires it undone. If seen anyway, drop it and stay silent rather than claim. Test that the code doesn't crash.
3. **A findings group spanning several characters:** the outcome comes from the first combo's signal, the same rule as `missing`. Document it in a comment.
4. **Mixed any-of outcomes:** per-quest endings joined with `, or `. Test it.
5. **A quest accepted, abandoned and re-accepted:** still `never-completed` if it was never turned in. Test it.

---

### Task 1: Outcome endings for missing prerequisites

**Files:**
- Modify:
  - `src/hwc/driver/run.lua` (remember the step counter of the refusal on the signal; at `Driver:finish`, set `sig.missing_outcome` for each `accept-refused` signal with `missing`)
  - `src/hwc/world/questlog.lua` only if accept/turn-in step order isn't already observable (prefer the driver's own step log or the questlog `_record` entries)
  - `src/hwc/findings/group.lua` (carry `missing_outcome`)
  - `src/hwc/findings/text.lua` (the `prerequisite` accept sentence)
- Test: `spec/driver/run_spec.lua`, `spec/findings/text_spec.lua`, `spec/findings/group_spec.lua`

**Interfaces:**
- Produces: on signals and findings, `missing_outcome = { ["<id>"] = "never-accepted" | "never-completed" | "completed-later" }`.

- [ ] **Step 1: Failing specs:**
  - run_spec, a scripted guide where quest 19 is refused for missing 98387 and 98387 is never accepted → `missing_outcome["98387"] == "never-accepted"`.
  - A variant where 98387 is accepted later but not completed → `never-completed`.
  - A variant where it's completed later → `completed-later`.
  - text_spec:
    - the single-quest sentence ends exactly `quest 98387 "Blackrock Blockade", which is never accepted.`
    - all-of with two mixed outcomes uses `, and `
    - any-of with a shared outcome uses `none of which is ever accepted`
    - mixed any-of uses `, or `
    - with no `missing_outcome`, today's text
  - Review Focus 1-5.
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: GREEN.** Full suite, slow suite (21 + 1 known pending; anchors unchanged), luacheck; `web/report` `npm test` if fixture JSON changes.
- [ ] **Step 5: Real check.** From `~/Projects/WoW-Pro-Guides`, run `<worktree>/bin/hwc run --race Dwarf --class WARRIOR --date 2026-11-18 --out "$TMPDIR/preout"`. The Tharil'zun finding at `25_30_Alliance.lua:85` should read `…needs quest 98387 "Blackrock Blockade", which is never accepted.` Paste it.
- [ ] **Step 6: Commit** `feat: Say whether a missing prerequisite is never accepted or never completed`.
