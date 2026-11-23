# Arrival Emulation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Travel steps (`F f b P H h R`) run on real Forever data, never on the step's own
text. A step that doesn't advance in the addon's own checks becomes a guide finding. A gap
in hwc's data becomes a harness notice.

**Architecture:**
- `hwc update` also installs Forever client tables from wago.tools as converted JSON under
  `~/.hwc/forever/<build>/` (`hwc.forever.*`), the way it installs QuestieDB.
- `hwc.forever.db` derives taxi nodes, map and continent links and area names from them.
- A committed first-party file, `hwc.world.arrivals`, holds the in-game captures.
- `hwc.driver.arrival` does the matching.
- `hwc.driver.actions` emulates each step with world changes and addon events only.
- The driver turns `out.data_gap` into the harness signal `arrival-data-gap`.

**Tech Stack:** LuaJIT 2.1, busted 2.3, dkjson, luafilesystem, curl (via
`hwc.questie.http`); report page TypeScript (web/report, vitest).

**Spec:** `docs/superpowers/specs/2026-11-19-arrival-emulation-design.md`. Read it first;
§ numbers below are its sections.

## Global Constraints

- **Landing values come from data.** Zone, subzone, map id and bind text never come from
  the step being judged. The step only picks *which* real point it means (spec §6, §9).
- **Unknown is never a pass.** Unknown data becomes `arrival-data-gap`, never
  `did-not-advance`, and never silence.
- **Actions never write engine state.** They change the world and fire events. Each event
  sequence cites the addon line it mirrors (`~/Projects/WoW-Pro-Guides`).
- **No third-party data committed.** Downloaded tables live in `~/.hwc`. Spec fixtures are
  trimmed, hand-made CSV/JSON labelled test data, a few rows each.
- **Runs never hit the network.** Only `hwc update`/`hwc init` download.
- **Forever is not Classic.** The client tables are Forever's own build. Classic values
  never enter `hwc.world.arrivals`.
- **Commits.** Use Conventional Commit subjects, ending with the `Co-Authored-By` line.
- **Specs.** `~/.luarocks/bin/busted` per task; `~/.luarocks/bin/busted --tags=slow`
  before Task 9's commit; `npm test && npm run typecheck` in `web/report` for Task 10.

## Plan decisions (where the spec left a choice)

- **Departure radius.** `arrival.RADIUS = 0.05`, as a map fraction.
- **Units.** Positions in `hwc.world.arrivals` are percent, converted to fractions at
  load, as `parse_coords` does.
- **wago URLs.** Builds: `https://wago.tools/api/builds`, key `wowf`, newest first; the
  newest is `[1].version`. Tables:
  `https://wago.tools/db2/<Table>/csv?build=<version>`.
- **Build check.** A build string must match `^%d+%.%d+%.%d+%.%d+$` before it becomes a
  path.
- **`fp-unknown` downgrade.** After any `fp-unknown` on a continent, a later
  `flight-point-undiscovered` there is a notice.
- **`arrival-mismatch`.** The driver sets it as the reason when the action traveled
  (`out.arrived`) and set no other reason.
- **Two settles for `F`.** `actions.perform` may settle twice for `F`. `out.settle` keeps
  the last result, with `hit_limit` OR-ed.

## Review Focus

1. **No tables installed** (fresh checkout, CI). Every travel step runs; none crashes;
   none gives `did-not-advance`. Each step that doesn't advance gives a `tables-missing`
   notice, and the report says to run `hwc update`. Test: Task 9 (`#slow`).
2. **A CSV field with a comma or doubled quote** (`"Stormwind, Elwynn"`,
   `"Say ""hi"""`). It parses as one field. Test: Task 1.
3. **A wago download that fails halfway, or a CSV missing a kept column.** Nothing is
   installed, `active` is unchanged, and the error names the table. Test: Task 2.
4. **A boat to another continent** (Menethil to Theramore). The next `F` lists the new
   continent's nodes. Test: Task 7.
