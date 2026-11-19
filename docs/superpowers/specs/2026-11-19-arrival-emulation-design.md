# Arrival emulation: real landing data for F, f, b, P, H, h and R steps

Status: draft for review · 2026-11-19

## Why

In game, `F` (fly), `b` (boat), `P` (portal/teleport) and `R` (run to) steps complete in
`WoWPro.AutoCompleteZone` (`WoWPro/WoWPro_AutoComplete.lua:488-530`), and only when, on
arrival, one of these holds:

- the step name equals `GetZoneText()` or `GetSubZoneText()`;
- the first `;` part of the `TZ` tag equals one of them;
- a numeric `TZ` equals the map id.

`R` steps also complete on TomTom waypoint arrival when they carry `CC` or `CS`
(`WoWPro_Mapping.lua:133-158`).

hwc sets the arrival subzone to the step's own name (`src/hwc/driver/actions.lua`
`perform_arrival` :496-504 for F/b/P, `perform_travel` :624 for R), so the name test always
passes. That hides real guide bugs. The user saw `F` steps stay up in game (2026-11-18).
In the Forever guides, 13 `F Stormwind` steps have no `TZ`, and the arrival zone is
"Stormwind City". Other suspects: `Crossroads` (5), `Grom'gol` (5), `Theramore` (4),
`Feathermoon` (3), `Undercity` (14), `Gadgetzem`, `Rut'Theran Village`. The guide's own
history agrees: commit `a3df10408` "Human run through part 1" added `TZ|Stormwind City`
to the steps its author played. A Human Warrior hwc run advanced `19_25_Alliance.lua:137`
and `:255` (bare `F Stormwind`) with no finding.

The same masking applies to `f` (get a flight point). hwc's taxi stub names the nodes
after the guide's `f` step names (`src/hwc/stubs/core.lua:240-256`,
`Player:learn_flight_point(step.name)`).

## Goals

- Arrival steps run on accurate world data. The addon's own checks, fed real inputs,
  decide whether a step advances.
- If a step doesn't advance, the run records a guide finding (`did-not-advance`) with the
  reason: what the step expected and where the player actually arrived.
- If hwc has no accurate data for an arrival, the report says so as a harness notice.
  The step never passes on the guide's word.

## Non-goals

- Correcting guides. hwc reports; it never rewrites or second-guesses a step.
- Real subzone data for arbitrary `R` coordinates. That is a follow-up design (see
  "Phase 2").
- Flight times, en-route zone changes, multi-hop routing costs.
- Vendor buys (`B Rhapsody Malt`). That is a separate investigation, waiting on the
  in-game `GetItemCount(2894)` evidence.

## Anti-goals

- Any code path that takes landing values (zone, subzone, map id, bind text) from the
  step being judged: its name, its `TZ`, or its note. That is the bug this design
  removes. The step may name *which* real arrival point it means (§4, §10); the values
  always come from the data file.
- Defaulting an unknown arrival to "advanced". Unknown means a harness notice, never a
  pass.
- Committing third-party data. The README's data policy applies: the arrival file is
  local, like the counts file.

## Approaches considered

1. **An arrival-point data file checked in game, cross-checked by QuestieDB (chosen).**
   One local file lists every arrival point: taxi nodes, boat/zeppelin docks, portal
   exits and teleport destinations. For each it gives the zone, subzone and map id read
   in game. QuestieDB flight masters (`npcFlags` bit 8, with zone and spawn) cross-check
   each taxi node's zone and supply the departure flight master's position. Accurate for
   Forever. It costs one in-game capture per point.
2. **QuestieDB only.** The zone comes from the flight master's `zoneID`; the subzone is
   unknown. Most `F` steps name a subzone (`Thelsamar`, `Auberdine`), so most can't be
   judged. Rejected as the main source; kept as the cross-check.
3. **Client DB2 tables (TaxiNodes/AreaTable).** A new external source; the Forever build
   may not be published; the subzone at a coordinate still needs area polygons. Rejected.

The user chose 1, split into phases: F/b/P/f now with the data file; R now as
"stop faking, emulate what's real, flag the rest"; real R subzones later.

## Design

### 1. Arrival data file

- Config key `arrivals`, default `local/catalog/arrivals.json`, resolved like `counts`
  (`src/hwc/config.lua:35-40`). Optional and not committed. Commit a structure-only
  `catalog/arrivals.example.json`.
