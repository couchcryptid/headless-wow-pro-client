-- The quest catalog: world facts (design spec §6) merged per field from the
-- Wowhead extract, pinned QuestieDB Forever and a hand-checked supplement.
-- World facts never come from guide lines; the only guide-derived values are
-- in `placeholder`, which is marked unverified.
--
-- No third-party data lives in this repo: every source is read from a path in
-- the config and every source is optional (absent ones are recorded).
local dkjson = require("dkjson")
local lfs = require("lfs")
local questie = require("hwc.catalog.questie")

local Catalog = {}
Catalog.__index = Catalog

local TWO32 = 4294967296

-- WoW race and class bits (Classic); masks decode to sorted token lists.
local RACE_BITS = { Human = 1, Orc = 2, Dwarf = 4, NightElf = 8, Undead = 16, Tauren = 32, Gnome = 64, Troll = 128 }
local CLASS_BITS = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }
-- QuestieDB masks that mean "any race" (sim.py:205-209).
local ANY_RACES = { [0] = true, [4294967373] = true, [77] = true, [2047] = true }

-- Quest fields a supplement entry may set.
local SUPPLEMENT_FIELDS = {
  "name", "level", "required_level", "xp", "races", "classes", "pre_single", "pre_group",
  "objectives", "starter", "ender", "requires_skill",
}

-- Python's `a or b` treats 0 as missing; the old simulator's data relies on it.
local function nz(v)
  if v == nil or v == 0 then return nil end
  return v
end

