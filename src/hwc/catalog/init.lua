-- The quest catalog: world facts (design spec §6) merged per field from the
-- installed QuestieDB Forever release (run per character through
-- hwc.questie.source) and a hand-checked supplement.
-- World facts never come from guide lines; the only guide-derived values are
-- in `placeholder`, which is marked unverified.
--
-- No third-party data lives in this repo: every source is read from a path in
-- the config and every source is optional (absent ones are recorded).
local dkjson = require("dkjson")
local lfs = require("lfs")
local source = require("hwc.questie.source")
local kills = require("hwc.world.kills")

local Catalog = {}
Catalog.__index = Catalog

-- QuestieDB requiredRaces bits (QuestieDB src/corrections/enum/expansions.lua:11-29,
-- Forever ChrRaces build 1.60.1.69893): masks decode to sorted Player.RACES keys.
-- Keys, not client tokens: both Skyborne races answer the token "Skyborne".
local RACE_BITS = {
  Human = 1, Orc = 2, Dwarf = 4, NightElf = 8, Undead = 16, Tauren = 32, Gnome = 64, Troll = 128,
  SkyborneAlliance = 4294967296, SkyborneHorde = 8589934592,
}
local CLASS_BITS = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }
-- QuestieDB masks that mean "any race" (sim.py:205-209). The faction masks
-- (77 classic Alliance, 4294967373 Forever Alliance with Skyborne) used to be
-- here too; they decode now, so a Horde character can't take an Alliance quest.
local ANY_RACES = { [0] = true, [2047] = true }

-- Quest fields a supplement entry may set.
local SUPPLEMENT_FIELDS = {
  "name", "level", "required_level", "xp", "races", "classes", "pre_single", "pre_group",
  "objectives", "starter", "ender", "requires_skill", "completed_by_training", "source_item",
  "reputation_reward", "min_rep", "max_rep",
}

-- Python's `a or b` treats 0 as missing; the old simulator's data relies on it.
local function nz(v)
  if v == nil or v == 0 then return nil end
  return v
end

