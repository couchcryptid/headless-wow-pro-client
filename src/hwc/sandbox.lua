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
  "loadstring", "setfenv", "getfenv", "coroutine", "bit", "print",
}

local function build_builtins()
  local b = {}
  for _, name in ipairs(BUILTIN_NAMES) do b[name] = _G[name] end
  b.os = { date = os.date, time = os.time, clock = os.clock }
  return b
end

function M.new(cfg)
  local sb = setmetatable({
    cfg = cfg, env = {}, errors = {}, missing = {}, missing_order = {},
    chat = {}, standin_calls = {},
  }, Sandbox)
  sb.clock = clock.new()
  sb.frames = frames.new(sb.clock)

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

  -- Ace libs (e.g. CallbackHandler-1.0) build code with loadstring; compile it
  -- into the sandbox so it cannot reach the real _G or skip the missing trap.
  local real_loadstring = loadstring
  function env.loadstring(src, chunkname)
    local fn, err = real_loadstring(src, chunkname)
    if not fn then return nil, err end
    return setfenv(fn, env)
  end

  local custom
  local function handler(msg)
    sb:record(msg, "call")
    if custom then pcall(custom, msg) end
    return msg
  end
  function env.geterrorhandler() return handler end
  function env.seterrorhandler(fn) custom = fn end
  return sb
end

function Sandbox:record(err, where, tb)
  self.errors[#self.errors + 1] = {
    msg = tostring(err), stack = tb or debug.traceback("", 3), where = where,
  }
end

local function protected(sb, where, fn, ...)
  local res = { xpcall(fn, function(e)
    sb:record(e, where, debug.traceback("", 2))
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
