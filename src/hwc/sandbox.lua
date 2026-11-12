-- Isolated environment for the addon's chunks. Reads that miss env fall back
-- to a fixed list of Lua builtins; any other miss is recorded as a missing
-- WoW global (so we know what still needs a stub). Errors, including those
-- AceAddon's safecall would swallow, are recorded in `errors`.
local polyfills = require("hwc.polyfills")
local clock = require("hwc.clock")
local frames = require("hwc.frames")

local M = {}
local Sandbox = {}
Sandbox.__index = Sandbox

local BUILTIN_NAMES = {
  "string", "table", "math", "pairs", "ipairs", "select", "type", "tostring",
  "tonumber", "pcall", "xpcall", "error", "assert", "setmetatable",
  "getmetatable", "rawget", "rawset", "rawequal", "next", "unpack",
  "loadstring", "setfenv", "coroutine", "bit",
}

local function build_builtins()
  local b = {}
  for _, name in ipairs(BUILTIN_NAMES) do b[name] = _G[name] end
  return b
end

function M.new(cfg)
  local sb = setmetatable({
    cfg = cfg, env = {}, errors = {}, missing = {}, missing_order = {},
    chat = {}, standin_calls = {},
  }, Sandbox)
  sb.clock = clock.new()
  -- script errors go to the current error handler, as in the client
  -- unknown frame getters are reported as missing like globals ("Frame:GetX")
  -- MUST stay a tail call: it keeps this closure out of the stack, so the
  -- handler's debug.traceback(..., 3) starts at the addon frame and boot's
  -- is_harness_error classifies script/timer errors as addon errors.
  sb.frames = frames.new(sb.clock, function(e) return sb.env.geterrorhandler()(e) end,
    function(name) sb.missing[name] = true; sb.missing_order[#sb.missing_order + 1] = name end)

  local env = sb.env
  local builtins = build_builtins()
  env._G = env
  setmetatable(env, { __index = function(_, name)
    local v = builtins[name]
    if v ~= nil then return v end
    if type(name) == "string" and not sb.missing[name] then
      sb.missing[name] = true
      sb.missing_order[#sb.missing_order + 1] = name
    end
    return nil
  end })
  polyfills.install(env)

  -- Virtual time: a fixed epoch plus the virtual clock; never the wall clock.
  -- clock:now() starts at 1000.0 (clock.lua START).
  local EPOCH, CLOCK_START = 1767225600, 1000.0
  local function vtime() return EPOCH + math.floor(sb.clock:now() - CLOCK_START) end
  local function vdate(fmt, t)
    fmt = fmt or "%c"
    if fmt:sub(1, 1) ~= "!" then fmt = "!" .. fmt end
    return os.date(fmt, t or vtime())
  end
  local function vclock() return sb.clock:now() - CLOCK_START end
  env.date, env.time = vdate, vtime
  builtins.os = { date = vdate, time = vtime, clock = vclock }

  -- print goes to the chat frame in WoW, never stdout
  function env.print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    sb.chat[#sb.chat + 1] = table.concat(parts, " ")
  end

  -- Every way of asking for an environment answers with the sandbox: any
  -- numeric level (0 = the global env, n = the env of the function n levels up)
  -- and any function whose real env is the real _G (C functions, harness code).
  local real_getfenv, real_setfenv, real_G = getfenv, setfenv, _G
  function env.getfenv(f)
    if f == nil or type(f) == "number" then return env end
    local e = real_getfenv(f)
    if e == real_G then return env end
    return e
  end
  function env.setfenv(f, t)
    if t == real_G then error("hwc: setfenv to real _G refused", 2) end
    return real_setfenv(f, t)
  end

  -- Ace libs (e.g. CallbackHandler-1.0) build code with loadstring; compile it
  -- into the sandbox so it cannot reach the real _G or skip the missing trap.
  local real_loadstring = loadstring
  function env.loadstring(src, chunkname)
    local fn, err = real_loadstring(src, chunkname)
    if not fn then return nil, err end
    return setfenv(fn, env)
  end

  -- A custom handler may chain back to the one it replaced (WoWPro.lua:200-211
  -- captures geterrorhandler() before seterrorhandler), so re-entry while the
  -- custom handler runs returns at once instead of recursing.
  local custom, active = nil, false
  local function handler(msg)
    if active then return msg end
    active = true
    -- every path resets the guard: a throwing record or custom handler must
    -- not leave the handler dead for the rest of the run
    pcall(sb.record, sb, msg, sb.frames.where or "call", debug.traceback("", 2))
    if custom then pcall(custom, msg) end
    active = false
    return msg
  end
  function env.geterrorhandler() return handler end
  function env.seterrorhandler(fn) custom = fn end
  return sb
end

function Sandbox:record(err, where, tb)
  local ok, msg = pcall(tostring, err)
  if not ok then msg = "<error object with failing __tostring>" end
  self.errors[#self.errors + 1] = {
    msg = msg, stack = tb or debug.traceback("", 3), where = where,
  }
end

local function protected(sb, where, fn, ...)
  local res = { xpcall(fn, function(e)
    pcall(sb.record, sb, e, where, debug.traceback("", 2))
    return e
  end, ...) }
  if not res[1] then return false end
  return unpack(res, 1, table.maxn(res))
end

function Sandbox:run_file(path, ...)
  local f, oerr = io.open(path, "rb")
  if not f then self:record(oerr, path); return false end
  local src = f:read("*a")
  f:close()
  if src:sub(1, 3) == "\239\187\191" then src = src:sub(4) end
  local chunk, cerr = loadstring(src, "@" .. path)
  if not chunk then self:record(cerr, path); return false end
  setfenv(chunk, self.env)
  return (protected(self, path, chunk, ...))
end

function Sandbox:call(fn, ...)
  return protected(self, "call", fn, ...)
end

return M
