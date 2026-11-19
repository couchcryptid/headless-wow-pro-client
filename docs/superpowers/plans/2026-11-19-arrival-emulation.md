# Arrival Emulation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Travel steps (`F f b P H h R`) run on real arrival data, never on the step's own
text. A step that doesn't advance in the addon's own checks becomes a guide finding. A gap
in hwc's data becomes a harness notice.

**Architecture:**
- **Data:** a local, optional arrivals file (`local/catalog/arrivals.json`), loaded by
  `hwc.catalog.arrivals` and hung on the catalog as `catalog.arrivals`.
- **Matching:** a pure helper module, `hwc.driver.arrival`, does the matching (nearest
  departure, exact route choice, loose destination resolution).
- **Actions and stubs:** `hwc.driver.actions` performs each step with world changes and
  addon events only. The taxi stubs replay the captured taxi map.
- **Driver and report:** the driver turns `out.data_gap` into a harness signal,
  `arrival-data-gap`, and the findings and report layers treat that signal as harness.

**Tech Stack:** LuaJIT 2.1, busted 2.3, dkjson, luafilesystem; the report page is
TypeScript (web/report, vitest).

**Spec:** `docs/superpowers/specs/2026-11-19-arrival-emulation-design.md` (read it first;
section numbers below are its §).

## Global Constraints

- Landing values (zone, subzone, map id, bind text) never come from the step being
  judged. The step may only pick *which* real arrival entry it means (spec §4, §10).
- Unknown data is never a pass: it becomes `arrival-data-gap`, never `did-not-advance`,
  and it is never silent.
- Actions never write engine state. They change the world and fire events. Every event
  sequence carries a comment citing the addon line it mirrors (`~/Projects/WoW-Pro-Guides`).
- No third-party data is committed. Only `catalog/arrivals.example.json`, which holds
  structure only, goes in the repo.
- Forever is not Classic. No Classic zone/subzone value goes into fixtures as fact.
  Fixture values are labelled test data.
- Each PR lands one or more Conventional Commit subjects. Only `feat`/`fix` release.
- Run specs: `~/.luarocks/bin/busted` (default suite) and `~/.luarocks/bin/busted --tags=slow`
  before the last task's commit; `npm test` and `npm run typecheck` in `web/report` for
  Task 8.

## Plan decisions (where the spec left a choice)

- **Coordinates:** file `x`/`y` are percent, converted to fractions at load, as
  `parse_coords` does. `arrival.RADIUS = 0.05` (fraction of the map) for nearest
  departure.
- **Continents:** the file maps continents to their map ids and records whether the
  client lists unlearned nodes (`lists_unlearned`), as the capture showed.
- **`fp-unknown` downgrade:** after any `fp-unknown` on a continent, a later
  `flight-point-undiscovered` on that continent is a notice. The unknown node can't be
  identified, so the downgrade is per continent.
- **When a gap becomes a signal:** `out.data_gap` turns into a signal only when the step
  didn't advance, and then it replaces `did-not-advance`. The exception is
  `start-node-unknown`, which the driver emits once at run start with no step.
- **`arrival-mismatch`:** the driver sets it as the did-not-advance reason when the
  action traveled (`out.arrived`) and gave no other reason.
- **Settles:** `actions.perform` may settle twice for `F` (once after
  `PLAYER_CONTROL_LOST`, once at the end). `out.settle` keeps the last result, with
  `hit_limit` OR-ed across both.

## Review Focus

1. **No arrivals file at all** (fresh checkout, CI). Every travel step runs, none
   crashes, none gives `did-not-advance`, and the harness fold shows one
   `arrival-data-gap` group per reason. Test it in Task 7.
2. **A file that's present but partial** (continent `complete: false`). An `F` whose node
   is missing gives `taxi-map-incomplete`, not `no-taxi-node`. Test it in Task 4.
3. **A step name that loosely matches two entries** (e.g. `Stormwind` against
   "Stormwind, Elwynn" and an inn bound to "Stormwind City"). The loose resolver only
   looks within one kind, so this resolves to the single taxi entry. Two taxi hits give
   `destination-unresolved`. Test it in Task 2.
4. **A boat leaving a dock to another continent** (Menethil to Theramore). The player's
   continent follows the landing's map id, so the next `F` lists that continent's nodes.
   Test it in Task 5.
