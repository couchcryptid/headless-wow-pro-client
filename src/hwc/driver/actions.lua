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
--   ZONE_CHANGED / ZONE_CHANGED_NEW_AREA  WoWPro_Events.lua:301-316 (also _INDOORS): the
--       handler runs AutoCompleteZone (AutoComplete.lua:488-530), which matches the
--       step name or TZ against GetZoneText / GetSubZoneText and the map id.
--   TAXIMAP_OPENED              WoWPro_Events.lua:806-815 (F/b: RecordTaxiLocations).
--   HEARTHSTONE_BOUND           WoWPro_Events.lua:861-872 reads GetBindLocation() and runs
--       AutoCompleteSetHearth.
--   UI_INFO_MESSAGE(idx, msg)   WoWPro_Events.lua:908-911; AutoCompleteGetFP reads
--       `_event, _idx, msg` and tests msg == ERR_NEWTAXIPATH (AutoComplete.lua:94-98).
--
-- Tag value forms (WoWPro_Parser.lua DefineTag, 416-620; the engine stores the parsed
-- value under the key name): Z "1426; Dun Morogh" | "1426" | name (:483, raw string);
-- M "x,y" / "x,y;x,y" / "PLAYER" (:481, raw); L {[itemID]=qty} (:491-504; the setter
-- splits on ";" and reads "(%d+)%s?(%-?%d*)", count default 1); U list of ints (:529);
-- LVL "n" (:547); P "Name;id;lvl..." (:548, WoWPro_Broker.lua:2738); SPELL
-- "Name; spellID; flip" (:553, WoWPro_Broker.lua:3332, tested with IsPlayerSpell).
--
-- Multi-QID steps (QID|179^180): the engine treats a step as satisfied when
-- any listed id is involved: the A test is QIDsInTable(QID, QuestLog), any of
-- "^&" (WoWPro_Events.lua:709; Broker.lua:266-275), and AutoCompleteQuestUpdate
-- walks every listed id for the T/C branches (AutoComplete.lua:329-336). So A is
-- a noop (already-in-log / already-completed, Ruling J) when ANY listed id is in
-- the log or completed, and otherwise accepts the first listed id the world allows
-- (alternatives such as 5926^5927^5928 are race/class variants); C/K/T act on the
-- first listed id in the log (qids[1] when none is).
local kills = require("hwc.world.kills")
local stubs_core = require("hwc.stubs.core")

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

-- Bag changes (Ruling Z). An item objective's progress is the bag count, so a bag
-- change that moves an in-log quest's item objective is also a quest-log change:
-- the client fires QUEST_LOG_UPDATE with the BAG_UPDATE (the engine re-reads the quest
-- log on QUEST_LOG_UPDATE, WoWPro_Events.lua:888 on main). Every bag change in
-- an action goes through add_item / remove_item, which mark the first event index
-- after such a change; actions.perform fires QUEST_LOG_UPDATE at the end when none
-- followed the mark. The in-game order of the two events is not confirmed.
local function mark_bags(ctx, out, id)
  if out.objective_mark == nil and ctx.world.log:counts_item(id) then out.objective_mark = #out.events end
end

local function add_item(ctx, out, id, n)
  ctx.world.player:add_item(id, n)
  mark_bags(ctx, out, id)
end

local function remove_item(ctx, out, id, n)
  if not ctx.world.player:remove_item(id, n) then return false end
  mark_bags(ctx, out, id)
  return true
end

