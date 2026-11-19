-- The quest catalog: world facts (design spec §6) merged per field from the
-- installed QuestieDB Forever release (run per character through
-- hwc.questie.source), plus hand-checked objective counts, which QuestieDB lacks.
-- World facts never come from guide lines; the only guide-derived values are
-- in `placeholder`, which is marked unverified.
--
-- No third-party data lives in this repo: each source is read from a path in the
-- config and is optional (an absent one is recorded).
local dkjson = require("dkjson")
local lfs = require("lfs")
local source = require("hwc.questie.source")
local forever_db = require("hwc.forever.db")

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

-- Objective kinds a counts entry can name: the ones whose objectives carry an id.
local COUNT_KINDS = { npc = true, object = true, item = true }

-- The problem with one counts-file quest entry, or nil when it is valid.
function Catalog.counts_entry_problem(entry)
  if type(entry) ~= "table" then return "is not an object" end
  if type(entry.source) ~= "string" or entry.source == "" then return "has no source" end
  if type(entry.objectives) ~= "table" or #entry.objectives == 0 then return "has no objectives" end
  for i, o in ipairs(entry.objectives) do
    local count = type(o) == "table" and o.count
    if type(o) ~= "table" or not COUNT_KINDS[o.kind] or type(o.id) ~= "number"
      or type(count) ~= "number" or count < 1 or count % 1 ~= 0 then
      return "objective " .. i .. " needs kind npc, object or item, a numeric id and a whole count of at least 1"
    end
  end
  return nil
end

-- Hand-checked objective counts (QuestieDB has none): { quests = { ["<id>"] = {
-- source = "how it was checked", objectives = { { kind, id, count }, ... } } } }.
local function load_counts(self, path)
  local ok = path ~= nil and lfs.attributes(path, "mode") == "file"
  self.sources.counts = { path = path, present = ok }
  if not ok then return {} end
  self.sources.counts.sha256 = file_sha256(path)
  local f, err = io.open(path, "rb")
  if not f then error("hwc: catalog: cannot read " .. path .. ": " .. tostring(err), 0) end
  local text = f:read("*a")
  f:close()
  local obj, _, jerr = dkjson.decode(text)
  if jerr or type(obj) ~= "table" then error("hwc: catalog: " .. path .. ": " .. tostring(jerr or "not an object"), 0) end
  local quests = obj.quests or {}
  for id, entry in pairs(quests) do
    local problem = Catalog.counts_entry_problem(entry)
    if problem then error("hwc: catalog: " .. path .. ": quest " .. tostring(id) .. " " .. problem, 0) end
  end
  return quests
end

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
  self.counts = load_counts(self, c.counts)

  -- c.forever_db (a ready DB, used by specs) bypasses opening forever_dir.
  local db, freason = c.forever_db, nil
  if not db then db, freason = forever_db.open(c.forever_dir) end
  if db then
    self.forever = db
    self.sources.forever = { path = db.dir or c.forever_dir, present = true, build = db.build }
  else
    self.sources.forever = { path = c.forever_dir, present = false, reason = freason }
  end
  return self
end

