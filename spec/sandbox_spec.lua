local sandbox = require("hwc.sandbox")

local function tmpfile(content)
  local p = os.tmpname()
  local f = assert(io.open(p, "wb")); f:write(content); f:close()
  return p
end

describe("sandbox", function()
  local sb
  before_each(function() sb = sandbox.new({}) end)

  it("isolates globals from the real _G", function()
    local p = tmpfile("X = 1")
    assert.is_true(sb:run_file(p))
    os.remove(p)
    assert.equal(1, sb.env.X)
    assert.is_nil(rawget(_G, "X"))
    assert.equal(sb.env, sb.env._G)
  end)

  it("records missing globals once and resolves builtins silently", function()
    local p = tmpfile("local a = TomTom; local b = TomTom; local c = string; local d = os.date")
    assert.is_true(sb:run_file(p))
    os.remove(p)
    assert.is_true(sb.missing.TomTom)
    assert.is_nil(sb.missing.string)
    assert.same({ "TomTom" }, sb.missing_order)
  end)

  it("does not treat polyfills as missing", function()
    local p = tmpfile("local x = strtrim(' a ')")
    assert.is_true(sb:run_file(p))
    os.remove(p)
    assert.is_nil(sb.missing.strtrim)
  end)

  it("exposes only date/time/clock on os", function()
    assert.is_nil(sb.env.os.execute)
    assert.is_function(sb.env.os.date)
  end)

  it("loads a file with a leading BOM", function()
    local p = tmpfile("\239\187\191Y = 2")
    assert.is_true(sb:run_file(p))
    os.remove(p)
    assert.equal(2, sb.env.Y)
  end)

  it("passes varargs to the chunk", function()
    local p = tmpfile("local n, t = ...; N = n; T = t")
    local priv = {}
    assert.is_true(sb:run_file(p, "Addon", priv))
    os.remove(p)
    assert.equal("Addon", sb.env.N)
    assert.equal(priv, sb.env.T)
  end)

  it("records runtime errors and returns false", function()
    local p = tmpfile('error("boom")')
    assert.is_false(sb:run_file(p))
    os.remove(p)
    assert.matches("boom", sb.errors[1].msg)
    assert.equal(p, sb.errors[1].where)
  end)

  it("records compile errors and returns false", function()
    local p = tmpfile("this is not lua")
    assert.is_false(sb:run_file(p))
    os.remove(p)
    assert.equal(1, #sb.errors)
    assert.equal(p, sb.errors[1].where)
  end)

  it("geterrorhandler records and is stable", function()
    local h = sb.env.geterrorhandler()
    assert.equal(h, sb.env.geterrorhandler())
    xpcall(function() error("x") end, h)
    assert.matches("x", sb.errors[1].msg)
  end)

  it("seterrorhandler still records and calls the custom handler", function()
    local seen
    sb.env.seterrorhandler(function(m) seen = m; return m end)
    xpcall(function() error("y") end, sb.env.geterrorhandler())
    assert.matches("y", sb.errors[1].msg)
    assert.matches("y", seen)
  end)

  -- WoWPro.lua:200-211 captures geterrorhandler() and its replacement chains back to it
  it("a custom handler chaining to the previous handler records once", function()
    local prev = sb.env.geterrorhandler()
    local calls = 0
    sb.env.seterrorhandler(function(m) calls = calls + 1; return prev(m) end)
    xpcall(function() error("w") end, sb.env.geterrorhandler())
    assert.equal(1, #sb.errors)
    assert.equal(1, calls)
  end)

  it("call() is protected and records", function()
    assert.is_false(sb:call(function() error("z") end))
    assert.matches("z", sb.errors[1].msg)
    assert.equal("call", sb.errors[1].where)
    local ok, v = sb:call(function(a) return a end, 5)
    assert.is_true(ok); assert.equal(5, v)
  end)

  it("two sandboxes do not share globals", function()
    local sb2 = sandbox.new({})
    sb.env.Z = 1
    assert.is_nil(sb2.env.Z)
    assert.is_nil(sb.missing.Z)
  end)

  it("initialises chat, standin_calls, clock, frames, cfg", function()
    local cfg = {}
    local s = sandbox.new(cfg)
    assert.same({}, s.chat); assert.same({}, s.standin_calls)
    assert.is_table(s.clock); assert.is_table(s.frames); assert.equal(cfg, s.cfg)
  end)

  it("compiles loadstring chunks into the sandbox env", function()
    local fn = sb.env.loadstring("Z = 5; return Unknown")
    fn()
    assert.equal(5, sb.env.Z)
    assert.is_nil(rawget(_G, "Z"))
    assert.is_true(sb.missing.Unknown)
    local bad, err = sb.env.loadstring("this is not lua")
    assert.is_nil(bad)
    assert.is_string(err)
  end)
end)

describe("sandbox virtual time", function()
  it("date/time start at the fixed virtual epoch and follow the clock", function()
    local sb = sandbox.new({})
    local env = sb.env
    assert.equal(1767225600, env.time())
    assert.equal("000000", env.date("%H%M%S"))
    assert.equal(0, env.os.clock())
    sb.clock:after(65, function() end)
    sb.clock:settle({ max_virtual = 100 })
    assert.equal("000105", env.date("%H%M%S"))
    assert.equal(1767225600 + 65, env.time())
    assert.equal(65, env.os.clock())
    assert.equal("000105", env.os.date("%H%M%S"))
    assert.equal(env.time(), env.os.time())
  end)

  it("formats explicit times in UTC and keeps table forms", function()
    local env = sandbox.new({}).env
    assert.equal("2026-01-01", env.date("%Y-%m-%d", 1767225600))
    assert.equal("2026-01-01", env.date("!%Y-%m-%d", 1767225600))
    local t = env.date("*t", 1767225600)
    assert.equal(2026, t.year); assert.equal(0, t.hour)
    assert.equal(2026, env.date("!*t", 1767225600).year)
  end)

  it("two sandboxes give identical date strings", function()
    assert.equal(sandbox.new({}).env.date(), sandbox.new({}).env.date())
  end)
end)

describe("sandbox print and getfenv", function()
  it("routes print to chat, not stdout", function()
    local sb = sandbox.new({})
    sb.env.print("a", 1, nil, true)
    assert.same({ "a 1 nil true" }, sb.chat)
  end)

  it("getfenv(0) and bare getfenv from a sandboxed chunk return env", function()
    local sb = sandbox.new({})
    assert.equal(sb.env, sb.env.getfenv(0))
    local p = tmpfile("R = getfenv()")
    sb:run_file(p); os.remove(p)
    assert.equal(sb.env, sb.env.R)
    local function f() end
    assert.equal(getfenv(f), sb.env.getfenv(f))
  end)
end)

describe("sandbox error classification", function()
  it("classifies an OnUpdate script error from a non-harness chunk as an addon error", function()
    local sb = sandbox.new({})
    sb.env.NewFrame = function() return sb.frames:create("Frame") end
    local p = tmpfile("local f = NewFrame(); f:SetScript('OnUpdate', function() error('addonboom') end)")
    assert.is_true(sb:run_file(p))
    os.remove(p)
    sb.clock:after(0.2, function() end)
    sb.clock:settle({ max_virtual = 1 })
    assert.matches("addonboom", sb.errors[1].msg)
    assert.is_false(require("hwc.boot").is_harness_error(sb.errors[1]))
  end)
end)

describe("sandbox getfenv/setfenv confinement", function()
  it("getfenv(2) from a sandboxed chunk and getfenv(print) return env", function()
    local sb = sandbox.new({})
    local p = tmpfile("local function f() return getfenv(2) end; R = f(); P = getfenv(print); L = getfenv(loadstring)")
    assert.is_true(sb:run_file(p)); os.remove(p)
    assert.equal(sb.env, sb.env.R)
    assert.equal(sb.env, sb.env.P)
    assert.equal(sb.env, sb.env.L)
  end)

  it("setfenv refuses the real _G and otherwise works", function()
    local sb = sandbox.new({})
    local function f() end
    local ok, err = pcall(sb.env.setfenv, f, _G)
    assert.is_false(ok)
    assert.matches("hwc: setfenv to real _G refused", err)
    local t = {}
    sb.env.setfenv(f, t)
    assert.equal(t, getfenv(f))
  end)
end)

describe("sandbox error recording", function()
  it("keeps recording after sb:record throws inside the error handler", function()
    local sb = sandbox.new({})
    local real = sb.record
    sb.record = function() error("record broke") end
    sb.env.geterrorhandler()("first")
    sb.record = real
    sb:call(function() error("x") end)
    local found = false
    for _, e in ipairs(sb.errors) do if e.msg:find("x", 1, true) then found = true end end
    assert.is_true(found)
    -- and the handler re-entry guard is clear: a handler call records again
    local n = #sb.errors
    sb.env.geterrorhandler()("again")
    assert.equal(n + 1, #sb.errors)
  end)

  it("tags frame script and timer errors with where", function()
    local sb = sandbox.new({})
    sb.env.CreateFrame = function() return sb.frames:create("Frame") end
    sb.env.Boom = function(msg) error(msg) end
    local p = tmpfile([[
      local f = CreateFrame()
      f:RegisterEvent("FOO")
      f:SetScript("OnEvent", function() Boom("ev") end)
      f:SetScript("OnUpdate", function() Boom("up"); f:SetScript("OnUpdate", nil) end)
    ]])
    assert.is_true(sb:run_file(p)); os.remove(p)
    sb.frames:fire("FOO")
    sb.clock:after(0.1, function() sb.env.geterrorhandler() end)
    sb.clock:settle({ max_virtual = 1 })
    local where = {}
    for _, e in ipairs(sb.errors) do where[e.msg:match("ev") and "ev" or "up"] = e.where end
    assert.equal("OnEvent", where.ev)
    assert.equal("OnUpdate", where.up)
  end)

  it("tags C_Timer callback errors with where = timer", function()
    local cfg = require("hwc.config").load({ race = "Dwarf", class = "WARRIOR" })
    local sb = sandbox.new(cfg)
    local stubs = require("hwc.stubs.core")
    stubs.install(sb, cfg)
    sb.env.C_Timer.After(0.1, function() error("tick") end)
    sb.clock:settle({ max_virtual = 1 })
    assert.equal("timer", sb.errors[1].where)
  end)
end)
