-- One character's reputation (design spec 2026-11-18-reputation-design.md §4.2, §4.5),
-- built on the pure rules in hwc.world.reputation. Points for the factions the
-- character knows, the changes quest rewards made, and the faction ids the
-- C_Reputation stub was asked for (`lookups`) and those it returned nil for because
-- the character hadn't met them (`unmet_lookups`); the stub writes both.
local reputation = require("hwc.world.reputation")

local ReputationState = {}
ReputationState.__index = ReputationState

local SCALING = "reward scaling by level is unverified for Forever"

-- names: { [id] = name } or function(id) -> name; any id without one shows as "Faction <id>".
-- The second argument (the faction side) is ignored: the start table follows the race.
function ReputationState.new(race_key, _, names)
  local start, inferred = reputation.start(race_key)
  return setmetatable({
    race_key = race_key, _names = names,
    _points = start, _inferred = inferred, _assumed_met = {},
    changes = {}, lookups = {}, unmet_lookups = {},
  }, ReputationState)
end

function ReputationState:name(id)
  local n = self._names
  if type(n) == "function" then n = n(id) elseif type(n) == "table" then n = n[id] end
  return n or ("Faction " .. tostring(id))
end

-- nil for a faction the character hasn't met.
function ReputationState:points(id) return self._points[id] end

function ReputationState:known(id) return self._points[id] ~= nil end

-- An unmet faction is compared at its met-at value: the server holds a value before
-- the client lists the faction (design §4.5, builder's call).
function ReputationState:value_for_gate(id)
  local p = self._points[id]
  if p ~= nil then return p end
  return (reputation.met_at(id))
end

-- Adds value to a faction, meeting it first at its met-at value. Returns the new
-- points and whether this call met the faction at an assumed value.
-- The value applies in full: no racial bonus (Human Diplomacy was removed in Forever;
-- user, 2026-11-18) and no scaling by level (none known either way; unverified for Forever).
function ReputationState:gain(id, value)
  local assumed_start = false
  if self._points[id] == nil then
    local start, assumed = reputation.met_at(id)
    self._points[id] = start
    if assumed then
      self._assumed_met[id] = true
      assumed_start = true
    end
  end
  self._points[id] = reputation.clamp(self._points[id] + value)
  return self._points[id], assumed_start
end

-- One quest reward: the gain, recorded in turn-in order for the run log.
function ReputationState:reward(qid, id, value)
  local total, assumed_start = self:gain(id, value)
  self.changes[#self.changes + 1] = { qid = qid, faction = id, value = value, total = total, assumed_start = assumed_start }
  return total
end

-- The quest's failing reputation gate, or nil when both pass:
-- { faction, bound = "min"|"max", value, points }. min_rep needs points >= value;
-- max_rep needs points < value (QuestieDB requiredMinRep/requiredMaxRep).
function ReputationState:gate(quest)
  local min, max = quest.min_rep, quest.max_rep
  if min then
    local p = self:value_for_gate(min.faction)
    if p < min.value then return { faction = min.faction, bound = "min", value = min.value, points = p } end
  end
  if max then
    local p = self:value_for_gate(max.faction)
    if p >= max.value then return { faction = max.faction, bound = "max", value = max.value, points = p } end
  end
  return nil
end

-- The assumptions in force for this run, as findings-header gap lines (design §4.5).
function ReputationState:assumptions()
  local out = {}
  if self._inferred then
    out[#out + 1] = "starting reputation for " .. self.race_key .. " is inferred, not captured"
  end
  local names = {}
  for id in pairs(self._assumed_met) do names[#names + 1] = self:name(id) end
  if #names > 0 then
    table.sort(names)
    out[#out + 1] = "factions first met at an assumed Neutral 0: " .. table.concat(names, ", ")
  end
  if #self.changes > 0 then out[#out + 1] = SCALING end
  return out
end

return ReputationState