- Entry shape (one per arrival point):

  ```json
  {
    "kind": "taxi",                 // taxi | boat | portal | teleport
    "name": "Thelsamar, Loch Modan",// taxi: TaxiNodeName exactly as the client shows it
    "npc": 1572,                    // taxi: flight master NPC id (QuestieDB)
    "continent": 1415,              // taxi: so the taxi map lists only same-continent nodes
    "zone": "Loch Modan",           // GetZoneText() on arrival
    "subzone": "Thelsamar",         // GetSubZoneText() on arrival ("" allowed)
    "map_id": 1432,                 // C_Map.GetBestMapForUnit on arrival
    "x": 33.94, "y": 50.95,         // arrival position, percent
    "checked": "in game 2026-11-20" // how it was checked, as the counts file does
  }
  ```

  Boat and portal entries add `"from": { "map_id": ..., "x": ..., "y": ... }`, the
  departure dock or portal. Teleport entries add `"spell": <spellID>`.
- Loader validation, with the counts file's error style: each entry needs a kind, zone,
  map id and `checked`; taxi entries need a name and npc. A taxi entry whose `npc` has
  QuestieDB data with a different zone id than `map_id`'s zone gets a load-time note.
  That makes it a harness notice, never a silent fix.
- A capture helper. `hwc arrivals capture-script` prints a `/run` line for the user to
  paste in game. At a flight master it dumps every `TaxiNodeName` with its type; after a
  landing, boat or portal it dumps zone, subzone, map id and position. Exact text is the
  builder's.

### 2. `f`: learning a flight point

- The departure position is the step's `M`/`Z`, which `walk_to_step` already applies.
  The flight master is the QuestieDB NPC with the flight-master flag nearest that
  position in that map. The node is the arrival entry with that `npc`.
- Found: learn the node by its real name. Fire `TAXIMAP_OPENED` (talking to a flight
  master opens the map; `RecordTaxiLocations` runs). If the node is new, also fire
  `UI_INFO_MESSAGE(ERR_NEWTAXIPATH)`. If it is already known, fire no discovery message,
  as in game. Whether the step advances is then the addon's call.
- Not found (no flight master near the step, or no arrival entry for it): learn nothing.
  The outcome carries a harness reason (see 6). It is not a `did-not-advance`.

### 3. `F`: flying

The taxi stub stops reading `player.flight_points` names. It lists the arrival file's
taxi nodes on the player's current continent, sorted by name. `TaxiNodeGetType` is
`REACHABLE` for nodes the player has learned and `NONE` for the rest; `GetNumRoutes` and
`TaxiGetNodeSlot` stay as now. `TakeTaxiNode(i)` records the chosen node in
`sb.taxi_taken`; it starts a flight only for a learned node.

Sequence for an `F` step (the player is already at the departure through `walk_to_step`):

1. Fire `TAXIMAP_OPENED`. With AutoSelect (default true) the addon's own
   `TakeTaxiClassic(step name)` picks a node by `location:find(step name)` and calls
   `TakeTaxiNode`. hwc chooses nothing itself.
2. If no `TakeTaxiNode` call was recorded, or the node isn't learned, the addon's pick
   failed. The step falls to the existing did-not-advance path with reason
   `no-taxi-node` or `flight-point-undiscovered`, and the player still reaches the
   destination by §10.
3. Otherwise run the flight. Set `UnitOnTaxi` true (a player flag; the stub reads it)
   and fire `PLAYER_CONTROL_LOST`. Settle the clock past `QuestEngineDelay` so
   `PLAYER_CONTROL_LOST_PUNTED` records `TaxiPendingStep`. Set the player to the node's
   arrival zone, subzone, map id and position. Set `UnitOnTaxi` false. Fire
   `ZONE_CHANGED_NEW_AREA`, `ZONE_CHANGED` and `PLAYER_CONTROL_GAINED`, then settle.
   `AutoCompleteZone` decides.
4. If the step didn't advance, the did-not-advance signal carries `expected` (the step
   name and TZ) and `arrived` (the zone, subzone and map id), so the report can say
   "named 'Stormwind'; landed in Stormwind City / Trade District".

### 4. `b` and `P`: boats, portals, teleports

