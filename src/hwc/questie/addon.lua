-- Loads the installed, unmodified QuestieDB release into its own hwc sandbox,
-- as one character's client would at login. QuestieDB's dynamic corrections
-- read the player's class and faction while they load, so every call gets a
-- fresh sandbox; only the parsed TOC metadata (tocmeta's per-process cache)
-- is shared between characters.
local sandbox = require("hwc.sandbox")
local toc = require("hwc.toc")
local tocmeta = require("hwc.questie.tocmeta")
local encoding = require("hwc.questie.encoding")
local release = require("hwc.questie.release")

local M = {}

local ADDON = "QuestieDB"
local TOC = "QuestieDB/QuestieDB_Forever.toc"
local GAME = "Forever"

-- Classic class IDs, the second value UnitClassBase returns.
local CLASS_ID = {
  WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5,
  SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11,
}

-- Globals QuestieDB only probes with rawget, so their absence is expected.
local ALLOWED_MISSING = {}

local function fail(msg) error("hwc: questie: " .. msg, 0) end

local function install_standins(env, version_dir, character)
  local toc_path = version_dir .. "/" .. TOC
  -- The baked store reads every entity field from the TOC metadata
  -- (QuestieDB src/read/baked.lua:21).
  env.C_AddOns = {
    GetAddOnMetadata = function(name, key)
      if name ~= ADDON then return nil end
      return tocmeta.parse(toc_path)[key]
    end,
  }
  -- src/read/baked.lua:15, src/l10n/overlay.lua:19
  env.C_EncodingUtil = encoding.c_encoding_util()
  -- A Forever client answers 0 (src/corrections/register.lua:68-70).
  env.C_Seasons = { GetActiveSeason = function() return 0 end }
  -- src/corrections/Forever/legacy/classicQuestFixes.lua:32,
  -- src/corrections/Forever/foreverQuestFixes.lua:42
  env.UnitClassBase = function(unit)
    if unit == "player" then return character.class, CLASS_ID[character.class] end
  end
  -- Called as UnitFactionGroup("Player") by every fix file and
  -- support/Forever/Zones/dungeons.lua:5; the client ignores the case.
  env.UnitFactionGroup = function(unit)
    if type(unit) == "string" and unit:lower() == "player" then
      return character.faction, character.faction
    end
  end
  -- src/l10n/overlay.lua:395
  env.GetLocale = function() return "enUS" end
end

-- Returns QuestieDB's private addon table (the second vararg every file
-- receives) and the sandbox it ran in. lib.xp_db and lib.drop_tables are hwc's:
-- the QuestXP db and the drop tables the support files populated
-- (src/support/data.lua:21; support/Forever/DropTables/*.lua).
function M.load(version_dir, character)
  local sb = sandbox.new({ class = character.class, faction = character.faction })
  install_standins(sb.env, version_dir, character)

  local lib = {}
  for _, e in ipairs(toc.files(version_dir, TOC, GAME)) do
    if e.skipped then fail(e.rel .. ": skipped (" .. e.skipped .. ")") end
    local before = #sb.errors
    sb:run_file(e.path, ADDON, lib)
    if #sb.errors > before then fail(e.rel .. ": " .. sb.errors[before + 1].msg) end
  end
  if #sb.errors > 0 then fail(sb.errors[1].msg) end
  for _, name in ipairs(sb.missing_order) do
    if not ALLOWED_MISSING[name] then fail("missing global " .. name) end
  end

  local ok, msg = lib.RequireContract(release.SUPPORTED_CONTRACT)
  if not ok then local installed = tostring(version_dir):match("([^/]+)/*$") or tostring(version_dir)
    fail(tostring(msg) .. "; installed " .. installed .. "; run hwc sync questie --tag <a compatible tag>") end

  local xp = lib.Support and lib.Support.Get("QuestXP")
  if not (xp and type(xp.db) == "table") then fail("no QuestXP data") end
  lib.xp_db = xp.db
  -- Optional: a release without drop tables leaves item drops rate-less.
  lib.drop_tables = {
    data = lib.Support.Get("QuestieClassicItemDrops"),
    corrections = lib.Support.Get("QuestieItemDropCorrections"),
    keys = lib.Support.Get("DropDB") and lib.Support.Get("DropDB").correctionKeys,
  }
  return lib, sb
end

return M
