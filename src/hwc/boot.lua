-- Boot sequence (design spec §4.3): load the real addon into a sandbox, log
-- the character in, settle the virtual clock and collect the first shown steps.
local addon_info = require("hwc.addon_info")
local sandbox = require("hwc.sandbox")
local toc = require("hwc.toc")
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
local HARNESS = "src/hwc/"
function M.is_harness_error(e)
  local where = e.msg:match("^(.-):%d+:")
  if where and where:find(HARNESS, 1, true) then return true end
  for line in (e.stack or ""):gmatch("[^\n]+") do
    local file = line:match("^%s*(.-):%d+:")
    if file then return file:find(HARNESS, 1, true) ~= nil end
  end
  return false
end

function M.harness_errors(result)
  local out = {}
  for _, e in ipairs(result.errors) do
    if M.is_harness_error(e) then out[#out + 1] = e end
  end
  return out
end

function M.run(cfg)
  local info = addon_info.read(cfg.addon_path)
  if info.commit == "" then
    error("hwc: no git commit for addon path " .. cfg.addon_path
      .. "; refusing to boot an unidentified checkout", 0)
  end

  local sb = sandbox.new(cfg)
  local env = sb.env
  stubs.install(sb, cfg, stubs.player_from(cfg))
  env.math = seeded_math(cfg.seed)
  local function phase(name)
    if cfg.on_phase then cfg.on_phase(name, sb) end
  end
  phase("after_stubs")

  local result = {
    addon = { path = cfg.addon_path, branch = info.branch, commit = info.commit, dirty = info.dirty },
    files_loaded = 0, files_failed = {}, skipped = {},
    errors = sb.errors, missing_order = sb.missing_order, standin_calls = sb.standin_calls,
    sb = sb,
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
