local clock = require("hwc.clock")

describe("clock", function()
  it("runs timers in time order and advances now to the last one", function()
    local c = clock.new()
    assert.are.equal(1000.0, c:now())
    local order = {}
    c:after(0.25, function() order[#order + 1] = "b" end)
    c:after(0.1, function() order[#order + 1] = "a" end)
    local r = c:settle()
    assert.are.same({ "a", "b" }, order)
    assert.are.equal(2, r.ran)
    assert.is_false(r.hit_limit)
    assert.is_true(math.abs(c:now() - 1000.25) < 1e-9)
    assert.are.equal(c:now(), r.now)
  end)

  it("runs same-time timers in insertion order and treats negative delay as 0", function()
    local c = clock.new()
    local order = {}
    c:after(0.5, function() order[#order + 1] = 1 end)
    c:after(0.5, function() order[#order + 1] = 2 end)
    c:after(-3, function() order[#order + 1] = 0 end)
    c:settle()
    assert.are.same({ 0, 1, 2 }, order)
  end)

  it("runs an after(0) scheduled from a callback within the same settle, after itself", function()
    local c = clock.new()
    local order = {}
    c:after(0.1, function()
      order[#order + 1] = "outer"
      c:after(0, function() order[#order + 1] = "inner" end)
      order[#order + 1] = "outer-end"
    end)
    local r = c:settle()
    assert.are.same({ "outer", "outer-end", "inner" }, order)
    assert.are.equal(2, r.ran)
  end)

  it("does not let tickers keep settle running", function()
    local c = clock.new()
    local n = 0
    c:add_ticker(function() n = n + 1 end)
    local r = c:settle()
    assert.are.equal(0, r.ran)
    assert.are.equal(0, n)
  end)

  it("calls tickers about 30 times per second until a timer", function()
    local c = clock.new()
    local n, total = 0, 0
    c:add_ticker(function(e) n = n + 1; total = total + e end)
    c:after(1.0, function() end)
    c:settle()
    assert.is_true(n >= 29 and n <= 31)
    assert.is_true(math.abs(total - 1.0) < 1e-9)
  end)

  it("stops calling a cancelled ticker", function()
    local c = clock.new()
    local n = 0
    local h = c:add_ticker(function() n = n + 1 end)
    c:after(0.2, function() h:cancel() end)
    c:after(1.0, function() end)
    c:settle()
    assert.is_true(n <= 7)
  end)

  it("returns hit_limit for a self-rescheduling timer", function()
    local c = clock.new()
    local function again() c:after(0.1, again) end
    c:after(0.1, again)
    local r = c:settle({ max_virtual = 5 })
    assert.is_true(r.hit_limit)
    assert.is_true(c:now() - 1000.0 >= 5 - 1e-9)
  end)

  -- OnUpdate-driven work (WoWPro_Broker.lua:4840-4874 lockdown) has no timer to wait on
  it("keeps ticking with an empty queue while busy() holds", function()
    local c = clock.new()
    local left = 1.5
    c:add_ticker(function(dt) if left then left = left - dt; if left < 0 then left = nil; c:after(0.25, function() end) end end end)
    local r = c:settle({ busy = function() return left ~= nil end })
    assert.is_nil(left)
    assert.equal(1, r.ran)
    assert.is_false(r.hit_limit)
    assert.is_true(c:now() - 1000.0 >= 1.75 - 1e-9)
  end)

  it("hits the limit when busy() never clears", function()
    local c = clock.new()
    local r = c:settle({ max_virtual = 2, busy = function() return true end })
    assert.is_true(r.hit_limit)
  end)

  it("propagates callback errors", function()
    local c = clock.new()
    c:after(0.1, function() error("boom") end)
    assert.has_error(function() c:settle() end)
  end)
end)