5. **A malformed entry** (missing `checked`, or a taxi entry without `npc`). The load
   fails with the path and the entry index, like the counts file. Test it in Task 1.

---

### Task 1: Arrivals file: loader, config, example, doctor

**Files:**
- Create: `src/hwc/catalog/arrivals.lua`, `catalog/arrivals.example.json`, `spec/catalog/arrivals_spec.lua`, `spec/fixtures/catalog/arrivals.json`
- Modify: `src/hwc/config.lua:35-41` (`arrivals` key), `src/hwc/catalog/init.lua:113-131` (`self.arrivals`), `src/hwc/doctor.lua:182-206` (add `check_arrivals` beside `check_counts`), `README.md` ("World and catalog": an "Arrival points" subsection; config table row)

**Interfaces:**
- Produces:
  - `Arrivals.entry_problem(entry) -> string|nil`
  - `Arrivals.from_table(obj) -> Arrivals`
  - `Arrivals.load(path) -> Arrivals`. A missing file gives an empty object with `present = false`. Invalid JSON or an invalid entry raises `"hwc: arrivals: <path>: point <i> <problem>"`.
  - Fields: `a.present: boolean`, `a.path`, `a.sha256`.
  - `a:continent_of(map_id) -> continent_id|nil`
  - `a:continent(id) -> { complete: boolean, lists_unlearned: boolean, taxi_order: {string} }|nil`
  - `a:points(kind) -> {entry}` (file order)
  - `a:taxi(name) -> entry|nil`
  - `a:by_npc(kind, npc_id) -> entry|nil`
  - `a:start_node(race_key) -> string|nil`
  - `a:start_bind(race_key) -> entry|nil`
  - Entry fields after load: `kind, name, npc, continent, zone, subzone, map_id, x, y, checked, from = {map_id,x,y}|nil, spell, bind`, with `x`/`y` as fractions.
  - `Catalog.load` sets `self.arrivals` (from `c.arrivals`, or `c.arrivals_table` for specs) and `self.sources.arrivals = { path, present, sha256 }`.
  - `config.load({}).catalog.arrivals` defaults to `<repo>/local/catalog/arrivals.json`.

File shape (copy into `catalog/arrivals.example.json` with placeholder values and
`"checked": "how this was checked (e.g. in game, 2026-11-20)"`):

```json
{
  "continents": { "1415": { "complete": false, "lists_unlearned": true,
                            "maps": [1426, 1432, 1453, 1455], "taxi_order": ["Ironforge, Dun Morogh"] } },
  "start_nodes": { "Dwarf": "Ironforge, Dun Morogh" },
  "start_bind": { "Dwarf": { "bind": "...", "zone": "...", "subzone": "...", "map_id": 1426, "x": 0, "y": 0, "checked": "..." } },
  "points": [ { "kind": "taxi", "name": "...", "npc": 1573, "continent": 1415, "zone": "...", "subzone": "...",
                "map_id": 1455, "x": 55.5, "y": 47.74, "checked": "..." } ]
}
```

- [ ] **Step 1: Write the failing specs** in `spec/catalog/arrivals_spec.lua`:
  - `it("loads the fixture and converts percent to fractions")`: `a:taxi(<fixture name>).x == 0.555`; `a:continent_of(1455) == 1415`.
  - `it("a missing file is empty and not present")`: `Arrivals.load("nope.json").present == false`; `a:points("taxi")` is `{}`.
  - `it("rejects a point without checked, naming path and index")`: error matches `"hwc: arrivals: .*: point 1 needs checked"`.
  - `it("rejects a taxi point without npc or name")`, `it("rejects an unknown kind")`, `it("rejects a boat or portal without from")`, `it("rejects a teleport without spell")`, `it("rejects an inn without npc or bind")`.
  - `it("start_node and start_bind read per race key")`.
  - In `spec/config_spec.lua`: the default `catalog.arrivals` ends in `local/catalog/arrivals.json`.
  - In `spec/doctor_spec.lua`: absent gives `warn` "absent (optional; arrival steps are not judged)", invalid gives `fail`, valid gives `ok`.
