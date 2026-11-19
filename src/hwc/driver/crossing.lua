-- b (boat or zeppelin) and P (portal or teleport) on first-party crossing facts (arrival
-- emulation design spec sections 6, 8 and 9). Same fidelity rule as hwc.driver.flight:
-- nothing here writes engine state; it moves the player in the world and fires the zone
-- events. actions.lua passes its helpers in `h`: fire(ctx, out, event, ...) and
-- depart(ctx, step, out) (the step's Z/M, spec section 8).
--
-- Outcome fields set here (see the hwc.driver.flight header): out.data_gap
-- ("arrival-unknown" with key "<action>:<map_id>:<x>,<y>", "destination-unresolved"),
-- out.expected, out.arrived, out.resolved_by = "loose", out.classify. Crossings come
-- from ctx.world.arrivals.crossings, so they land with or without the Forever tables;
-- only out.classify needs them (nil without).
local arrival = require("hwc.driver.arrival")

local crossing = {}

-- Which `kind` of crossing each action takes from a departure point. P also takes any
-- teleport the player can cast (spell known or named by the step's SPELL tag).
local KIND = { b = "boat", P = "portal" }

local function db_of(ctx)
  return ctx.world.catalog and ctx.world.catalog.forever
end

local function gap(out, reason, key)
  out.data_gap = out.data_gap or { reason = reason, key = key }
end

-- Facts positions are percent; the world works in fractions.
local function from_pos(c)
  local f = c.from
  if not f then return nil end
  return f.map_id, f.x and f.x / 100, f.y and f.y / 100
end

local function step_spell(step)
  local v = step.tags and step.tags.spell
  if type(v) ~= "string" then return nil end
  local _, id = v:match("^%s*([^;]*);%s*(%d+)")
  return tonumber(id)
end

-- Crossings the step may take: those leaving the departure's dock (every route sharing
-- the nearest dock's position), plus, for P, teleports whose spell is known or named.
local function candidates(ctx, step, p)
  local list = (ctx.world.arrivals or {}).crossings or {}
  local kind = KIND[step.action]
  local docks = {}
  for _, c in ipairs(list) do
    if c.kind == kind and c.from then docks[#docks + 1] = c end
  end
  local out = {}
  local near = arrival.nearest(docks, p.map_id, p.x, p.y, from_pos)
  if near then
    for _, c in ipairs(docks) do
      if c.from.map_id == near.from.map_id and c.from.x == near.from.x and c.from.y == near.from.y then
        out[#out + 1] = c
      end
    end
  end
  if step.action == "P" then
    local named = step_spell(step)
    for _, c in ipairs(list) do
      if c.kind == "teleport" and c.spell and (p.spells[c.spell] or c.spell == named) then
        out[#out + 1] = c
      end
    end
  end
  return out
end

local function pick(cands, name, tz)
  if #cands == 1 then return cands[1] end
  for _, c in ipairs(cands) do
    if arrival.exact(c, name) or arrival.exact(c, tz) then return c end
  end
  return arrival.loose(cands, name, tz), "loose"
end

-- Lands the player at the crossing and fires the zone events (WoWPro_Events.lua:301-316,
-- which run AutoCompleteZone, WoWPro_AutoComplete.lua:488-530). The continent of the new
-- map is whatever DB:continent_of says, which is what the next F's taxi map lists.
local function land(ctx, step, out, c, h)
  local p = ctx.world.player
  p:set_zone(c.zone, c.subzone, c.map_id, c.x / 100, c.y / 100)
  out.arrived = { zone = c.zone, subzone = c.subzone, map_id = c.map_id }
  local db = db_of(ctx)
  out.classify = db and arrival.classify(db, out.arrived, step.name, step.tags and step.tags.targetzone) or nil
  h.fire(ctx, out, "ZONE_CHANGED_NEW_AREA")
  h.fire(ctx, out, "ZONE_CHANGED")
end

function crossing.perform(ctx, step, out, h)
  local p = ctx.world.player
  local tz = step.tags and step.tags.targetzone
  out.kind = "acted"
  h.depart(ctx, step, out)
  out.expected = { name = step.name, tz = tz }
  local cands = candidates(ctx, step, p)
  if #cands == 0 then
    gap(out, "arrival-unknown", string.format("%s:%s:%.1f,%.1f", step.action, tostring(p.map_id), p.x * 100, p.y * 100))
    return
  end
  local c, how = pick(cands, step.name, tz)
  if not c then
    gap(out, "destination-unresolved", step.name or "")
    return
  end
  out.resolved_by = how
  land(ctx, step, out, c, h)
end

return crossing
