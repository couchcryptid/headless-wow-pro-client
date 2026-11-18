-- The catalog's view of one character's QuestieDB: records keyed by
-- QuestieDB's own field names, quest XP and the item id list.
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