local function finish_bags(ctx, out)
  local mark = out.objective_mark
  out.objective_mark = nil
  if mark == nil then return end
  for i = mark + 1, #out.events do
    if out.events[i] == "QUEST_LOG_UPDATE" then return end
  end
  fire(ctx, out, "QUEST_LOG_UPDATE")
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
-- Returns a list of { index, op, target }, or nil without a QO tag or when no part
-- parses (treated as no QO: the engine's ValidObjective rejects such parts too,
-- WoWPro_Broker.lua:381-391 called at WoWPro_AutoComplete.lua:405 on main, so it
-- cannot complete the step by them).
local function parse_qo(questtext)
  if type(questtext) ~= "string" then return nil end
  local out = {}
  for part in questtext:gmatch("[^;]+") do
    local n, op, target = part:match("^(%d*)([<=>]*)(%d*)$")
    n = tonumber(n)
    if n then out[#out + 1] = { index = n, op = op or "", target = tonumber(target) } end
  end
  if #out == 0 then return nil end
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
  for _, q in ipairs(qids or {}) do
    if world.log:get(q) then return q end
  end
  return qids and qids[1]
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

-- What training teaches (spec §5.2 train row): fires SKILL_LINES_CHANGED and
-- SPELLS_CHANGED once when anything was learned. learn = { skill = name, spell = id }.
local function train(ctx, out, learn)
  local player = ctx.world.player
  local changed = false
  if learn.skill and not player:knows_skill(learn.skill) then
    player:learn_skill(learn.skill, TRAINED_RANK, TRAINED_MAX)
    changed = true
  end
  if learn.spell and not player.spells[learn.spell] then
    player:learn_spell(learn.spell)
    changed = true
  end
  if changed then
    fire(ctx, out, "SKILL_LINES_CHANGED")
    fire(ctx, out, "SPELLS_CHANGED")
  end
  return changed
end

-- Turn-in under the NPC's reward dialog. Returns ok, reason.
local function turn_in(ctx, out, qid)
  local w = ctx.world
  w.dialog = { qid = qid, kind = "complete" }
  local ok, reason, gained, levels, bags = w.log:turn_in(qid)
  if not ok then
    w.dialog = nil
    return false, reason
  end
  out.levels = out.levels + levels
  fire(ctx, out, "QUEST_TURNED_IN", qid, gained, 0)
  fire(ctx, out, "QUEST_LOG_UPDATE")
  -- The objective items (and a held source item) left the bags with the turn-in.
  if bags then fire(ctx, out, "BAG_UPDATE", 0) end
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
  -- Ruling J: the engine treats the step as satisfied when ANY listed id is in the log
  -- or completed (WoWPro_Events.lua:709), so never accept a later alternative.
  for _, q in ipairs(step.qids) do
    local why = w.log:refusal(q, accept_opts(w, q, qo))
    if why == "already-in-log" or why == "already-completed" then
      out.qid, out.kind, out.reason = q, "noop", why
      return
    end
  end
  local qid, opts, needs_grind = choose_accept(w, step.qids, qo)
  if not qid then
    local reason = opts
    out.qid = step.qids[1]
    out.kind, out.reason = "refused", reason
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
  -- A quest whose starter hands over an item (catalog source_item, QuestieDB sourceItemId) puts it
  -- in the bags with the accept: e.g. Elemental Bracers (1016) gives the Divining Scroll (5456)
  -- that its U step uses, and the engine shows a U step only while the U item is in the bags
  -- (WoWPro_Broker.lua NextStep, SelectItemToUse). BAG_UPDATE after the accept events: the in-game
  -- order of the item push against QUEST_ACCEPTED is not confirmed.
  local src = w.log:get(qid).quest.source_item
  if src and w.player:item_count(src) == 0 then
    add_item(ctx, out, src, 1)
    fire(ctx, out, "BAG_UPDATE", 0)
  end

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
    out.abstracted_turnin = qid -- the run log's snapshot carries it (spec §5.2)
  else
    out.reason = why -- accepted, but the abstracted turn-in was refused; it stays in the log
  end
end

-- Credits one objective's progress delta: kill XP (drop kills for items) and the items.
local function credit_objective(ctx, out, quest, obj, delta)
  local w = ctx.world
  local party = (ctx.cfg and ctx.cfg.party_size) or 1
  local partial = { kind = obj.kind, ids = obj.ids, count = delta }
  local k = w.catalog and kills.objective_kills(w.catalog, partial, quest)
  local levels, elite = 0, false
  if k then
    local _, l = kills.credit(w.player, k, party)
    levels, elite = l, k.elite
  end
  local items = false
  if obj.kind == "item" and obj.ids and obj.ids[1] then
    add_item(ctx, out, obj.ids[1], delta)
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

local parse_loot -- defined with the tag parsers below

-- Ruling M: the item objectives a no-QO C/K step names through its item tags: the
-- engine-parsed L tag (loot, credited to the tag's count) or a raw B|<id> in the
-- step's guide source line (buy). The engine defines no B tag (WoWPro_Parser.lua:795
-- logs it as unknown), so it is read from the source line; global constraints allow a
-- step's own item tags to say what the player buys or loots. The old simulator did
-- the same for L (sim.py:840-843). Returns a todo list, or nil when no tag names one.
local function tagged_item_objectives(ctx, step, quest)
  local loot = {}
  for _, it in ipairs(parse_loot(step.tags and step.tags.lootitem)) do loot[it.id] = it.n end
  local bought = {}
  local raw = ctx.engine.source_line and ctx.engine:source_line(step)
  if type(raw) == "string" then
    for id in (raw .. "|"):gmatch("|B|(%d+)") do bought[tonumber(id)] = true end
  end
  local todo = {}
  for i, obj in ipairs(quest.objectives or {}) do
    if obj.kind == "item" then
      for _, id in ipairs(obj.ids or {}) do
        if bought[id] then
          todo[#todo + 1] = { index = i, bought = true }
          break
        elseif loot[id] then
          todo[#todo + 1] = { index = i, cap = math.min(obj.count, loot[id]) }
          break
        end
      end
    end
  end
  return #todo > 0 and todo or nil
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
  if is_camping(quest) and quest.completed_by_training then train(ctx, out, { skill = quest.completed_by_training }) end

  -- QO indices are 1-based and matched to the catalog objectives by order;
  -- without QO every objective is done.
  local parts = parse_qo(step.tags and step.tags.questtext)
  local todo = {}
  if parts then
    for _, p in ipairs(parts) do todo[#todo + 1] = { index = p.index, part = p } end
  else
    todo = tagged_item_objectives(ctx, step, quest)
    if not todo then
      todo = {}
      for i = 1, #quest.objectives do todo[#todo + 1] = { index = i } end
    end
  end

  local items_changed = false
  for _, t in ipairs(todo) do
    local obj = quest.objectives[t.index]
    if obj then
      local have = w.log:have(qid, t.index)
      local delta = (t.cap or wanted(obj, have, t.part)) - have
      if delta > 0 and t.bought then
        -- Bought, not looted: the item (its progress is the bag count), no drop kills.
        add_item(ctx, out, obj.ids[1], delta)
        items_changed = true
      elseif delta > 0 then
        local levels, elite, items = credit_objective(ctx, out, quest, obj, delta)
        -- An item objective's progress is the bag count credit_objective just changed.
        if not items then w.log:progress(qid, t.index, delta) end
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

-- Tag parsing -------------------------------------------------------------

local function first_part(value)
  if type(value) ~= "string" then return nil end
  local p = value:match("^%s*([^;]*)")
  p = p and p:gsub("^%s+", ""):gsub("%s+$", "")
  if p == "" then return nil end
  return p
end

-- Z: "1426; Dun Morogh" | "1426" | zone name -> zone name or nil, map id or nil.
local function parse_zone(value)
  if type(value) ~= "string" then return nil, nil end
  local head, rest = value:match("^%s*([^;]*);?(.*)$")
  head = head:gsub("%s+$", "")
  rest = rest:gsub("^%s+", ""):gsub("%s+$", "")
  local id = tonumber(head)
  if id then return (rest ~= "" and rest or nil), id end
  return (head ~= "" and head or nil), nil
end

-- M: first "x,y" pair, percent -> fraction; nil for "PLAYER" / absent.
local function parse_coords(value)
  if type(value) ~= "string" then return nil, nil end
  local x, y = value:match("^%s*(%d*%.?%d+)%s*,%s*(%d*%.?%d+)")
  if not x then return nil, nil end
  -- Round through text so 46.74 gives the double 0.4674 (not 0.46739999...).
  local function frac(v) return tonumber(string.format("%.6f", tonumber(v) / 100)) end
  return frac(x), frac(y)
end

-- L: { [itemID] = qty } as the engine stores it, or the raw "id qty;id qty" text.
-- Returns a list of { id, n } sorted by id (deterministic).
function parse_loot(value)
  local items = {}
  if type(value) == "table" then
    for id, n in pairs(value) do items[#items + 1] = { id = tonumber(id), n = tonumber(n) or 1 } end
    table.sort(items, function(a, b) return a.id < b.id end)
  elseif type(value) == "string" then
    for pair in value:gmatch("[^;]+") do
      local id, n = pair:match("(%d+)%s?(%-?%d*)")
      if id then items[#items + 1] = { id = tonumber(id), n = tonumber(n) or 1 } end
    end
  end
  return items
end

-- Rules ---------------------------------------------------------------------

-- Ruling Y: F, b and P land the player at the destination. Their Z and M tags say
-- where the player departs from (the flight master, the boat dock), so they are not
-- used. AutoCompleteZone completes F/H/b/P/R when the step name or the TZ tag's
-- first ";" part equals GetZoneText() or GetSubZoneText(), or a numeric TZ equals
-- the map id (WoWPro_AutoComplete.lua:499-526; TZ is DefineTag("TZ","targetzone")
-- at WoWPro_Parser.lua:484). An F step completes there only while
-- UnitOnTaxi("player") is false (:507-512; the stub returns false). TZ joins the
-- Global Constraints' Z/M exception: it says where the player goes.
-- subzone = step name; zone = TZ when it names one, else the current zone; map id
-- = TZ when it is numeric, else the current one; x/y are kept.
local function perform_arrival(ctx, step, out)
  local p = ctx.world.player
  local tz_name, tz_map = parse_zone(step.tags and step.tags.targetzone)
  p:set_zone(tz_name or p.zone, step.name or "", tz_map or p.map_id, p.x, p.y)
  out.kind = "acted"
  if step.action == "F" then fire(ctx, out, "TAXIMAP_OPENED") end
  fire(ctx, out, "ZONE_CHANGED_NEW_AREA")
  fire(ctx, out, "ZONE_CHANGED")
end

-- Spec §5.1: the player's position is the step's M coordinate when it has one. A
-- player walks to every step, so a non-travel step with a Z or M tag moves the
-- player there before its own rule runs. Without this the player stays where the
-- last travel step put them, and a later travel step to the same place completes
-- on the engine's "already there" check (WoWPro_Broker.lua:2531-2537,
-- AutoCompleteZone at WoWPro_AutoComplete.lua:499-526) without being acted on.
-- No Z, no usable M, or the current spot: no move and no zone events.
local TRAVEL = { R = true, F = true, b = true, P = true, H = true }
local function walk_to_step(ctx, step, out)
  if TRAVEL[step.action] then return end
  local tags = step.tags or {}
  local zone, map_id = parse_zone(tags.zone)
  local x, y = parse_coords(tags.map)
  if not (zone or map_id or x) then return end
  local p = ctx.world.player
  -- A new zone or map: the subzone is unknown, so it is cleared. The same zone and map:
  -- the player walks within it and keeps the subzone (the catalog has no subzone for an
  -- arbitrary M). A numeric-only Z keeps the previous zone name (no map-name catalog).
  local same_area = (zone or p.zone) == p.zone and (map_id or p.map_id) == p.map_id
  local to = { zone or p.zone, same_area and p.subzone or "", map_id or p.map_id, x or p.x, y or p.y }
  -- Already standing on that spot (subzone included): stay put.
  if to[1] == p.zone and to[3] == p.map_id and to[4] == p.x and to[5] == p.y then return end
  p:set_zone(to[1], to[2], to[3], to[4], to[5])
  fire(ctx, out, "ZONE_CHANGED_NEW_AREA")
  fire(ctx, out, "ZONE_CHANGED")
end

local function perform_travel(ctx, step, out)
  local p = ctx.world.player
  local tags = step.tags or {}
  local zone, map_id = parse_zone(tags.zone)
  local x, y = parse_coords(tags.map)
  if step.action == "H" then
    -- The hearth takes the player to the bind location (zone = bind name).
    local bind = p.bind
    if bind then
      zone, map_id = bind.name, bind.map_id
    elseif not zone and not map_id then
      out.kind, out.reason = "refused", "no-bind"
      return
    end
  end
  local subzone = (step.action == "R") and (step.name or "") or ""
  p:set_zone(zone or p.zone, subzone, map_id or p.map_id, x or p.x, y or p.y)
  out.kind = "acted"
  fire(ctx, out, "ZONE_CHANGED_NEW_AREA")
  fire(ctx, out, "ZONE_CHANGED")
end

local function perform_flight_point(ctx, step, out)
  ctx.world.player:learn_flight_point(step.name)
  out.kind = "acted"
  fire(ctx, out, "UI_INFO_MESSAGE", 0, stubs_core.ERR_NEWTAXIPATH)
end

local function perform_bind(ctx, step, out)
  local _, map_id = parse_zone(step.tags and step.tags.zone)
  ctx.world.player:set_bind(step.name, map_id or ctx.world.player.map_id)
  out.kind = "acted"
  fire(ctx, out, "HEARTHSTONE_BOUND")
end

-- U: the use item is in the bags (added when missing); a quest in the log gets the C
-- objective rule, then one use item is consumed unless it is also the L item.
local function perform_use(ctx, step, out)
  local w = ctx.world
  local use = tonumber(first_part(step.tags and step.tags.use and tostring(step.tags.use):gsub("[%^&].*", "")))
  out.kind = "acted"
  local is_loot = false
  for _, it in ipairs(parse_loot(step.tags and step.tags.lootitem)) do
    if it.id == use then is_loot = true end
  end
  -- The L tag supplies a use item that is also looted (see apply_item_tag).
  if use and not is_loot and w.player:item_count(use) == 0 then add_item(ctx, out, use, 1) end
  fire(ctx, out, "BAG_UPDATE", 0)
  local qid
  for _, q in ipairs(step.qids or {}) do
    if w.log:get(q) then qid = q; break end
  end
  if not qid then return end
  perform_objectives(ctx, step, out)
  if not use then return end
  if is_loot then return end
  if remove_item(ctx, out, use, 1) then fire(ctx, out, "BAG_UPDATE", 0) end
end

-- l (loot) and B (buy) through the item rule (Ruling Z): the L item is added by
-- apply_item_tag, which runs for every step; a B step with a QO and no L tag buys
-- the item of each QO-named catalog item objective, up to what the QO part asks.
-- The engine completes such a B step by its QO (QID filled from ACTIVE with a QO,
-- WoWPro_Parser.lua:834-836; partial completion, WoWPro_AutoComplete.lua:397-414 on main).
local function perform_item_step(ctx, step, out)
  if step.action ~= "B" or #parse_loot(step.tags and step.tags.lootitem) > 0 then return end
  local parts = parse_qo(step.tags and step.tags.questtext)
  if not parts then return end
  local w = ctx.world
  local qid = in_log_qid(w, step.qids)
  local entry = qid and w.log:get(qid)
  if not entry then return end
  out.qid = qid
  local added = false
  for _, p in ipairs(parts) do
    local obj = entry.quest.objectives[p.index]
    if obj and obj.kind == "item" and obj.ids and obj.ids[1] then
      local have = w.log:have(qid, p.index)
      local delta = wanted(obj, have, p) - have
      if delta > 0 then
        add_item(ctx, out, obj.ids[1], delta)
        added = true
      end
    end
  end
  if not added then return end
  out.kind = "acted"
  fire(ctx, out, "BAG_UPDATE", 0)
end

-- `*` (trash an item): the player destroys the item the step names, every copy held.
-- The step name is the item name, resolved by the catalog (Player:item_count). The
-- engine leaves the step for a right-click, so it is expected manual.
local function perform_trash(ctx, step, out)
  local w = ctx.world
  local id = w.catalog and w.catalog.item_id and w.catalog:item_id(step.name)
  local n = id and w.player:item_count(id) or 0
  if n == 0 then return end
  remove_item(ctx, out, id, n)
  out.kind = "acted"
  fire(ctx, out, "BAG_UPDATE", 0)
end

local function perform_level(ctx, step, out)
  local w = ctx.world
  local want = tonumber(tostring(step.tags and step.tags.level or ""):match("%d+"))
  if not want or w.player.level >= want then return end
  local n, _, levels = kills.grind_to(w.player, want)
  out.kind = "acted"
  out.grind = { kills = n, to = want }
  out.levels = out.levels + levels
  after_levels(ctx, levels)
end

-- The tags every step can carry, applied after the step's own rule.
local function apply_item_tag(ctx, step, out)
  local items = parse_loot(step.tags and step.tags.lootitem)
  if #items == 0 then return end
  -- Ruling L: top up to the tag's quantity (the step's own rule, e.g. an item
  -- objective, may already have added some); BAG_UPDATE only when something was
  -- added and the step has not already fired it.
  local added = false
  for _, it in ipairs(items) do
    local need = it.n - ctx.world.player:item_count(it.id)
    if need > 0 then
      add_item(ctx, out, it.id, need)
      added = true
    end
  end
  if not added then return end
  out.kind = "acted"
  for _, e in ipairs(out.events) do
    if e == "BAG_UPDATE" then return end
  end
  fire(ctx, out, "BAG_UPDATE", 0)
end

-- P / SPELL name what a training step teaches; unknown ones are learned.
local function apply_training_tags(ctx, step, out)
  local tags = step.tags or {}
  local learn = {}
  learn.skill = first_part(tags.prof)
  if type(tags.spell) == "string" then
    local _, id = tags.spell:match("^%s*([^;]*);%s*(%d+)")
    learn.spell = tonumber(id)
  end
  if (learn.skill or learn.spell) and train(ctx, out, learn) then out.kind = "acted" end
end

-- = (training): a player at a trainer opens the trainer window. The engine completes
-- the first visible = row on TRAINER_SHOW (WoWPro_Events.lua:809-811, AutoCompleteTrain
-- at WoWPro_AutoComplete.lua:199-210). P/SPELL tags then teach what they name
-- (apply_training_tags). r (repair/sell) steps stay manual: the engine completes them
-- on MERCHANT_SHOW only when CanMerchantRepair() is true (WoWPro_Events.lua:515-526),
-- and the world can't tell yet whether the vendor at a step repairs.
local function perform_trainer(ctx, step, out)
  out.kind = "acted"
  fire(ctx, out, "TRAINER_SHOW")
  fire(ctx, out, "TRAINER_CLOSED")
end

local QUEST_HANDLERS = { A = perform_accept, C = perform_objectives, K = perform_objectives, T = perform_turn_in }
local OTHER_HANDLERS = {
  R = perform_travel, F = perform_arrival, b = perform_arrival, P = perform_arrival, H = perform_travel,
  f = perform_flight_point, h = perform_bind, U = perform_use, L = perform_level,
  l = perform_item_step, B = perform_item_step, ["*"] = perform_trash, ["="] = perform_trainer,
}

-- Actions whose completion is expected to need a right-click (Task 6 splits
-- manual-completion into expected and unexpected with this). A step whose note says
-- "Manually check this step off" is also expected: see actions.expects_manual.
-- = is not here: opening the trainer completes it (perform_trainer), so an = step that
-- still doesn't advance is a did-not-advance, unless its note says to check it off by
-- hand (actions.expects_manual), as the guides' class-training notes do.
actions.EXPECTED_MANUAL = { N = true, D = true, r = true, ["*"] = true }

function actions.expects_manual(step)
  if actions.EXPECTED_MANUAL[step.action] then return true end
  local note = step.tags and step.tags.note
  return type(note) == "string" and note:find("Manually check this step off", 1, true) ~= nil
end

-- ctx = { engine = E, world = W, cfg = cfg }; step is an Engine:step() record.
-- Returns { kind = "acted"|"refused"|"noop", reason, qid, events = {names...},
-- levels, grind = {kills, to}|nil, elite, settle = <E:settle() result> }.
-- Every call settles exactly once at the end and leaves world.dialog nil.
function actions.perform(ctx, step)
  local qids = step.qids or {}
  local out = new_outcome(qids[1])
  local quest_handler = QUEST_HANDLERS[step.action]
  local handler = OTHER_HANDLERS[step.action]
  walk_to_step(ctx, step, out)
  if quest_handler then
    if #qids == 0 then
      out.reason = "no-qid"
    else
      quest_handler(ctx, step, out)
    end
  elseif handler then
    handler(ctx, step, out)
  else
    out.reason = "not-a-quest-action"
  end
  if out.kind ~= "refused" then
    -- Tags any step can carry: LVL grinds (Ruling G), L adds items, P/SPELL train.
    -- U already adds its own use item; the L tag still applies to it.
    if step.action ~= "L" then perform_level(ctx, step, out) end
    apply_item_tag(ctx, step, out)
    apply_training_tags(ctx, step, out)
  end
  finish_bags(ctx, out)
  out.elite = out.elite or (step.tags ~= nil and step.tags.elite ~= nil and step.tags.elite ~= false)
  out.settle = ctx.engine:settle()
  ctx.world.dialog = nil
  return out
end

return actions
