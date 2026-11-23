-- TomTom stub (design docs/superpowers/specs/2026-11-23-tomtom-stub-design.md). WoW-Pro
-- expects TomTom on Classic-type clients (WoWPro_Broker.lua:4824, startup check :4843).
-- MapPoint (WoWPro_Mapping.lua:440-600) adds one waypoint per M coordinate with a distance
-- callback; WoWProMapping_distance (:103-170) completes CC/CS R steps on arrival.
--
-- Like TomTom, an OnUpdate checks the player against every waypoint and calls
-- callbacks.distance[range]("distance", uid, range, distance, lastdistance) once each time
-- the player comes within range. Distance is in yards on the waypoint's map, sized by the
-- Forever tables (DB:map_yards); another map, no region or no tables: no callback.
--
-- hwc's clock only ticks frames while something is queued or busy, so pending(sb) is true
-- after a player move or a waypoint add until a tick has looked; the engine's settle treats
-- it as busy (in game OnUpdate runs every frame).
local M = {}

local function state(sb)
  sb.tomtom = sb.tomtom or { waypoints = {}, version = 0 }
  return sb.tomtom
end
M.state = state

local function yards(sb, wp, p)
  if p.map_id ~= wp.map then return nil end
  local db = sb.world.catalog and sb.world.catalog.forever
  if not (db and db.map_yards) then return nil end
  local w, h = db:map_yards(wp.map)
  if not w then return nil end
  local dx, dy = (wp.x - (p.x or 0)) * w, (wp.y - (p.y or 0)) * h
  return math.sqrt(dx * dx + dy * dy)
end

local function position(sb)
  local p = sb.world.player
  return tostring(p.map_id) .. ":" .. tostring(p.x) .. ":" .. tostring(p.y)
end

function M.pending(sb)
  local st = state(sb)
  return st.seen_version ~= st.version or st.seen_position ~= position(sb)
end

function M.tick(sb)
  local st = state(sb)
  local p = sb.world.player
  st.seen_version, st.seen_position = st.version, position(sb)
  -- Snapshot: a callback may remove waypoints (WoWProMapping_distance does).
  local list = {}
  for _, wp in ipairs(st.waypoints) do list[#list + 1] = wp end
  for _, wp in ipairs(list) do
    if not wp.removed then
      local d = yards(sb, wp, p)
      local cbs = wp.opts and wp.opts.callbacks and wp.opts.callbacks.distance
      if cbs then
        local ranges = {}
        for range in pairs(cbs) do ranges[#ranges + 1] = range end
        table.sort(ranges)
        for _, range in ipairs(ranges) do
          local inside = d ~= nil and d <= range
          if inside and not wp.inside[range] and not wp.removed then
            sb:call(cbs[range], "distance", wp.uid, range, d, wp.last)
          end
          wp.inside[range] = inside
        end
      end
      wp.last = d
    end
  end
end

function M.install(sb)
  local env = sb.env
  local st = state(sb)
  local TomTom = {
    -- TomTom's defaults, unverified for the version a Forever player runs.
    db = { profile = { arrow = { setclosest = false, arrival = 15 }, persistence = { cleardistance = 10 } } },
  }
  function TomTom:AddWaypoint(map, x, y, opts)
    local uid = {}
    st.waypoints[#st.waypoints + 1] = { uid = uid, map = map, x = x, y = y, opts = opts, inside = {} }
    st.version = st.version + 1
    return uid
  end
  function TomTom:RemoveWaypoint(uid)
    for i, wp in ipairs(st.waypoints) do
      if wp.uid == uid then
        wp.removed = true
        table.remove(st.waypoints, i)
        st.version = st.version + 1
        return
      end
    end
  end
  function TomTom:SetCrazyArrow(uid, dist, title)
    st.arrow = { uid, dist, title }
  end
  function TomTom:GetClosestWaypoint()
    local best, best_d
    for _, wp in ipairs(st.waypoints) do
      local d = yards(sb, wp, sb.world.player)
      if d and (not best_d or d < best_d) then best, best_d = wp.uid, d end
    end
    return best
  end
  env.TomTom = TomTom
  local frame = env.CreateFrame("Frame", "hwcTomTomTicker")
  frame:SetScript("OnUpdate", function() M.tick(sb) end)
end

return M
