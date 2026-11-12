-- Kill and grind XP model (design spec §5.5). Pure functions over the catalog and a Player.
-- Kill counts for drop objectives use the old simulator's 90%-confidence binomial rule
-- (wow-pro-leveling/sim/sim.py:323-335 kills_needed) and its source choice (sim.py:520-551):
-- an ordinary mob beats an elite/rare, then the highest known rate; a named elite with 1-2 spawns
-- always drops; an unknown rate costs count * 3 kills (sim.py:550).
local xp = require("hwc.world.xp")

local kills = {}

local CONFIDENCE = 0.9
local MAX_KILLS = 5000

-- Smallest n with P(>= needed drops in n kills at probability rate) >= 0.9. rate is 0-1.
function kills.for_drop(rate, needed)
  if rate >= 0.999 then return needed end
  local n = needed
  while n < MAX_KILLS do
    local q, term = 0, (1 - rate) ^ n  -- term = P(exactly 0 drops)
    for i = 0, needed - 1 do
      q = q + term
      -- P(i+1) = P(i) * (n-i)/(i+1) * rate/(1-rate)
      term = term * (n - i) / (i + 1) * rate / (1 - rate)
    end
    if 1 - q >= CONFIDENCE then return n end
    n = n + 1
  end
  return n
end

function kills.mob_level(npc)
  return math.floor((npc.level_min + npc.level_max) / 2)
end

local function is_elite(npc) return npc.rank == 1 or npc.rank == 2 end

local function spawn_count(npc)
  local n = 0
  for _, v in pairs(npc.spawns or {}) do
    if type(v) == "table" and type(v[1]) == "table" then n = n + #v else n = n + 1 end
  end
  return n
end

local function result(npc, count)
  return { npc_id = npc.id, level = kills.mob_level(npc), elite = is_elite(npc), count = count }
end

local function item_kills(catalog, objective)
  local item = catalog:item(objective.ids and objective.ids[1])
  if not item then return nil end
  local count = objective.count or 1
  local best, best_score
  for _, d in ipairs(item.drops or {}) do
    local npc = catalog:npc(d.npc)
    if npc then
      local ordinary = (npc.rank == 1 or npc.rank == 2 or npc.rank == 4) and 0 or 1
      local score_rate = d.rate or 0
      if not best or ordinary > best_score[1] or (ordinary == best_score[1] and score_rate > best_score[2]) then
        best, best_score = { npc = npc, rate = d.rate }, { ordinary, score_rate }
      end
    end
  end
  if not best then return nil end
  local npc, rate = best.npc, best.rate
  local spawns = spawn_count(npc)
  if is_elite(npc) and spawns >= 1 and spawns <= 2 then rate = 1 end
  if not rate or rate <= 0 then return result(npc, count * 3) end
  return result(npc, kills.for_drop(rate, count))
end

-- Ruling AC: is an npc objective's NPC someone the player talks to rather than
-- kills? QuestieDB's objective groups cannot tell: its creatureObjective is a kill
-- ("If text is nil the default '<Name> slain x/y' is used", foreverQuestDB.lua:22),
-- but Forever's talk-to objectives (e.g. 96044 -> Tognus Flintfire, 96629 ->
-- Gremlock Pilsnor) come from the Wowhead objectives file as kind "npc", and those
-- quests have no QuestieDB row at all. So a heuristic decides, flagged in the
-- findings gaps: the quest's starter or ender NPC; an NPC with no level range; or,
-- beyond the ruling's two tests (which miss both examples above: neither quest has a
-- starter/ender on record and both NPCs have levels), a service NPC, one with any
-- QuestieDB npcFlags bit set (gossip, questgiver, vendor, trainer, ...).
local function talk_to(npc, quest)
  if not (npc.level_min and npc.level_max) then return true end
  if (npc.flags or 0) ~= 0 then return true end
  if quest then
    if quest.starter == npc.id and (quest.starter_kind == nil or quest.starter_kind == "npc") then return true end
    if quest.ender == npc.id and (quest.ender_kind == nil or quest.ender_kind == "npc") then return true end
  end
  return false
end

-- { npc_id, level, elite, count } for a kill/drop objective, or nil when it yields no
-- kill XP (quest, optional, lets a talk-to NPC objective be told from a kill).
function kills.objective_kills(catalog, objective, quest)
  if objective.kind == "npc" then
    local npc = catalog:npc(objective.ids and objective.ids[1])
    if not npc or talk_to(npc, quest) then return nil end
    return result(npc, objective.count or 1)
  elseif objective.kind == "item" then
    return item_kills(catalog, objective)
  end
  return nil
end

-- Credits k.count kills, flooring each kill and recomputing at the current level. Returns xp, levels.
function kills.credit(player, k, party_size)
  local total, levels = 0, 0
  for _ = 1, k.count do
    if player.level >= xp.CAP_LEVEL then break end
    local n = math.floor(xp.mob_xp(player.level, k.level, k.elite, party_size))
    total = total + n
    levels = levels + player:add_xp(n)
  end
  return total, levels
end

-- Grinds same-level generic mobs until player.level >= target_level (clamped to the cap).
-- Returns kills, xp, levels.
function kills.grind_to(player, target_level)
  local target = math.min(target_level, xp.CAP_LEVEL)
  local n, total, levels = 0, 0, 0
  while player.level < target do
    local gained = math.floor(xp.mob_xp(player.level, player.level, false, 1))
    total = total + gained
    levels = levels + player:add_xp(gained)
    n = n + 1
  end
  player._record("grind", { to = target_level, kills = n })
  return n, total, levels
end

return kills