- [ ] **Step 2: Run** `~/.luarocks/bin/busted spec/catalog/arrivals_spec.lua spec/config_spec.lua spec/doctor_spec.lua`. Expected: FAIL (module not found).
- [ ] **Step 3: Implement** the module, config key, catalog hook, doctor check and README section, mirroring `load_counts` / `check_counts`. The fixture `spec/fixtures/catalog/arrivals.json` carries the nodes the later tasks name:
  - "Ironforge, Dun Morogh" (npc 1573, map 1455) and "Thelsamar, Loch Modan" (npc 1572, map 1432), both on continent 1415;
  - "Stormwind, Elwynn" (npc 352, map 1453, zone "Stormwind City", subzone "Trade District");
  - two boats from one dock, an inn (Kharanos) and a teleport;
  - `start_nodes.Dwarf`.
  The top of the file says the values are test data.
- [ ] **Step 4: Run** the same command. Expected: PASS.
- [ ] **Step 5: Commit** `feat: Load an optional arrival-points file for travel steps`

### Task 2: Matching helpers (pure)

**Files:**
- Create: `src/hwc/driver/arrival.lua`, `spec/driver/arrival_spec.lua`

**Interfaces:**
- Consumes: Task 1 entry fields.
- Produces:
  - `arrival.RADIUS = 0.05`
  - `arrival.nearest(entries, map_id, x, y, pos_of) -> entry|nil`. `pos_of(entry) -> map_id, x, y | nil`. Only entries on the same map and within `RADIUS` count; the closest wins and a tie goes to the earlier entry.
  - `arrival.exact(entry, text) -> boolean`. True when `text` equals `entry.zone` or `entry.subzone`, or `tonumber(text) == entry.map_id`. This mirrors `AutoCompleteZone` (`WoWPro_AutoComplete.lua:515-526`).
  - `arrival.loose(entries, name, tz) -> entry|nil, why`, where `why` is `"none"` or `"ambiguous"`.
  - `arrival.location(entry) -> string`. For a taxi node, this is the name before the first `,`.

`loose` algorithm (the spec leaves its exact form open):

```
for each probe in { name, first ";" part of tz } (skip nil/""):
  p = lower(trim(probe))
  hits = entries where any of lower(location(e)), lower(e.zone), lower(e.subzone)
         equals p, or starts with p, or contains p (in that order of preference:
         take the highest tier that has any hit)
  if #hits == 1 return hits[1]; if #hits > 1 return nil, "ambiguous"
return nil, "none"
```

- [ ] **Step 1: Write the failing specs:**
  - `nearest` picks the closer of two points on the same map, ignores other maps and anything beyond `RADIUS`.
  - `exact("Stormwind City")` is true for zone "Stormwind City", false for "Stormwind", and true for `"1453"` against map 1453.
  - `loose(taxi, "Stormwind")` returns "Stormwind, Elwynn".
  - `loose(taxi, "Gadgetzem")` returns `nil, "none"`.
  - `loose` with two taxi entries containing "port" returns `nil, "ambiguous"`.
  - `loose(taxi, "x", "Stormwind City")` falls back to the TZ probe.
- [ ] **Step 2: Run** `~/.luarocks/bin/busted spec/driver/arrival_spec.lua`. Expected: FAIL.
- [ ] **Step 3: Implement** `src/hwc/driver/arrival.lua`.
- [ ] **Step 4: Run** it again. Expected: PASS.
- [ ] **Step 5: Commit** `feat: Add arrival matching helpers`

### Task 3: QuestieDB cross-check and NPC positions

**Files:**
- Modify: `src/hwc/questie/source.lua` (add `Source:ui_map_of_area`), `src/hwc/catalog/init.lua` (add `Catalog:npc_position`, `Catalog:arrival_problems`), `spec/fixtures/catalog/questie_source.lua` (add the fixture flight masters/innkeeper and an area map)
- Test: `spec/catalog/catalog_spec.lua`

**Interfaces:**
- Produces:
  - `Source:ui_map_of_area(area_id) -> uiMapID|nil`. Reads `QuestieLoader:ImportModule("ZoneDB").private.areaIdToUiMapId` from `self.sandbox`: a Lua source string, run with an empty env and cached, as `drop_table` does. The `...Override` string wins over the base table.
  - `Catalog:npc_position(npc_id) -> map_id, x, y | nil`. Uses the first spawn: area id converted to a uiMapID, percent converted to fractions.
  - `Catalog:arrival_problems() -> { { key = string, detail = string } }`. For each `taxi`/`inn` entry with QuestieDB data, it flags:
    - a missing flag (taxi needs bit 8, inn needs bit 128 in `npcFlags`);
    - a QuestieDB position map id that differs from the entry's `map_id`. Taxi entries are compared on `map_id` too, since the flight master stands where the player lands.
  - `key` is `"<kind>:<name or npc>"`.

