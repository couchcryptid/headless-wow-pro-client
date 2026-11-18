# Quest Chain Part Numbers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Findings that name a quest in a same-name chain show its position as `(part/total)`.

**Architecture:** The catalog gains `next_in_chain` (from QuestieDB `nextQuestInChain`) and a pure `Catalog:chain_part(qid)`. The driver attaches `chain` (and the chain of a referenced prerequisite) to signals. `text.lua` renders it in titles and sentences.

**Tech Stack:** LuaJIT 2.1, busted 2.3, luacheck 1.2.

**Spec:** `docs/superpowers/specs/2026-11-18-quest-chain-parts-design.md`

## Global Constraints

- Format: `(part/total)` right after the quoted quest name, e.g. `"Raene's Cleansing" (8/11)`.
- Data comes from catalog/QuestieDB only. The guide's step labels are unchanged.
- Findings format 2. Finding ids are unchanged. Deterministic. luacheck 0. Conventional Commits ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A cycle in `nextQuestInChain`/prerequisites:** terminate, and return nil rather than loop. Test it.
2. **A branch where two quests share the name and the same predecessor:** each gets a deterministic part number (lowest-id predecessor rule), with no error. Test it.
3. **A quest absent from the catalog (placeholder):** no chain and no error. Test it.
4. **A finding without a qid** (e.g. lua-error): text unchanged. Test it.
5. **A chain of one** (same name elsewhere, but not adjacent): no number. Test it.

---

### Task 1: Chain part numbers in findings

**Files:**
- Modify:
  - `src/hwc/catalog/init.lua` (`next_in_chain` field; `Catalog:chain_part`)
  - `src/hwc/driver/run.lua` (attach `chain` where `qname` is set, ~lines 138/272/387; attach `pre_chain` for the never-shown-accept prerequisite parsed from the why, and `missing_chain` for missing prerequisites)
  - `src/hwc/findings/group.lua` (carry the new fields onto findings)
  - `src/hwc/findings/text.lua` (titles via `name_of`, the never-shown sentence ~329, the missing list ~370, the left-in-log title ~303/432)
- Test: `spec/catalog/catalog_spec.lua` (fixture quests in `spec/fixtures/catalog/questie_source.lua`), `spec/findings/text_spec.lua`, `spec/findings/group_spec.lua`, `spec/driver/run_spec.lua`

**Interfaces:**
- Produces:
  - `quest.next_in_chain`: a number or nil.
  - `Catalog:chain_part(qid) -> part, total | nil`.
  - Signals and findings: `chain = { part = n, total = m }` (only when in a chain); `pre_chain` and `pre_qname` for the prerequisite a never-shown-accept names; `missing_chain = { [tostring(id)] = { part, total } }`.
  - Text: `text.with_part(name, chain)` gives `"<name>" (p/t)`. It's used wherever a quest's quoted name is rendered from these fields.

- [ ] **Step 1: Failing specs:**
  - A fixture chain of 4 same-name quests (A1→A2→A3→A4 via pre_single and next_in_chain) plus one branch with another name: `chain_part(A3) == 3, 4`, and the branch returns nil.
  - Review Focus 1-5.
  - text: a never-shown-accept title with `chain = {9,11}` reads `"Raene's Cleansing" (9/11) is never offered`.
  - The prerequisite sentence with `pre_chain = {8,11}` contains `quest 1029 "Raene's Cleansing" (8/11)`.
  - The left-in-log title is `Quest "Raene's Cleansing" (8/11) (1029) is left in the log`.
  - A finding with no `chain` renders exactly as today, so the existing text specs pass unchanged.
- [ ] **Step 2: RED.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: GREEN.** Full suite, slow suite (21 + 1 known pending; the anchors unchanged), luacheck. If fixture JSON changes, run `web/report` `npm test`.
- [ ] **Step 5: Real check.** From `~/Projects/WoW-Pro-Guides`, run `<worktree>/bin/hwc run --race Dwarf --class WARRIOR --date 2026-11-18 --out "$TMPDIR/chain"`. Expected:
  - the 25_30 findings read `"Raene's Cleansing" (9/11)`, `(10/11)` and `(11/11)` at lines 390, 396 and 401
  - the left-in-log reads `(8/11) (1029)`

  Paste them.
- [ ] **Step 6: Commit** `feat: Number the parts of quest chains that share a name`.