5. **A name that is a real area on another continent** (e.g. an `F` named after a
   Kalimdor subzone while in Eastern Kingdoms). It is not `name-not-an-area`, because
   area names are build-wide; §3's other branches decide. Test: Task 5.

---

### Task 1: CSV parser and table converter

**Files:**
- Create: `src/hwc/forever/csv.lua`, `src/hwc/forever/convert.lua`, `spec/forever/csv_spec.lua`, `spec/forever/convert_spec.lua`, `spec/fixtures/forever/*.csv` (TaxiNodes, UiMap, UiMapAssignment, AreaTable, WMOAreaTable, a few rows each, covering Stormwind/Thelsamar/Ironforge/a Kalimdor node)

**Interfaces:**
- Produces:
  - `csv.parse(text) -> { header = {string}, rows = {{string}} }`, RFC 4180 (quoted fields, `""` escapes, CRLF or LF, trailing newline). It raises `"hwc: csv: line <n>: <problem>"`.
  - `convert.TABLES`: an ordered list of `{ name = "TaxiNodes", keep = {...} }` with the spec §1 columns.
  - `convert.table(name, text) -> { columns = {string}, rows = {{...}} }`. Numeric columns become numbers. It raises `"hwc: forever: <name>: missing column <col>"`.

- [ ] **Step 1: Write the failing specs:**
  - `parse` keeps `"Stormwind, Elwynn"` as one field, unescapes `""`, and handles CRLF.
  - It errors on an unterminated quote with the line number.
  - `convert.table("TaxiNodes", fixture)` gives `rows` whose `ID`, `ContinentID`, `Flags` and `Pos_*` are numbers, keeping only the kept columns.
  - It errors on a CSV missing `Pos_1`.
- [ ] **Step 2: Run** `~/.luarocks/bin/busted spec/forever`. Expected: FAIL (module not found).
- [ ] **Step 3: Implement both modules.**
- [ ] **Step 4: Run** it again. Expected: PASS.
- [ ] **Step 5: Commit** `feat: Parse and convert Forever client table CSVs`

### Task 2: Install the tables (`hwc update`, `hwc init`, doctor, config)

**Files:**
- Create: `src/hwc/forever/home.lua`, `src/hwc/forever/install.lua`, `spec/forever/install_spec.lua`
- Modify:
  - `src/hwc/cli/update.lua`: also sync the tables; add a `--build VERSION` option; report a line `Forever tables <from> → <build>` or `... already installed; active`.
  - `src/hwc/cli/init.lua`: install both.
  - `src/hwc/doctor.lua`: a `forever` check after `questie_checks`.
  - `src/hwc/config.lua:35-41`: `catalog.forever_dir` defaults to the active build dir.
  - `README.md`: setup, "World and catalog", and the licence section (the tables are downloaded, never committed).
- Test: `spec/cli/commands_spec.lua`, `spec/doctor_spec.lua`, `spec/config_spec.lua`

**Interfaces:**
- Consumes: Task 1 `convert.TABLES`, `convert.table`; `hwc.questie.http` (`get_json`, `download`, `sha256`).
- Produces:
  - `home.dir(root, build) -> path`, which raises `"hwc: forever: bad build <b>"`.
  - `home.active(root) -> build|nil`; `home.set_active(root, build)`.
  - `home.active_dir(root) -> path|nil, reason` (`"none installed"` / `"broken: <b>"`).
  - `install.sync(root, opts, deps) -> { from, to, already } | nil, err`, with `opts = { build?, download_mode? }`.
  - `install.init(root, deps, opts)`, same as `hwc.questie.install.init`.
  - The installed dir holds `<Table>.json` for each table and `.hwc-release.json` = `{ build, tables = { [name] = { sha256, rows } }, downloaded_at }`.
  - `install.verify(dir) -> true|nil, err`: every table's JSON is present and parses.

`sync`:
1. Resolve the build: `opts.build`, or newest `wowf`.
2. If `dir(build)` verifies, set it active and return `already`.
3. Otherwise stage `root/forever/.stage-<build>-...`. For each table: download the CSV into the stage, sha256 it, convert it, write the JSON, remove the CSV.
4. Write the release file, place the stage atomically, set active.
5. On any failure, remove the stage and leave `active` as it was.

