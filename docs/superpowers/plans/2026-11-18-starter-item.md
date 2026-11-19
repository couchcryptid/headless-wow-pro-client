# Starter Item Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Accepting an item-started quest puts its starter item in the bags, so quests like Stolen Blasting Powder (95213) can be turned in.

**Architecture:** In `perform_accept` (`src/hwc/driver/actions.lua`), before the accept events, add the catalog quest's starter item when `starter_kind == "item"` and the bags lack it, then fire `BAG_UPDATE`. The catalog already exposes `starter` and `starter_kind`.

**Tech Stack:** LuaJIT 2.1, busted 2.3, luacheck 1.2.

**Spec:** `docs/superpowers/specs/2026-11-18-starter-item-design.md`

## Global Constraints

- Add the item only for `starter_kind == "item"`, and only when `item_count(starter) == 0`. Add it **before** `QUEST_ACCEPTED`. Never remove it.
- The existing `source_item` rule is unchanged.
- Data only from QuestieDB and the run. Never patch the guide or the addon. Deterministic. luacheck 0. Commit trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **The starter item is also an objective** (95213): after the accept, the quest's item objective is credited, the way any objective item in the bags is credited, and the turn-in succeeds. Test it.
2. **The item is already in the bags:** no second copy and no extra `BAG_UPDATE`. Test it.
3. **An NPC-started quest:** unchanged. Test it.
4. **A quest that has both an item starter and a `source_item`:** both items end up in the bags. Test it.
5. **A refused accept** (level or prerequisite): no item is added. Test it.

---

### Task 1: Give item-started quests their starter item on accept

**Files:**
- Modify: `src/hwc/driver/actions.lua` (`perform_accept`, near the `source_item` block, ~line 280)
- Test: `spec/driver/actions_quest_spec.lua` (plus `spec/driver/run_spec.lua` if the objective credit is checked there)

- [ ] **Step 1: Failing specs** for each Review Focus line, using fixture quests: one with `starter_kind = "item"` whose objective is that item, one with an item starter that isn't an objective, and one NPC-started quest.
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement.** The comment cites QuestieDB `startedBy` and says whether the game consumes the item is unverified for Forever.
- [ ] **Step 4: GREEN.**
  - Run the full suite, the slow suite (21 + 1 known pending) and luacheck.
  - Real Dwarf run: from `~/Projects/WoW-Pro-Guides`, `<worktree>/bin/hwc run --race Dwarf --class WARRIOR --date 2026-11-18 --out "$TMPDIR/si"`. Paste:
    - the 95213 / 95214 findings before and after (compare with `hwc diff` against the latest main-run findings file in `~/.hwc/findings`, or a main run)
    - the per-signal counts
- [ ] **Step 5: Commit** `fix: Give item-started quests their starter item on accept`.
