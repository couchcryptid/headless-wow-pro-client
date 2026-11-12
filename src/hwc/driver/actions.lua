-- Quest step actions (design spec §5.2): what a player does for an A, C/K or T
-- step, as world changes plus the events the client fires for them.
--
-- Fidelity: nothing here writes engine state. The engine is touched only by
-- firing events, settling the virtual clock and the player-equivalent
-- E:update_guide() after a level-up (the addon has no level-up handler).
--
-- Event sequences, checked against the handlers in ~/Projects/WoW-Pro-Guides:
--   QUEST_ACCEPTED(qlidx, qid)  WoWPro_Events.lua:783-793 (args read at :784); with
--       AutoAccept and GetTitleText() == the A step's name it runs
--       AutoCompleteQuestUpdate(nil) (:788-792), hence world.dialog = detail.
--   QUEST_LOG_UPDATE            WoWPro_Events.lua:881-905: PopulateQuestLog's diff
--       drives AutoCompleteQuestUpdate (AutoComplete.lua:317-399; "via QuestLog"
--       :368-380, partial QO completion :382-399) and UpdateGuide (:896).
--   BAG_UPDATE(bag)             WoWPro.lua:615, bucketed into AutoCompleteLoot
--       (AutoComplete.lua:251-277).
--   QUEST_TURNED_IN(qid, xp, money)  WoWPro_Events.lua:772-781: sets CompletingQuest,
--       then AutoCompleteQuestUpdate(qid) (:780) completes the T step (AutoComplete.lua
--       :356-366); the following QUEST_LOG_UPDATE's diff sets missingQuest
--       (Broker.lua:4103-4115) for the turn-in branch (AutoComplete.lua:339-347).
--   SKILL_LINES_CHANGED         WoWPro_Events.lua:796-798 (UpdateTradeSkills).
--
-- Multi-QID steps (QID|179^180): the engine treats a step as satisfied when
-- any listed id is involved: the A test is QIDsInTable(QID, QuestLog), any of
-- "^&" (WoWPro_Events.lua:709; Broker.lua:266-275), and AutoCompleteQuestUpdate
-- walks every listed id for the T/C branches (AutoComplete.lua:329-336). So A
-- accepts the first listed id the world allows (alternatives such as
-- 5926^5927^5928 are race/class variants); C/K/T act on the first listed id in
-- the log (qids[1] when none is).
local kills = require("hwc.world.kills")

local actions = {}

-- Training Cooking at the trainer (Camping 101: Cooking): Apprentice, 1/75.
local TRAINED_RANK, TRAINED_MAX = 1, 75

local function new_outcome(qid)
  return { kind = "noop", qid = qid, events = {}, levels = 0, elite = false }
end