Mirror `hwc.questie.install` (`stage_name`, `place`).

- [ ] **Step 1: Write the failing specs** (`deps` fakes serve the fixture CSVs from Task 1):
  - `"installs the newest wowf build and makes it active"`
  - `"--build pins the version"`
  - `"an installed, verified build is already, with no download"`
  - `"a failed download leaves active unchanged and no stage dir"` (Review Focus 3)
  - `"a CSV missing a kept column fails with the table named"` (Review Focus 3)
  - `"a bad build string is refused before any path is built"`
  - doctor: `"forever ok shows the build"`; `"forever missing fails with fix hwc update"`.
  - commands: `hwc update` prints both result lines; `--build` reaches `sync`.
  - config: `catalog.forever_dir` is the active dir under `HWC_HOME`.
- [ ] **Step 2: Run** `~/.luarocks/bin/busted spec/forever spec/cli/commands_spec.lua spec/doctor_spec.lua spec/config_spec.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** it again. Expected: PASS.
- [ ] **Step 5: Commit** `feat: Install Forever client tables with hwc update`

### Task 3: Forever table reader and derived data

**Files:**
- Create: `src/hwc/forever/db.lua`, `spec/forever/db_spec.lua`, `spec/fixtures/forever/installed/` (the Task 1 fixtures converted, plus a `.hwc-release.json`)
- Modify: `src/hwc/catalog/init.lua:113-131` (`self.forever`, `self.sources.forever = { path, present, build }`; specs may pass `c.forever_db`)

**Interfaces:**
- Consumes: Task 2 store layout.
- Produces:
  - `db.open(dir) -> DB | nil, reason`.
  - `DB.build: string`.
  - `DB:taxi_nodes(continent_id, faction) -> {node}`. Nodes come in `ID` order; `faction` is `"Alliance"` or `"Horde"` and matches `Flags & 3` 1, 2 or 3.
  - `node = { id, name, continent, faction_bits, map_id, x, y, zone }`, with `x`/`y` as fractions per the spec §1 formula and `zone` from `AreaTable`.
  - `DB:node(name) -> node|nil`.
  - `DB:continent_of(ui_map_id) -> continent_ui_map_id|nil`, by walking `UiMap` parents to `Type` 2.
  - `DB:zone_of_map(ui_map_id) -> string|nil`: the `AreaTable` name of the map's `UiMapAssignment.AreaID`, falling back to the `UiMap` name.
  - `DB:ui_map_of_area(area_id) -> ui_map_id|nil` (for QuestieDB spawns).
  - `DB:is_area_name(s) -> boolean`: in `AreaTable`, `WMOAreaTable` or `UiMap` names, exact and case-sensitive.
  - `Catalog:npc_position(npc_id) -> map_id, x, y | nil`: QuestieDB first spawn, area converted to a UI map via `DB:ui_map_of_area`, percent converted to fractions.

- [ ] **Step 1: Write the failing specs:**
  - `"Thelsamar, Loch Modan"` derives map 1432, zone "Loch Modan", x ≈ 0.3394 and y ≈ 0.5079 (within 0.001).
  - `continent_of(1453) == 1415`.
  - `is_area_name("Stormwind")` is false; `is_area_name("Stormwind City")` and `is_area_name("Trade District")` are true.
  - `taxi_nodes(1415, "Alliance")` excludes Horde-only nodes.
  - `npc_position(1572)` returns 1432 and fractions.
  - `db.open` of a missing dir returns `nil, "none installed"`.
- [ ] **Step 2: Run** `~/.luarocks/bin/busted spec/forever/db_spec.lua spec/catalog`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** it again. Expected: PASS.
- [ ] **Step 5: Commit** `feat: Derive taxi nodes, maps and area names from the Forever tables`

### Task 4: First-party arrival facts and cross-check

**Files:**
- Create: `src/hwc/world/arrivals.lua`, `spec/world/arrivals_spec.lua`
- Modify: `src/hwc/catalog/init.lua` (`Catalog:arrival_problems`)

**Interfaces:**
- Produces `hwc.world.arrivals`, a plain table:
  - `subzones = { [node_name] = { subzone, checked } }`
  - `inns = { { npc, bind, zone, subzone, map_id, x, y, checked } }`
  - `crossings = { { kind = "boat"|"portal"|"teleport", from = {map_id,x,y}|nil, spell = id|nil, zone, subzone, map_id, x, y, checked } }`
  - `start_nodes = { [race_key] = node_name }`
  - `start_bind = { [race_key] = { bind, zone, subzone, map_id, x, y, checked } }`
  - `taxi_map = { lists_undiscovered = true, order = "id", checked = "unverified" }`
  - `arrivals.problem(kind, entry) -> string|nil`, which validates the required fields and that `checked` is present.
  - Ship it with `start_nodes` for every race in `Player.RACES`, holding the capital node names read from the installed `TaxiNodes`, with `checked = "user, 2026-11-19: capital node learned"`. Every other list ships empty; captures fill them later.
- Produces `Catalog:arrival_problems() -> { { key, detail } }`:
  - an inn npc without `npcFlags` bit 128;
  - a `start_nodes` name the installed `DB:node` doesn't know;
  - an inn whose QuestieDB map id differs from the entry's.
  It is empty without QuestieDB or the tables.

- [ ] **Step 1: Write the failing specs:**
  - every `Player.RACES` key has a `start_nodes` entry;
  - `problem` rejects an inn without `checked`;
  - `arrival_problems` flags an unknown start node and a mislabelled innkeeper, and is `{}` without the tables.
- [ ] **Step 2: Run** `~/.luarocks/bin/busted spec/world/arrivals_spec.lua spec/catalog`. Expected: FAIL.
- [ ] **Step 3: Implement.** Read the capital node names from your installed tables (`hwc update` first), not from memory.
- [ ] **Step 4: Run** it again. Expected: PASS.
- [ ] **Step 5: Commit** `feat: Add first-party arrival facts with a QuestieDB and table cross-check`

### Task 5: Matching helpers

**Files:**
- Create: `src/hwc/driver/arrival.lua`, `spec/driver/arrival_spec.lua`

**Interfaces:**
- Produces:
  - `arrival.RADIUS = 0.05`
  - `arrival.nearest(list, map_id, x, y, pos_of) -> item|nil`: same map, within `RADIUS`, the closest wins, a tie goes to the earlier item.
  - `arrival.exact(landing, text) -> boolean`: `text` equals `landing.zone` or `landing.subzone`, or `tonumber(text) == landing.map_id`. This mirrors `WoWPro_AutoComplete.lua:515-526`.
  - `arrival.location(name) -> string`: the text before the first `,`, trimmed.
  - `arrival.loose(candidates, name, tz) -> item|nil, "none"|"ambiguous"`. Probe the name, then the first `;` part of `tz`, lower-cased and trimmed. For each probe, match against `location(c.name)`, `c.zone` and `c.subzone`. Tiers are equals, then prefix, then substring; take the first tier with any hit. One hit returns it; several return `"ambiguous"`.
  - `arrival.classify(db, landing, name, tz) -> "advances"|"name-not-an-area"|"subzone-unknown"|"subzone-known"`, per spec §3:
    - `"name-not-an-area"` when the name and the TZ part (each when present) are neither `db:is_area_name` nor a number;
    - `"advances"` when `exact` holds against the zone or map id;
    - `"subzone-known"` when `landing.subzone ~= nil`;
    - else `"subzone-unknown"`.

- [ ] **Step 1: Write the failing specs:**
  - `nearest` (closer wins, other maps ignored, outside the radius ignored);
  - `exact("Stormwind City")` against zone "Stormwind City" is true, `"Stormwind"` is false, `"1453"` against map 1453 is true;
  - `loose(nodes, "Stormwind")` gives "Stormwind, Elwynn"; `"Gadgetzem"` gives `nil, "none"`; two `"port"` hits give `nil, "ambiguous"`; the TZ fallback works;
  - `classify`: `"Stormwind"` gives `name-not-an-area`; `"Thelsamar"` with no captured subzone gives `subzone-unknown`; `"Loch Modan"` gives `advances`; a Kalimdor area name while in Eastern Kingdoms isn't `name-not-an-area` (Review Focus 5).
- [ ] **Step 2: Run** `~/.luarocks/bin/busted spec/driver/arrival_spec.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** it again. Expected: PASS.
- [ ] **Step 5: Commit** `feat: Add arrival matching and name classification`

