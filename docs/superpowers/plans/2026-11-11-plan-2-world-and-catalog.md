# Plan 2: Simulated world and quest catalog

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the booted addon a simulated player and world: player state, a 40-slot quest log behind the real quest-log API, Classic XP and levelling, and a quest catalog built from pinned external data. Finish by proving, with the real engine in the loop, that accepting, progressing and turning in Dun Morogh's first quest completes its guide steps. No driver loop yet (that's Plan 3); specs fire the events by hand.

**Architecture:**
- **World state:** a `World` object owned by the sandbox (`sb.world`) holds the player, quest log, completed history, bags and skills.
- **Stubs:** every WoW API stub that reports player or world state reads `sb.world` on each call. Nothing is captured at install time, because the addon looks these up per call (`WoWPro_CompatUtil.lua:121–123`).
- **Catalog:**
  - **Sources:** the pinned QuestieDB Lua data files plus the old simulator's Wowhead extract. Both are read from local, git-ignored paths.
  - **How QuestieDB is read:** its files are executed in an empty sandbox env. They're data tables, but they're still downloaded code, so they get no `io` or `os` access.
  - **Merging:** per-field precedence rules merge the sources into plain quest, NPC and item objects.

**Tech Stack:** LuaJIT 2.1 (`/opt/homebrew/bin/luajit`), busted 2.3.0 (`~/.luarocks/bin/busted`), dkjson (already reachable via `bin/hwc`'s luarocks path). Shell `curl` and `shasum` only in the fetch script.

**Spec:** `docs/superpowers/specs/2026-11-11-headless-client-design.md` (§4.3 boot, §5.1 player state, §5.4 quest-log API, §5.5 XP rules, §6 catalog, §3 professions/Camping 101). **Carry-over:** `docs/superpowers/plans/2026-11-11-plan-1-carryover.md`. This is plan 2 of 4.

## Global Constraints

- **Runtime and tests:** LuaJIT/Lua 5.1 only. Specs run with `~/.luarocks/bin/busted`. Homebrew `lua` (5.5) is never used.
- **The addon is read-only input** (default `~/Projects/WoW-Pro-Guides`).
- **Fidelity:** addon behaviour, bugs included, is reproduced, never corrected. The harness never writes engine state (`WoWPro.*` decisions, `ActiveStep`, `completion`, `GuideLoaded`, `LockdownTimer`).
- **World facts come from the catalog, never from guide lines.** Only the catalog's marked placeholder path may use a step's own `QO` numbers, and it flags "unverified quest data".
- **Data storage:** no QuestieDB, Wowhead or other third-party data committed. Catalog sources live under `local/` (git-ignored) and are referenced by path in config. Only scripts, loaders and structure-only examples are committed.
- **No GPL code copied. No LICENSE file.**
- **Determinism:**
  - identical inputs give identical output;
  - no wall-clock time inside the sandbox;
  - anything serialised is key-sorted (the existing `hwc.json`).
- **Commits:** imperative subject; body ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Quest log size:** 40 (confirmed Forever cap). **Rank:** single default rank 2, guarded, not compared.

## Review Focus

1. **A quest log at exactly 40 quests.** The 41st accept is refused and leaves the log, history and engine state unchanged, and the refusal is reported to the caller (test in Task 5).
2. **`C_QuestLog.GetInfo(i)` past the last entry, including after an abandon in the middle.** It returns nil and log indices stay dense, or `PopulateQuestLog` loops forever or misses quests (test in Task 5).
3. **A quest present in no catalog source.** It's placeholder-flagged, never crashes, and never takes values from the guide except the `QO` count (test in Task 4).
4. **Levelling across several levels from one turn-in** (e.g. 2,000 XP at level 1). The XP carry is exact, and `UnitLevel`/`UnitXP`/`UnitXPMax` agree afterwards (test in Task 3).
5. **A downloaded QuestieDB file that tries to touch `io`, `os` or globals.** The loader's empty env blocks it, and the error is reported with the file name (test in Task 4).

---

## File structure

| Path | Responsibility |
|---|---|
| `src/hwc/boot.lua` (modify) | per-addon `ADDON_LOADED` interleaving, SavedVariables timing, `sb.world` creation |
| `src/hwc/sandbox.lua`, `src/hwc/polyfills.lua` (modify) | carry-over hardening |
| `src/hwc/world/init.lua` | `World.new(cfg, catalog)`, owns player, quest log, history, bags, skills |
| `src/hwc/world/player.lua` | identity, level/XP, zone/position, bind location, flight points, skills/spells, bags |
| `src/hwc/world/xp.lua` | Classic XP table and rules (pure functions) |
| `src/hwc/world/questlog.lua` | 40-slot log model: accept / progress / turn_in / abandon, completed history |
| `src/hwc/stubs/questlog.lua` (rewrite) | the real quest-log API, backed by `sb.world` |
| `src/hwc/stubs/core.lua` (modify) | `Unit*`, zone, map, items, spells and skills stubs read `sb.world.player` per call |
| `src/hwc/catalog/questie.lua` | loads pinned QuestieDB Lua data files in an empty env, decodes keyed rows |
| `src/hwc/catalog/init.lua` | builds Quest/NPC/Item objects with per-field precedence, placeholders and source notes |
| `tools/fetch-questie.sh` | downloads the pinned QuestieDB files into `local/questie/<commit>/`, writes SHA-256s |
| `catalog/supplement.example.json` | structure-only example of the hand-checked supplement (no third-party data) |
| `src/hwc/cli.lua` (modify) | `hwc quest <id>` prints one catalog quest (sorted JSON) |
| `spec/world/*_spec.lua`, `spec/catalog/*_spec.lua`, `spec/integration/world_engine_spec.lua` | tests |

## Tasks

### Task 1: Carry-over hardening and per-addon load order

**Files:** Modify `src/hwc/boot.lua`, `src/hwc/sandbox.lua`, `src/hwc/polyfills.lua` and `docs/superpowers/specs/2026-11-11-headless-client-design.md` (§4.3). Test: `spec/integration/boot_spec.lua`, `spec/sandbox_spec.lua` and `spec/polyfills_spec.lua`.

**Interfaces:**
- Produces: `boot.run(cfg)` with the same `BootResult` as Plan 1, plus `result.addon_events = {"ADDON_LOADED:WoWPro", "ADDON_LOADED:WoWPro_Leveling", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD"}` in fire order.
- **Boot order** (client behaviour; replaces Plan 1's "load both TOCs, then fire both"):
  1. Stubs.
  2. WoWPro TOC files.
  3. Assign WoWPro's SavedVariables: `WoWProData = nil` (fresh account) and `WoWProCharDB = {DebugLevel = 0}` (a saved setting, pinned per spec §4.2).
  4. `ADDON_LOADED("WoWPro")`.
  5. WoWPro_Leveling TOC files.
  6. `ADDON_LOADED("WoWPro_Leveling")`.
  7. `IsLoggedIn = true`, then `PLAYER_LOGIN`, then `PLAYER_ENTERING_WORLD(true, false)`, then settle.

  The Plan 1 pre-seed `WoWProCharDB = {QID2Guide = {}, DebugLevel = 0}` before any file is removed; `OnInitialize` creates the sub-tables, as in the client.

- [ ] **Step 1: Write failing specs:**
  - `addon_events` order is exactly as listed.
  - The Leveling module's AceAddon `baseName` is `"WoWPro_Leveling"` (`AceAddon-3.0.lua:618`).
  - `env.WoWProCharDB` is nil until WoWPro's TOC files have run. The spec drives `boot` through a hook `cfg.on_phase(name, sb)`, which `boot` calls with `"after_wowpro_files"`, `"after_addon_loaded_wowpro"` and so on.
  - The Dwarf boot still reaches `ClassicDunMorogh0112`, step 2 "A Dwarven Outfitters" (179), with 0 errors and `settle.hit_limit == false`.
  - Sandbox:
    - `env.getfenv(2)` called from a sandboxed chunk returns `env`;
    - `env.getfenv(print)` returns `env`;
    - `env.setfenv` refuses to set a function's env to the real `_G` (errors with `"hwc: setfenv to real _G refused"`) and otherwise works.
  - If `sb:record` throws (an error object whose `__tostring` errors), a later `error("x")` is still recorded.
  - Errors recorded from frame scripts and timers carry `where = "OnUpdate"`, `"OnEvent"` or `"timer"`.
  - Polyfills: the strsplit edge cases from the carry-over:
    - `strsplit("&", "a&&b", 2)` gives `"a","&b"`;
    - pieces greater than the number of pieces;
    - `pieces == 1`;
    - empty input gives `""`;
    - a leading delimiter gives `"", "a"`.
- [ ] **Step 2:** Run. Expect FAIL.
- [ ] **Step 3: Implement.**
  - Delete `polyfills.lua`'s real-clock `env.date, env.time = os.date, os.time`; the sandbox owns time.
  - `env.getfenv(f)`: map every numeric level, and every function whose real env is `_G`, to `env`.
  - Reset the error-handler re-entry guard on every path (record under `pcall`).
  - Pass a `where` tag from the frame-script and timer error routes.
  - Amend spec §4.3 with the new boot order, citing the final Plan 1 review.
- [ ] **Step 4:** Run the full suite and `bin/hwc boot --race Dwarf --class WARRIOR`. Expect PASS and the same first step.
- [ ] **Step 5:** Commit: "Load addons in client order and close Plan 1 carry-over items".

### Task 2: World and player state behind the stubs

**Files:** Create `src/hwc/world/init.lua` and `src/hwc/world/player.lua`. Modify `src/hwc/stubs/core.lua` and `src/hwc/boot.lua` (create `sb.world` before stubs install). Test: `spec/world/player_spec.lua` and `spec/stubs_spec.lua`.

**Interfaces:**
- Produces:
  - `World.new(cfg, catalog) -> World`, with fields `player`, `log` (Task 5), `catalog`, `events` (an append-only array of `{t = clock time, kind, ...}` world-change records for later plans).
  - `Player` fields: `name`, `realm`, `race`, `race_token`, `class`, `class_token`, `faction`, `sex`, `level = 1`, `xp = 0`, `zone = "Dun Morogh"`, `subzone = ""`, `map_id = 1426`, `x`, `y`, `bind = nil` (`{name, map_id}`), `flight_points = {}` (set of names), `skills = {}` (`name -> {rank, max}`), `spells = {}` (set of ids), `bags = {}` (`item_id -> count`).
  - `Player:set_zone(zone, subzone, map_id, x, y)`, `Player:add_item(id, n)`, `Player:remove_item(id, n) -> ok`, `Player:item_count(id_or_name) -> n`, `Player:learn_skill(name, rank, max)`, `Player:knows_skill(name) -> bool`, `Player:learn_spell(id)`, `Player:learn_flight_point(name)`, `Player:set_bind(name, map_id)`.
- **Behaviour:**
  - `item_count` accepts a numeric id, a numeric string, or an item name. Names resolve through `catalog:item_id(name)`; an unknown name gives 0. `B` steps pass step text (`WoWPro_Broker.lua:3717`).
  - Race tokens come from an explicit Alliance table: Human→"Human", Dwarf→"Dwarf", Gnome→"Gnome", NightElf→"NightElf".
  - `config.load` rejects races outside that table with `"hwc: race not in scope: <race>"`, until Horde is in scope (carry-over).
- **Stubs rewired to read `sb.world.player` on every call:**
  - `UnitLevel`, `UnitXP`, `UnitXPMax` (Task 3's table), `UnitRace`, `UnitClass`, `UnitSex`, `UnitFactionGroup`, `UnitName`;
  - `GetZoneText`/`GetRealZoneText`/`GetSubZoneText`, `C_Map.GetBestMapForUnit`, `C_Map.GetPlayerMapPosition`;
  - `GetItemCount` and `C_Item.GetItemCount`;
  - `IsPlayerSpell`;
  - `GetBindLocation` (returns `bind.name` or nil);
  - the skill APIs `WoWPro_Trade.lua:433` uses for Forever. Read `WoWPro_Trade.lua:405–506` first and stub exactly the calls on the `(RETAIL or FOREVER)` path (`GetProfessions`, `GetProfessionInfo`, `C_TradeSkillUI.*` as reached), backed by `player.skills`.

  Each stub keeps its citation comment.
- **Config:** `config.load` accepts `professions = { {name = "First Aid", rank = 1, max = 75}, ... }` (default empty). `World.new` applies them with `learn_skill`. These are the profession variants.

- [ ] **Step 1: Write failing specs:**
  - After `set_zone("Ironforge", "", 1455, 0.5, 0.5)`, `env.GetZoneText()` is "Ironforge" and `C_Map.GetBestMapForUnit("player")` is 1455.
  - `add_item(750, 8)` makes `env.GetItemCount(750) == 8` and `env.GetItemCount("750") == 8`.
  - With the catalog stub naming 750 "Tough Wolf Meat", `env.GetItemCount("Tough Wolf Meat") == 8`.
  - `config.load{race = "Orc"}` errors with "race not in scope".
  - A First Aid profession variant makes the Trade stubs report First Aid rank 1.
  - The Dwarf boot is unchanged (step 2, 179).
- [ ] **Step 2:** Run. Expect FAIL.
- [ ] **Step 3:** Implement. Stubs are closures that read `sb.world.player` when called.
- [ ] **Step 4:** Run the full suite. Expect PASS.
- [ ] **Step 5:** Commit: "Back player-facing WoW stubs with a simulated world".

### Task 3: XP rules and levelling

**Files:** Create `src/hwc/world/xp.lua`. Modify `src/hwc/world/player.lua` (`add_xp`). Test: `spec/world/xp_spec.lua`.

**Interfaces:**
- Produces:
  - `xp.to_next(level) -> integer` for levels 1–25. Table, from the old simulator's `TNL` (`wow-pro-leveling/sim/sim.py:31`) for 1–23, extended:
    `1:400 2:900 3:1400 4:2100 5:2800 6:3600 7:4500 8:5400 9:6500 10:7600 11:8800 12:10100 13:11400 14:12900 15:14400 16:16000 17:17700 18:19400 19:21300 20:23200 21:25200 22:27300 23:29400 24:31700 25:34000`.

    The builder **must verify 24 and 25 against a cited Classic source** (warcraft.wiki.gg "Experience to level" / Classic tables) and record the URL in a comment. If they disagree, use the source and say so in the report. Errors for levels outside 1–25.
  - `xp.quest_xp(base, char_level, quest_level) -> integer`: the multiplier is 1 when `char_level - quest_level <= 5`, then 0.8, 0.6, 0.4, 0.2 for differences 6, 7, 8, 9, and 0.1 beyond. The result is floored. (`sim.py:362`.)
  - `xp.gray_level(char_level)`: 0 if `c <= 5`, otherwise `c - floor(c/10) - 5`. `xp.zero_diff(c)`: 5 if `c <= 7`, 6 if `c <= 9`, 7 if `c <= 11`, 8 if `c <= 15`, 9 if `c <= 19`, 11 otherwise. (`sim.py:339–340`.)
  - `xp.mob_xp(char_level, mob_level, elite, party_size) -> number`, with `base = c*5 + 45`:
    - if `m >= c`: `base * (1 + 0.05 * min(m - c, 4))`;
    - if `m <= gray`: 0;
    - otherwise: `base * (1 - (c - m) / zero_diff(c))`.
    - Elite multiplies by 2 × the party share. The share is 1.0 for a party of 1, 1/2 for 2, 1.166/3, 1.3/4, 1.4/5 (`sim.py:347–360`).
    - Cite a Classic source for the formula in a comment, alongside the `sim.py` reference.
  - `Player:add_xp(n) -> levels_gained` carries the remainder across levels and stops adding at level 26. `UnitXPMax` comes from `xp.to_next(player.level)`.

- [ ] **Step 1: Write failing specs:**
  - `quest_xp(80, 1, 1) == 80`; `quest_xp(1000, 20, 12) == 400` (difference 8, multiplier 0.4).
  - `mob_xp(10, 10, false, 1) == 95`; `mob_xp(10, 12, false, 1) == 104.5`; `mob_xp(10, 4, false, 1) == 0` (grey is 4 at level 10); `mob_xp(10, 10, true, 1) == 190`.
  - At level 1, `add_xp(2000)` reaches level 3 with xp `2000 - 400 - 900 = 700`, returning 2. Afterwards `env.UnitLevel("player") == 3`, `UnitXP == 700` and `UnitXPMax == 1400`. [Review Focus 4]
- [ ] **Step 2:** Run. Expect FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expect PASS.
- [ ] **Step 5:** Commit: "Add Classic XP rules and levelling".

### Task 4: Quest catalog from pinned sources

**Files:** Create `tools/fetch-questie.sh`, `src/hwc/catalog/questie.lua`, `src/hwc/catalog/init.lua` and `catalog/supplement.example.json`. Modify `src/hwc/config.lua` (catalog paths), `src/hwc/cli.lua` (`hwc quest <id>`) and `.gitignore` (confirm `local/`). Test: `spec/catalog/questie_spec.lua` and `spec/catalog/catalog_spec.lua`, with tiny hand-written fixtures under `spec/fixtures/catalog/`. The fixtures are invented rows in QuestieDB's layout, not copied data.

**Interfaces:**
- **Config:** `catalog = {questie_dir = "local/questie/d57637f490c9dfcdbbc967dab47a8b0d8fe1b3cc", wh_json = "<path>", objs_json = "<path>", rate_overrides = "<path>", supplement = "local/catalog/supplement.json"}`.
  - The `wh_json`, `objs_json` and `rate_overrides` paths default to `$HOME/Projects/wow-pro-leveling/sim/data/{wh.json,objs.json,rate_overrides.json}`.
  - Every source is optional; a missing source is recorded in `catalog.sources[name] = {path, present = false}`.
- **`tools/fetch-questie.sh <commit>`:**
  - Downloads `data/Forever/{foreverQuestDB,foreverNpcDB,foreverItemDB,foreverObjectDB}.lua` and `support/Forever/QuestXP/{xpDB-classic,xpDB-traces}.lua` from `https://raw.githubusercontent.com/Questie/QuestieDB/<commit>/<path>` into `local/questie/<commit>/`.
  - Writes `SHA256SUMS` there with `shasum -a 256`.
  - Refuses to overwrite an existing directory with different hashes.
- **`questie.load(dir) -> {quests, npcs, items, objects, xp, keys, sha256}`:**
  - Each file runs as a chunk with `setfenv` to a fresh env holding only:
    - `QuestieDB = {}`;
    - a `QuestieLoader` whose `ImportModule(name)` returns a table (`QuestXP`);
    - the Lua 5.1 `pairs`, `ipairs`, `next`, `type`, `tostring`, `tonumber`, `select`, `unpack`, `string`, `table`, `math`.
  - No `io`, `os`, `require`, `load*`, `dofile` or `getfenv`/`setfenv`.
  - Field order comes from each file's own `QuestieDB.<x>Keys` table, never hard-coded (e.g. `questKeys.preQuestSingle` is 13 at the pin, which a spec asserts against the real file when present).
  - `xp[qid] = {level, xp}` from `QuestXP.db`, with `xpDB-traces.lua` loaded after `xpDB-classic.lua`, so later rows win.
  - `sha256` is read from `SHA256SUMS`.
- **`catalog.load(cfg) -> Catalog`:**
  - Methods: `quest(id) -> Quest|nil` (nil only if the id appears in no source and no guide placeholder was requested), `placeholder(id, qo_count) -> Quest`, `npc(id)`, `item(id)`, `item_id(name)`.
  - Fields: `sources` (name → `{path, present, sha256|nil, commit|nil}`).
- **Quest fields:**
  - `id`, `name`;
  - `level`, `required_level`;
  - `races` (nil means any), `classes` (nil means any);
  - `pre_single`, `pre_group` (arrays);
  - `objectives` (array of `{kind = "npc"|"item"|"object"|"other", ids, count, text}`);
  - `xp`, `starter`, `ender`;
  - `requires_skill` (profession name or nil);
  - `confidence = "verified"|"unverified"`;
  - `notes` (an array of source-disagreement strings).
- **Per-field precedence** (spec §6; carry over `sim.py:205–222, 795–825` *without* its use of the guide's `C|` tag, since world facts never come from the guide):
  - `level`, `required_level`: Wowhead extract (`wh.json` `level`/`reqlevel`), then QuestieDB `questLevel`/`requiredLevel`, then the QuestXP level. Required level defaults to 1.
  - `xp`: Wowhead `xp`, then QuestXP, then 0 with `confidence = "unverified"`.
  - `races`:
    - For quests below 90000: QuestieDB `requiredRaces`. 4294967373, 77 and 2047 mean any.
    - Otherwise: Wowhead `reqrace` when it is non-zero and below 2^32. A mask of 2^32 or more is unreliable on Forever-added quests and is ignored, with a note.
    - When the two sources disagree, add a note.
  - `classes`: QuestieDB `requiredClasses`, otherwise Wowhead `reqclass` when it names a single class and the quest name doesn't start with "Camping 101", otherwise nil.
  - `pre_single`/`pre_group`: QuestieDB.
  - `objectives`: `objs.json` (keep `from_db_only` as a note), then QuestieDB `objectives`, then none.
  - `name`, `starter`, `ender`: QuestieDB, then the supplement.
  - `requires_skill`: the supplement only, a hand-checked file in local storage (its format is shown in `catalog/supplement.example.json`).
  - The supplement may override any field for a listed quest, each with a `source` string.
- **NPC** (from QuestieDB `npcKeys`): `{id, name, level_min, level_max, rank (0 normal, 1 elite, 2 rare elite, 3 boss, 4 rare), spawns = {[zone_id] = {{x, y}, ...}}, zone_id}`.
- **Item:** `{id, name, drops = {{npc = id, rate = 0..1}, ...}}`.
  - Drops come from the Wowhead extract's `item[id].drops`, where each row is `[npc, rate, ...]`, with QuestieDB item `npcDrops` as a fallback (rate nil).
  - `rate_overrides.json[id].rate` replaces the rate for all of that item's drops, with its `source` string kept as a note.
  - Plan 3's kill-count model reads these.
- **`db2.pickle` is not used** (spec §6 allows it only as a cross-check, and its provenance is untraced; loading a pickle also executes code). Pinned QuestieDB plus the Wowhead extract are the sources.
- **Placeholder** (spec §6): `placeholder(id, qo_count)` gives required level 1, any race and class, `qo_count` objectives `{kind = "other", count = 1, text = "Objective <n>"}`, 0 XP and `confidence = "unverified"`. It's the only path that uses a guide-derived value, and Plan 3 calls it.
- **`hwc quest <id>`** prints the Quest as sorted JSON with its sources.

- [ ] **Step 1: Write failing specs** (fixtures only, so no network in specs):
  - A fixture QuestieDB quest file with a `questKeys` block decodes into named fields.
  - A fixture file that calls `io.open` or `os.execute`, or reads an undefined global, fails to load with an error naming the file. [Review Focus 5]
  - Precedence:
    - a fixture quest present in both sources takes Wowhead `level`;
    - a Forever 9xxxx fixture with a Wowhead race mask of 2^32 or more gets `races == nil` plus a note;
    - a fixture "Camping 101: First Aid" with supplement `requires_skill = "First Aid"` carries it.
  - An id in no source: `quest(id) == nil`, and `placeholder(id, 2)` has 2 objectives, `xp == 0` and `confidence == "unverified"`. [Review Focus 3]
  - **Integration** (pending when `local/questie/<pin>` is absent):
    - `questKeys.preQuestSingle == 13`;
    - quest 282 has `pre_single == {218}`, starter NPC 786 and ender 1965;
    - quest 179 has `xp == 80` and objective item 750 ×8 (`objs.json`);
    - NPC 1388 (Vagash) has `rank == 1` and level 11;
    - item 750 has at least one drop with a numeric rate;
    - `catalog.sources.questie.sha256` matches the pin's files.
- [ ] **Step 2:** Run. Expect FAIL.
- [ ] **Step 3:** Implement. Run `tools/fetch-questie.sh d57637f490c9dfcdbbc967dab47a8b0d8fe1b3cc` once locally (network) so the integration specs exercise real data. Commit only code and the example.
- [ ] **Step 4:** Run the full suite and `bin/hwc quest 282`. Expect PASS, with the JSON showing `pre_single [218]`.
- [ ] **Step 5:** Commit: "Add quest catalog from pinned QuestieDB and Wowhead extract".

### Task 5: Quest log model and the real quest-log API

**Files:** Create `src/hwc/world/questlog.lua`. Rewrite `src/hwc/stubs/questlog.lua`. Test: `spec/world/questlog_spec.lua` and `spec/stubs_spec.lua`.

**Interfaces:**
- Consumes: `World`, `Player:add_xp` (Task 3) and `Catalog` (Task 4).
- Produces: `QuestLog`, at `world.log`:
  - `accept(qid) -> ok, reason`. Reasons:
    - `"log-full"` at 40 entries;
    - `"already-in-log"`;
    - `"already-completed"`;
    - `"below-level"` when `player.level < quest.required_level`;
    - `"race"` / `"class"` when the catalog excludes the character;
    - `"prerequisite"` when `pre_single` (any) or `pre_group` (all) is unmet against history;
    - `"unknown-quest"` when the catalog has no quest and no placeholder was passed.

    A refused accept changes nothing. `accept(qid, {placeholder_qo = n})` uses `catalog:placeholder`.
  - `progress(qid, objective_index, amount) -> ok`. Clamps at `count`.
  - `complete_objectives(qid, indices_or_nil)`. nil means all.
  - `is_complete(qid)`: all objectives fulfilled, or the quest has none.
  - `turn_in(qid) -> ok, reason, xp_gained, levels_gained`. Reasons are `"not-in-log"`, `"incomplete"` and `"requires-skill"` (the Camping gate: `quest.requires_skill` not known by the player). On success it records the quest in history, adds `xp.quest_xp(quest.xp, level, quest.level)`, and removes the quest from the log.
  - `abandon(qid) -> ok`.
  - `entries()` returns quests in acceptance order, as dense indices 1..n.
  - `history[qid] = true`.
  - Every change appends to `world.events`.
- **`stubs/questlog.lua`**, the real API on Forever's path (`WoWPro_CompatUtil.lua:121–208`, `WoWPro_Broker.lua:4011–4060`, `:4131`), all reading `world.log` on each call:
  - `C_QuestLog.GetNumQuestLogEntries() -> n, n`.
  - `C_QuestLog.GetInfo(i)` returns `{title, level = quest.level, questID, isHeader = false, suggestedGroup = 0, frequency = 0, isHidden = false}` for i in 1..n and nil otherwise. No header rows, since the Forever log isn't headered in the engine's path.
  - `C_QuestLog.GetQuestObjectives(qid)` returns `{text = "<objective text>: <have>/<count>", type = (kind == "item" and "item" or kind == "npc" and "monster" or "object"), finished, numFulfilled, numRequired}`.
  - `C_QuestLog.IsComplete(qid)`, `C_QuestLog.IsFailed(qid) = false`, `C_QuestLog.IsQuestFlaggedCompleted(qid) = history[qid] == true`, with the OnAccount/ForAccount variants false.
  - `GetNumQuestLeaderBoards(i) = #objectives`.
  - `GetQuestLogLeaderBoard(idx, i) -> text, type, finished`.
  - `GetQuestProgressBarPercent(qid) = 0`.
  - `LE_QUEST_FREQUENCY_DAILY = 1` and `Enum.QuestFrequency = {Default = 0, Daily = 1, Weekly = 2}`.
  - Each gets its citation comment.

- [ ] **Step 1: Write failing specs:**
  - The 41st accept returns `false, "log-full"`, and the log, history and `world.events` are unchanged. [Review Focus 1]
  - Accept 3 quests, abandon the second: `GetInfo(1)`, `GetInfo(2)` and `GetInfo(3) == nil`; `GetNumQuestLogEntries() == 2`. [Review Focus 2]
  - Accepting a fixture quest with required level 4 at level 1 returns `false, "below-level"`.
  - After `progress(179, 1, 8)`, `GetQuestObjectives(179)[1]` is `{text = "Tough Wolf Meat: 8/8", finished = true, numFulfilled = 8, numRequired = 8}` and `IsComplete(179)` is true.
  - `turn_in(179)` at level 1 gives `true, nil, 80, 0`, `IsQuestFlaggedCompleted(179) == true`, and the log is empty.
  - Camping gate: a fixture quest with `requires_skill = "First Aid"` gives `turn_in -> false, "requires-skill"` without First Aid, and succeeds with it.
- [ ] **Step 2:** Run. Expect FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expect PASS.
- [ ] **Step 5:** Commit: "Model the 40-slot quest log behind the real quest-log API".

### Task 6: Real engine in the loop on Dun Morogh's first quest

**Files:** Modify `src/hwc/boot.lua` (load the catalog from `cfg.catalog`; `result.world`). Test: `spec/integration/world_engine_spec.lua`, pending when the addon or catalog is absent.

**Interfaces:**
- Produces: `boot.run(cfg)` returns `result.world` and `result.sb` after boot, so specs and Plan 3's driver can act and then `sb.clock:settle{...}`.
- **Event sequences** (spec §5.2; the builder checks each against `WoWPro_Events.lua:752–940` and `WoWPro_AutoComplete.lua:317–399` and cites the lines in the spec file):
  - **accept:** `world.log:accept(qid)`, then `fire("QUEST_ACCEPTED", logIndex, qid)`, then `fire("QUEST_LOG_UPDATE")`.
  - **objective progress:** `progress(...)`, `player:add_item(...)` for item objectives, then `fire("QUEST_LOG_UPDATE")` and `fire("BAG_UPDATE", 0)`.
  - **turn-in:** `turn_in(qid)`, then `fire("QUEST_TURNED_IN", qid, xp, 0)`, then `fire("QUEST_LOG_UPDATE")`. If levels were gained, also `WoWPro:UpdateGuide("sim:level")` (the addon has no level-up handler).

  Settle after each sequence. The spec does this by hand; Plan 3 turns it into the driver.

- [ ] **Step 1: Write the failing spec** "Dwarf Warrior completes Dwarven Outfitters with the real engine":
  - after boot, the visible step is `A Dwarven Outfitters` (179);
  - accept, then settle: that step's index has `WoWPro.completion[idx]` truthy, and the visible step becomes `C Dwarven Outfitters`;
  - progress objective 1 by 8 (items 750 ×8), then settle: the C step completes and the visible step is `T Dwarven Outfitters`;
  - turn in, then settle: the T step completes, `world.player.xp == 80`, `env.C_QuestLog.IsQuestFlaggedCompleted(179) == true`, and the next visible step is the one after the T line in `01_12_Dun_Morogh.lua`, found by content, not by index;
  - `result.sb.errors` has no harness errors, and every `settle` returns `hit_limit == false`;
  - **Gnome Mage:** the same flow passes.
  - **Determinism:** two runs in separate processes give identical `world.events` (sorted JSON).
- [ ] **Step 2:** Run. Expect FAIL.
- [ ] **Step 3:** Implement the `boot.lua` changes. If the engine does not advance at a step, use `superpowers:systematic-debugging` (root cause first). Fix only harness fidelity (stubs, event order, world model), with citations. **Never change engine decisions.** If the real engine legitimately does not advance (an addon or guide bug), stop and report it with file:line, because it's a finding, not a harness bug.
- [ ] **Step 4:** Run the full suite. Expect PASS.
- [ ] **Step 5:** Commit: "Drive the real engine through Dun Morogh's first quest". Update `README.md` with catalog setup (`tools/fetch-questie.sh`, config paths, the local-only data policy) and `hwc quest`, then commit "Document world and catalog setup".

---

## Follow-on plans

- **Plan 3: Driver and findings.** The loop (spec §4.4) and the step-action table (§5.2), using Task 6's event sequences:
  - the refusal policy, grind-to-level, the immediate Camping 101 turn-in, and the forced update on level-up;
  - signals with severity and root-cause links (§7.1);
  - a canonicalised findings markdown, byte-identical across processes (§7.2);
  - anchors from §10: #3535 Red/Green, #3554 U-step, Rhapsody Malt, and the `EnableDungeons` engine-bug finding;
  - the Dwarf/Gnome 1–25 matrix.
- **Plan 4: `/triage` skill** (§8).
