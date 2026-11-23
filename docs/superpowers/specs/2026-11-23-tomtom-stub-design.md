# TomTom stub (short design)

Date: 2026-11-23. Status: approved by the user ("go for it", 2026-11-23).

## Why

WoW-Pro expects TomTom on Classic-type clients (`WoWPro_Broker.lua:4824`: "Classic/Vanilla must
have TomTom"). hwc doesn't stub it, so WoW-Pro skips its whole waypoint block
(`WoWPro_Mapping.lua:457`), a path no real Forever player with TomTom is on. The 355 Forever `R`
steps tagged `CC`/`CS` can only complete through TomTom's distance callback, so hwc reports each one
as the harness notice `waypoint-arrival-not-emulated`. Memory: the user scheduled this as the plan
after arrival emulation (2026-11-19).

## How WoW-Pro uses TomTom (2026.11.21.A)

- `MapPoint` (`Mapping.lua:440-590`), for the active step: if `TomTom and TomTom.db`, it sets
  `db.profile.arrow.setclosest = true` and saves `db.profile.persistence.cleardistance`. The arrival
  range is 10 yards, or `cleardistance + 1` when that is set. It registers
  `callbacks.distance[range] = WoWProMapping_distance`, and with `CS` sets `cleardistance = 0`.
  Then, for each coordinate of `M` from last to first, it calls
  `uid = TomTom:AddWaypoint(zm, x/100, y/100, options)` and appends to `cache`. So `cache[1]` is the
  final destination and `cache[#cache]` is the first coordinate. After that it reads
  `TomTom:GetClosestWaypoint()` and may `RemoveWaypoint` some, then restores `cleardistance`.
- `RemoveMapPoint` (`:596-600`): `RemoveWaypoint(uid)` for each cached waypoint.
- `WoWProMapping_distance(event, uid, range, distance, lastdistance)` (`:103-170`):
  - Ignored on a taxi.
  - Only `R`, `r` or `N` steps complete.
  - `CC` (autoarrival 1): reaching cache entry i removes entries i..n; it completes when i == 1.
  - `CS` (autoarrival 2): only i == #cache (the next coordinate in order) counts. It completes when
    that entry is also 1; otherwise it removes it, calls `SetCrazyArrow` on the next, and shifts.
- Startup (`Broker.lua:4843`): `TomTom and TomTom.AddWaypoint` decides whether WoW-Pro shows the
  "missing arrow" popup.

## Approaches

- **A. Faithful stub plus an arrival check on hwc's clock (picked).** `TomTom` is a table with the
  API above. A hidden frame's `OnUpdate` (hwc's clock already runs frame tickers) checks the
  player against every waypoint and fires the distance callback when the player enters range, as
  TomTom does.
- **B. The driver fires the callback directly from the `R` action.** Fewer parts, but the action
  would be writing addon-facing behaviour that belongs to TomTom, and arrivals from any other move
  (a non-travel step's `M`) would be missed. Rejected.

## Design

1. **`src/hwc/stubs/tomtom.lua`, installed with the stubs.**
   - `TomTom.db.profile = { arrow = { setclosest = false, arrival = 15 }, persistence =
     { cleardistance = 10 } }`. These are TomTom's defaults, *unverified*; a later in-game check can
     replace them.
   - `AddWaypoint(self, map, x, y, opts)` stores `{ map, x, y, opts }` and returns a uid table.
   - `RemoveWaypoint(self, uid)` drops it.
   - `SetCrazyArrow(self, uid, dist, title)` records the arrow target.
   - `GetClosestWaypoint(self)` returns the nearest stored uid on the player's map, or nil.
2. **Arrival.** One frame from `CreateFrame` with an `OnUpdate` script. Each tick, for each
   waypoint with `opts.callbacks.distance`, it computes the player's distance in yards. For each
   range key the player has newly come within, it calls `fn("distance", uid, range, distance,
   lastdistance)`, once per entry into that range. Yards come from the Forever UiMapAssignment
   region of the waypoint's map:
   - width = `|Region_4 − Region_1|`, height = `|Region_3 − Region_0|`;
   - player and waypoint must be on the same map id;
   - no tables, or no region for the map: no callback.
3. **`R` walks the step's `M` coordinates in order.** `destination` today takes the first; `R` now
   moves through each coordinate in turn and ends on the last. Each move runs a settle, so the
   `OnUpdate` check sees each arrival. This is the guide's own path, not a route choice. Non-travel
   steps keep moving to their first coordinate (they don't complete on arrival).
4. **Findings.** `R` stops setting `waypoint-arrival-not-emulated`. A `CC`/`CS` `R` that doesn't
   advance is judged like any other `R`. If the tables are missing, the existing rule makes it
   `tables-missing`. The reason, its text and its README line are removed.
5. **Harness list.**
   - `UnitAura` joins `boot.EXPECTED_ABSENT` (checked in game, 2026-11-23).
   - `TomTom` stops showing as a missing global.
   - The always-present interface globals get constants or no-op stand-ins: `CANCEL`, `OKAY`,
     `FACTION_ALLIANCE`, `FACTION_HORDE`, `GameFontNormal`, `GameFontNormalSmall`,
     `BackdropTemplateMixin`, and `LE_EXPANSION_CLASSIC` … `LE_EXPANSION_MIDNIGHT` (0 … 11, the
     client's enum values, unverified for Forever).

## Non-goals

TomTom's own UI, the crazy-arrow display, minimap and world-map icons, waypoint persistence, Carbonite.
Travel time.

## Left to the builder

- Uid shape: a table, as TomTom returns.
- Where the frame is created: when the stubs are installed.
- Several range keys per waypoint: handle all of them; WoW-Pro registers one.