### Task 6: Player, taxi stubs, `F` and `f`

**Files:**
- Modify:
  - `src/hwc/world/player.lua:97-98,181-189`
  - `src/hwc/world/init.lua:11-29`
  - `src/hwc/stubs/core.lua:145-148,232-256`
  - `src/hwc/driver/actions.lua`: `perform_flight_point`; a new `perform_flight` for `F`; a `depart(ctx, step, out)` helper; the header and Ruling Y comment at `:486-495`
  - `src/hwc/driver/engine.lua:26-46`: add `"waypcomplete"` to `TAG_KEYS`, with CC=1, CS=2, CN=0 per `WoWPro_Parser.lua:486-488`
  - `spec/helpers/driver_fixtures.lua`: the world gets the fixture `DB`; the fake engine gets `sb = { taxi_taken = {} }`; plus a no-tables variant
- Test: `spec/world/player_spec.lua`, `spec/stubs_spec.lua:205-218`, `spec/driver/actions_other_spec.lua` (replace :40-103, which assert the old step-name landing)

**Interfaces:**
- Consumes: Task 3 `DB`, Task 4 `arrivals`, Task 5 helpers.
- Produces:
  - Player: `p.flight_points[node_name]`, `p.on_taxi`, `Player:set_on_taxi(bool)` (recorded as `"taxi"`).
  - `World.new` learns `arrivals.start_nodes[race_key]` when the tables know it, and applies `start_bind`.
  - `world.fp_unknown[continent] = true`.
  - Outcome fields: `out.data_gap = { reason, key }`, `out.expected = { name, tz }`, `out.arrived = { zone, subzone, map_id }`, `out.resolved_by = "loose"|nil`, `out.classify` (from `arrival.classify`).
  - Guide reasons: `"no-taxi-node"`, `"flight-point-undiscovered"`.