local function fire(ctx, out, event, ...)
  ctx.engine:fire(event, ...)
  out.events[#out.events + 1] = event
end

-- Forces the engine to re-evaluate after a ding (spec §5.2 "Level-up"). An addon
-- error is recorded in sb.errors by the adapter; the action carries on.
local function after_levels(ctx, levels)
  if levels and levels > 0 then ctx.engine:update_guide() end
end

local function log_index(world, qid)
  for i, e in ipairs(world.log:entries()) do
    if e.id == qid then return i end
  end
  return nil
end

-- The step's QO tag (engine key "questtext", Parser.lua:511), ";"-separated as the
-- engine splits it (AutoComplete.lua:385-388). Each part follows the engine's
-- OBJECTIVE_PATTERN "^(%d*)([<=>]*)(%d*)$" (Broker.lua:369): N, N>k / N>=k (count
-- >= k), N=k, N<k / N<=k (count <= k) (Broker.lua:420-441, 532-551).
-- Returns a list of { index, op, target } or nil without a QO tag.
local function parse_qo(questtext)
  if type(questtext) ~= "string" then return nil end
  local out = {}
  for part in questtext:gmatch("[^;]+") do
    local n, op, target = part:match("^(%d*)([<=>]*)(%d*)$")
    n = tonumber(n)
    if n then out[#out + 1] = { index = n, op = op or "", target = tonumber(target) } end
  end
  return out
end

-- Placeholder objective count: enough objectives for every QO index the step names.
local function placeholder_count(qo)
  local n = 0
  for _, o in ipairs(qo or {}) do
    if o.index > n then n = o.index end
  end
  return math.max(n, qo and #qo or 0)
end

local function in_log_qid(world, qids)
  for _, q in ipairs(qids) do
    if world.log:get(q) then return q end
  end
  return qids[1]
end

local function is_camping(quest)
  return type(quest.name) == "string" and quest.name:sub(1, 11) == "Camping 101"
end

local function guide_turns_in(engine, qid)
  for i = 1, engine:num_steps() do
    local s = engine:step(i)
    if s and s.action == "T" then
      for _, q in ipairs(s.qids or {}) do
        if q == qid then return true end
      end
    end
  end
  return false
end

local function train(ctx, out, skill)
  local player = ctx.world.player
  if player:knows_skill(skill) then return end
  player:learn_skill(skill, TRAINED_RANK, TRAINED_MAX)
  fire(ctx, out, "SKILL_LINES_CHANGED")
end

-- Turn-in under the NPC's reward dialog. Returns ok, reason.
local function turn_in(ctx, out, qid)
  local w = ctx.world
  w.dialog = { qid = qid, kind = "complete" }
  local ok, reason, gained, levels = w.log:turn_in(qid)
  if not ok then
    w.dialog = nil
    return false, reason
  end
  out.levels = out.levels + levels
  fire(ctx, out, "QUEST_TURNED_IN", qid, gained, 0)
  fire(ctx, out, "QUEST_LOG_UPDATE")
  after_levels(ctx, levels)
  w.dialog = nil
  return true
end

local function accept_opts(w, qid, qo)
  if w.catalog and w.catalog:quest(qid) then return nil end
  return { placeholder_qo = placeholder_count(qo) }
end

-- Picks the id to accept from a multi-QID A step (any-of, as the engine's own
-- QIDsInTable test at WoWPro_Events.lua:709): the first id acceptable now, else
-- the first id whose only refusal is below-level (acceptable after a grind).
-- Returns qid, opts, needs_grind; or nil, first id's reason when every id is refused.
local function choose_accept(w, qids, qo)
  local first_reason, grind_qid, grind_opts
  for _, qid in ipairs(qids) do
    local opts = accept_opts(w, qid, qo)
    local reason = w.log:refusal(qid, opts)
    if not reason then return qid, opts, false end
    first_reason = first_reason or reason
    if reason == "below-level" and not grind_qid then
      local other = w.log:refusal(qid, { placeholder_qo = opts and opts.placeholder_qo, ignore_level = true })
      if not other then grind_qid, grind_opts = qid, opts end
    end
  end
  if grind_qid then return grind_qid, grind_opts, true end
  -- Every id refused: the first id's reason, the world unchanged (no grind for a
  -- quest the player can't take even once levelled).
  if first_reason == "below-level" then
    local o = accept_opts(w, qids[1], qo)
    first_reason = w.log:refusal(qids[1], { placeholder_qo = o and o.placeholder_qo, ignore_level = true }) or first_reason
  end
  return nil, first_reason
end

local function perform_accept(ctx, step, out)
  local w = ctx.world
  local qo = parse_qo(step.tags and step.tags.questtext)
  local qid, opts, needs_grind = choose_accept(w, step.qids, qo)
  if not qid then
    local reason = opts
    out.qid = step.qids[1]
    out.kind, out.reason = (reason == "already-in-log") and "noop" or "refused", reason
    return
  end
  out.qid = qid

  if needs_grind then
    -- Under-levelled only (spec §5.2): grind generic mobs to the required level,
    -- fire nothing until the ding, force the update, then accept.
    local target = w.catalog:quest(qid).required_level
    local n, _, levels = kills.grind_to(w.player, target)
    out.grind = { kills = n, to = target }
    out.levels = out.levels + levels
    after_levels(ctx, levels)
  end
  local ok, reason = w.log:accept(qid, opts)
  if not ok then
    out.kind, out.reason = "refused", reason
    return
  end

  out.kind = "acted"
  w.dialog = { qid = qid, kind = "detail" }
  fire(ctx, out, "QUEST_ACCEPTED", log_index(w, qid), qid)
  fire(ctx, out, "QUEST_LOG_UPDATE")
  w.dialog = nil

  -- Camping 101 (spec §5.2): the client abstracts levelling the profession and
  -- turns the quest in at once, unless the guide has its own T step or the
  -- character lacks the gating skill. No skill is trained here: the baseline
  -- trains only when a guide step says so (spec §11), and Cooking has no
  -- requires_skill gate, so it is turned in without learning Cooking.
  local quest = w.log:get(qid).quest
  if not is_camping(quest) or guide_turns_in(ctx.engine, qid) then return end
  if quest.requires_skill and not w.player:knows_skill(quest.requires_skill) then return end
  w.log:complete_objectives(qid, nil)
  local done, why = turn_in(ctx, out, qid)
  if done then
    w.log:record_abstracted_turnin(qid)
  else
    out.reason = why -- accepted, but the abstracted turn-in was refused; it stays in the log
  end
end

-- Credits one objective's progress delta: kill XP (drop kills for items) and the items.
local function credit_objective(ctx, obj, delta)
  local w = ctx.world
  local party = (ctx.cfg and ctx.cfg.party_size) or 1
  local partial = { kind = obj.kind, ids = obj.ids, count = delta }
  local k = kills.objective_kills(w.catalog, partial)
  local levels, elite = 0, false
  if k then
    local _, l = kills.credit(w.player, k, party)
    levels, elite = l, k.elite
  end
  local items = false
  if obj.kind == "item" and obj.ids and obj.ids[1] then
    w.player:add_item(obj.ids[1], delta)
    items = true
  end
  return levels, elite, items
end

-- The have-count a QO part asks for (Broker.lua:420-441 operator semantics).
local function wanted(obj, have, part)
  if not part or part.op == "" or part.target == nil then return obj.count end
  if part.op == ">" or part.op == ">=" or part.op == "=" then return math.min(obj.count, part.target) end
  return have -- "<" / "<=": already satisfied by not progressing
end

local function perform_objectives(ctx, step, out)
  local w = ctx.world
  local qid = in_log_qid(w, step.qids)
  out.qid = qid
  local entry = w.log:get(qid)
  if not entry then
    out.kind, out.reason = "refused", "not-in-log"
    return
  end
  out.kind = "acted"
  local quest = entry.quest
  if is_camping(quest) and quest.completed_by_training then train(ctx, out, quest.completed_by_training) end

  -- QO indices are 1-based and matched to the catalog objectives by order;
  -- without QO every objective is done.
  local parts = parse_qo(step.tags and step.tags.questtext)
  local todo = {}
  if parts then
    for _, p in ipairs(parts) do todo[#todo + 1] = { index = p.index, part = p } end
  else
    for i = 1, #quest.objectives do todo[#todo + 1] = { index = i } end
  end

  local items_changed = false
  for _, t in ipairs(todo) do
    local obj = quest.objectives[t.index]
    if obj then
      local have = entry.have[t.index]
      local delta = wanted(obj, have, t.part) - have
      if delta > 0 then
        local levels, elite, items = credit_objective(ctx, obj, delta)
        w.log:progress(qid, t.index, delta)
        out.levels = out.levels + levels
        out.elite = out.elite or elite
        items_changed = items_changed or items
      end
    end
  end

  fire(ctx, out, "QUEST_LOG_UPDATE")
  if items_changed then fire(ctx, out, "BAG_UPDATE", 0) end
  after_levels(ctx, out.levels)
end

local function perform_turn_in(ctx, step, out)
  local qid = in_log_qid(ctx.world, step.qids)
  out.qid = qid
  local ok, reason = turn_in(ctx, out, qid)
  if ok then out.kind = "acted" else out.kind, out.reason = "refused", reason end
end

local HANDLERS = { A = perform_accept, C = perform_objectives, K = perform_objectives, T = perform_turn_in }

-- ctx = { engine = E, world = W, cfg = cfg }; step is an Engine:step() record.
-- Returns { kind = "acted"|"refused"|"noop", reason, qid, events = {names...},
-- levels, grind = {kills, to}|nil, elite, settle = <E:settle() result> }.
-- Every call settles exactly once at the end and leaves world.dialog nil.
function actions.perform(ctx, step)
  local qids = step.qids or {}
  local out = new_outcome(qids[1])
  local handler = HANDLERS[step.action]
  if not handler then
    out.reason = "not-a-quest-action"
  elseif #qids == 0 then
    out.reason = "no-qid"
  else
    handler(ctx, step, out)
  end
  out.elite = out.elite or (step.tags ~= nil and step.tags.elite ~= nil and step.tags.elite ~= false)
  out.settle = ctx.engine:settle()
  ctx.world.dialog = nil
  return out
end

return actions