- [ ] **Step 1: Write the failing specs:**
  - `npc_position(1572)` returns `1432, 0.3394, 0.5095` from the fixture (area 38 maps to 1432).
  - `arrival_problems()` is empty for a consistent fixture.
  - It reports `taxi:Thelsamar, Loch Modan` when the fixture's map id is changed to 1426.
  - It reports a missing flight-master flag.
  - Without QuestieDB, `npc_position` is nil and `arrival_problems()` is `{}`.
- [ ] **Step 2: Run** `~/.luarocks/bin/busted spec/catalog/catalog_spec.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** it again. Expected: PASS.
- [ ] **Step 5: Commit** `feat: Cross-check arrival points against QuestieDB flight masters and innkeepers`

### Task 4: Player state, start node, taxi stubs, `F` and `f`

**Files:**
- Modify: `src/hwc/world/player.lua:97-98,181-189`, `src/hwc/world/init.lua:11-29`, `src/hwc/stubs/core.lua:145-148,232-256`, `src/hwc/driver/actions.lua` (`perform_flight_point`, a new `perform_flight` replacing `F` in `OTHER_HANDLERS`, plus a `depart` helper), `src/hwc/driver/engine.lua:26-46` (add `"waypcomplete"` to `TAG_KEYS`; CC=1, CS=2, CN=0 per `WoWPro_Parser.lua:486-488`)
- Test: `spec/world/player_spec.lua`, `spec/stubs_spec.lua:205-218`, `spec/driver/actions_other_spec.lua` (replace the tests at :40-103 that assert the old step-name landing)

**Interfaces:**
- Consumes: Task 1 (`catalog.arrivals`), Task 2 (`nearest`, `exact`, `loose`), Task 3 (`npc_position`).
- Produces:
  - Player fields: `p.flight_points[node_name] = true`, `p.on_taxi: boolean`, `p.bind = { name, map_id, entry }`.
  - `Player:learn_flight_point(node_name)` (unchanged signature; it now takes real node names).
  - `Player:set_on_taxi(bool)`, recorded as `"taxi"`.
  - `World.new` learns `arrivals:start_node(race_key)` and binds `start_bind` before clearing `self.events`.
  - `world.fp_unknown[continent_id] = true`.
  - Outcome fields used later: `out.data_gap = { reason, key }`, `out.expected = { name, tz }`, `out.arrived = { zone, subzone, map_id }`, `out.resolved_by = "taxi"|"loose"`, `out.route = "not-emulated"|nil`.
  - Guide reasons: `out.reason ∈ { "no-taxi-node", "flight-point-undiscovered" }`.

Taxi stubs (spec §3, §7):
- The node list is `arrivals:continent(continent_of(p.map_id)).taxi_order`. With `lists_unlearned == false`, it is filtered to learned nodes.
- `TaxiNodeGetType` gives `"REACHABLE"` for a learned node and `"NONE"` otherwise.
- `UnitOnTaxi` returns `p.on_taxi`.
- `TakeTaxiNode(i)` appends the name to `sb.taxi_taken`.

`F` sequence:
1. `depart`: the same move rule as `walk_to_step`, for travel actions.
2. Fire `TAXIMAP_OPENED` and settle.
3. Read the new tail of `ctx.engine.sb.taxi_taken` (`Engine.new` keeps `sb`, `engine.lua:63`). In specs the fake engine gets an `sb = { taxi_taken = {} }`.
4. If a learned node was taken: `set_on_taxi(true)`, fire `PLAYER_CONTROL_LOST`, settle, `set_zone` to the node, `set_on_taxi(false)`, then fire `ZONE_CHANGED_NEW_AREA`, `ZONE_CHANGED` and `PLAYER_CONTROL_GAINED`. Cite `WoWPro_Events.lua:828-866` and `WoWPro_AutoComplete.lua:461-530`.
5. Otherwise, if a node was taken but isn't learned: reason `flight-point-undiscovered`. It becomes the gap `taxi-map-incomplete` when the continent isn't complete or `world.fp_unknown[continent]` is set.
6. Otherwise, with no node taken: reason `no-taxi-node`, or the gap `taxi-map-incomplete` when the continent isn't complete.
7. In cases 5 and 6, resolve the destination with `arrival.loose(points("taxi"), name, tz)`. On a hit, land there with zone events only, set `resolved_by = "loose"` and `route = "not-emulated"`, and learn nothing. On a miss, the gap is `destination-unresolved` and the player stays.
8. No file (`not arrivals.present`): the gap is `arrival-unknown` with key `"no-file"`. Don't fire `TAXIMAP_OPENED` at all.

`f` (spec §2):
1. `depart`.
2. Find the nearest taxi entry by `npc_position`, falling back to the entry's own `x`/`y`.
3. If found: learn its name, fire `TAXIMAP_OPENED`, and if the node is new, fire `UI_INFO_MESSAGE(0, ERR_NEWTAXIPATH)`.
4. If not found: gap `fp-unknown` with key `"<map_id>:<x>,<y>"`, and set `world.fp_unknown[continent] = true`.

- [ ] **Step 1: Write the failing specs** (fixture arrivals via `setup`; extend `spec/helpers/driver_fixtures.lua` to pass `arrivals_table`, plus a variant with no file):
  - `"a new Dwarf knows its start node"`
  - `"the taxi map lists the continent's captured order, NONE for unlearned"`
  - `"F Stormwind with a learned node flies: control lost, on taxi, lands in Stormwind City / Trade District, control gained"`. Assert the event order and `p.zone`/`p.subzone`, and that `p.subzone ~= "Stormwind"`.
  - `"F to a taken but unlearned node is flight-point-undiscovered and lands by ground with route not-emulated"`
  - `"F naming no node is no-taxi-node and lands at the loose match"`
  - `"F on an incomplete continent gives taxi-map-incomplete, not a guide reason"`
  - `"F with no arrivals file is an arrival-unknown gap and fires no taxi events"`
  - `"f learns the nearest flight master's real node name and fires the discovery once"`
  - `"f for a known node fires TAXIMAP_OPENED but no ERR_NEWTAXIPATH"`
  - `"f with no flight master nearby is fp-unknown and marks the continent"`

  The fake engine never calls `TakeTaxiNode`, so for `F` specs stub `E:fire` to append to `sb.taxi_taken` when `TAXIMAP_OPENED` fires. That emulates the addon's AutoSelect.
- [ ] **Step 2: Run** `~/.luarocks/bin/busted spec/world spec/stubs_spec.lua spec/driver/actions_other_spec.lua`. Expected: the new specs FAIL.
- [ ] **Step 3: Implement.** Update the `actions.lua` header and the comment at `:486-495` (Ruling Y) to describe real arrivals.
- [ ] **Step 4: Run** it again. Expected: PASS.
- [ ] **Step 5: Commit** `feat: Fly F steps on real taxi nodes and learn real flight points`

### Task 5: `b` and `P`

**Files:**
- Modify: `src/hwc/driver/actions.lua` (`perform_crossing` for `b`/`P` in `OTHER_HANDLERS`)
- Test: `spec/driver/actions_other_spec.lua`

**Interfaces:**
- Consumes: Tasks 1, 2 and 4 (`depart`, the outcome fields).
- Produces: guide reason `"ambiguous-route"`; gaps `arrival-unknown` and `destination-unresolved`.

Rules (spec §4, §10):
- **Candidates:**
  - `b`: boat entries whose `from` is within `RADIUS` of the departure.
  - `P`: portal entries the same way, plus teleport entries whose `spell` the player knows or that equals the step's `SPELL` id.
- **One candidate:** land there.
- **Several candidates:** take the one where `arrival.exact(e, name)` or `exact(e, tz)`. With none, the reason is `ambiguous-route` and `loose` decides the landing. With no loose hit either, the gap is `destination-unresolved`.
- **No candidate:** gap `arrival-unknown` with key `"<kind>:<map_id>:<x>,<y>"`.
- **Landing:** zone events only.

- [ ] **Step 1: Write the failing specs:**
  - `"b from a one-boat dock lands at the dock's real arrival"`
  - `"b from a two-boat dock picks the route the step names exactly"`
  - `"b naming neither route is ambiguous-route and lands by the loose match"`
  - `"b to another continent changes the continent the next F lists"` (Review Focus 4)
  - `"P teleport lands at the known spell's destination"`
  - `"b with no dock nearby is an arrival-unknown gap"`
- [ ] **Step 2: Run** `~/.luarocks/bin/busted spec/driver/actions_other_spec.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** it again. Expected: PASS.
- [ ] **Step 5: Commit** `feat: Land boat and portal steps at real arrival points`