**Stubs:**
- The node list comes from `DB:taxi_nodes(continent_of(p.map_id), p.faction)`. When `arrivals.taxi_map.lists_undiscovered` is false, it is filtered to learned nodes.
- `TaxiNodeGetType` gives `REACHABLE` for learned nodes and `NONE` otherwise.
- `UnitOnTaxi` returns `p.on_taxi`.
- `TakeTaxiNode(i)` appends the name to `sb.taxi_taken`.

**`F` (spec §5):**
1. `depart`.
2. With no `DB`: `data_gap = { "tables-missing", "no-tables" }` and no taxi events.
3. Otherwise fire `TAXIMAP_OPENED` and settle, then read the new tail of `ctx.engine.sb.taxi_taken` (`engine.lua:63` keeps `sb`).
4. A learned node was taken: `set_on_taxi(true)`, fire `PLAYER_CONTROL_LOST`, settle. Then `set_zone(node.zone, subzone or "", node.map_id, node.x, node.y)`, where `subzone` is `arrivals.subzones[name]`. Then `set_on_taxi(false)` and fire `ZONE_CHANGED_NEW_AREA`, `ZONE_CHANGED` and `PLAYER_CONTROL_GAINED`. Cite `WoWPro_Events.lua:828-866` and `WoWPro_AutoComplete.lua:461-530`.
5. An undiscovered node was taken: reason `flight-point-undiscovered`. It becomes the notice `start-node-unknown` when the race has no start node, or `fp-unknown` when `world.fp_unknown[continent]` is set.
6. No node was taken: reason `no-taxi-node`.
7. In cases 5 and 6, resolve with `arrival.loose(nodes, name, tz)`. On a hit, land with zone events only and learn nothing; on a miss, `data_gap = destination-unresolved`.
8. Always set `out.expected`; set `out.arrived` and `out.classify` whenever the player landed.

