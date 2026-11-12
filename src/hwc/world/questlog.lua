-- The simulated quest log (design spec §5): 40 slots (Forever cap), history of
-- turned-in quests, and per-objective progress. Quest facts come from the catalog.
--
-- Ruling Z: an item objective's progress is the bag count, as in the game (an item
-- objective's numFulfilled is how many the bags hold), so it is derived from the
-- player's bags on every read (have, is_complete, turn_in and the quest-log stubs),
-- never stored. Other objectives (npc, object, other) keep their stored progress.
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

-- An objective that follows the bags: kind item with at least one item id.
local function follows_bags(obj)
  return obj.kind == "item" and type(obj.ids) == "table" and obj.ids[1] ~= nil
end

-- The listed id the bags hold most of (any listed id counts) and that count.
local function held(player, obj)
  local best_id, best_n = obj.ids[1], 0
  for _, id in ipairs(obj.ids) do
    local n = player:item_count(id)
    if n > best_n then best_id, best_n = id, n end
  end
  return best_id, best_n
end

-- Objective index's progress for an in-log quest (0 when not in the log).
function QuestLog:have(qid, index)
  local e = self.entries_by_id[qid]
  local obj = e and e.quest.objectives[index]
  if not obj then return 0 end
  if follows_bags(obj) then
    local _, n = held(self.world.player, obj)
    return math.min(obj.count, n)
  end
  return e.have[index]
end

-- Every objective's progress, in objective order.
function QuestLog:haves(qid)
  local e = self.entries_by_id[qid]
  local out = {}
  if not e then return out end
  for i = 1, #e.quest.objectives do out[i] = self:have(qid, i) end
  return out
end

-- True when id is an item an in-log quest's item objective counts.
function QuestLog:counts_item(id)
  for _, qid in ipairs(self.order) do
    for _, obj in ipairs(self.entries_by_id[qid].quest.objectives or {}) do
      if follows_bags(obj) then
        for _, x in ipairs(obj.ids) do
          if x == id then return true end
        end
      end
    end
  end
  return false
end

-- Non-item objectives only: an item objective's progress is the bag count, so the
-- caller changes the bags instead (returns false, "item-objective").
function QuestLog:progress(qid, index, amount)
  local e = self.entries_by_id[qid]
  local obj = e and e.quest.objectives[index]
  if not obj then return false end
  if type(amount) ~= "number" or amount < 0 then return false, "bad-amount" end
  if follows_bags(obj) then return false, "item-objective" end
  e.have[index] = math.min(obj.count, e.have[index] + amount)
  self:_record("quest_progress", { id = qid, index = index, have = e.have[index] })
  return true
end

-- indices nil means every objective. An item objective gets its missing items in
-- the bags (its progress is the bag count). Returns ok, bags_changed.
function QuestLog:complete_objectives(qid, indices)
  local e = self.entries_by_id[qid]
  if not e then return false end
  local bags = false
  for i, obj in ipairs(e.quest.objectives) do
    if indices == nil or contains(indices, i) then
      if follows_bags(obj) then
        local id, n = held(self.world.player, obj)
        if n < obj.count then
          self.world.player:add_item(id, obj.count - n)
          bags = true
        end
      else
        e.have[i] = obj.count
        self:_record("quest_progress", { id = qid, index = i, have = obj.count })
      end
    end
  end
  return true, bags
end

function QuestLog:is_complete(qid)
  local e = self.entries_by_id[qid]
  if not e then return false end
  for i, obj in ipairs(e.quest.objectives) do
    if self:have(qid, i) < obj.count then return false end
  end
  return true
end

local function remove(self, qid)
  self.entries_by_id[qid] = nil
  for i, id in ipairs(self.order) do
    if id == qid then table.remove(self.order, i); break end
  end
end

-- Returns ok, reason, xp_gained, levels_gained, bags_changed.
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
  -- The client takes the collected objective items on turn-in (the id the bags hold).
  local bags = false
  for _, obj in ipairs(quest.objectives or {}) do
    if follows_bags(obj) then
      local id = held(player, obj)
      if player:remove_item(id, obj.count) then bags = true end
    end
  end
  -- The item the quest starter handed over (QuestieDB sourceItemId) goes on turn-in
  -- when still held. Not verifiable from the addon or the catalog; this follows the
  -- server's quest reward code as recalled (cmangos Player::RewardQuest destroys the
  -- quest's SrcItemId) and is unverified.
  local src = quest.source_item
  if src and player:item_count(src) > 0 and player:remove_item(src, player:item_count(src)) then bags = true end
  self.history[qid] = true
  remove(self, qid)
  self:_record("quest_turn_in", { id = qid, xp = gained, levels = levels })
  return true, nil, gained, levels, bags
end

-- Marks a turn-in the client did without a guide step (Camping 101, spec §5.2).
function QuestLog:record_abstracted_turnin(qid)
  self:_record("abstracted-turnin", { id = qid })
end

-- Leaves the bags alone (Ruling Z: as the client does; the server may take a
-- source item back, which is not modelled). The driver never abandons.
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
