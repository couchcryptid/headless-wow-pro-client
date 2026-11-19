-- The simulated world behind the WoW client stubs (design spec §5).
local Player = require("hwc.world.player")
local QuestLog = require("hwc.world.questlog")
local ReputationState = require("hwc.world.reputation_state")

local World = {}
World.__index = World

-- The starting flight point and bind (arrival emulation spec section 2). A race's
-- start node is learned only when the Forever tables know it. With the tables present,
-- a race with no entry, or a node the tables don't know, sets start_node_unknown (the
-- driver reports it once); false means the race starts with no node. Without the
-- tables nothing is learned and nothing flagged (every arrival is tables-missing then).
local function apply_start(self)
  local p, facts = self.player, self.arrivals
  local db = self.catalog and self.catalog.forever
  if db then
    local name = (facts.start_nodes or {})[p.race_key]
    if name and db:node(name) then
      p:learn_flight_point(name)
    elseif name ~= false then
      self.start_node_unknown = true
    end
  end
  local bind = (facts.start_bind or {})[p.race_key]
  if bind then p:set_bind(bind.bind, bind.map_id) end
end

-- catalog may be nil (the catalog arrives in a later task); clock is optional
-- and stamps event records (t = 0 without one). cfg.arrivals replaces the first-party
-- arrival facts (hwc.world.arrivals) in specs.
function World.new(cfg, catalog, clock)
  local self = setmetatable({ catalog = catalog, clock = clock, events = {}, log = nil, dialog = nil,
    arrivals = cfg.arrivals or require("hwc.world.arrivals"),
    -- continent UiMap id -> true once an f step there found no taxi node (fp-unknown).
    fp_unknown = {} }, World)
  self.player = Player.new(cfg, function(kind, fields)
    local rec = { t = self.clock and self.clock:now() or 0, kind = kind }
    for k, v in pairs(fields) do rec[k] = v end
    self.events[#self.events + 1] = rec
  end)
  self.player.catalog = catalog
  -- Applied before any event is recorded or clock is attached: the starting state.
  for _, p in ipairs(cfg.professions or {}) do self.player:learn_skill(p.name, p.rank, p.max) end
  apply_start(self)
  self.events = {}
  self.log = QuestLog.new(self)
  -- Faction names come from the catalog's QuestieDB (Catalog:faction_name); a catalog
  -- without them (spec stubs, no QuestieDB) leaves ids shown as "Faction <id>".
  local names = catalog and catalog.faction_name and function(id) return catalog:faction_name(id) end
  self.reputation = ReputationState.new(self.player.race_key, self.player.faction, names)
  return self
end

return World
