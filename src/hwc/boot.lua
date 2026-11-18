-- Boot sequence (design spec §4.3): load the real addon into a sandbox, log
-- the character in, settle the virtual clock and collect the first shown steps.
local addon_info = require("hwc.addon_info")
local sandbox = require("hwc.sandbox")
local toc = require("hwc.toc")
local World = require("hwc.world")
local catalog = require("hwc.catalog")
local stubs = require("hwc.stubs.core")
local hbd = require("hwc.stubs.hbd")
local standins = require("hwc.stubs.standins")

local M = {}

local WOWPRO = { addon = "WoWPro", toc = "WoWPro/WoWPro.toc" }
local LEVELING = { addon = "WoWPro_Leveling", toc = "WoWPro_Leveling/WoWPro_Leveling.toc" }
local MAX_STEPS = 15
local SETTLE_MAX_VIRTUAL = 60

-- Park-Miller minimal standard generator: per sandbox, so a run's draws depend
-- only on cfg.seed and never on other runs in the same process.
local function seeded_math(seed)
  local state
  local function reseed(s)
    state = math.floor(tonumber(s) or 1) % 2147483647
    if state <= 0 then state = state + 2147483646 end
  end
  reseed(seed)
  local function next_unit()
    state = (state * 16807) % 2147483647
    return (state - 1) / 2147483646
  end
  local m = {}
  for k, v in pairs(math) do m[k] = v end
  m.randomseed = reseed
  function m.random(lo, hi)
    local u = next_unit()
    if lo == nil then return u end
    if hi == nil then lo, hi = 1, lo end
    if lo > hi then error("bad argument to 'random' (interval is empty)", 2) end
    return lo + math.floor(u * (hi - lo + 1))
  end
  return m
end