local function mask_to_list(mask, bits)
  local low = mask % TWO32
  local out = {}
  for token, bit in pairs(bits) do
    if math.floor(low / bit) % 2 == 1 then out[#out + 1] = token end
  end
  table.sort(out)
  return out
end

local function races_from_mask(mask)
  if mask == nil or ANY_RACES[mask] then return nil end
  local list = mask_to_list(mask, RACE_BITS)
  return #list > 0 and list or nil
end

local function same_list(a, b)
  if a == nil or b == nil then return a == b end
  return table.concat(a, ",") == table.concat(b, ",")
end

local function fmt_list(l) return l and table.concat(l, "/") or "any" end

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

local function basename(path) return path:match("([^/]+)/*$") end

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

  local qdir = c.questie_dir
  local present = qdir ~= nil and exists(qdir, "directory")
  self.sources.questie = { path = qdir, present = present }
  if present then
    self.questie = questie.load(qdir)
    self.sources.questie.sha256 = self.questie.sha256
    self.sources.questie.commit = basename(qdir)
    if #self.questie.missing > 0 then
      self.sources.questie.present = "partial"
      self.sources.questie.missing = self.questie.missing
    end
  end

  local function json_source(name, path, default)
    local ok = path ~= nil and exists(path, "file")
    self.sources[name] = { path = path, present = ok }
    if not ok then return default end
    self.sources[name].sha256 = file_sha256(path)
    return read_json(path)
  end
  local wh = json_source("wh_json", c.wh_json, {})
  self.wh_quests, self.wh_items = wh.quest or {}, wh.item or {}
  self.objs = json_source("objs_json", c.objs_json, {})
  self.rate_overrides = json_source("rate_overrides", c.rate_overrides, {})
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
  local qd = self.questie
  if not qd then return nil end
  local pool = (kind == "npc" and qd.npcs) or (kind == "item" and qd.items) or qd.objects
  local rec = pool[id]
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

local function objectives_for(self, id, qrec, notes)
  local entry = self.objs[tostring(id)]
  if entry ~= nil then
    local has_tooltip = false
    for _, o in ipairs(entry) do
      if not o.from_db_only then has_tooltip = true end
    end
    local out = {}
    for i, o in ipairs(entry) do
      if o.from_db_only then
        notes[#notes + 1] = "objective " .. i .. " is from_db_only (not in the Wowhead tooltip)" ..
          (has_tooltip and "; dropped" or "; kept")
      end
      if not (has_tooltip and o.from_db_only) then
        out[#out + 1] = { kind = o.kind, ids = copy_array(o.ids), count = o.count, text = o.text }
      end
    end
    return out
  end
  if qrec and type(qrec.objectives) == "table" then
    local out = questie_objectives(self, qrec.objectives)
    if #out > 0 then notes[#notes + 1] = "objective counts are not in QuestieDB (assumed 1)" end
    return out
  end
  return {}
end

-- ---------- quests ----------

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
  local qd = self.questie
  local q = qd and qd.quests[id]
  local wh = self.wh_quests[tostring(id)]
  local sup = self.supplement[tostring(id)]
  local xpr = qd and qd.xp[id]
  local has_objs = self.objs[tostring(id)] ~= nil
  if not (q or wh or sup or xpr or has_objs) then return nil end
  q, wh = q or {}, wh or {}

  local notes = {}
  local function note(s) notes[#notes + 1] = s end
  local quest = { id = id, name = q.name or (sup and sup.name) }

  -- level / required_level: Wowhead, then QuestieDB, then QuestXP (sim.py:205-212, no guide data).
  local wl, ql, xl = nz(wh.level), nz(q.questLevel), xpr and nz(xpr[1])
  quest.level = wl or ql or xl
  if wl and ql and wl ~= ql then note("level: wowhead " .. wl .. " vs questie " .. ql .. " (wowhead used)") end
  local wr, qr = nz(wh.reqlevel), nz(q.requiredLevel)
  quest.required_level = wr or qr or 1
  if wr and qr and wr ~= qr then note("required_level: wowhead " .. wr .. " vs questie " .. qr .. " (wowhead used)") end

  -- xp: Wowhead, then QuestXP, then 0 (unverified).
  local xp_known = false
  if wh.xp ~= nil then
    quest.xp, xp_known = wh.xp, true
    if xpr and xpr[2] and xpr[2] ~= wh.xp then note("xp: wowhead " .. wh.xp .. " vs questxp " .. xpr[2] .. " (wowhead used)") end
  elseif xpr and xpr[2] ~= nil then
    quest.xp, xp_known = xpr[2], true
  else
    quest.xp = 0
  end

  -- races (sim.py:804-817 reasoning): Wowhead's mask is unreliable on Forever-added
  -- (>= 90000) quests, so there it is used only when below 2^32; below 90000 QuestieDB decides.
  local wmask = nz(wh.reqrace)
  if id < 90000 then
    local have_row = next(q) ~= nil
    quest.races = races_from_mask(q.requiredRaces)
    if wmask and wmask < TWO32 then
      local wl_races = races_from_mask(wmask)
      if have_row and not same_list(wl_races, quest.races) then
        note("race: wowhead " .. fmt_list(wl_races) .. " vs questie " .. fmt_list(quest.races) .. " (questie used)")
      elseif not have_row then
        note("race: wowhead mask " .. wmask .. " not used (quest not in QuestieDB)")
      end
    end
  else
    if wmask and wmask < TWO32 then
      quest.races = races_from_mask(wmask)
    elseif wmask then
      note("race: wowhead mask " .. string.format("%.0f", wmask) .. " ignored (2^32 or more, unreliable on Forever quests)")
    end
  end

  -- classes: QuestieDB, else a single-class Wowhead mask (not for Camping 101 profession quests).
  local qclasses = nz(q.requiredClasses) and mask_to_list(q.requiredClasses, CLASS_BITS) or nil
  if qclasses and #qclasses == 0 then qclasses = nil end
  local wclass
  local rc = nz(wh.reqclass)
  if rc then
    for token, bit in pairs(CLASS_BITS) do
      if bit == rc then wclass = token end
    end
  end
  local camping = (quest.name or ""):sub(1, 11) == "Camping 101"
  if qclasses then
    quest.classes = qclasses
    if wclass and not camping and not (#qclasses == 1 and qclasses[1] == wclass) then
      note("class: wowhead " .. wclass .. " vs questie " .. table.concat(qclasses, "/") .. " (questie used)")
    end
  elseif wclass and not camping then
    quest.classes = { wclass }
  end

  quest.pre_single = sorted_values(q.preQuestSingle)
  quest.pre_group = sorted_values(q.preQuestGroup)
  quest.objectives = objectives_for(self, id, q, notes)
  quest.starter, quest.starter_kind = starter_of(q.startedBy)
  quest.ender, quest.ender_kind = starter_of(q.finishedBy)

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

  quest.confidence = (xp_known and quest.level ~= nil and not assumed) and "verified" or "unverified"
  quest.notes = notes
  return quest
end

function Catalog:quest(id)
  id = tonumber(id)
  if not id then return nil end
  if self._quests[id] == nil then self._quests[id] = build_quest(self, id) or false end
  return self._quests[id] or nil
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

-- ---------- npcs and items ----------

function Catalog:npc(id)
  id = tonumber(id)
  if not id then return nil end
  if self._npcs[id] == nil then
    local n = self.questie and self.questie.npcs[id]
    self._npcs[id] = n and {
      id = id, name = n.name, level_min = n.minLevel, level_max = n.maxLevel, rank = n.rank,
      spawns = n.spawns or {}, zone_id = n.zoneID,
    } or false
  end
  return self._npcs[id] or nil
end

function Catalog:item(id)
  id = tonumber(id)
  if not id then return nil end
  if self._items[id] == nil then
    local it = self.questie and self.questie.items[id]
    local wh = self.wh_items[tostring(id)]
    if not (it or wh) then
      self._items[id] = false
    else
      local drops, notes = {}, {}
      for _, r in ipairs(wh and wh.drops or {}) do drops[#drops + 1] = { npc = r[1], rate = r[2] } end
      if #drops == 0 and it then
        for _, npc in ipairs(it.npcDrops or {}) do drops[#drops + 1] = { npc = npc } end
      end
      local override = self.rate_overrides[tostring(id)]
      if override then
        for _, d in ipairs(drops) do d.rate = override.rate end
        notes[#notes + 1] = "drop rate override: " .. tostring(override.source)
      end
      self._items[id] = { id = id, name = it and it.name, drops = drops, notes = notes }
    end
  end
  return self._items[id] or nil
end

-- Item name -> id for the player's item_count; the lowest id wins a shared name.
function Catalog:item_id(name)
  if not self._item_ids then
    local ids = {}
    local qd = self.questie
    if qd then
      local name_idx = qd.keys.item.name
      for id, row in pairs(qd.rows.item) do
        local n = row[name_idx]
        if n and (ids[n] == nil or id < ids[n]) then ids[n] = id end
      end
    end
    self._item_ids = ids
  end
  return self._item_ids[name]
end

return Catalog
