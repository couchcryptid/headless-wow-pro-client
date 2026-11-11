-- Determinism driver (run as its own luajit process by world_engine_spec):
-- runs the Dwarven Outfitters flow and prints world.events as sorted JSON.
-- usage: luajit spec/helpers/world_engine_events.lua <repo> <race> <class>
local repo, race, class = arg[1], arg[2], arg[3]
local flow = dofile(repo .. "/spec/helpers/world_engine_flow.lua")
local r = flow.run(race, class)
io.write(require("hwc.json").encode(r.world.events), "\n")