### Task 6: `h`, `H` and `R`

**Files:**
- Modify: `src/hwc/driver/actions.lua` (`perform_bind`, `perform_travel`), `src/hwc/world/player.lua` (`set_bind(entry)`)
- Test: `spec/driver/actions_other_spec.lua:87-118`, `spec/world/player_spec.lua:57-61`

**Interfaces:**
- Consumes: Tasks 1-4.
- Produces:
  - `Player:set_bind(entry)`, which stores `{ name = entry.bind, map_id = entry.map_id, entry = entry }`. `GetBindLocation` keeps returning `bind.name`.
  - Gaps: `inn-unknown`, `subzone-unknown`, `waypoint-arrival-not-emulated`.

Rules:
- **`h` (spec §9):**
  1. Take the nearest inn entry by `npc_position`, falling back to the entry's `x`/`y`.
  2. Then `set_bind(entry)` and fire `HEARTHSTONE_BOUND`.
  3. With no inn: gap `inn-unknown`, and the bind is unchanged.
- **`H`:** land at `p.bind.entry`, firing zone events. With no `bind.entry`: gap `inn-unknown`, and the player stays.
- **`R` (spec §5):**
  - Zone, map id and x/y come from `Z`/`M` as now. The subzone is `""` when the zone or map changes, and kept otherwise.
  - `credit_arrival` is unchanged.
  - Set `out.data_gap`, which the driver uses only if the step didn't advance:
    - `waypoint-arrival-not-emulated` when `tags.waypcomplete` is 1 or 2;
    - otherwise `subzone-unknown`, when neither the name nor the TZ part is `exact` against the new zone or map id.
  - Key is `"<gid>:<line>"`.

