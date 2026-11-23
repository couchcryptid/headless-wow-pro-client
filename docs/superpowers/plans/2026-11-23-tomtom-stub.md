# TomTom Stub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stub TomTom so WoW-Pro sets its waypoints and completes `CC`/`CS` `R` steps on arrival, as it does for a real Forever player. Also clean the missing-globals list.

**Architecture:**
- A `TomTom` table holds waypoints.
- A hidden frame's `OnUpdate`, ticked by hwc's clock, fires each waypoint's distance callback when the player comes within range. Yards come from the Forever UiMapAssignment regions.
- `R` walks its `M` coordinates in order and settles after each move.

**Tech Stack:** LuaJIT 2.1, busted 2.3, luacheck.

**Spec:** `docs/superpowers/specs/2026-11-23-tomtom-stub-design.md`

## Global Constraints

- Actions change the world and fire events only. TomTom's callback is fired by the stub's own `OnUpdate`, never by the driver.
- Arrival range keys come from WoW-Pro's `callbacks.distance`. The callback signature is `fn("distance", uid, range, distance, lastdistance)`, fired once per entry into a range.
- Distance needs the same map id for player and waypoint, plus a region for that map. Otherwise there is no callback.
- `TomTom.db.profile` defaults: `arrow = { setclosest = false, arrival = 15 }`, `persistence = { cleardistance = 10 }` (unverified).
- `LE_EXPANSION_CLASSIC` … `LE_EXPANSION_MIDNIGHT` = 0 … 11, in this order: CLASSIC, BURNING_CRUSADE, WRATH_OF_THE_LICH_KING, CATACLYSM, MISTS_OF_PANDARIA, WARLORDS_OF_DRAENOR, LEGION, BATTLE_FOR_AZEROTH, SHADOWLANDS, DRAGONFLIGHT, WAR_WITHIN, MIDNIGHT.
- Run `~/.luarocks/bin/busted`, `~/.luarocks/bin/busted --tags=slow` and `~/.luarocks/bin/luacheck src spec` before each commit.

## Review Focus

1. A `CS` step with 3 coordinates: the player reaches them in order and the step completes only at the last one.
2. The player is already standing on the waypoint when it's added: the callback fires on the next tick, not never.
3. The player is on a taxi: the callback may fire, but WoW-Pro ignores it. The stub doesn't need to filter.
4. A waypoint on a map with no region in the tables, or on another map: no callback, no error.
5. `RemoveWaypoint` on an unknown or already-removed uid: no error.

---

### Task 1: Map size in yards from the Forever tables

**Files:**
- Modify: `src/hwc/forever/db.lua`
- Test: `spec/forever/db_spec.lua`

**Interfaces:**
- Produces: `DB:map_yards(ui_map_id) -> width, height` (positive numbers), or nil. Taken from the largest UiMapAssignment region whose `UiMapID` is that map: width = `|Region_4 − Region_1|`, height = `|Region_3 − Region_0|`.

- [ ] **Step 1: Write the failing tests.**
  - For Dun Morogh (1426) in the fixture tables, the returned sizes equal the fixture row's region spans. Compute the expected values from the fixture CSV in the test, rather than hard-coding them.
  - An unknown map id returns nil.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement `map_yards`**, indexing the regions by `UiMapID` once in `DB:_index`.
- [ ] **Step 4: Run them and confirm they pass**, then run the full fast suite.
- [ ] **Step 5: Commit** `feat: Size Forever maps in yards from UiMapAssignment`.

### Task 2: The TomTom stub and its arrival ticker

**Files:**
- Create: `src/hwc/stubs/tomtom.lua`
- Modify: `src/hwc/boot.lua` (install after `stubs.install`, once `CreateFrame` exists)
- Test: `spec/stubs/tomtom_spec.lua`

**Interfaces:**
- Consumes: `DB:map_yards`; `sb.world.player` (`map_id`, `x`, `y` as fractions); `sb.world.catalog.forever`.
- Produces:
  - `env.TomTom` with `db`, `AddWaypoint`, `RemoveWaypoint`, `SetCrazyArrow` and `GetClosestWaypoint`;
  - `M.install(sb)` and `M.tick(sb)`, the `OnUpdate` body, exposed for tests.

