# Arrival emulation: real landing data for F, f, b, P, H, h and R steps

Status: revised 2026-11-19 (Forever client tables via wago.tools); awaiting approval

## Why

In game, `F` (fly), `b` (boat), `P` (portal/teleport), `H` (hearth) and `R` (run to) steps
complete in `WoWPro.AutoCompleteZone` (`WoWPro/WoWPro_AutoComplete.lua:488-530`), and only
when, on arrival, one of these holds:

- the step name equals `GetZoneText()` or `GetSubZoneText()`;
- the first `;` part of the `TZ` tag equals one of them;
- a numeric `TZ` equals the map id.

`R` steps also complete on TomTom waypoint arrival when they carry `CC` or `CS`
(`WoWPro_Mapping.lua:133-158`).

hwc sets the arrival subzone to the step's own name (`src/hwc/driver/actions.lua`
`perform_arrival` :496-504 for F/b/P, `perform_travel` :624 for R), so the name test always
passes. `h` stores the step's text as the bind location and `H` lands there
(`actions.lua:612-616, 636-640`; `stubs/core.lua:148`). `f` names taxi nodes after the
guide's step text (`stubs/core.lua:240-256`). All of this hides real guide bugs.

The user saw `F` steps stay up in game (2026-11-18). Forever's own client tables (build
1.60.1.70959) show why: `Stormwind`, `Crossroads`, `Theramore`, `Feathermoon`, `Grom'gol`,
`Gadgetzem` and `Rut'Theran Village` are not the name of any area, subzone, indoor area
or map in Forever. A step named that way can never complete by zone, anywhere. The guide's
own history agrees: commit `a3df10408` "Human run through part 1" added `TZ|Stormwind City`
to the bare `F Stormwind` steps its author played. A Human Warrior hwc run advanced
`19_25_Alliance.lua:137` and `:255` (bare `F Stormwind`) with no finding.

## Goals

- Arrival steps run on accurate world data. The addon's own checks, fed real inputs,
  decide whether a step advances.
- If a step doesn't advance, the run records a guide finding (`did-not-advance`) with the
  reason: what the step expected and where the player actually arrived.
- If hwc has no accurate data for an arrival, the report says so as a harness notice.
  The step never passes on the guide's word.
- Data stays accurate and easy to refresh when Forever's client changes, and no
  third-party data enters the repository.

## Non-goals

- Correcting guides. hwc reports; it never rewrites or second-guesses a step.
- Route quality and travel time. hwc only needs to know the player arrived. How they got
  there (flight legs, detours) is not emulated or graded (user, 2026-11-19).
- Subzones at arbitrary `R` coordinates (phase 2).
- Vendor buys (`B Rhapsody Malt`). That is a separate investigation, waiting on the
  in-game `GetItemCount(2894)` evidence.

## Anti-goals

- Any code path that takes landing values (zone, subzone, map id, bind text) from the
  step being judged: its name, its `TZ`, or its note. That is the bug this design
  removes. The step may name *which* real arrival point it means (§6, §9); the values
  always come from data.
- Defaulting an unknown arrival to "advanced". Unknown means a harness notice, never a
  pass.
- Committing third-party data. Downloaded client tables live in `~/.hwc`, like QuestieDB.

## Approaches considered

1. **Hand-authored arrivals file checked in game.** Accurate, but every node, zone and
   map id is typed by hand, and every value is a chance for the kind of typo hwc exists
   to catch. Rejected as the main source.
2. **QuestieDB only.** It gives flight masters, innkeepers, positions and parent zones,
   but no node names and no area names. Kept as the source for NPCs.
3. **Forever client tables from wago.tools, installed like QuestieDB (chosen, user
   2026-11-19).** `hwc update` downloads the tables for a pinned Forever build as CSV,
   converts them to JSON and stores them under `~/.hwc`. That gives accurate node names,
   positions, maps, zones and every area name, refreshable per build, never committed.
   A small committed first-party file holds only what the tables can't give.
4. **Flight route emulation from `TaxiPath`.** Rejected: it decides routing, and nothing
   in hwc depends on the route (user, 2026-11-19).

## Design

### 1. Forever client tables (downloaded)

- **Source:** `https://wago.tools/db2/<Table>/csv?build=<version>`. The build list is
  `https://wago.tools/api/builds`, key `wowf` (Forever).