- [ ] **Step 1: Write the failing specs:**
  - `"h binds at the nearest innkeeper: GetBindLocation is the captured bind text, not the step name"`
  - `"H lands at the bound inn's real location"`
  - `"H with no captured inn is inn-unknown"`
  - `"R no longer sets the subzone to the step name"`
  - `"R with CC carries waypoint-arrival-not-emulated"`
  - `"R named after its zone carries no gap"`
  - `"R named after a subzone carries subzone-unknown"`
- [ ] **Step 2: Run** `~/.luarocks/bin/busted spec/driver/actions_other_spec.lua spec/world/player_spec.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** it again. Expected: PASS.
- [ ] **Step 5: Commit** `feat: Bind and hearth at real inns; stop faking run-to subzones`

### Task 7: Driver signals

**Files:**
- Modify: `src/hwc/driver/run.lua:509-570` (gap handling next to `refusals`), `:773-792` (did-not-advance fields), run start (`start-node-unknown`, `arrival_problems`)
- Test: `spec/driver/run_spec.lua`, plus a `#slow` spec in the existing full-run spec file that runs a Dwarf Warrior with no arrivals file

**Interfaces:**
- Consumes: the outcome fields from Tasks 4-6; `catalog:arrival_problems()`.
- Produces signals:
  - `arrival-data-gap { reason, key, outcome }`. It is emitted when the step didn't advance and `out.data_gap` is set, and it sets `out.explained`. It is also emitted with no step:
    - once at start for `start-node-unknown` (key = race key) when the file is present;
    - once per `arrival_problems()` row as `arrival-data-mismatch` (key = row key, `detail`).
  - `did-not-advance` gains `expected`, `arrived`, `resolved_by` and `route`. Its reason is `out.reason` or, when `out.arrived` is set, `"arrival-mismatch"`.

- [ ] **Step 1: Write the failing specs** (scripted engine):
  - `"an arrival step that didn't advance with a data gap records arrival-data-gap, not did-not-advance"`
  - `"an F that traveled and didn't advance is did-not-advance arrival-mismatch with expected and arrived"`
  - `"an advanced step with a data gap records nothing"`
  - `"a race with no start node records start-node-unknown once"`
  - `"arrival_problems rows become arrival-data-mismatch signals"`
  - `#slow`: `"a Dwarf Warrior run with no arrivals file has no did-not-advance on F/f/b/P/H/h steps"` (Review Focus 1)
