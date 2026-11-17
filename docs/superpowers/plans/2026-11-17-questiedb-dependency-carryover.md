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
