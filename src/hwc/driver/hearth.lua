-- h (bind at an inn) and H (hearth to the bind) on first-party inn facts (arrival
-- emulation design spec section 7). Same fidelity rule as hwc.driver.crossing: nothing here
-- writes engine state; it binds or moves the player in the world and fires the events
-- the game would. actions.lua passes its helpers in `h`: fire(ctx, out, event, ...) and
-- (for h) depart(ctx, step, out).
--
-- h: the player stands at the step's Z/M (depart); the inn entry nearest them within
-- arrival.RADIUS becomes the bind (Player:set_bind(entry)), then HEARTHSTONE_BOUND
-- fires (WoWPro_Events.lua:868-879 reads GetBindLocation and runs AutoCompleteSetHearth).
-- H: lands at the bound entry and fires the zone events (WoWPro_Events.lua:301-316, which
-- run AutoCompleteZone, WoWPro_AutoComplete.lua:488-530).
--
-- Outcome fields: out.data_gap ("inn-unknown", key "<map_id>:<x>,<y>" for h, the bind
-- name for H, or "<gid>:<line>" when there is no bind), out.named, out.arrived, out.classify (nil without the Forever tables).
local arrival = require("hwc.driver.arrival")

local hearth = {}

local function db_of(ctx)
  return ctx.world.catalog and ctx.world.catalog.forever
end

-- Facts positions are percent; the world works in fractions.
local function inn_pos(e)
  return e.map_id, e.x and e.x / 100, e.y and e.y / 100
end

local function gap(out, key)
  out.data_gap = out.data_gap or { reason = "inn-unknown", key = key }
end

function hearth.bind(ctx, step, out, h)
  local p = ctx.world.player
  out.kind = "acted"
  h.depart(ctx, step, out)
  local inns = (ctx.world.arrivals or {}).inns or {}
  local entry = arrival.nearest(inns, p.map_id, p.x, p.y, inn_pos)
  if not entry then
    gap(out, string.format("%s:%.1f,%.1f", tostring(p.map_id), p.x * 100, p.y * 100))
    return
  end
  p:set_bind(entry)
  h.fire(ctx, out, "HEARTHSTONE_BOUND")
end

function hearth.home(ctx, step, out, h)
  local p = ctx.world.player
  local tz = step.tags and step.tags.targetzone
  out.kind = "acted"
  out.named = { name = step.name, tz = tz }
  local e = p.bind and p.bind.entry
  if not e then
    -- A bind with no inn entry names itself; with no bind at all, the step is the key.
    gap(out, p.bind and p.bind.name
      or string.format("%s:%s", tostring(step.gid), tostring(step.line or step.index)))
    return
  end
  p:set_zone(e.zone, e.subzone, e.map_id, e.x / 100, e.y / 100)
  out.arrived = { zone = e.zone, subzone = e.subzone, map_id = e.map_id }
  local db = db_of(ctx)
  out.classify = db and arrival.classify(db, out.arrived, step.name, tz) or nil
  h.fire(ctx, out, "ZONE_CHANGED_NEW_AREA")
  h.fire(ctx, out, "ZONE_CHANGED")
end

return hearth