- [ ] **Step 2: Run** `~/.luarocks/bin/busted spec/driver/run_spec.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `~/.luarocks/bin/busted` and `~/.luarocks/bin/busted --tags=slow`. Expected: PASS. Fix any older spec that asserted the step-name landing so it uses the fixture arrivals.
- [ ] **Step 5: Commit** `feat: Report arrival data gaps as harness notices`

### Task 8: Findings, text and report page

**Files:**
- Modify:
  - `src/hwc/findings/group.lua`: SEVERITY `["arrival-data-gap"] = "low"`; `key_of` for the gap is `{"arrival-data-gap", reason, key}`; `new_finding` copies `expected, arrived, resolved_by, route, detail`, and `name = reason .. ": " .. key` for the gap.
  - `src/hwc/findings/report.lua:34-36`: `is_harness` includes `arrival-data-gap`.
  - `src/hwc/findings/text.lua`:
    - a label for `arrival-data-gap`;
    - did-not-advance explanations for `arrival-mismatch`, `no-taxi-node`, `flight-point-undiscovered` and `ambiguous-route`;
    - one sentence per gap reason.
  - `web/report/src/types.ts`: new fields.
  - `web/report/src/logic/state.ts:41`: `isHarness` mirrors Lua.
  - `tools/report-fixtures.lua`: a fixture case for each.
- Test: `spec/findings/group_spec.lua`, `spec/findings/text_spec.lua`, `spec/findings/report_spec.lua`, `web/report/test/logic/state.test.ts`

**Interfaces:**
- Consumes: Task 7 signals.

Exact copy:
- `arrival-mismatch`: `"The step names " .. quoted(name) .. (tz and (" (TZ " .. quoted(tz) .. ")") or "") .. ", but the player arrived in " .. zone .. (subzone ~= "" and (" / " .. subzone) or "") .. ", so the addon didn't complete it and the client clicked it off."`
- `flight-point-undiscovered`: `"The guide flies to a flight point the character hasn't discovered, so the client travelled there another way."`, plus `" The route there isn't emulated."` when `route == "not-emulated"`.
- `no-taxi-node`: `"No flight point on the taxi map matches " .. quoted(name) .. "."`
- `ambiguous-route`: `"This departure has several routes and the step names none of them exactly."`
- Gap reasons, as `"hwc has no arrival data for this: <reason-specific clause>"`. The clauses are the builder's, one per reason.

- [ ] **Step 1: Write the failing specs:**
  - group: one finding per (reason, key) across combos; severity low; `report.counted` is false.
  - text: each sentence above, exactly.
  - state.test.ts: `isHarness({signal: "arrival-data-gap"})` is true.
- [ ] **Step 2: Run** `~/.luarocks/bin/busted spec/findings` and `cd web/report && npm test`. Expected: FAIL.
- [ ] **Step 3: Implement**, then rebuild the bundled `src/hwc/findings/report.html` the way the package script does (`npm run build` in `web/report`).
- [ ] **Step 4: Run** `~/.luarocks/bin/busted`, `cd web/report && npm test && npm run typecheck`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: Explain arrival findings and fold arrival data gaps with harness notices`

### Task 9: In-game capture script

**Files:**
- Create: `src/hwc/cli/arrivals.lua`
- Modify: `src/hwc/cli/commands.lua`, `src/hwc/cli/help.lua`, `README.md` (the "Arrival points" section gets the capture steps)
- Test: `spec/cli/commands_spec.lua`, `spec/cli/help_spec.lua`

**Interfaces:**
- Produces: `hwc arrivals capture-script [taxi|landing|bind]`, which prints one `/run` line per mode:
  - `taxi`: prints `i`, `TaxiNodeName(i)` and `TaxiNodeGetType(i)` for every node, in slot order.
  - `landing`: prints `GetZoneText()`, `GetSubZoneText()`, `C_Map.GetBestMapForUnit("player")` and the player's map position as percent.
  - `bind`: prints `GetBindLocation()`.

  Every line must fit WoW's 255-character macro limit. The specs assert `#line <= 255` and that each line starts with `/run `.

- [ ] **Step 1: Write the failing specs** (output per mode, the length limit, help text lists the command).
- [ ] **Step 2: Run** `~/.luarocks/bin/busted spec/cli`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `~/.luarocks/bin/busted` and `~/.luarocks/bin/busted --tags=slow`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: Print in-game capture scripts for arrival points`