**`f` (spec §4):**
1. `depart`.
2. Take the node of the player's faction nearest the departure on that map
   (`arrival.nearest` over `DB:taxi_nodes`).
   - This replaces the spec's "nearest QuestieDB flight master": QuestieDB has no index
     by NPC flag, and the departure *is* the flight master's spot, where the node sits.
3. Learn the node, fire `TAXIMAP_OPENED`, and fire `UI_INFO_MESSAGE(0, ERR_NEWTAXIPATH)`
   only if the node is new.
4. With no node: `data_gap = { "fp-unknown", "<map_id>:<x>,<y>" }` and set `fp_unknown`.

- [ ] **Step 1: Write the failing specs:**
  - `"a new Dwarf knows its capital node"`
  - `"the taxi map lists the continent's faction nodes in ID order, NONE for undiscovered"`
  - `"F Stormwind with a learned node flies: control lost, on taxi, lands in Stormwind City, control gained; subzone is not 'Stormwind'"` (assert the event order)
  - `"F to an undiscovered node is flight-point-undiscovered and lands by the loose match without learning it"`
  - `"F naming no node is no-taxi-node"`
  - `"F with no tables is tables-missing and fires no taxi events"`
  - `"f learns the real node name nearest the departure and fires the discovery once"`
  - `"f for a known node fires TAXIMAP_OPENED but no ERR_NEWTAXIPATH"`
  - `"f with no node nearby is fp-unknown"`

  The fake engine doesn't run the addon, so `F` specs make `E:fire("TAXIMAP_OPENED")` append the node AutoSelect would pick to `E.sb.taxi_taken`.
- [ ] **Step 2: Run** `~/.luarocks/bin/busted spec/world spec/stubs_spec.lua spec/driver/actions_other_spec.lua`. Expected: the new specs FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** it again. Expected: PASS.
- [ ] **Step 5: Commit** `feat: Fly F steps on real taxi nodes and learn real flight points`

### Task 7: `b` and `P`

**Files:**
- Modify: `src/hwc/driver/actions.lua` (`perform_crossing` for `b`/`P`)
- Test: `spec/driver/actions_other_spec.lua` (fixture crossings passed through the world, not `hwc.world.arrivals`)

**Interfaces:**
- Consumes: Tasks 4-6.
- Produces: the `arrival-unknown` and `destination-unresolved` gaps; `out.arrived` and `out.classify`.

Rules (spec §6):
- **Candidates:** crossings whose `from` is `arrival.nearest` to the departure; for `P`, also teleports whose `spell` the player knows or the step's `SPELL` names.
- **One candidate:** land there.
- **Several:** take the one with `exact(c, name)` or `exact(c, tz)`; failing that, `loose`.
- **None:** `arrival-unknown` with key `"<action>:<map_id>:<x>,<y>"`.
- **Landing:** zone events only. Crossings are read from `ctx.world.arrivals`, which defaults to `hwc.world.arrivals` and is overridable in specs.

- [ ] **Step 1: Write the failing specs:**
  - `"b from a one-route dock lands at its real arrival"`
  - `"b from a two-route dock takes the route the step names exactly"`
  - `"b naming neither route lands by the loose match"`
  - `"b to another continent changes the continent the next F lists"` (Review Focus 4)
  - `"P teleport lands at the known spell's destination"`
  - `"b with no dock nearby is arrival-unknown"`
