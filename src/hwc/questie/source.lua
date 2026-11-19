-- The catalog's view of one character's QuestieDB: records keyed by
-- QuestieDB's own field names, quest XP, item drop rates and the item id list.
local lfs = require("lfs")
local addon = require("hwc.questie.addon")
local home = require("hwc.questie.home")
local tocmeta = require("hwc.questie.tocmeta")

local M = {}

local TOC = "QuestieDB/QuestieDB_Forever.toc"

local Source = {}
Source.__index = Source

-- Field names in field-index order, from lib.Meta.<Entity>.keys
-- (QuestieDB src/meta/*Meta.lua).
local function field_names(meta)
  local names, max = {}, 0
  for name, i in pairs(meta.keys) do
    names[i] = name
    if i > max then max = i end
  end
  local indices = {}
  for i = 1, max do indices[i] = i end
  return names, indices
end

-- entity: lib.<Entity>, the same table QuestieDB publishes as the
-- <Entity>DB global (src/api.lua:26-30).
local function record(self, entity_name, id)
  local fields = self._fields[entity_name]
  if not fields then
    local names, indices = field_names(self._lib.Meta[entity_name])
    fields = { names = names, indices = indices }
    self._fields[entity_name] = fields
  end
  -- GetAll takes positional indices too (src/read/shared.lua:393-405).
  local values = self._lib[entity_name].GetAll(id, fields.indices)
  if not values then return nil end
  local out = { id = id }
  for i, name in pairs(fields.names) do out[name] = values[i] end
  return out
end

function Source:quest(id) return record(self, "Quest", id) end
function Source:npc(id) return record(self, "Npc", id) end
function Source:item(id) return record(self, "Item", id) end
function Source:object(id) return record(self, "Object", id) end

function Source:xp(id)
  local e = self._lib.xp_db[id]
  if not e then return nil end
  return { e[1], e[2] }
end

-- QuestieDB ships its generated drop tables as Lua source strings
-- (support/Forever/DropTables/classicItemDrops.lua); each is data only, so it
-- runs with an empty environment. nil when the release lacks the table.
local function drop_table(self, field)
  self._drop_cache = self._drop_cache or {}
  if self._drop_cache[field] == nil then
    local dt = self._lib.drop_tables
    local text = dt and dt.data and dt.data[field]
    local t = false
    if type(text) == "string" then
      local chunk = loadstring(text, "=" .. field)
      if chunk then
        setfenv(chunk, {})
        local ok, v = pcall(chunk)
        if ok and type(v) == "table" then t = v end
      end
    end
    self._drop_cache[field] = t
  end
  return self._drop_cache[field] or nil
end

-- Item id -> { {npc, rate}, ... } sorted by npc, rate 0-1; nil when QuestieDB
-- has no drop data for the item. QuestieDB leaves the merge logic to the
-- consumer (src/support/data.lua:53-56), so hwc's rule per item:NPC pair is:
-- an Era correction wins (a DropDB.correctionKeys sentinel resolves to the
-- matching table's pair, any other number is a manual percent), then the
-- pserver (cmangos) table, then QuestieDB's other generated table.
function Source:drops(item_id)
  local dt = self._lib.drop_tables
  if not dt then return nil end
  local generated = (drop_table(self, "wowheadData") or {})[item_id] or {}
  local pserver = (drop_table(self, "cmangosData") or {})[item_id] or {}
  local era = dt.corrections and dt.corrections.Era
  local fix = (type(era) == "table" and era[item_id]) or {}
  local keys = dt.keys or {}
  local npcs, seen = {}, {}
  for _, t in ipairs({ fix, pserver, generated }) do
    for npc in pairs(t) do
      if not seen[npc] then seen[npc] = true; npcs[#npcs + 1] = npc end
    end
  end
  if #npcs == 0 then return nil end
  table.sort(npcs)
  local out = {}
  for _, npc in ipairs(npcs) do
    local pct = fix[npc]
    if pct == keys.WOWHEAD then pct = generated[npc]
    elseif pct == keys.PSERVER then pct = pserver[npc]
    elseif pct == nil then pct = pserver[npc] or generated[npc] end
    if type(pct) == "number" and pct >= 0 then out[#out + 1] = { npc = npc, rate = pct / 100 } end
  end
  return #out > 0 and out or nil
end

-- QuestieDB's faction constants (src/corrections/enum/factions.lua, loaded into
-- lib.Enum.factionIDs): constant name -> faction id, as a copy; empty when absent.
function Source:factions()
  local out = {}
  local enum = self._lib.Enum
  for k, v in pairs(type(enum) == "table" and type(enum.factionIDs) == "table" and enum.factionIDs or {}) do out[k] = v end
  return out
end

function Source:quest_ids()
  local ids = {}
  for i, id in ipairs(self._lib.Quest.GetAllIds()) do ids[i] = id end
  table.sort(ids)
  return ids
end

function Source:item_ids()
  local ids = {}
  for i, id in ipairs(self._lib.Item.GetAllIds()) do ids[i] = id end
  table.sort(ids)
  return ids
end

function M.from_lib(lib, info)
  return setmetatable({ _lib = lib, _fields = {}, info = info }, Source)
end

local function basename(path) return path:match("([^/]+)/*$") or path end

-- {path, tag, build, sha256} for a version dir whose TOC exists. tag and
-- sha256 come from .hwc-release.json; without a readable one (or outside the
-- <root>/questie/<tag> layout) tag is the dir's basename and sha256 is nil.
function M.info(questie_dir)
  local rel
  local root, tag = questie_dir:match("^(.*)/questie/([^/]+)/*$")
  if root then
    local ok, r = pcall(home.read_release, root, tag)
    rel = ok and r or nil
  end
  rel = rel or {}
  return {
    path = questie_dir, tag = rel.tag or basename(questie_dir),
    build = tocmeta.header(questie_dir .. "/" .. TOC)["X-BUILD-COMMIT"], sha256 = rel.sha256,
  }
end

-- questie_dir is a version dir, <root>/questie/<tag>. The reasons match
-- home.active_dir's.
function M.open(questie_dir, character)
  if not questie_dir then return nil, "none installed" end
  local toc_path = questie_dir .. "/" .. TOC
  if lfs.attributes(toc_path, "mode") ~= "file" then
    return nil, "broken: " .. basename(questie_dir)
  end
  local info = M.info(questie_dir)
  local lib, sb = addon.load(questie_dir, character)
  local src = M.from_lib(lib, info)
  src.sandbox = sb
  return src
end

return M