-- A QuestieDB npc's first spawn as map_id, x, y (fractions), or nil without
-- QuestieDB, the Forever tables, a spawn, or a UI map for its area.
function Catalog:npc_position(npc_id)
  if not (self.questie and self.forever) then return nil end
  local npc = self.questie:npc(npc_id)
  local spawns = npc and npc.spawns
  if type(spawns) ~= "table" then return nil end
  local areas = {}
  for area in pairs(spawns) do areas[#areas + 1] = area end
  table.sort(areas)
  for _, area in ipairs(areas) do
    local pt = spawns[area][1]
    local map_id = pt and self.forever:ui_map_of_area(area)
    if map_id then return map_id, pt[1] / 100, pt[2] / 100 end
  end
  return nil
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

local function objectives_for(self, qrec)
  if qrec and type(qrec.objectives) == "table" then
    return questie_objectives(self, qrec.objectives)
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

local NUMBER_WORDS = {
  one = 1, two = 2, three = 3, four = 4, five = 5, six = 6, seven = 7, eight = 8, nine = 9, ten = 10,
  eleven = 11, twelve = 12, thirteen = 13, fourteen = 14, fifteen = 15, sixteen = 16, seventeen = 17,
  eighteen = 18, nineteen = 19, twenty = 20,
}
-- Words between a number and the name it counts ("8 pieces of Tough Wolf Meat").
local MAX_GAP_WORDS = 4

-- Plurals of one word.
local function plurals(word)
  local out = { word .. "es", word .. "s" }
  if word:match("[^aeiou]y$") then out[#out + 1] = word:sub(1, -2) .. "ies" end
  if word:match("fe?$") then out[#out + 1] = (word:gsub("fe?$", "ves")) end
  if word:match("man$") then out[#out + 1] = word:sub(1, -4) .. "men" end
  return out
end

local function name_forms(name)
  -- A leading article is the item's, not the text's ("A Sparkling Stone" -> "the Sparkling Stone").
  name = name:gsub("^an? ", ""):gsub("^the ", "")
  -- Plurals of the last word ("Mosshide Gnolls"), or of the head word before "of"
  -- ("Flasks of Oil"), then the name itself (singular last).
  local forms = plurals(name)
  local head, rest = name:match("^(%S+)( of .+)$")
  if head then
    for _, p in ipairs(plurals(head)) do forms[#forms + 1] = p .. rest end
  end
  forms[#forms + 1] = name
  return forms
end

-- Words that make the name after them one thing ("the Sparkling Stone", "his head").
local SINGLE_WORDS = {
  the = true, a = true, an = true, his = true, her = true, its = true, their = true,
  my = true, your = true, our = true, this = true, that = true,
}

-- An objective's count from its quest's objective text: the number just before
-- the name ("8 pieces of Tough Wolf Meat", "Kill 10 Kobold Vermin"), within the
-- same clause. With no number, 1 when the name appears unpluralised: "named-single"
-- when the context makes it one thing (a possessive name, "Pamela's doll", or a
-- singular word before it, "the Sparkling Stone"), else "named-once", a guess.
-- Returns count, "number" | "named-single" | "named-once", or nil when the name
-- isn't in the text or appears only plural without a number.
function Catalog.count_from_text(text, name)
  local lt, forms = text:lower(), name_forms(name:lower())
  local possessive = forms[#forms]:find("'s ", 1, true) ~= nil or forms[#forms]:find("s' ", 1, true) ~= nil
  local singular, single
  for i, form in ipairs(forms) do
    local init = 1
    while true do
      local s, e = lt:find(form, init, true)
      if not s then break end
      init = e + 1
      local before, after = lt:sub(s - 1, s - 1), lt:sub(e + 1, e + 1)
      if not before:match("[%w']") and not after:match("[%w']") then
        -- The clause this mention sits in: from the last sentence break, comma or "and".
        local clause = lt:sub(1, s - 1):gsub("^.*[%.;:!?,]", ""):gsub("^.* and ", "")
        local words = {}
        for w in clause:gmatch("%S+") do words[#words + 1] = w end
        for k = #words, math.max(1, #words - MAX_GAP_WORDS), -1 do
          local w = words[k]:gsub("[^%w]", "")
          local n = tonumber(w) or NUMBER_WORDS[w]
          if n then return n, "number" end
        end
        if i == #forms then
          singular = true
          local prev = (words[#words] or ""):gsub("[^%w']", "")
          if possessive or SINGLE_WORDS[prev] or prev:match("'s$") or prev:match("s'$") then single = true end
        end
      end
    end
  end
  if single then return 1, "named-single" end
  if singular then return 1, "named-once" end
  return nil
end

-- One of its kind in the world: elite, rare elite, boss or rare (QuestieDB rank 1-4),
-- or one or two spawns in all.
local function unique_npc(self, npc_id)
  local rec = self.questie and npc_id and self.questie:npc(npc_id)
  if not rec then return false end
  if (rec.rank or 0) ~= 0 then return true end
  local n = 0
  for _, list in pairs(rec.spawns or {}) do
    if type(list) == "table" then n = n + #list end
  end
  return n >= 1 and n <= 2
end

local function build_quest(self, id)
  local src = self.questie
  local q = src and src:quest(id)
  local xpr = src and src:xp(id)
  if not (q or xpr) then return nil end
  q = q or {}

  local notes = {}
  local function note(s) notes[#notes + 1] = s end
  local quest = { id = id, name = q.name }

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
  quest.objectives = objectives_for(self, q)
  quest.starter, quest.starter_kind = starter_of(q.startedBy)
  quest.ender, quest.ender_kind = starter_of(q.finishedBy)
  -- QuestieDB sourceItemId: "item provided by quest starter" (the client puts it in the bags on accept).
  quest.source_item = nz(q.sourceItemId)
  -- Reputation (design 2026-11-18-reputation §4.3): the rewards a turn-in gives and the
  -- standing an accept needs, on QuestieDB's cumulative scale.
  quest.reputation_reward = rep_rewards(q.reputationReward)
  quest.min_rep = rep_gate(q.requiredMinRep)
  quest.max_rep = rep_gate(q.requiredMaxRep)

  -- Camping 101 profession quests (design spec §3, the user in game 2026-11-11): "Camping 101: <Prof>" ends at the trainer and gates
  -- on knowing <Prof>, except Cooking, whose turn-in is completed by training
  -- Cooking.
  local prof = type(quest.name) == "string" and quest.name:match("^Camping 101: (.+)$")
  if prof == "Cooking" then
    quest.completed_by_training = "Cooking"
  elseif prof then
    quest.requires_skill = prof
  end

  -- QuestieDB's objective rows have no counts (objectives_for assumes 1). Its quest
  -- text usually says them ("would like 8 pieces of Tough Wolf Meat"), so they are
  -- read from there first; the counts file below wins over the text.
  local text = type(q.objectivesText) == "table" and table.concat(q.objectivesText, " ") or nil
  if text then
    for _, o in ipairs(quest.objectives) do
      if o.count_assumed and o.kind ~= "other" and type(o.text) == "string" then
        local n, how = Catalog.count_from_text(text, o.text)
        local why = how == "number" and "a number before its name"
          or how == "named-single" and "named as one thing: possessive, or after a word like 'the'"
          or "named with no number"
        -- A named NPC the world holds one of (elite/rare/boss, or 1-2 spawns) is one to kill or meet.
        if how == "named-once" and o.kind == "npc" and unique_npc(self, o.ids[1]) then
          how, why = "named-single", "a named NPC with one or two spawns, or elite"
        end
        if n then
          o.count, o.count_assumed, o.count_from = n, nil, how
          note(o.kind .. " " .. tostring(o.ids[1]) .. " count " .. n .. " from the quest text (" .. why .. ")")
        end
      end
    end
  end

  -- Hand-checked counts, matched by kind and id. An entry that matches nothing is noted.
  local counted = self.counts[tostring(id)]
  if counted then
    for _, e in ipairs(counted.objectives) do
      local hit = false
      for _, o in ipairs(quest.objectives) do
        if o.kind == e.kind then
          for _, oid in ipairs(o.ids or {}) do
            if oid == e.id then o.count, o.count_assumed, o.count_from, hit = e.count, nil, "counts file", true end
          end
        end
      end
      if hit then
        note(e.kind .. " " .. e.id .. " count " .. e.count .. " from the counts file (" .. counted.source .. ")")
      else
        note("counts file: " .. e.kind .. " " .. e.id .. " matches no objective of this quest")
      end
    end
  end

  -- A quest with a count nobody checked cannot be called verified: one assumed, or
  -- one read as 1 only because the text names it with no number and nothing in the
  -- context makes it one thing (a guess).
  local assumed, guessed = false, false
  for _, o in ipairs(quest.objectives) do
    if o.count_assumed then assumed = true end
    if o.count_from == "named-once" then guessed = true end
  end
  if assumed then note("an objective count is in neither the quest text nor the counts file (assumed 1)") end
  if guessed then note("an objective count is 1 only because the quest text names it with no number") end

  -- Ruling AB: rules keyed on the name (Camping 101's requires_skill and
  -- completed_by_training above) cannot apply to a quest no source names, so its
  -- data cannot be called verified.
  local named = type(quest.name) == "string" and quest.name ~= ""
  if not named then note("no name in any source; name-based rules (Camping 101) cannot apply") end

  quest.confidence = (xp_known and quest.level ~= nil and not assumed and not guessed and named) and "verified"
    or "unverified"
  quest.notes = notes
  return quest
end

function Catalog:quest(id)
  id = tonumber(id)
  if not id then return nil end
  if self._quests[id] == nil then self._quests[id] = build_quest(self, id) or false end
  return self._quests[id] or nil
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