- [ ] **Step 2: Run** `~/.luarocks/bin/busted spec/driver/actions_other_spec.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** it again. Expected: PASS.
- [ ] **Step 5: Commit** `feat: Land boat and portal steps at real arrival points`

### Task 8: `h`, `H` and `R`

**Files:**
- Modify: `src/hwc/driver/actions.lua` (`perform_bind`, `perform_travel`), `src/hwc/world/player.lua` (`set_bind(entry)`)
- Test: `spec/driver/actions_other_spec.lua:87-118`, `spec/world/player_spec.lua:57-61`

**Interfaces:**
- Produces:
  - `Player:set_bind(entry)` stores `{ name = entry.bind, map_id = entry.map_id, entry = entry }`. `GetBindLocation` still returns `bind.name`.
  - Gaps: `inn-unknown`, `subzone-unknown`, `waypoint-arrival-not-emulated`.
  - `R` sets `out.arrived` and `out.classify`.

Rules (spec §7):
- **`h`:** the inn entry nearest the departure (by its `x`/`y`, within `RADIUS`). `set_bind`, then fire `HEARTHSTONE_BOUND`. With no entry: `inn-unknown`.
- **`H`:** land at `p.bind.entry`. With no entry: `inn-unknown`, and the player stays.
- **`R`:**
  - Zone comes from `Z` via `DB:zone_of_map` when `Z` is numeric-only (otherwise the `Z` name); map and x/y as today.
  - The subzone is `""` on a zone or map change and kept otherwise.
  - `credit_arrival` is unchanged.
  - `data_gap`: `waypoint-arrival-not-emulated` when `tags.waypcomplete` is 1 or 2; otherwise none (the driver uses `out.classify`).

- [ ] **Step 1: Write the failing specs:**
  - `"h binds at the nearest inn: GetBindLocation is the captured bind, not the step name"`
  - `"H lands at the bound inn"`
  - `"H with no inn entry is inn-unknown"`
  - `"R no longer sets the subzone to the step name"`
  - `"R with CC carries waypoint-arrival-not-emulated"`
  - `"R named after a non-area classifies name-not-an-area"`
- [ ] **Step 2: Run** `~/.luarocks/bin/busted spec/driver/actions_other_spec.lua spec/world/player_spec.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** it again. Expected: PASS.
- [ ] **Step 5: Commit** `feat: Bind and hearth at real inns; stop faking run-to subzones`

### Task 9: Driver signals

**Files:**
- Modify: `src/hwc/driver/run.lua`: gap handling next to `refusals` (`:527-563`); did-not-advance fields (`:773-792`); run start (`start-node-unknown`, `arrival_problems`)
- Test: `spec/driver/run_spec.lua`; a `#slow` spec in the existing full-run spec file

**Interfaces:**
- Consumes: the outcome fields from Tasks 6-8; `catalog:arrival_problems()`.
- Produces:
  - When a step didn't advance, the first rule that applies decides:
    1. `out.data_gap` gives `arrival-data-gap { reason, key }`;
    2. else `out.classify == "subzone-unknown"` gives `arrival-data-gap { "subzone-unknown", "<gid>:<line>" }`;
    3. else `did-not-advance`, with reason `out.reason`, or `"name-not-an-area"` when `out.classify` says so, or `"arrival-mismatch"` when `out.arrived` is set. It carries `expected`, `arrived` and `resolved_by`.
  - Gap signals set `out.explained`.
  - At run start, once each: `start-node-unknown` (when the tables exist but don't know the race's start node), and each `arrival_problems()` row as `arrival-data-mismatch`.

- [ ] **Step 1: Write the failing specs** (scripted engine):
  - `"a stalled arrival with a data gap records arrival-data-gap, not did-not-advance"`
  - `"a stalled F named Stormwind records did-not-advance name-not-an-area with expected and arrived"`
  - `"a stalled F named after a real area records arrival-mismatch"`
  - `"subzone-unknown is a notice"`
  - `"an advanced step records nothing"`
  - `"arrival_problems rows become arrival-data-mismatch once"`
  - `#slow`: `"a Dwarf Warrior run with no Forever tables has no did-not-advance on F/f/b/P/H/h steps"` (Review Focus 1)