-- Whole-number arithmetic, not the 32-bit bit library: Skyborne sits on bits 32/33.
local function mask_to_list(mask, bits)
  local out = {}
  for token, bit in pairs(bits) do
    if math.floor(mask / bit) % 2 == 1 then out[#out + 1] = token end
  end
  table.sort(out)
  return out
end

local function races_from_mask(mask)
  if mask == nil or ANY_RACES[mask] then return nil end
  local list = mask_to_list(mask, RACE_BITS)
  return #list > 0 and list or nil
end

local function copy_array(t)
  local out = {}
  for i, v in ipairs(t or {}) do out[i] = v end
  return out
end

local function sorted_values(t)
  local out = {}
  for _, v in pairs(t or {}) do out[#out + 1] = v end
  table.sort(out)
  return out
end

local function shell_quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

local function file_sha256(path)
  local p = io.popen("shasum -a 256 " .. shell_quote(path) .. " 2>/dev/null")
  if not p then return nil end
  local out = p:read("*a")
  p:close()
  return out:match("^(%x+)")
end

local function read_json(path)
  local f, err = io.open(path, "rb")
  if not f then error("hwc: catalog: cannot read " .. path .. ": " .. tostring(err), 0) end
  local text = f:read("*a")
  f:close()
  local obj, _, jerr = dkjson.decode(text)
  if jerr then error("hwc: catalog: " .. path .. ": " .. tostring(jerr), 0) end
  return obj
end

local function exists(path, mode) return lfs.attributes(path, "mode") == mode end

function Catalog.load(cfg)
  local c = (cfg and cfg.catalog) or {}
  local self = setmetatable({ sources = {}, _quests = {}, _npcs = {}, _items = {} }, Catalog)

  -- c.questie_source (a ready Source, used by specs) bypasses opening questie_dir.
  local src, reason = c.questie_source, nil
  if not src then
    src, reason = source.open(c.questie_dir, { class = cfg.class, faction = cfg.faction })
  end
  if src then
    self.questie = src
    local info = src.info
    self.sources.questie = { path = info.path, present = true, tag = info.tag, build = info.build, sha256 = info.sha256 }
  else
    self.sources.questie = { path = c.questie_dir, present = false, reason = reason }
  end

  local function json_source(name, path, default)
    local ok = path ~= nil and exists(path, "file")
    self.sources[name] = { path = path, present = ok }
    if not ok then return default end
    self.sources[name].sha256 = file_sha256(path)
    return read_json(path)
  end
  local sup = json_source("supplement", c.supplement, {})
  self.supplement = sup.quests or {}
  for id, entry in pairs(self.supplement) do
    if type(entry.source) ~= "string" or entry.source == "" then
      error("hwc: catalog: supplement quest " .. id .. " has no source string", 0)
    end
  end
  return self
end

-- ---------- objectives ----------

local function name_of(self, kind, id)
  local src = self.questie
  if not src then return nil end
  local rec
  if kind == "npc" then
    rec = src:npc(id)
  elseif kind == "item" then
    rec = src:item(id)
  else
    rec = src:object(id)
  end
  return rec and rec.name
end

-- QuestieDB objective groups by index: 1 creature, 2 object, 3 item,
-- 4 reputation, 5 kill credit, 6 spell.
local function questie_objectives(self, ob)
  local out = {}
  local function simple(group, kind)
    for _, e in ipairs(ob[group] or {}) do
      out[#out + 1] = { kind = kind, ids = { e[1] }, count = 1, count_assumed = true, text = e[2] or name_of(self, kind, e[1]) }
    end
  end
  simple(1, "npc")
  simple(2, "object")
  simple(3, "item")
  for _, e in ipairs(ob[4] and { ob[4] } or {}) do
    out[#out + 1] = { kind = "other", ids = {}, count = 1, count_assumed = true, text = "Reputation " .. tostring(e[1]) .. " " .. tostring(e[2]) }
  end
  for _, e in ipairs(ob[5] or {}) do
    out[#out + 1] = { kind = "npc", ids = copy_array(e[1]), count = 1, count_assumed = true, text = e[3] or name_of(self, "npc", e[2]) }
  end
  for _, e in ipairs(ob[6] or {}) do
    out[#out + 1] = { kind = "other", ids = {}, count = 1, count_assumed = true, text = e[2] or ("Spell " .. tostring(e[1])) }
  end
  return out
end

local function objectives_for(self, qrec, notes)
  if qrec and type(qrec.objectives) == "table" then
    local out = questie_objectives(self, qrec.objectives)
    if #out > 0 then notes[#notes + 1] = "objective counts are not in QuestieDB (assumed 1)" end
    return out
  end
  return {}
end

-- ---------- quests ----------

-- QuestieDB reputationReward { {factionId, value}, ... } -> { {faction, value}, ... }, in order.
local function rep_rewards(list)
  local out = {}
  for _, e in ipairs(type(list) == "table" and list or {}) do out[#out + 1] = { faction = e[1], value = e[2] } end
  return out
end

-- QuestieDB requiredMinRep/requiredMaxRep {factionId, value} -> { faction, value } or nil.
local function rep_gate(pair)
  if type(pair) ~= "table" or type(pair[1]) ~= "number" or type(pair[2]) ~= "number" then return nil end
  return { faction = pair[1], value = pair[2] }
end

local function starter_of(list)
  -- startedBy/finishedBy = {creatures, objects, items}; the first creature wins.
  if type(list) ~= "table" then return nil end
  for i, kind in ipairs({ "npc", "object", "item" }) do
    local group = list[i]
    if type(group) == "table" and group[1] then return group[1], kind end
  end
  return nil
end

local function build_quest(self, id)
  local src = self.questie
  local q = src and src:quest(id)
  local sup = self.supplement[tostring(id)]
  local xpr = src and src:xp(id)
  if not (q or sup or xpr) then return nil end
  q = q or {}

  local notes = {}
  local function note(s) notes[#notes + 1] = s end
  local quest = { id = id, name = q.name or (sup and sup.name) }

  -- level / required_level: QuestieDB, then QuestXP (sim.py:205-212, no guide data).
  quest.level = nz(q.questLevel) or (xpr and nz(xpr[1]))
  quest.required_level = nz(q.requiredLevel) or 1

  -- xp: QuestXP, then 0 (unverified).
  local xp_known = false
  if xpr and xpr[2] ~= nil then
    quest.xp, xp_known = xpr[2], true
  else
    quest.xp = 0
  end

  quest.races = races_from_mask(q.requiredRaces)
  local qclasses = nz(q.requiredClasses) and mask_to_list(q.requiredClasses, CLASS_BITS) or nil
  if qclasses and #qclasses > 0 then quest.classes = qclasses end

  quest.pre_single = sorted_values(q.preQuestSingle)
  quest.pre_group = sorted_values(q.preQuestGroup)
  quest.next_in_chain = nz(q.nextQuestInChain)
  quest.objectives = objectives_for(self, q, notes)
  quest.starter, quest.starter_kind = starter_of(q.startedBy)
  quest.ender, quest.ender_kind = starter_of(q.finishedBy)
  -- QuestieDB sourceItemId: "item provided by quest starter" (the client puts it in the bags on accept).
  quest.source_item = nz(q.sourceItemId)
  -- Reputation (design 2026-11-18-reputation §4.3): the rewards a turn-in gives and the
  -- standing an accept needs, on QuestieDB's cumulative scale.
  quest.reputation_reward = rep_rewards(q.reputationReward)
  -- QuestieDB zoneOrSort: a zone id, or a negative sort id (-364 Darkmoon Faire).
  quest.zone_or_sort = type(q.zoneOrSort) == "number" and q.zoneOrSort or nil
  quest.min_rep = rep_gate(q.requiredMinRep)
  quest.max_rep = rep_gate(q.requiredMaxRep)

  -- Camping 101 profession quests (design spec §3, the user in game 2026-11-11): "Camping 101: <Prof>" ends at the trainer and gates
  -- on knowing <Prof>, except Cooking, whose turn-in is completed by training
  -- Cooking. The supplement below may override either field, and a
  -- supplement-set name is taken into account.
  local final_name = (sup and sup.name) or quest.name
  local prof = type(final_name) == "string" and final_name:match("^Camping 101: (.+)$")
  if prof == "Cooking" then
    quest.completed_by_training = "Cooking"
  elseif prof then
    quest.requires_skill = prof
  end

  -- The supplement may override any field for a listed quest.
  if sup then
    for _, field in ipairs(SUPPLEMENT_FIELDS) do
      if sup[field] ~= nil then
        quest[field] = sup[field]
        if field == "xp" then xp_known = true end
        if field == "starter" then quest.starter_kind = nil end
        if field == "ender" then quest.ender_kind = nil end
        note("supplement sets " .. field .. " (" .. sup.source .. ")")
      end
    end
  end

  -- A count nobody supplied is assumed 1; the quest cannot be called verified.
  local assumed = false
  for i, o in ipairs(quest.objectives) do
    if o.count == nil then
      o.count = 1
      o.count_assumed = true
      note("objective " .. i .. " has no count (assumed 1)")
    end
    if o.count_assumed then assumed = true end
  end

  -- Ruling AB: rules keyed on the name (Camping 101's requires_skill and
  -- completed_by_training above) cannot apply to a quest no source names, so its
  -- data cannot be called verified.
  local named = type(quest.name) == "string" and quest.name ~= ""
  if not named then note("no name in any source; name-based rules (Camping 101) cannot apply") end

  quest.confidence = (xp_known and quest.level ~= nil and not assumed and named) and "verified" or "unverified"
  quest.notes = notes
  return quest
end

function Catalog:quest(id)
  id = tonumber(id)
  if not id then return nil end
  if self._quests[id] == nil then self._quests[id] = build_quest(self, id) or false end
  return self._quests[id] or nil
end

-- Faction ids whose rewards mark a quest as a non-combat activity.
local COMMERCE_FACTION = 2586 -- Azeroth Commerce Authority
local DARKMOON_FACTION = 909 -- Darkmoon Faire
local DARKMOON_SORT = -364

-- Is the quest something the player does without fighting (design 2026-11-18-quest-color)?
-- true, reason: "commerce" / "darkmoon" (QuestieDB marks it a non-combat activity), or
-- "no-combat-objective" (no kill objective and no item objective whose item a mob drops).
-- false for a quest with a combat objective, or one not in the catalog. An objective NPC or item
-- missing from QuestieDB counts as non-combat (fail open: no data is not evidence of combat).
-- Item drops come from the catalog's own item data (Catalog:item), so "combat" has one definition.
function Catalog:noncombat(qid)
  local quest = self:quest(qid)
  if not quest then return false end
  for _, r in ipairs(quest.reputation_reward or {}) do
    if r.faction == COMMERCE_FACTION then return true, "commerce" end
    if r.faction == DARKMOON_FACTION then return true, "darkmoon" end
  end
  if quest.zone_or_sort == DARKMOON_SORT then return true, "darkmoon" end
  for _, o in ipairs(quest.objectives or {}) do
    if o.kind == "npc" then
      local npc = self:npc(o.ids and o.ids[1])
      if npc and not kills.talk_to(npc, quest) then return false end
    elseif o.kind == "item" then
      -- Combat only when a mob drops it AND nobody sells it: an item you can buy is never a
      -- combat objective, whatever rare drops exist.
      local id = o.ids and o.ids[1]
      local it = self:item(id)
      local raw = self.questie and self.questie:item(id)
      if it and #it.drops > 0 and #(raw and raw.vendors or {}) == 0 then return false end
    end
  end
  return true, "no-combat-objective"
end

-- The part and total of a quest in a chain whose parts share one name (design
-- 2026-11-18-quest-chain-parts): part = 1 + same-name predecessors walked back (the
-- lowest-id one when several), total = the same-name run walked forward from part 1
-- through nextQuestInChain. nil for a quest with no same-name neighbour, one not in
-- the catalog, or a cycle. Pure: catalog data only.
function Catalog:chain_part(qid)
  local quest = self:quest(qid)
  local name = quest and quest.name
  if type(name) ~= "string" or name == "" then return nil end
  local function same_name(id)
    local o = id and self:quest(id)
    return o and o.name == name and o or nil
  end
  local function predecessor(o)
    local best
    for _, list in ipairs({ o.pre_single or {}, o.pre_group or {} }) do
      for _, id in ipairs(list) do
        if same_name(id) and (not best or id < best) then best = id end
      end
    end
    return best
  end
  local seen, part, cur = { [quest.id] = true }, 1, quest
  while true do
    local pid = predecessor(cur)
    if not pid then break end
    if seen[pid] then return nil end -- a cycle
    seen[pid] = true
    part, cur = part + 1, same_name(pid)
  end
  local total, walk = 1, cur
  local fwd = { [cur.id] = true }
  while walk.next_in_chain and same_name(walk.next_in_chain) do
    if fwd[walk.next_in_chain] then return nil end
    fwd[walk.next_in_chain] = true
    walk = same_name(walk.next_in_chain)
    total = total + 1
  end
  if total < part then total = part end
  if total < 2 then return nil end
  return part, total
end

-- The only guide-derived path (design spec §6): a quest in no source, shaped from
-- the step's own QO count. Always marked unverified.
function Catalog:placeholder(id, qo_count)
  local objectives = {}
  for n = 1, qo_count or 0 do
    objectives[n] = { kind = "other", count = 1, text = "Objective " .. n }
  end
  return {
    id = id, required_level = 1, xp = 0, objectives = objectives,
    pre_single = {}, pre_group = {}, confidence = "unverified",
    notes = { "unverified quest data: placeholder shaped from the guide step's QO count" },
  }
end

-- ---------- factions ----------

-- Words kept lower case inside a name ("The League of Arathor").
local MINOR_WORDS = { OF = true, THE = true, AND = true }

-- QuestieDB constant -> display name: GELKIS_CLAN_CENTAUR -> "Gelkis Clan Centaur".
local function display_name(constant)
  local words = {}
  for w in constant:gmatch("[^_]+") do
    if #words > 0 and MINOR_WORDS[w] then
      words[#words + 1] = w:lower()
    else
      words[#words + 1] = w:sub(1, 1):upper() .. w:sub(2):lower()
    end
  end
  return table.concat(words, " ")
end

-- A faction's display name from the installed QuestieDB's faction constants
-- (src/corrections/enum/factions.lua, Enum.factionIDs), read at run time; no names
-- are kept in this repo. An id with no constant (or no QuestieDB) is "Faction <id>".
function Catalog:faction_name(id)
  if not self._faction_names then
    local by_id = {}
    local src = self.questie
    local constants = src and src.factions and src:factions() or {}
    local keys = {}
    for k in pairs(constants) do keys[#keys + 1] = k end
    -- Sorted, so a shared id names the same constant on every run.
    table.sort(keys)
    for _, k in ipairs(keys) do
      local v = constants[k]
      if type(v) == "number" and by_id[v] == nil then by_id[v] = display_name(k) end
    end
    self._faction_names = by_id
  end
  return self._faction_names[tonumber(id)] or ("Faction " .. tostring(id))
end

-- ---------- npcs and items ----------

function Catalog:npc(id)
  id = tonumber(id)
  if not id then return nil end
  if self._npcs[id] == nil then
    local n = self.questie and self.questie:npc(id)
    self._npcs[id] = n and {
      id = id, name = n.name, level_min = n.minLevel, level_max = n.maxLevel, rank = n.rank,
      spawns = n.spawns or {}, zone_id = n.zoneID,
      -- npcFlags (foreverNpcDB.lua npcKeys :21-22): service bits, e.g. gossip 1,
      -- questgiver 2, vendor 4, trainer 16 (kills.objective_kills, Ruling AC).
      flags = n.npcFlags,
    } or false
  end
  return self._npcs[id] or nil
end

function Catalog:item(id)
  id = tonumber(id)
  if not id then return nil end
  if self._items[id] == nil then
    local it = self.questie and self.questie:item(id)
    if not it then
      self._items[id] = false
    else
      -- QuestieDB drop tables give rates; without them, npcDrops gives droppers only.
      local drops = self.questie.drops and self.questie:drops(id)
      if not drops then
        drops = {}
        for _, npc in ipairs(it.npcDrops or {}) do drops[#drops + 1] = { npc = npc } end
      end
      self._items[id] = { id = id, name = it.name, drops = drops, notes = {} }
    end
  end
  return self._items[id] or nil
end

-- Quest id -> the items QuestieDB lists as its rewards (itemData.questRewards:
-- "table or nil, quest IDs", item -> rewarding quests), sorted. QuestieDB gives no
-- counts and doesn't separate a choice of rewards from fixed ones.
function Catalog:quest_rewards(qid)
  if not self._rewards then
    local by_quest = {}
    local src = self.questie
    if src then
      -- item_ids is ascending, so each quest's list is built sorted.
      for _, id in ipairs(src:item_ids()) do
        local rewards = src:item(id).questRewards
        for _, q in ipairs(type(rewards) == "table" and rewards or {}) do
          by_quest[q] = by_quest[q] or {}
          table.insert(by_quest[q], id)
        end
      end
    end
    self._rewards = by_quest
  end
  return self._rewards[tonumber(qid)] or {}
end

-- Item name -> id for the player's item_count; the lowest id wins a shared name.
function Catalog:item_id(name)
  if not self._item_ids then
    local ids = {}
    local src = self.questie
    if src then
      -- item_ids is ascending, so the first id seen for a name is the lowest.
      for _, id in ipairs(src:item_ids()) do
        local n = src:item(id).name
        if n and ids[n] == nil then ids[n] = id end
      end
    end
    self._item_ids = ids
  end
  return self._item_ids[name]
end

return Catalog
