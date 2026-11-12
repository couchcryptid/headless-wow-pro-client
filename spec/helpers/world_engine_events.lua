-- Determinism driver (run as its own luajit process by world_engine_spec):
-- runs the Dwarven Outfitters flow and prints, as sorted JSON, the world
-- events, the engine's own state after each step (current step, completion
-- flags) and the sandbox error messages. world.events are harness-written, so
-- only the engine snapshots and errors can expose engine non-determinism.
-- usage: luajit spec/helpers/world_engine_events.lua <repo> <race> <class>
local repo, race, class = arg[1], arg[2], arg[3]
local flow = dofile(repo .. "/spec/helpers/world_engine_flow.lua")
local r, snap = flow.run(race, class)

local function step(cur) return { index = cur.index, action = cur.action, step = cur.step, qid = cur.qid } end

-- Every completion flag the engine has set, as a sorted list of step indices.
local function completed_indices(env)
  local gid = env.WoWProDB.char.currentguide
  local out = {}
  for i, v in pairs(env.WoWProCharDB.Guide[gid].completion) do
    if v then out[#out + 1] = i end
  end
  table.sort(out)
  return out
end

local errors = {}
for i, e in ipairs(r.errors) do errors[i] = e.msg end

io.write(require("hwc.json").encode({
  events = r.world.events,
  snapshots = {
    boot = step(snap.boot),
    accept = { current = step(snap.accept.current), completed = snap.accept.completed },
    progress = { current = step(snap.progress.current), completed = snap.progress.completed },
    turn_in = { current = step(snap.turn_in.current), completed = snap.turn_in.completed },
    completion = completed_indices(r.sb.env),
  },
  errors = errors,
}), "\n")