- [ ] **Step 2: Run** `~/.luarocks/bin/busted spec/driver/run_spec.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `~/.luarocks/bin/busted` and `~/.luarocks/bin/busted --tags=slow`. Expected: PASS. Update any older spec that asserted the step-name landing to use the fixtures.
- [ ] **Step 5: Commit** `feat: Report arrival data gaps as harness notices`

### Task 10: Findings, text and report page

**Files:**
- Modify:
  - `src/hwc/findings/group.lua`:
    - SEVERITY: `["arrival-data-gap"] = "low"`;
    - `key_of`: `{"arrival-data-gap", reason, key}`;
    - `new_finding`: copy `expected, arrived, resolved_by, detail`; a gap's `name` is `reason .. ": " .. key`.
  - `src/hwc/findings/report.lua:34-36`: `is_harness` includes `arrival-data-gap`.
  - `src/hwc/findings/text.lua`: the label, the did-not-advance explanations and the gap sentences.
  - `web/report/src/types.ts`: the new fields.
  - `web/report/src/logic/state.ts:41`: `isHarness`.
  - `tools/report-fixtures.lua`.
  - The bundled `src/hwc/findings/report.html`: rebuild with `npm run build` in `web/report`.
- Test: `spec/findings/group_spec.lua`, `spec/findings/text_spec.lua`, `spec/findings/report_spec.lua`, `web/report/test/logic/state.test.ts`

Exact copy:
- `name-not-an-area`: `quoted(name) .. (tz and (" and TZ " .. quoted(tz)) or "") .. " name no area in Forever, so the addon can never complete this step by zone; the client clicked it off."`
- `arrival-mismatch`: `"The step names " .. quoted(name) .. (tz and (" (TZ " .. quoted(tz) .. ")") or "") .. ", but the player arrived in " .. zone .. (subzone ~= "" and (" / " .. subzone) or "") .. ", so the addon didn't complete it and the client clicked it off."`
- `flight-point-undiscovered`: `"The guide flies to a flight point the character hasn't discovered, so the client travelled there another way."`
- `no-taxi-node`: `"No flight point on the taxi map matches " .. quoted(name) .. ", so the client travelled there another way."`
- `tables-missing`: `"The Forever client tables aren't installed, so arrival steps aren't judged. Run hwc update."`
- The other gap reasons: `"hwc has no arrival data for this: "` plus one clause per reason, worded by the builder.

- [ ] **Step 1: Write the failing specs:**
  - group: one finding per (reason, key) across combos; severity low; `report.counted` is false.
  - text: each sentence above, exactly.
  - `state.test.ts`: `isHarness({ signal: "arrival-data-gap" })` is true.
- [ ] **Step 2: Run** `~/.luarocks/bin/busted spec/findings` and `cd web/report && npm test`. Expected: FAIL.
- [ ] **Step 3: Implement, then rebuild the report bundle.**
- [ ] **Step 4: Run** `~/.luarocks/bin/busted` and `cd web/report && npm test && npm run typecheck`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: Explain arrival findings and fold arrival data gaps with harness notices`

### Task 11: In-game capture scripts

**Files:**
- Create: `src/hwc/cli/arrivals.lua`
- Modify: `src/hwc/cli/commands.lua`, `src/hwc/cli/help.lua`, `README.md` ("Arrival facts": what to capture and where it goes in `src/hwc/world/arrivals.lua`)
- Test: `spec/cli/commands_spec.lua`, `spec/cli/help_spec.lua`

**Interfaces:**
- Produces `hwc arrivals capture-script [taxi|landing|bind]`, printing one `/run` line:
  - `taxi`: `i`, `TaxiNodeName(i)` and `TaxiNodeGetType(i)` in slot order;
  - `landing`: `GetZoneText()`, `GetSubZoneText()`, `C_Map.GetBestMapForUnit("player")` and the map position as percent;
  - `bind`: `GetBindLocation()`.

  Each line is at most 255 characters and starts with `/run `.

- [ ] **Step 1: Write the failing specs:** each mode's output; the length limit; the help text lists the command.
- [ ] **Step 2: Run** `~/.luarocks/bin/busted spec/cli`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `~/.luarocks/bin/busted` and `~/.luarocks/bin/busted --tags=slow`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: Print in-game capture scripts for arrival facts`
