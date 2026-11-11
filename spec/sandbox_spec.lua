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
end)