local function load_addon(sb, cfg, spec, result)
  local private = {}
  for _, e in ipairs(toc.files(cfg.addon_path, spec.toc, cfg.flavor)) do
    if e.skipped then
      result.skipped[e.rel] = e.skipped
    else
      local before = #sb.errors
      local ok = sb:run_file(e.path, spec.addon, private)
      if ok == false and #sb.errors > before then
        result.files_failed[#result.files_failed + 1] = e.rel
      else
        result.files_loaded = result.files_loaded + 1
      end
      -- ordering: see the stub modules for the addon lines that need these here
      if e.rel == "WoWPro/Libraries/Ace/LibStub/LibStub.lua" then hbd.register(sb) end
      if e.rel == "WoWPro/WoWPro.lua" then standins.install(sb) end
    end
  end
end

local function collect_steps(env)
  local wowpro = env.WoWPro
  local steps = {}
  if type(wowpro) ~= "table" or type(wowpro.rows) ~= "table" then return steps end
  for _, row in ipairs(wowpro.rows) do
    if #steps >= MAX_STEPS then break end
    if row:IsVisible() and row.index then
      local i = row.index
      steps[#steps + 1] = {
        index = i, action = wowpro.action and wowpro.action[i], step = wowpro.step and wowpro.step[i],
        qid = wowpro.QID and wowpro.QID[i], why = wowpro.why and wowpro.why[i],
      }
    end
  end
  return steps
end

-- A harness bug is an error raised in harness code: its message location or
-- the innermost Lua frame of its stack is under src/hwc. (Every stack passes
-- through src/hwc on the way in, so "the stack mentions src/hwc" is not it.)
-- It is also one when the addon indexes or calls a global the sandbox recorded as
-- missing (`missing`, the sandbox's set; design 2026-11-18-reputation §4.7) that the
-- harness should have defined. The sandbox records every nil global read, so a name
-- in `missing` is a gap only when the addon doesn't own it (no `WoWPro` prefix) and
-- it isn't in EXPECTED_ABSENT. The bare name matches a "ns.field" key on its last
-- part, so an addon bug on a same-named field would match too (accepted as rare).
local HARNESS = "src/hwc/"

-- Globals a real Forever player's client also lacks, so the addon meeting them nil is
-- the addon's behaviour, not a harness gap. TomTom is deliberately left out: the
-- guides expect it installed, so its absence is a harness gap until it is stubbed.
M.EXPECTED_ABSENT = {
  -- Absent in the Forever client: GetFactionInfoByID by in-game check, 2026-11-18.
  -- The rest are retail-only APIs WoWPro probes (unverified for Forever).
  GetFactionInfoByID = true, GetQuestLogTitle = true, GetNumQuestLogEntries = true,
  C_PetBattles = true, C_Covenants = true, C_Garrison = true, C_Seasons = true,
  C_QuestLine = true, C_QuestInfoSystem = true, SetSuperTrackedQuestID = true,
  PlayerGetTimerunningSeasonID = true,
  -- Other addons a player may not run; WoWPro checks for them.
  Grail = true, Nx = true, TourGuide = true,
  -- Libraries the addon ships itself (WoWPro/Libraries), so a nil one is the addon's.
  LibStub = true,
}

local function harness_gap(name)
  return name:sub(1, 6) ~= "WoWPro" and not M.EXPECTED_ABSENT[name]
end

local function names_missing(msg, missing)
  if not missing then return false end
  local name = msg:match("attempt to index field '([^']+)' %(a nil value%)")
    or msg:match("attempt to index global '([^']+)' %(a nil value%)")
    or msg:match("attempt to call field '([^']+)' %(a nil value%)")
    or msg:match("attempt to call global '([^']+)' %(a nil value%)")
  if not name or not harness_gap(name) then return false end
  if missing[name] then return true end
  for key in pairs(missing) do
    if type(key) == "string" and key:match("%.([^.]+)$") == name then return true end
  end
  return false
end

function M.is_harness_error(e, missing)
  local where = e.msg:match("^(.-):%d+:")
  if where and where:find(HARNESS, 1, true) then return true end
  if names_missing(e.msg, missing) then return true end
  for line in (e.stack or ""):gmatch("[^\n]+") do
    local file = line:match("^%s*(.-):%d+:")
    if file then return file:find(HARNESS, 1, true) ~= nil end
  end
  return false
end

function M.harness_errors(result)
  local out = {}
  for _, e in ipairs(result.errors) do
    if M.is_harness_error(e, result.missing) then out[#out + 1] = e end
  end
  return out
end

function M.run(cfg)
  if not cfg.addon_path then error("hwc: no WoW-Pro folder", 0) end
  local info = addon_info.read(cfg.addon_path)
  if info.git and info.commit == "" then
    error("hwc: no git commit for addon path " .. cfg.addon_path
      .. "; refusing to boot an unidentified checkout", 0)
  end

  local sb = sandbox.new(cfg)
  local env = sb.env
  -- World facts come from the catalog (design spec §6); absent sources are
  -- recorded in catalog.sources, never fatal.
  local cat = catalog.load(cfg)
  if not cat.sources.questie.present then
    -- cfg.warn (optional) takes the message; without one it goes to stderr.
    local msg = "no QuestieDB installed (" .. tostring(cat.sources.questie.reason) .. "); run hwc init"
    if cfg.warn then
      cfg.warn(msg)
    else
      io.stderr:write("hwc: ", msg, "\n")
    end
  end
  sb.world = World.new(cfg, cat, sb.clock)
  stubs.install(sb, cfg)
  env.math = seeded_math(cfg.seed)
  local function phase(name)
    if cfg.on_phase then cfg.on_phase(name, sb) end
  end
  phase("after_stubs")

  local result = {
    addon = { path = cfg.addon_path, git = info.git, branch = info.branch, commit = info.commit,
      dirty = info.dirty, version = info.version },
    files_loaded = 0, files_failed = {}, skipped = {},
    errors = sb.errors, missing_order = sb.missing_order, missing = sb.missing, standin_calls = sb.standin_calls,
    sb = sb, world = sb.world,
  }
  result.addon_events = {}

  -- Client order (design spec §4.3): each addon's files load, then its
  -- ADDON_LOADED fires, before the next addon's files load.
  local function fire(...)
    sb:call(sb.frames.fire, sb.frames, ...)
    local event, arg1 = ...
    result.addon_events[#result.addon_events + 1] = event == "ADDON_LOADED" and (event .. ":" .. arg1) or event
  end

  load_addon(sb, cfg, WOWPRO, result)
  -- UI stand-ins replace WoWPro's own UI entry points; they must be in place
  -- before any event reaches WoWPro.
  standins.override(sb)
  phase("after_wowpro_files")
  -- The client assigns SavedVariables after the addon's files run and before
  -- ADDON_LOADED. Design spec §4.2: fresh account (WoWProData nil); a saved
  -- DebugLevel 0 keeps ';' lines out of the steps. OnInitialize creates the rest.
  env.WoWProData = nil
  env.WoWProCharDB = { DebugLevel = 0 }
  phase("after_saved_variables")
  fire("ADDON_LOADED", "WoWPro")
  phase("after_addon_loaded_wowpro")
  load_addon(sb, cfg, LEVELING, result)
  phase("after_leveling_files")
  fire("ADDON_LOADED", "WoWPro_Leveling")
  phase("after_addon_loaded_wowpro_leveling")
  env.IsLoggedIn = function() return true end
  fire("PLAYER_LOGIN")
  phase("after_player_login")
  fire("PLAYER_ENTERING_WORLD", true, false)
  phase("after_player_entering_world")
  -- The startup lockdown (WoWPro_Events.lua:279) is released by an OnUpdate
  -- handler (WoWPro_Broker.lua:4840-4874), not a timer: keep frames ticking
  -- while it is pending. Read only; the engine's own handler clears it.
  local function lockdown_pending()
    local w = rawget(env, "WoWPro")
    return type(w) == "table" and w.LockdownTimer ~= nil
  end
  result.settle = sb.clock:settle({ max_virtual = SETTLE_MAX_VIRTUAL, busy = lockdown_pending })

  local wowpro = type(env.WoWPro) == "table" and env.WoWPro or {}
  local db = rawget(env, "WoWProDB")
  result.guide = {
    gid = db and db.char and db.char.currentguide or nil,
    loaded = wowpro.GuideLoaded == true,
    active_step = wowpro.ActiveStep,
  }
  result.steps = collect_steps(env)
  return result
end

return M