- **Tables and the columns kept:**

  | Table | Columns | Used for |
  |---|---|---|
  | `TaxiNodes` | `ID, Name_lang, ContinentID, Flags, Pos_0, Pos_1` | node names, continent, faction (`Flags & 3`: 1 Alliance, 2 Horde, 3 both), world position |
  | `UiMap` | `ID, Name_lang, ParentUiMapID, Type` | map names; the continent of a map (walk parents to `Type` 2) |
  | `UiMapAssignment` | `UiMapID, MapID, AreaID, Region_0, Region_1, Region_3, Region_4` | world position to map id and map percent; a map's zone area |
  | `AreaTable` | `ID, AreaName_lang, ParentAreaID, ContinentID` | zone and subzone names (`GetZoneText` is the zone area's name) |
  | `WMOAreaTable` | `AreaName_lang, AreaTableID` | indoor area names, which `GetSubZoneText` also returns (e.g. "Trade District") |

- **Store:** `~/.hwc/forever/<build>/` holds one JSON per table and `.hwc-release.json`
  (build, per-table CSV sha256, `downloaded_at`). `~/.hwc/forever/active` names the build
  in use. Install is staged and atomic, as `hwc.questie.install` does.
- **Commands:**
  - `hwc update` installs the newest QuestieDB release *and* the newest `wowf` build's
    tables. `--build VERSION` pins the tables; `--tag` still pins QuestieDB.
  - `hwc init` and `hwc doctor` cover the tables the way they cover QuestieDB.
- **Derived data (built at load, not stored):**
  - **Taxi nodes:** name, continent, faction, and the landing map id, x and y. Map id and
    position come from the `UiMapAssignment` whose region holds the node's world
    position: `x = (Region_4 - Pos_1) / (Region_4 - Region_1)` and
    `y = (Region_3 - Pos_0) / (Region_3 - Region_0)`. (This checks out for "Thelsamar,
    Loch Modan": 33.94, 50.8 against QuestieDB's flight master at 33.94, 50.95.) The zone
    is the `AreaTable` name of that assignment's `AreaID`.
  - **Continent of a map:** `UiMap` parents up to `Type` 2.
  - **Area names:** every `AreaTable`, `WMOAreaTable` and `UiMap` name in the build.

### 2. Hand-checked arrival facts (committed, first-party)

Like the reputation tables (`2026-11-18-reputation-design.md:204`), these are in-game
captures. Each is dated and says how it was checked. File: `src/hwc/world/arrivals.lua`.
It holds only what the client tables can't give:

- `subzones[node_name]`: `GetSubZoneText()` after landing at that node.
- `inns`: innkeeper npc, `bind` (`GetBindLocation()` after binding), and the hearth
  landing (zone, subzone, map id, x, y).
- `crossings`: boats, zeppelins, portals and teleports, each with its departure
  (`from = { map_id, x, y }`, or `spell`) and its landing (zone, subzone, map id, x, y).
- `start_nodes[race_key]`: each race's capital node (user, 2026-11-19: every character
  starts with its capital's node learned).
- `start_bind[race_key]`: the starting bind and hearth landing.
- `taxi_map`: whether the client lists undiscovered nodes and in what order. Until it is
  checked: list every node of the continent and the player's faction in `TaxiNodes.ID`
  order, typed `NONE` when undiscovered, marked unverified in the file.

`hwc arrivals capture-script` prints `/run` lines for taking these in game.

### 3. Judging a name without a subzone

The area names (§1) settle many steps without any capture:

- If the step name and the `TZ` part are each neither an area name in the build nor a
  map id, the step can never complete by zone anywhere. When it doesn't advance, the
  reason is `name-not-an-area`, a guide finding, whatever the subzone is.
- If the name or `TZ` equals the landing zone, or the landing map id, the addon
  completes it on the derived data alone.
- Otherwise the answer depends on the landing subzone. With a captured subzone, the
  addon decides. Without one, the outcome is an `arrival-data-gap` notice
  (`subzone-unknown`).

### 4. `f`: learning a flight point

- The departure is the step's `Z`/`M` (§8). The flight master is the QuestieDB NPC with
  the flight-master flag (`npcFlags` bit 8) nearest that spot. The node is the taxi node
  of the player's faction nearest that NPC on the same map.
- Found: learn the node's real name. Fire `TAXIMAP_OPENED`, and if the node is new, also
  `UI_INFO_MESSAGE(ERR_NEWTAXIPATH)`. A node already known gives no discovery message, as
  in game. The addon decides whether the step advances.
- Not found: learn nothing. Notice `fp-unknown`.

### 5. `F`: flying

The taxi stub lists nodes per §2 `taxi_map`. `TaxiNodeGetType` is `REACHABLE` for learned
nodes and `NONE` otherwise. `UnitOnTaxi` reads a player flag. `TakeTaxiNode(i)` records
the chosen node.

1. Walk to the departure (§8) and fire `TAXIMAP_OPENED`. With AutoSelect (default true)
   the addon's own `TakeTaxiClassic(step name)` picks a node by `location:find(step name)`
   and calls `TakeTaxiNode`. hwc chooses nothing.
2. A learned node was taken: set `UnitOnTaxi`, fire `PLAYER_CONTROL_LOST`, and settle past
   `QuestEngineDelay` (`PLAYER_CONTROL_LOST_PUNTED` records `TaxiPendingStep`). Then land
   at the node's derived zone and map id, plus its captured subzone or `""`, clear
   `UnitOnTaxi`, fire `ZONE_CHANGED_NEW_AREA`, `ZONE_CHANGED` and
   `PLAYER_CONTROL_GAINED`, and settle. `AutoCompleteZone` decides; §3 classifies a step
   that doesn't advance.
3. An undiscovered node was taken: an undiscovered node can't be flown to, so there is
   no flight. Guide finding `flight-point-undiscovered`, unless hwc's knowledge is
   incomplete (the race has no `start_nodes` entry, or an earlier `f` on that continent
   was `fp-unknown`); then it is a notice. The player still arrives (§9).
4. No node was taken: guide finding `no-taxi-node`. The player still arrives (§9).

### 6. `b` and `P`

- Candidates: `crossings` whose `from` is nearest the departure (§8), or teleports whose
  `spell` the player knows or the step's `SPELL` names.
- One candidate: land there. Several: take the one whose landing zone, subzone or map id
  equals the step name or `TZ`. If none does, the player takes one by the loose match
  (§9), and the addon decides as usual. No candidate: notice `arrival-unknown`.
- Landing fires `ZONE_CHANGED_NEW_AREA` and `ZONE_CHANGED`. §3 classifies a step that
  doesn't advance.

### 7. `h`, `H` and `R`

- `h`: the nearest QuestieDB innkeeper (`npcFlags` bit 128) gives the `inns` entry. Bind
  it and fire `HEARTHSTONE_BOUND`. `AutoCompleteSetHearth` compares the step name to the
  real `GetBindLocation()`. With no entry: notice `inn-unknown`, bind unchanged.
- `H`: land at the bound inn's landing and fire the zone events. With no entry, notice
  `inn-unknown`, and the player stays.
- `R`:
  - Zone and map id from `Z` (real data); the subzone is `""` on a zone or map change
    and kept otherwise; `credit_arrival` is unchanged.
  - If it doesn't advance:
    - `CC`/`CS` gives notice `waypoint-arrival-not-emulated` (until the TomTom plan);
    - otherwise §3 classifies it: `name-not-an-area` (guide) or `subzone-unknown`
      (notice).

### 8. Departure for F, f, b and P

`walk_to_step` skips travel actions (`actions.lua:513-515`). These actions first apply
the step's `Z`/`M` departure (Ruling Y) with the same move rule and events.

### 9. Where the player ends up when the addon's pick fails

The player arrives anyway, as a real player would (user, 2026-11-19). The route isn't
emulated. Only the end point matters.

- The step only identifies *which* real point it means. A loose match on the step name,
  then the `TZ` part, against the candidates' node locations (text before the comma),
  zones and subzones: case-insensitive, then exact, prefix and substring, taking the
  highest tier with a hit. One hit: land there with zone events only, learn nothing, and
  record `resolved_by = "loose"` on the finding.
- No hit or several: notice `destination-unresolved`. The player stays, and the next
  step's `Z`/`M` moves them.

### 10. Findings and report

- **Guide findings:** `did-not-advance` with reason `name-not-an-area`,
  `arrival-mismatch` (traveled, the name is a real area, the addon didn't complete it),
  `flight-point-undiscovered` or `no-taxi-node`. Each carries `expected` (name, TZ),
  `arrived` (zone, subzone, map id) and `resolved_by` when set.
- **Harness notices:** signal `arrival-data-gap`, with reason `tables-missing`,
  `fp-unknown`, `subzone-unknown`, `inn-unknown`, `arrival-unknown`,
  `destination-unresolved`, `start-node-unknown`, `waypoint-arrival-not-emulated` or
  `arrival-data-mismatch` (the QuestieDB cross-check of §2 entries).
  - It sits in the harness fold, out of every count, grouped by reason and data key.
  - It replaces `did-not-advance` for that step.
  - It is recorded only when the step didn't advance, except `start-node-unknown` and
    `arrival-data-mismatch`, which are recorded once per run.
- **No tables installed:** every arrival step that doesn't advance is a
  `tables-missing` notice. Nothing is judged, nothing crashes, and the report says to
  run `hwc update`.

## Constraints

- Fidelity rule (actions.lua header): actions never write engine state.
- Every event sequence cites the addon line it mirrors.
- Forever is not Classic: no Classic value enters §2 without an in-game check. The client
  tables are Forever's own build.
- wago.tools is an external service. Downloads are pinned to a build and checksummed per
  table, and runs read only the installed copy, never the network.

## Next plan: TomTom (decided 2026-11-19)

Mock the TomTom API calls WoW-Pro makes, so `CC`/`CS` waypoint arrival runs through
`WoWPro_Mapping.lua`. That retires `waypoint-arrival-not-emulated` (347 Forever `R` steps).

## Phase 2 (later)

Subzones at arbitrary `R` coordinates. That retires most `subzone-unknown` notices.

## Left to the builder

- The departure radius; the capture `/run` text; module placement beside
  `hwc.questie.*`.
- A small CSV parser (quoted fields with commas, e.g. `"Stormwind, Elwynn"`).
- Spec fixtures: trimmed CSVs and JSONs for a matching node, a bare `F Stormwind`, an
  undiscovered node, a two-route dock and an unknown node.
