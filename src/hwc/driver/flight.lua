-- F (fly) and f (learn a flight point) on the Forever client tables (arrival emulation
-- design spec sections 4, 5, 8 and 9). Part of hwc.driver.actions, kept apart so the
-- travel logic stays in one place: the same fidelity rule holds (nothing here writes
-- engine state; it changes the world and fires client events). actions.lua passes its
-- own helpers in `h`: fire(ctx, out, event, ...), depart(ctx, step, out) (the step's Z/M,
-- spec section 8) and settle(ctx, out) (out.settle keeps the last result, hit_limit OR-ed).
--
-- Outcome fields set here (read by the driver):
--   out.reason    guide reason: "no-taxi-node" | "flight-point-undiscovered"
--   out.data_gap  { reason, key }: hwc's own data is missing ("tables-missing", "fp-unknown",
--                 "start-node-unknown", "destination-unresolved", "arrival-unknown" for a
--                 departure map on no continent), or "taxi-not-taken": the
--                 addon never tried to pick a node it would have matched (ruling R12). The
--                 first gap recorded wins.
--   out.named     { name, tz }: what the step asks for (F)
--   out.arrived   { zone, subzone, map_id }: where the player landed; subzone nil when no
--                 capture says what it is (ruling R4)
--   out.resolved_by "loose" when the landing came from arrival.loose (spec section 9)
--   out.classify  arrival.classify(db, out.arrived, name, tz) whenever the player landed
local arrival = require("hwc.driver.arrival")
local stubs_core = require("hwc.stubs.core")

local flight = {}

local NO_TABLES = arrival.NO_TABLES

local function gap(out, reason, key)
  out.data_gap = out.data_gap or { reason = reason, key = key }
end

local function db_of(ctx)
  return ctx.world.catalog and ctx.world.catalog.forever
end

local function captured_subzone(world, name)
  local e = (world.arrivals.subzones or {})[name]
  return e and e.subzone or nil
end

