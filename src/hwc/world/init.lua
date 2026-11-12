-- The simulated world behind the WoW client stubs (design spec §5).
local Player = require("hwc.world.player")
local QuestLog = require("hwc.world.questlog")

local World = {}
World.__index = World

-- catalog may be nil (the catalog arrives in a later task); clock is optional
-- and stamps event records (t = 0 without one).
function World.new(cfg, catalog, clock)
  local self = setmetatable({ catalog = catalog, clock = clock, events = {}, log = nil, dialog = nil }, World)
  self.player = Player.new(cfg, function(kind, fields)
    local rec = { t = self.clock and self.clock:now() or 0, kind = kind }
    for k, v in pairs(fields) do rec[k] = v end
    self.events[#self.events + 1] = rec
  end)
  self.player.catalog = catalog
  -- Applied before any event is recorded or clock is attached: the starting state.
  for _, p in ipairs(cfg.professions or {}) do self.player:learn_skill(p.name, p.rank, p.max) end
  self.events = {}
  self.log = QuestLog.new(self)
  return self
end

return World
