# QuestieDB dependency carryover

## Baseline (old loader, pin d57637f)

Run from `~/Projects/WoW-Pro-Guides` (branch `main`, commit `fb1d504`, dirty) with the main checkout's `hwc` (old raw-file loader), 2026-11-17.

| Command | `real` |
|---|---|
| `hwc boot --race Dwarf --class WARRIOR` | 0.25 s |
| `hwc matrix --races Dwarf` | 97.17 s |

Boot result: 64 files loaded, 0 failed, 0 errors, 36 missing globals.

Findings copy (not committed, since findings embed third-party data):
`/private/tmp/claude-501/-Users-brendanvinson-Projects-headless-wow-pro-client/d1430667-cc7f-4df7-9212-b51d3aeb23c1/scratchpad/hwc-baseline`

Findings files (matrix writes one combined report per race/faction, plus one per-combo file):
- `2026-11-17-forever-alliance-dwarf.md` and `.json` (combined, 12 characters)
- `2026-11-17-forever-alliance-dwarf/Dwarf-WARRIOR-baseline.json` (per-combo)
- MAGE: no findings file. The Dwarf matrix has no MAGE combo (12 characters: HUNTER x7 variants, PALADIN, PRIEST, ROGUE, SHAMAN, WARRIOR).

Counts per category, combined report (272 findings after folding duplicates across combos, 166 roots, 106 follow from others):

| Signal | Count |
|---|---|
| never-shown-accept | 154 |
| did-not-advance | 94 |
| leftover-quests | 12 |
| accept-refused | 7 |
| below-level | 4 |
| wrong-race-class | 1 |

By severity: high 162, medium-high 4, medium 94, low 12.
The JSON `findings` array has 360 entries, because it also holds 49 manual-completion and 39 missing-global harness notices that the summary excludes.

Dwarf WARRIOR baseline combo (338 entries in the JSON findings that list it): never-shown-accept 145, did-not-advance 91, manual-completion 46, missing-global 38, leftover-quests 9, accept-refused 6, below-level 3.

## After (v<tag>)

## Differences explained

### Task 8 (catalog on the v1.1.2 Source): spec assertions

No findings assertion that ran moved. Two anchor assertions were never compared, so whether they changed is unknown:

- **#3554 Green: NOT COMPARABLE.** It was excluded with `--filter-out` because its run on `fix-u-step-loot-result` livelocks (below) on both loaders, so no findings were produced to compare.
- **#3554 Red: NOT COMPARABLE.** It fails at its precondition ("run stopped outside 19_25") on both loaders, before it reaches its findings assertion (the U|5456 step never shown).

Every catalog value pinned by `spec/catalog/catalog_spec.lua`'s installed-data block (282's prereq/starter/ender, 179's xp and objective, Vagash, Tognus Flintfire's npcFlags 19, item 750's drops) holds on v1.1.2 unchanged.

`busted --tags=slow` on v1.1.2 has three problems. All three also happen on the old raw loader at the merge base `1c5adac`, run from the main checkout, so they predate this change and aren't data differences:

- `anchors_spec` #3554 Green (`fix-u-step-loot-result`) never ends. The driver switches between `ClassicAlliance3041` and `Dungeon_Uld` about twice a second, re-capturing each guide every time. The `max_iterations` (20000) watchdog would stop it only after hours. On both loaders a 90–120 s CPU watchdog fired inside `Driver:open` → `engine.step` → `guide_source.line_in`. The suite was re-run with `--filter-out='fix/u%-step%-loot%-result'`.
- `anchors_spec` #3554 Red fails with "run stopped outside 19_25". The `main` worktree run stops with `no-next-guide` in `ClassicAlliance3041` on both loaders (7.1 s old, 8.9 s new).
- `run_dun_morogh_spec` "records did-not-advance for the Rhapsody Malt C step (QID 384)" fails identically on the old loader.

All three (the livelock and both failing slow specs) are pre-existing, have no owner in this plan, and are escalated to the user.