- [ ] **Step 1: Write the failing tests** with a fake world on fixture tables, map 1426:
  - **Already there:** with the player at (0.5, 0.5), `AddWaypoint(1426, 0.5, 0.5, {callbacks = {distance = {[10] = fn}}})` returns a table uid. One `tick` calls `fn("distance", uid, 10, 0, <any>)`, and a second `tick` doesn't call it again.
  - **Out of range:** a player 100+ yards away gets no call. After the player moves onto the waypoint, the next tick makes one call.
  - **Leaving and returning:** after the player moves out of range and back, `fn` fires again.
  - **Other map, or no region:** a waypoint on another map id, or on a map with no region, gets no call and no error.
  - **Removing:** `RemoveWaypoint(uid)` stops calls; `RemoveWaypoint` of an unknown uid is fine.
  - **Closest:** `GetClosestWaypoint()` returns the nearer of two same-map uids, or nil with none.
  - **Arrow:** `SetCrazyArrow(uid, 15, "t")` records `{ uid, 15, "t" }` on the stub's state.
  - **Settings:** `TomTom.db.profile.persistence.cleardistance == 10` and `arrow.setclosest == false`.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement.**
  - Yard distance: `dx = (wx − px) * width`, `dy = (wy − py) * height`.
  - Per waypoint and range, keep an `inside` flag, so a callback fires only on the transition from outside to inside.
  - Install creates one hidden frame with `SetScript("OnUpdate", function() M.tick(sb) end)`. Check in `frames.lua` that the frame ticks when hidden; if it doesn't, make it shown with no size.
  - Header comment citing `WoWPro_Mapping.lua:103-170, 440-600` and `Broker.lua:4843`.
- [ ] **Step 4: Wire it into `boot.lua`**, then run the full fast suite. Any spec asserting that `TomTom` is missing or that the "missing arrow" popup is shown must be updated deliberately; record each in the ledger.
- [ ] **Step 5: Commit** `feat: Stub TomTom with an arrival ticker on the Forever maps`.

### Task 3: `R` walks its coordinates; drop the waypoint notice

**Files:**
- Modify: `src/hwc/driver/actions.lua` (`parse_coords` gains `parse_all_coords`, a list of fractions; `perform_travel`)
- Modify: `src/hwc/findings/text.lua` (remove `waypoint-arrival-not-emulated` from `GAP_CLAUSES`)
- Modify: `README.md` (remove the notice; TomTom is stubbed)
- Test: `spec/driver/actions_other_spec.lua`, `spec/findings/text_spec.lua`

**Interfaces:**
- Consumes: `settle(ctx, out)`, `fire`.
- Produces: `R` with `M` "a,b;c,d;e,f" calls `p:set_zone` for each coordinate in that order, settling after each, and ends on the last.

- [ ] **Step 1: Write the failing tests.**
  - `R` with `M` "10,10;20,20;30,30" records three zone moves in that order and ends at (0.3, 0.3), with one settle per move.
  - `R` with `CC`/`CS` no longer sets `out.data_gap`. Replace the test at `actions_other_spec.lua:171`.
  - The text spec no longer lists `waypoint-arrival-not-emulated`.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement.**
  - Zone events (`ZONE_CHANGED_NEW_AREA`, `ZONE_CHANGED`) fire once, on the first move; later moves within the step just settle.
  - `credit_arrival` and `classify` run after the last move.
  - Remove the `waypcomplete` gap. Keep the `waypcomplete` tag key, since the engine still parses it.
- [ ] **Step 4: Run the fast suite, the slow suite and luacheck, and confirm all pass.**
- [ ] **Step 5: Commit** `feat: Walk R steps through their waypoints so TomTom arrival completes them`.

### Task 4: Clean the harness list

**Files:**
- Modify: `src/hwc/boot.lua` (`EXPECTED_ABSENT` gains `UnitAura`; its comment notes the 2026-11-23 check)
- Modify: `src/hwc/stubs/core.lua` (the globals below)
- Test: `spec/stubs_spec.lua`, `spec/boot_spec.lua` (or wherever `EXPECTED_ABSENT` is tested)

- [ ] **Step 1: Write the failing tests.**
  - `env.CANCEL == "Cancel"`, `env.OKAY == "Okay"`, `env.FACTION_ALLIANCE == "Alliance"` and `env.FACTION_HORDE == "Horde"`.
  - `env.LE_EXPANSION_CLASSIC == 0` and `env.LE_EXPANSION_MIDNIGHT == 11`.
  - `GameFontNormal` and `GameFontNormalSmall` are tables, and `BackdropTemplateMixin` is a table.
  - `boot.EXPECTED_ABSENT.UnitAura == true`.
- [ ] **Step 2: Run them and confirm they fail; implement; run them and confirm they pass.**
- [ ] **Step 3: Run all three checks and commit** `fix: Stub the client's interface globals and expect UnitAura absent`.
- [ ] **Step 4: End to end.** From `~/Projects/WoW-Pro-Guides`, run `hwc run --race Dwarf --class WARRIOR`. Compare with the 2026.11.21.A run (47 findings, 39 missing globals, 73 arrival data gaps) using `hwc diff`, and report how many `CC`/`CS` steps now complete on arrival.