- Candidates:
  - `b` and portal `P`: the arrival entries whose `from` is nearest the step's departure
    `M`/`Z` (within a radius the builder picks).
  - Teleport `P`: the teleport entries for spells the player knows, plus the step's
    `SPELL` tag if it has one.
- One candidate: arrive there.
- Several candidates (e.g. Menethil's two boats): pick the one whose zone, subzone or
  numeric map id equals the step name or `TZ`. This is the only use of the step's text.
  It chooses between real routes, as a player reading the step would; it never sets the
  landing. If none matches exactly, the reason is `ambiguous-route` (a guide finding:
  the step names none of the places this dock goes), and §10 decides where the player
  ends up.
- No candidate: harness reason `arrival-unknown`.
- Arrival: set the player to the entry's location and fire `ZONE_CHANGED_NEW_AREA` and
  `ZONE_CHANGED`. Then the addon decides, as for `F`.

### 5. `R`: run to (phase 1)

- Stop setting the subzone to the step name. Moving to `Z`/`M` sets the zone and map id
  from the `Z` tag (real data). The subzone becomes "" when the zone or map changes, and
  is kept otherwise. This matches `walk_to_step`.
- `credit_arrival` (R steps with QO) is unchanged.
- If an `R` step didn't advance after the move, the run records a harness notice, not a
  `did-not-advance`, in two cases:
  - **`subzone-unknown`**: the step name or `TZ` might be a subzone (it matches neither
    the zone nor the map id), and hwc has no subzone data for that spot.
  - **`waypoint-arrival-not-emulated`**: the step has `CC` or `CS`, so in game TomTom's
    waypoint arrival would complete it. hwc doesn't emulate that yet (TomTom is
    unstubbed; see the "TomTom expected installed" follow-up).
  An `R` step whose name or numeric `TZ` matches the real zone or map id still advances
  through the addon's own check.

### 6. Findings and report

- Guide findings: the existing `did-not-advance`, with reasons `arrival-mismatch` (it
  traveled, but the addon didn't complete the step), `no-taxi-node`,
  `flight-point-undiscovered` and `ambiguous-route`, and the `expected`/`arrived` fields.
- Harness notices: one new signal, `arrival-data-gap`, whose reason is one of
  `arrival-unknown`, `fp-unknown`, `subzone-unknown`, `waypoint-arrival-not-emulated`
  or `arrival-data-mismatch` (the QuestieDB cross-check). `report.is_harness` treats it
  as harness, so it sits in the harness fold, out of every count. It groups one root
  cause per reason and data key (e.g. per unknown node), so 300 R steps make a handful
  of rows.
- The driver marks these outcomes `explained`, so they don't also produce a
  `did-not-advance` (run.lua:785).
- The text and HTML reports show `expected` and `arrived` on arrival findings.

### 7. Missing or partial data (builder check, settled by the goals)

The file is optional and often partial (CI, fresh checkouts). A data gap must never
become a guide finding:

- Each continent in the file carries `"complete": true | false`. `no-taxi-node` and
  `flight-point-undiscovered` are guide findings only when the departure continent is
  marked complete. Otherwise they become `arrival-data-gap` notices
  (`taxi-map-incomplete`).
- If the guide's own `f` step for a node got `fp-unknown`, a later `F` to that node that
  fails as `flight-point-undiscovered` is a notice, not a guide finding.
- With no file at all, every `F`/`b`/`P`/`f` outcome is a notice and nothing is judged.
  Specs and e2e fixtures that expect F steps to advance get an arrivals fixture.
- The capture script records the taxi map exactly as the client shows it: every node,
  its `TaxiNodeGetType` and its slot order. The stub replays that order and those
  types. Whether Forever lists unlearned nodes is then whatever the capture shows, not a
  Classic assumption.

### 8. Departure position for F/b/P (fix to §3)

`walk_to_step` skips travel actions (`actions.lua:513-515`). For `F`/`b`/`P`, the
departure from the step's `Z`/`M` (Ruling Y) is applied first, with the same move rule
and events, before the departure-dependent work in §2-§4.

### 9. `h` and `H`: bind and hearth (user, 2026-11-19: in scope)

Same masking today: `perform_bind` stores the step's own text as the bind location
(`actions.lua:636-640`), `GetBindLocation` returns it (`stubs/core.lua:148`), and `H`
lands there (`actions.lua:612-616`).

- New arrival kind `inn`: the innkeeper NPC id, `bind` (what `GetBindLocation()`
  returns after binding there, read in game) and the hearth landing (zone, subzone,
  map id, position).
- `h`: the innkeeper is the QuestieDB innkeeper (npcFlags innkeeper bit) nearest the
  step's `Z`/`M`. The bind becomes that inn entry. Fire `HEARTHSTONE_BOUND`; the addon's
  `AutoCompleteSetHearth` compares the step name to the real `GetBindLocation()`.
- `H`: land at the bound inn's location, fire the zone events, and let
  `AutoCompleteZone` decide.
- No inn entry: `arrival-data-gap` (`inn-unknown`). For `H`, the player then goes to
  the next step's place (§10).
- A new character's starting bind: from the file, per race (`start_bind`), captured in
  game.

### 10. Where the player is after a trip that didn't complete (user, 2026-11-19)

The player ends up at the destination, whatever the step calls it, because that's what
a real player does. Not advancing is a finding about the step, not a reason to strand
the player.

- The landing values (zone, subzone, map id, position) always come from an arrival
  entry, never from the step. The step may only *identify which* real arrival point it
  means. When the addon's own pick fails (`no-taxi-node`, `ambiguous-route`,
  `flight-point-undiscovered`), hwc resolves the destination with a looser match against
  the arrival entries' node names, zones and subzones: case-insensitive, prefix or
  substring, on the step name, then `TZ`. It lands there, records `resolved_by` on the
  finding, and the step is clicked off as today.
