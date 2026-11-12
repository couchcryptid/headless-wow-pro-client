-- The simulated quest log (design spec §5): 40 slots (Forever cap), history of
-- turned-in quests, and per-objective progress. Quest facts come from the catalog.
local xp = require("hwc.world.xp")

local QuestLog = {}
QuestLog.__index = QuestLog

QuestLog.SIZE = 40

function QuestLog.new(world)
  return setmetatable({ world = world, order = {}, entries_by_id = {}, history = {} }, QuestLog)
end

function QuestLog:_record(kind, fields)
  local w = self.world
  local rec = { t = w.clock and w.clock:now() or 0, kind = kind }
  for k, v in pairs(fields) do rec[k] = v end
  w.events[#w.events + 1] = rec
end

local function contains(list, v)
  for _, x in ipairs(list) do
    if x == v then return true end
  end
  return false
end

-- The refusal reason accept would give, or nil, quest when it would succeed.
-- opts.ignore_level skips the level check (the grind-then-accept path asks
-- whether levelling alone would make the quest acceptable).
function QuestLog:refusal(qid, opts)
  local w, player = self.world, self.world.player
  local quest = w.catalog and w.catalog:quest(qid)
  if not quest and opts and opts.placeholder_qo and w.catalog then
    quest = w.catalog:placeholder(qid, opts.placeholder_qo)
  end
  if not quest then return "unknown-quest" end
  if self.entries_by_id[qid] then return "already-in-log" end
  if self.history[qid] then return "already-completed" end
  if #self.order >= QuestLog.SIZE then return "log-full" end
  if not (opts and opts.ignore_level) and player.level < (quest.required_level or 1) then return "below-level" end
  if quest.races and not contains(quest.races, player.race_token) then return "race" end
  if quest.classes and not contains(quest.classes, player.class_token) then return "class" end
  if quest.pre_single and #quest.pre_single > 0 then
    local any = false
    for _, p in ipairs(quest.pre_single) do
      if self.history[p] then any = true end
    end
    if not any then return "prerequisite" end
  end
  for _, p in ipairs(quest.pre_group or {}) do
    if not self.history[p] then return "prerequisite" end
  end
  return nil, quest
end

-- opts.placeholder_qo = n shapes an unknown quest from the guide step's QO count (catalog:placeholder).
function QuestLog:accept(qid, opts)
  local reason, quest = self:refusal(qid, opts and { placeholder_qo = opts.placeholder_qo })
  if reason then return false, reason end
  local have = {}
  for i = 1, #(quest.objectives or {}) do have[i] = 0 end
  self.entries_by_id[qid] = { id = qid, quest = quest, have = have }
  self.order[#self.order + 1] = qid
  self:_record("quest_accept", { id = qid })
  return true
end

function QuestLog:get(qid) return self.entries_by_id[qid] end

function QuestLog:progress(qid, index, amount)
  local e = self.entries_by_id[qid]
  local obj = e and e.quest.objectives[index]
  if not obj then return false end
  if type(amount) ~= "number" or amount < 0 then return false, "bad-amount" end
  e.have[index] = math.min(obj.count, e.have[index] + amount)
  self:_record("quest_progress", { id = qid, index = index, have = e.have[index] })
  return true
end

-- indices nil means every objective.
function QuestLog:complete_objectives(qid, indices)
  local e = self.entries_by_id[qid]
  if not e then return false end
  for i, obj in ipairs(e.quest.objectives) do
    if indices == nil or contains(indices, i) then
      e.have[i] = obj.count
      self:_record("quest_progress", { id = qid, index = i, have = obj.count })
    end
  end
  return true
end

function QuestLog:is_complete(qid)
  local e = self.entries_by_id[qid]
  if not e then return false end
  for i, obj in ipairs(e.quest.objectives) do
    if e.have[i] < obj.count then return false end
  end
  return true
end

local function remove(self, qid)
  self.entries_by_id[qid] = nil
  for i, id in ipairs(self.order) do
    if id == qid then table.remove(self.order, i); break end
  end
end

-- Returns ok, reason, xp_gained, levels_gained.
function QuestLog:turn_in(qid)
  local e = self.entries_by_id[qid]
  if not e then return false, "not-in-log" end
  if not self:is_complete(qid) then return false, "incomplete" end
  local player = self.world.player
  local quest = e.quest
  -- Camping gate: the quest is refused without the profession.
  if quest.requires_skill and not player:knows_skill(quest.requires_skill) then
    return false, "requires-skill"
  end
  local gained = xp.quest_xp(quest.xp or 0, player.level, quest.level or player.level)
  local levels = player:add_xp(gained)
  -- The client takes the collected objective items on turn-in.
  for _, obj in ipairs(quest.objectives or {}) do
    if obj.kind == "item" and obj.ids and obj.ids[1] then player:remove_item(obj.ids[1], obj.count) end
  end
  self.history[qid] = true
  remove(self, qid)
  self:_record("quest_turn_in", { id = qid, xp = gained, levels = levels })
  return true, nil, gained, levels
end

function QuestLog:abandon(qid)
  if not self.entries_by_id[qid] then return false end
  remove(self, qid)
  self:_record("quest_abandon", { id = qid })
  return true
end

-- Entries in acceptance order, dense 1..n.
function QuestLog:entries()
  local out = {}
  for i, id in ipairs(self.order) do out[i] = self.entries_by_id[id] end
  return out
end

return QuestLog
