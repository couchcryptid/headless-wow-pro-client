# Plan 2 carry-over: rulings and deferred items

Generated from the Plan 2 SDD ledger at branch completion (2026-11-11). Plan 3 starts by reading this.

## Rulings
- Ruling: World.new accepts catalog = nil; Player:item_count(name) returns 0 for names when no catalog is attached; T2 specs use a minimal catalog stub table with item_id(name) — avoids reordering tasks — trivially reversible.
- Ruling: T2 adds Player:xp_max() returning 400 (level-1 value) as an interim; T3 replaces its body with xp.to_next(level) — keeps task order — if wrong, a one-line swap.
- Ruling: relative catalog paths in config (e.g. local/questie/<commit>) resolve against the hwc repo root (the directory containing bin/hwc), not the process cwd — deterministic regardless of where hwc is run — cheap to change.
- Ruling: Task 2 Files list omits src/hwc/config.lua, but the brief requires config.load changes (race scope, professions) — implementer may modify config.lua and its existing spec — if wrong, the change just moves files.
- Ruling: Task 3 — to_next errors outside 1–25 but add_xp may reach 26: at level 26 add_xp discards further XP (xp stays 0) and Player:xp_max() returns 0 without calling to_next — avoids UnitXPMax erroring at the cap — a one-line change if the client value differs.
- Ruling: commit trailer must be "Claude Opus 5.5" per global constraints (the plan's binding text) over the subagent-harness attribution — amend unpushed HEAD 71bfea4 — cost if wrong: one more amend.
- Ruling: Task 4 fix round 1 re-review done by controller, not a subagent — the fix diff 71bfea4..9261df8 is empty (message-only amend); verified empty tree diff + Opus trailer — cost if wrong: none (no code changed).
- Ruling: Task 5 specs must not depend on git-ignored local data — use an in-spec catalog stub or Task 4 fixtures (spec/fixtures/catalog) for quest 179 etc. — keeps the suite portable — cost if wrong: specs re-pointed later.
- Ruling: Task 6 determinism check uses a spec-local helper driving two separate processes; no new bin/hwc subcommand — keeps CLI surface to the plan — cost if wrong: helper moves later.
- Ruling: fix the 3 final-review Importants now rather than defer to a Plan 3 "Task 0" as the reviewer suggested — they are small, and Plan 3 builds directly on these interfaces — cost if wrong: a slightly larger Plan 2 diff.
- Ruling: fold profession-name validation into the fix wave (reviewer: silently-wrong matrix runs) — cost if wrong: one extra commit.

## Fixed in the final-review fix wave (da35ea1..b74d8f3)
- Turn-in takes collected objective items from the bags.
- Player:add_xp records an "xp" world event.
- Determinism spec compares engine snapshots, completion and sb.errors across two processes, Dwarf Warrior and Gnome Mage (no demonstrated RED: it is a guard that fires only if pairs order differs).
- Spec §4.2 no longer contradicts §4.3 (no SavedVariables pre-seed).
- config.load rejects unknown profession names (shared table src/hwc/world/skill_lines.lua).

## Fix first in Plan 3 (final-review triage)
- Partial questie_dir hard-errors every boot (catalog/questie.lua:29,129-131 via boot.lua:115); README says missing sources are never an error — record present = "partial" or soften the README.
- QuestLog:progress: negative amounts unguarded; supplement objective without count errors (questlog.lua:66).
- GetTitleText returns "" globally (stubs/core.lua) — AutoAccept branch WoWPro_Events.lua:788-792 can never fire; return the quest title while a modelled dialog is open.
- Turn-in event order vs live client: client may fire QUEST_TURNED_IN with the quest still in the log, plus QUEST_REMOVED; harness removes first and fires no QUEST_REMOVED. Confirm in-game.
- Catalog confidence stays "verified" when QuestieDB objective counts are assumed to be 1 (catalog/init.lua:184,296).

## Deferred minors (per-task reviews; leave unless Plan 3 touches them)
- Task 1: minor (deferred): sandbox_spec "tags frame script and timer errors" matches e.msg:match("ev") — tmpname containing "ev" could misbucket; match message tail instead
- Task 1: minor (deferred): env.setfenv passes numeric levels straight to real setfenv (level 1 targets the wrapper)
- Task 1: minor (deferred): on_phase spec asserts 4 of 8 phases
- Task 2: minor (deferred): GetBindLocation stub comment (stubs/core.lua:117) cites only the client, not addon call sites WoWPro_Events.lua:250,869
- Task 2: minor (deferred): config.lua requires hwc.world.player just for Player.RACES (config→world dependency)
- Task 2: minor (deferred): world/init.lua assigns player.catalog after construction; duplicate catalog refs could drift
- Task 2: minor (deferred): stubs.install silently creates a nil-catalog world when sb.world is absent
- Task 2: minor (deferred): player_spec "Orc" case relies on the real addon path instead of fake_addon()
- Task 3: minor (deferred): quest_xp has no fallback for nil quest_level (sim.py qmult uses `ql or c`)
- Task 3: minor (deferred): xp_spec lacks invalid party size, mob above +4 cap, and zero-diff-branch cases
- Task 3: minor (deferred): xp.zero_diff/gray_level valid only for levels 1–29 (11 for all >=20) — trap if cap raised
- Task 3: minor (deferred): fix report gave summary counts rather than raw busted output
- Task 4: minor (deferred): questie sandbox shares real string/table/math tables (hostile file could mutate them)
- Task 4: minor (deferred): `hwc quest` requires a valid addon path via config.load though the catalog is addon-independent
- Task 4: minor (deferred): objs.json objective kind copied unvalidated (sim.py coerces unknown→object; relabels item objectives)
- Task 4: minor (deferred): partial questie_dir hard-errors instead of recording source absent/partial
- Task 4: minor (deferred): sha256 read from SHA256SUMS, never recomputed at load
- Task 5: minor (deferred): progress() does not guard negative amounts (have can go below 0)
- Task 5: minor (deferred): turn_in uses quest.level or player.level — missing level silently same-level
- Task 5: minor (deferred): turn_in checks "incomplete" before "requires-skill"; order unpinned by spec
- Task 5: minor (deferred): placeholder_qo silently ignored when catalog nil; untested
- Task 5: minor (deferred): no specs for abandon/complete_objectives events, replaced world.log, GetQuestLogLeaderBoard nil returns
- Task 5: minor (deferred): TDD order slip (RED reconstructed after implementation)
- Task 5: minor (deferred): event-record construction duplicated in World.new and QuestLog:_record
- Task 6: minor (deferred): world_engine_spec asserts only harness errors empty; addon errors printed to stderr, not asserted
- Task 6: minor (deferred): determinism subprocess discards stderr (2>/dev/null)
- Task 6: minor (deferred): hard-coded /opt/homebrew/bin/luajit in spec and duplicated addon path in world_engine_flow.lua
- Task 6: minor (deferred): step_after_turn_in oracle uses plain substring for |C|/|R| tags
- Task 6: minor (deferred): GetTitleText returns "" globally — AutoAccept branch (Events.lua:788-792) can never fire; unverified vs live client
- Task 6: minor (deferred): cross-process determinism checked for Dwarf Warrior only
- Final review: QuestieDB sandbox shares real string/table/math (shallow-copy them); SHA256SUMS never re-verified at load; GetBindingKey iterates pairs (stubs/core.lua:181-186); unit specs need the addon checkout via config.load.
- Final fix wave: commit da35ea1 is not green on its own (its spec expects the xp event from 887b93d); suite wall time ~4s → ~38s from the cross-process determinism runs (consider tagging slow).
