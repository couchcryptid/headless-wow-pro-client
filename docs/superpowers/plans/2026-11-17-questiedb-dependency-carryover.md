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

## After (v1.1.2)

Same WoW-Pro checkout (`main`, `fb1d504`, dirty), same commands, 2026-11-17, with this branch's launcher and the installed v1.1.2 (build e1652ce) in `~/.hwc`.

| Command | `real` | Baseline |
|---|---|---|
| `hwc boot --race Dwarf --class WARRIOR` | 0.72 s | 0.25 s |
| `hwc matrix --races Dwarf` | 112.96 s | 97.17 s |

The new loader costs about 0.5 s per character open (the busted run logs `open WARRIOR Alliance: 0.55 s`, `open MAGE Alliance: 0.24 s`), so boot is about 0.5 s slower and the matrix about 16 s slower. Boot result is unchanged: 64 files loaded, 0 failed, 0 errors, 36 missing globals.

Findings copy (not committed): `/private/tmp/claude-501/-Users-brendanvinson-Projects-headless-wow-pro-client/d1430667-cc7f-4df7-9212-b51d3aeb23c1/scratchpad/hwc-after`

Counts per category, combined report (266 findings after folding, 158 roots, 108 follow from others; baseline 272, 166, 106):

| Signal | Baseline | After |
|---|---|---|
| never-shown-accept | 154 | 153 |
| did-not-advance | 94 | 87 |
| leftover-quests | 12 | 12 |
| accept-refused | 7 | 11 |
| below-level | 4 | 2 |
| wrong-race-class | 1 | 1 |

By severity: high 165 (was 162), medium-high 2 (4), medium 87 (94), low 12 (12). manual-completion (49) and missing-global (39) notices are unchanged.

Every changed finding was matched by (signal, quest id, guide, line, action).

## Differences explained

### Task 11 (v1.1.2 against the old raw pin d57637f)

**Attribution limit.** None of the changed quests has an entry in the repository's remaining fix files: `QuestieDB/src/corrections/Forever/foreverQuestFixes.lua` (`LoadDynamic`) and `.../legacy/classicQuestFixes.lua` (`LoadFactionFixes`). Their static `Load()` bodies are stripped from the release ("already folded into the TOC metadata store"), so a static correction can't be cited by file and quest id from the installed copy. I also queried v1.1.1 (build 4dbb824) for 12 of the quests (455, 1302, 1284, 6064, 473, 464, 19, 1679, 1252, 664, 1364, 115) and v1.1.1 and v1.1.2 returned identical fields. So the differences below all arrive between the old pin and v1.1.1, and they cannot be split further into "raw data update" and "static correction folded into the TOC" from the installed files. None of the examples below is attributable to a named fix file; they are reported as "old raw vs. installed release". (An attempt to fetch the unstripped fix files from the QuestieDB repository was not permitted, so that split remains open.)

Old raw fields below are from `local/questie/d57637f490c9dfcdbbc967dab47a8b0d8fe1b3cc/foreverQuestDB.lua`; new fields are from `catalog.load(...):quest(id)` on v1.1.2.

- **accept-refused 7 to 11 (+8, -4).** Example, 1284 *Suspicious Hoofprints* (`30_41_Alliance.lua:38`): the old raw row has no prerequisite and the starter is object 187273; v1.1.2 has `pre_single` `[1282, 1302]` and the starter is object 21015. The quest is now refused for an unfinished prerequisite, where before it was accepted and later hit a below-level refusal. The same shift explains 1252 and 1253 (prerequisite added), and 19 *Tharil'zun* and 115 *Shadow Magic* (old `preQuestSingle {20}`; now `pre_group [20, 98387]`, where 98387 is a Forever-added quest id). The four that left: 455 *The Algaz Gauntlet* (old `preQuestSingle {468}`, now none), 464 *War Banners* and 1302 *James Hyal* (old `{1301}`, now none).
- **did-not-advance 94 to 87 (+1, -8).** 1284, 1252, 1253, 1364, 664 and 665 left because they moved to accept-refused (above). 1302 *James Hyal* (line 347) came in: its prerequisite is gone, so the step is no longer refused at accept and instead is refused for level and clicked off (counted here under did-not-advance, not under the below-level signal, which fell for other quests). Two `L` "Level 10" steps (`01_12_Dun_Morogh.lua` lines 219 and 220) also left; I did not trace why.
- **never-shown-accept 154 to 153 (-1).** 473 *Report to Captain Stoutfist* (`19_25_Alliance.lua:18`) was hidden because quest 455 was never completed; with 455's prerequisite 468 removed, 455 is offered and 473 follows.
- **below-level 4 to 2 (-2).** 6064 *Taming the Beast* (line 240) and 1679 *Muren Stormpike* (line 273) no longer reach the accept below level 10. Their required level, class and race fields are the same in both sources (1679's `exclusiveTo {1638, 1684}` is gone), so the cause is upstream of the quest row (the level the client has on arrival). I did not trace it.
- **leftover-quests 12, wrong-race-class 1:** unchanged.

The 66-commit figure was verified during design via the GitHub compare API (pin d57637f is 66 commits behind v1.1.2). It was not re-verified from the installed files here.

### Task 11: fresh-machine path and suites

**Fresh HWC_HOME (this branch's launcher):**
- `hwc doctor` reported questie FAIL ("none installed") and exited 1.
- `hwc init` installed v1.1.2 (build e1652ce); doctor then passed.
- `hwc sync questie` said "already installed; active".
- `hwc sync questie --tag v1.1.1` worked (v1.1.1 has a Forever build, 4dbb824), and doctor showed the upstream warn ("v1.1.1 -> v1.1.2 available").
- `hwc sync questie --tag v1.1.2` switched back; doctor passed.

**Suites (v1.1.2):**
- Fast: 699 pass, 1 failure (`spec/driver/matrix_spec.lua:83`, pre-existing).
- Slow, with the #3554 Green filter-out: 18 pass, 2 failures (#3554 Red; `run_dun_morogh_spec` QID 384), both known and pre-existing, and 1 pending (`anchors_spec.lua:162`, #3535 Red Farsen's Watch), a deliberate `pending()` in the spec. It was not compared with the old loader.

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