-- The nodes the taxi stub lists (hwc.stubs.core taxi_nodes): `nodes`, less the undiscovered
-- ones when the taxi_map facts say the map doesn't show them.
local function listed(w, nodes)
  local tm = w.arrivals and w.arrivals.taxi_map
  if not (tm and tm.lists_undiscovered == false) then return nodes end
  local out = {}
  for _, n in ipairs(nodes) do
    if w.player.flight_points[n.name] then out[#out + 1] = n end
  end
  return out
end

-- Whether WoWPro.TakeTaxiClassic(name) would pick one of `nodes`: a location (the text
-- before the first comma) containing the name as plain text, or the whole node name equal
-- to it (WoWPro_AutoComplete.lua:32-53).
local function addon_would_take(nodes, name)
  if type(name) ~= "string" then return false end
  for _, n in ipairs(nodes) do
    local location = n.name:match("^([^,]*)")
    if location:find(name, 1, true) or n.name == name then return true end
  end
  return false
end

-- The continent's taxi nodes for the player's faction (spec section 5's listing, before
-- any taxi_map filter), or {} on a map the tables don't place on a continent.
local function continent_nodes(db, p)
  local continent = db:continent_of(p.map_id)
  return continent and db:taxi_nodes(continent, p.faction) or {}, continent
end

-- Puts the player at `node` with its captured subzone or "" (ruling R4) and records the
-- landing on the outcome. No events: the caller fires them.
local function land(ctx, step, out, node)
  local w = ctx.world
  local subzone = captured_subzone(w, node.name)
  w.player:set_zone(node.zone, subzone or "", node.map_id, node.x, node.y)
  out.arrived = { zone = node.zone, subzone = subzone, map_id = node.map_id }
  out.classify = arrival.classify(db_of(ctx), out.arrived, step.name, step.tags and step.tags.targetzone)
end

-- F: walk to the flight master (h.depart) and open the taxi map. With AutoSelect (default
-- true, WoWPro.lua:490-492) the addon's TAXIMAP_OPENED handler (WoWPro_Events.lua:815-826)
-- runs TakeTaxiClassic(step name) (WoWPro_AutoComplete.lua:32-53), which picks the first
-- listed node whose location contains the name and calls TakeTaxiNode; hwc chooses nothing
-- and reads the pick from sb.taxi_taken.
function flight.fly(ctx, step, out, h)
  local w, p = ctx.world, ctx.world.player
  local tz = step.tags and step.tags.targetzone
  out.kind = "acted"
  h.depart(ctx, step, out)
  out.named = { name = step.name, tz = tz }
  local db = db_of(ctx)
  if not db then
    gap(out, NO_TABLES.reason, NO_TABLES.key)
    return
  end
  local nodes, continent = continent_nodes(db, p)
  if not continent then
    -- A departure map the tables place on no continent: hwc can't list the taxi map, so a
    -- stall is its own gap (key "map:<id>"), never no-taxi-node. Only a name that is no area
    -- anywhere stays the guide's (spec section 3: it can't complete by zone wherever it lands).
    if arrival.names_no_area(db, step.name, tz) then
      out.classify = "name-not-an-area"
    else
      gap(out, "arrival-unknown", "map:" .. tostring(p.map_id))
    end
    return
  end
  local taken = ctx.engine.sb.taxi_taken
  local before = #taken
  h.fire(ctx, out, "TAXIMAP_OPENED")
  h.settle(ctx, out)
  local name = #taken > before and taken[#taken] or nil
  local node = name and db:node(name)

  if node and p.flight_points[name] then
    -- A learned node: the flight. PLAYER_CONTROL_LOST is punted by QuestEngineDelay
    -- (WoWPro_Events.lua:828-832, WoWPro.lua:484); PLAYER_CONTROL_LOST_PUNTED records
    -- TaxiPendingStep while UnitOnTaxi (:834-849), so settle past it. While on the taxi
    -- AutoCompleteZone holds an F step (WoWPro_AutoComplete.lua:507-512, ScheduleTaxiCompletion
    -- :461-486). Landing: off the taxi, the zone events run AutoCompleteZone (WoWPro_Events.lua
    -- :301-316, WoWPro_AutoComplete.lua:488-530) and PLAYER_CONTROL_GAINED completes the
    -- pending step there (WoWPro_Events.lua:851-866). The final settle is actions.perform's.
    p:set_on_taxi(true)
    h.fire(ctx, out, "PLAYER_CONTROL_LOST")
    h.settle(ctx, out)
    land(ctx, step, out, node)
    p:set_on_taxi(false)
    h.fire(ctx, out, "ZONE_CHANGED_NEW_AREA")
    h.fire(ctx, out, "ZONE_CHANGED")
    h.fire(ctx, out, "PLAYER_CONTROL_GAINED")
    return
  end

  if node then
    -- An undiscovered node was taken: no flight (spec section 5.3). A notice instead of the
    -- guide finding when hwc's knowledge of the learned nodes is incomplete.
    out.reason = "flight-point-undiscovered"
    if w.start_node_unknown then
      gap(out, "start-node-unknown", p.race_key)
    elseif w.fp_unknown[continent] then
      gap(out, "fp-unknown", tostring(continent))
    end
  elseif addon_would_take(listed(w, nodes), step.name) then
    -- A listed node matches, yet the addon took none: its TAXIMAP_OPENED handler never ran
    -- TakeTaxiClassic (the row wasn't active, or AutoSelect is off). Not the guide's fault.
    gap(out, "taxi-not-taken", arrival.step_key(step))
  else
    out.reason = "no-taxi-node"
  end
  -- The player still arrives (spec section 9): the step only picks which real node it
  -- means, by the loose match over the continent's nodes (with their captured subzones).
  local candidates = {}
  for i, n in ipairs(nodes) do
    candidates[i] = { name = n.name, zone = n.zone, subzone = captured_subzone(w, n.name), node = n }
  end
  local hit = arrival.loose(candidates, step.name, tz)
  if not hit then
    gap(out, "destination-unresolved", step.name or "")
    return
  end
  -- Zone events only (WoWPro_Events.lua:301-316): no flight, nothing learned.
  land(ctx, step, out, hit.node)
  out.resolved_by = "loose"
  h.fire(ctx, out, "ZONE_CHANGED_NEW_AREA")
  h.fire(ctx, out, "ZONE_CHANGED")
end

-- f: the departure (the step's Z/M) is the flight master's spot, where the node sits, so the
-- node is the player's-faction taxi node nearest it on that map (arrival.nearest within
-- arrival.RADIUS). This stands in for spec section 4's "nearest QuestieDB flight master":
-- QuestieDB has no index by NPC flag.
--
-- Found: learn the real node name. A new node fires UI_INFO_MESSAGE(0, ERR_NEWTAXIPATH),
-- which AutoCompleteGetFP reads as `_event, _idx, msg` (WoWPro_Events.lua:915-918,
-- WoWPro_AutoComplete.lua:94-112), then TAXIMAP_OPENED, whose RecordTaxiLocations
-- (WoWPro_AutoComplete.lua:9-29) completes the f step when its name is a known location.
-- The discovery message goes first: AutoCompleteGetFP completes the first visible
-- uncompleted f row of up to 15, so after RecordTaxiLocations has completed the step it
-- could take a later f row. The in-game order is not confirmed for Forever. A known node
-- gives no discovery message, as in game.
function flight.learn(ctx, step, out, h)
  local w, p = ctx.world, ctx.world.player
  out.kind = "acted"
  h.depart(ctx, step, out)
  local db = db_of(ctx)
  if not db then
    gap(out, NO_TABLES.reason, NO_TABLES.key)
    return
  end
  local nodes, continent = continent_nodes(db, p)
  if not continent then
    -- A map the tables place on no continent: a gap of its own, keyed by the map. It marks
    -- no continent in w.fp_unknown (keyed by continent only), since none is known.
    gap(out, "fp-unknown", "map:" .. tostring(p.map_id))
    return
  end
  local node = arrival.nearest(nodes, p.map_id, p.x, p.y, function(n) return n.map_id, n.x, n.y end)
  if not node then
    gap(out, "fp-unknown", string.format("%s:%.1f,%.1f", tostring(p.map_id), p.x * 100, p.y * 100))
    w.fp_unknown[continent] = true
    return
  end
  local new = not p.flight_points[node.name]
  if new then
    p:learn_flight_point(node.name)
    h.fire(ctx, out, "UI_INFO_MESSAGE", 0, stubs_core.ERR_NEWTAXIPATH)
  end
  h.fire(ctx, out, "TAXIMAP_OPENED")
end

return flight
