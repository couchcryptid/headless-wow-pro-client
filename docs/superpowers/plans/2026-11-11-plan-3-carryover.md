# Plan 3 carry-over: rulings and deferred items

Generated from the Plan 3 SDD ledger at branch completion (2026-11-12). Plan 4 starts by reading this.

## Rulings
- Ruling: work on a branch in the main checkout, not a separate git worktree — local/questie (git-ignored catalog) and config's repo-root-relative paths live here; a worktree would make every integration spec pending — cost if wrong: none beyond less isolation; main untouched.
- | T3→T4,T5 | kills.credit(player,k,party_size), grind_to(player,lvl) | party_size has no cfg source (config.load has none) — Ruling A |
- | T7↔T8 | T7 determinism spec runs `bin/hwc run --stop-level --date`, which T8 creates | conflict — Ruling B |
- | T6 self | integration spec uses opts.max_guides absent from opts list | Ruling C |
- | T7 self | ok except Ruling B |
- Ruling A: actions pass party_size = cfg.party_size or 1 (spec §5.2 default 1); no config.load change — cost if wrong: one-line config addition later.
- Ruling B: the cross-process byte-identical findings spec moves from Task 7 to Task 8 (after the CLI exists); Task 7 keeps the in-process shuffle-determinism test — cost if wrong: none, same test later.
- Ruling C: Task 6 adds opts.max_guides (default nil = unlimited) to run.character's opts — cost if wrong: an unused option.
- Ruling: complete_manual/update_guide return false, err (addon errors are findings the driver records and continues past, never raised); current/rows/rank return nil, err on failed engine calls — cost if wrong: callers change to raise later.
- Ruling D: catalog drop rates are already 0–1 probabilities (wh.json 0.32, rate_overrides 0.15); the plan's "÷100" is wrong and dropped — cost if wrong: kill counts off by 100×, caught by kills_spec values.
- Ruling E: drop-source choice mirrors sim.py:520-551 (ordinary mob over elite/rare, then highest rate; unique named elite always drops; unknown rate → count×3 kills; no source → nil) — the brief left source choice open — cost if wrong: XP per drop objective differs from the old sim.
- Ruling F: Task 3 credit example corrected to 488 XP / xp 88 (the plan's 500/100 ignored its own per-kill recompute: 8×50 dings at 400, then 2×floor(55×4/5)=44) — cost if wrong: none, arithmetic checked by controller.
- Ruling G: E:update_guide() after any level gain from grinding or C/K kill XP, not only turn-ins (spec §5.2 "after every ding") — cost if wrong: extra engine updates, harmless.
- Ruling H: abstracted Cooking turn-in does not train; training only on a guide C/K step — spec §12 — cost if wrong: baseline gains Cooking later than a player would.
- Ruling I: A tries listed QIDs in order, first acceptable wins (grind only if an id's sole refusal is below-level); all refused → first id's reason — engine's QIDsInTable is any-of (Broker.lua:266-275) — cost if wrong: a guide listing a wrong alternative id is masked.
- Ruling J: re-review noted multi-id A with an earlier id already in log/completed now accepts a later alternative; a player would not (engine treats the step satisfied, Events.lua:709). Fix carried into Task 5's dispatch (same file): if any listed id is in the log or completed, A returns noop with that reason — cost if wrong: one-line revert.
- Task 4: complete (commits c2b8059..436d132, review clean; Ruling J carried to Task 5)
- Ruling K: `=` class-training steps with no P/SPELL tag learn nothing and are expected-manual noops; train helper fires SKILL_LINES_CHANGED + SPELLS_CHANGED (spec §5.2) — cost if wrong: a skill-gated step misses its event.
- Ruling L: L-tag tops up to the tag qty (add max(0, qty - count)), BAG_UPDATE only if added, skipped on refused outcomes — cost if wrong: an L step that should stack items under-counts.
- Ruling M: a C/K step without QO whose L tag, or raw `B|<id>` in its source line, names a catalog item objective credits only that objective (buy/loot it), not the whole quest — quest 384 objectives are Crag Boar Rib ×6 + Rhapsody Malt ×1; buying the malt alone leaves the step incomplete → spec §10's did-not-advance; the B tag is unparsed by the engine (Parser.lua:795), so the driver reads it from the guide line (Global Constraints exception: item tags say what the player buys) — cost if wrong: other no-QO C steps with B/L under-credit and show did-not-advance.
- Ruling N: shown sticky C/K rows are performed once each (a player does sticky objectives; Boar Hunter 183's only objective step is sticky) — cost if wrong: stickies complete earlier than a player would.
- Ruling O: integration spec stop_level 13 not 12 (level 12 is reached before guide 2) — cost: none.
- Ruling P: wrong-race-class fires only if EVERY listed QID on the step excludes the character (multi-QID lists are race/class alternatives, engine any-of) — cost if wrong: a real mis-tagged alternative goes unflagged.
- Ruling Q: guide_source.line_of matches on action+name when the step has no QID (ACTIVE-only steps) — cost: none.
- Task 6: review 1 Approved (0 Important). Ruling R: part-way guide close reports only A indices < max_acted; unplayed loaded guides aren't closed — matches §7.1 "skipped for the whole run" — cost if wrong: hidden accepts past the stop point unreported. Ruling S: never-shown-accept before/after = guide neighbours — cost: none.
- Task 6: fix round 1 dispatched (FIX_BASE ad2dc02): Rulings M, P, Q + minors 1-3 + derived guides[2]
- Task 6: fix round 1 commit 2822161 (Rulings M/P/Q + minors; slow 5/0). Default suite 1 failure: spec/toc_spec.lua:87 Deadmines — addon checkout moved to 64fe6b36f (another session works in ~/Projects/WoW-Pro-Guides); addon a3df10408 commented Deadmines out of Guides.xml.
- Ruling T: toc_spec asserts a chain guide (12_20_Eastern_Kingdom.lua) instead of Deadmines — specs must not depend on guide files the guides team toggles — cost: none. Added to fix round 1.
- Ruling U: unmet prereq id parsed only from `not met:%s*(%d+)` (engine's sole format, WoWPro_Broker.lua:2292); no fallback scan — cost if wrong: a differently worded why links nothing (missed link, not wrong link).
- Ruling V: classes_for keeps the brief's rule (C| lines with no R| apply to every race loading the guide — the addon's own gating), giving Dwarf {HUNTER PALADIN PRIEST ROGUE SHAMAN WARLOCK WARRIOR}, Gnome {HUNTER MAGE PRIEST ROGUE SHAMAN WARLOCK WARRIOR}; Gnome SHAMAN and Dwarf WARLOCK come only from class-only lines — flagged to the user to confirm Forever allows them — cost if wrong: two extra matrix runs whose findings are moot.
- USER (2026-11-12): Gnome Shaman and Dwarf Warlock are not valid in game; Gnome Hunter not valid either. Ruling V superseded.
- Ruling W: classes_for counts only C| lines whose R| names the race (class-only lines don't add classes): Dwarf {HUNTER PALADIN PRIEST ROGUE SHAMAN WARRIOR}, Gnome {MAGE PRIEST ROGUE WARLOCK WARRIOR} — user-confirmed — fix dispatched after Task 9 completes (same files untouched by Task 9's anchors); Task 9's matrix run figures will include the 3 invalid classes and must be re-run.
- Task 9: implementer DONE_WITH_CONCERNS (39bb660 Ruling W, 720120e anchors+harness stubs); default 357/0, slow 15/0/1 pending (Farsen why names 96408 not 96629); matrix 23 runs all stop on level, 65.7s
- Ruling X: never-shown-accept excludes A steps whose why is the engine's "QID is complete" skip (Broker.lua:2042) — the quest is done, not hidden — cost if wrong: a completed-elsewhere quest the guide wrongly re-offers goes unreported.
- Task 9: fix round 1 dispatched (FIX_BASE 720120e): Ruling X + minors 1,4,5,6,8
- Final review: "With fixes" — C1 F/b never arrive (plan defect in Task 5); C2 bag items never count for item objectives (ACTIVE-only qids, l/B unhandled); I1 wrong file:line + merged steps (supersedes Ruling Q's "cost: none" and the deferred line_of collision minor); I2 Camping 101 quests nameless yet "verified"; I3 talk-to NPCs credited as kills.
- Ruling Y: F/b/P land at destination: subzone = step name, zone = TZ (targetzone) when present — TZ joins the Z/M "where the player goes" exception — cost if wrong: some travel steps still need clicks.
- Ruling Z: item-objective progress = min(count, bag count) (game behaviour); l/B through item rule; qids fall back to engine `active` tag — cost if wrong: an objective credited by a stray held item.
- Ruling AA: line_of filters by the character's C|/R|/FACTION| (engine semantics); grouping key adds a per-guide occurrence ordinal (survives line moves) — cost if wrong: finding ids change once vs earlier files.
- Ruling AB: nameless quests → unverified + header gap line + README correction; the 12 supplement entries stay user data work — cost: none.
- Ruling AC: kill XP only for kill objectives (Questie data if it distinguishes; else starter/ender heuristic + header gap line) — cost if wrong: small XP/level skew.
- Ruling AA': finding key uses the per-guide SOURCE-line ordinal (n-th source line with same action/name/qid), not the engine-step ordinal (which shifts with class/race filtering) — survives unrelated line moves — cost if wrong: an inserted same-name line above renumbers ids for that step.
- Ruling AC': service NPCs (QuestieDB npcFlags set) also earn no kill XP — the ruling's heuristic missed both named examples — cost if wrong: a quest that kills a vendor NPC under-credits XP.
- Parked: player location persists between travel steps → a repeated F/R step can auto-complete via the engine's "already there" check (Broker.lua:2531-2537) without being acted on — Ruling AD: park; add as a findings-header gap in the next plan and rule there on moving the player per step Z/M — cost if wrong: hidden defects on repeated travel steps.
- Parked: multi-id item objectives add to ids[1] while progress reads the most-held id (rare) — Ruling: defer.
- Parked: ordinal fallback uses engine occurrence when no source line matches; `*`/`=` steps never map to a source line — Ruling: defer.

## Needs a human (in game)
- Turn-in event order vs the live client: the client may fire QUEST_TURNED_IN with the quest still in the log, plus QUEST_REMOVED; the harness removes first and fires no QUEST_REMOVED.
- Source-item removal on turn-in and its BAG_UPDATE order are unverified against the client.

## Data work (user or /triage)
- Hand-checked supplement entries for the 12 Forever Camping 101 quests (96044, 96047, 96629, …) and 98321, 96392: no catalog source names them, so Camping 101 rules never fire and profession variants equal baselines.

## Deferred and parked
- | T1 self | Step 5 writes carry-over "at branch end" | fine: controller writes it at finish |
- Task 1: minor (deferred): questie readable() treats permission-denied as missing (questie.lua:328-343)
- Task 1: minor (deferred): progress() lets NaN through; unknown quest/index returns bare false without reason
- Task 1: minor (deferred): build_quest mutates shared objective tables (count/count_assumed), idempotent
- Task 1: minor (deferred): README.md:36 overlong line
- Task 2: minor (deferred): guide index rebuilt per Engine.new (flow helper builds one per call); step() occurrence count O(i) → rows() O(n²)
- Task 2: minor (deferred): no-write specs snapshot only top-level WoWPro keys (shallow)
- Task 2: minor (deferred): TDD order slip (RED reconstructed by moving module aside)
- Task 2: minor (deferred): boot.lua keeps its own busy predicate and collect_steps
- Task 2: minor (deferred): last_error may report a stale sb.errors msg if a call fails without recording; sticky_count `n or 0` on nil success
- Task 3: minor (deferred): named-elite rate=1 also applies when rate nil or overridden (sim.py:538-546 only when r known and no override); untested
- Task 3: minor (deferred): source tie-break ignores sim's spawn-proximity score (sim.py:529-530)
- Task 3: minor (deferred): coverage — credit at cap / count 0, exact cap-clamp count, for_drop rate 0/nil, rank-4 handling
- Task 3: minor (deferred): grind_to records a grind event with kills=0 when already at target
- Task 4: minor (deferred): parse_qo returns {} when all QO parts fail (step reports acted with nothing done)
- Task 4: minor (deferred): train fires only SKILL_LINES_CHANGED; spec §5.2 lists SPELLS_CHANGED too — Task 5 owns train
- Task 5: minor (deferred): actions.lua at 518 lines — tag parsing/travel handlers could split before growing further
- Task 5: minor (deferred): IsQuestFlaggedCompleted string coercion has no dedicated stub spec
- Task 6: minor (deferred): .busted argv hack — CLI --exclude-tags or --tags=<other> drops the slow exclusion
- Task 6: minor (deferred): A/B ping-pong runs to max_iterations (no per-index total cap)
- Task 6: minor (deferred): E:guide() (via NextGuide) called every pass just for .done
- Task 6: minor (deferred): never-shown-accept built inline (DRY); leftover-quests carries a meaningless before; run.lua 429 lines mixes jobs; determinism spec in-process only
- Task 6: minor (deferred): line_of no-QID match can collide with a same-name step carrying a QID; B-tag bought item uses obj.ids[1]
- Task 7: minor (deferred): same-combo tie-break not total (needs equal combo+professions+idx+why but different fields) — matrix combos are unique by construction (Task 8), so unreachable in practice
- Task 8: minor (deferred): --date/--out unvalidated (a date like ../x changes the write path); "race not in scope" string match dead/fragile (cli.lua:539); run defaults race to Dwarf vs USAGE "default Human"; guide lookup scans first 12 lines per call; coverage gaps (combos order, missing option value)
- Task 8: minor (deferred): findings embed absolute paths (byte-identity per machine); Client line doesn't flag a dirty tree
- Task 9: carry-over: source item from QuestieDB sourceItemId is never removed on turn-in/abandon; its BAG_UPDATE fires after QUEST_LOG_UPDATE (in-game order unconfirmed)
- Task 9: carry-over: Forever-added Camping 101 quests (e.g. 96629) and 98321 have no name in any catalog source and no local supplement exists → Camping 101 rules never fire; profession variants equal baselines. Needs hand-checked supplement entries (spec §6 path 3), user/triage data work.
- Task 9: minor (deferred): anchor spec duplicates run.character boot/drive wiring to keep the Engine
- Parked: player location persists between travel steps → a repeated F/R step can auto-complete via the engine's "already there" check (Broker.lua:2531-2537) without being acted on — Ruling AD: park; add as a findings-header gap in the next plan and rule there on moving the player per step Z/M — cost if wrong: hidden defects on repeated travel steps.
- Parked: multi-id item objectives add to ids[1] while progress reads the most-held id (rare) — Ruling: defer.
- Parked: ordinal fallback uses engine occurrence when no source line matches; `*`/`=` steps never map to a source line — Ruling: defer.