- If the looser match finds nothing, or finds several, hwc can't know where the player
  went. It records `arrival-data-gap` (`destination-unresolved`), leaves the player in
  place, and the next step's `Z`/`M` moves them.
- An undiscovered node can't be flown to (user, 2026-11-19), so no flight is emulated:
  no taxi events, no `UnitOnTaxi`, and `TakeTaxiNode` on an unlearned node does
  nothing. Reaching that state means the guide sends the player to a flight point it
  never had them discover (a guide finding, `flight-point-undiscovered`). That holds
  only while hwc's knowledge is complete: the start node is known (§11), no earlier `f`
  hit `fp-unknown`, and the continent is complete (§7). Otherwise it is an
  `arrival-data-gap` notice. In both cases the player still gets there by the shortest
  route, which may include flights between nodes they have learned (user, 2026-11-19).
  hwc has no taxi route graph and no world coordinates (the HBD stub's distances are
  constant), so it can't work out that route. Phase 1 emulates only the end point: the
  arrival's location with plain zone events, and the node stays unlearned. The finding
  records `route = "not-emulated"`. Emulating the route (which learned nodes, and the
  events of each leg) is deferred until hwc has a taxi graph and world coordinates.

### 11. Starting flight points (user, 2026-11-19)

Characters start with their capital's flight node learned. The file lists it per race
(`start_nodes: { Human: "Stormwind, Elwynn", ... }`), with the exact node names from
the capture. A new `Player` learns it at creation. A race missing from `start_nodes`
gets an `arrival-data-gap` notice (`start-node-unknown`) once per run.

## Constraints

- Fidelity rule (actions.lua header): actions never write engine state. They change the
  world and fire events only.
- Every event sequence cites the addon line it mirrors, as the existing code does.
- Forever is not Classic: no Classic zone or subzone value enters the data without an
  in-game check.

## Next plan: TomTom (decided 2026-11-19)

WoW-Pro assumes TomTom is installed. The next plan, right after this one, mocks the
TomTom API calls WoW-Pro makes, so `CC`/`CS` waypoint arrival runs through the addon's
own `WoWPro_Mapping.lua` path. That retires `waypoint-arrival-not-emulated`, which
covers the 347 Forever `R` steps with `CC`/`CS`. Until then they stay a known harness
gap.

## Phase 2 (separate design, later)

Real subzone data for `R` arrivals at arbitrary coordinates. That retires
`subzone-unknown`.

## Left to the builder

- The candidate radius for docks and portals; the capture `/run` text; where the
  arrival loader lives (next to the counts loader in `src/hwc/catalog/`).
- Event order details beyond those fixed above, each cited to the addon line it follows.
- Spec fixtures: a small arrivals fixture covering a matching node, a mismatching bare
  `F Stormwind`, an unlearned node, a two-boat dock and an unknown node.
