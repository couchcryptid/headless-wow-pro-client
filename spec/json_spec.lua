local json = require("hwc.json")

describe("hwc.json canonical encoder", function()
  it("sorts object keys at every nesting level and keeps arrays in order", function()
    local s = json.encode({ b = 1, a = { z = 1, y = { 3, 1, 2 }, x = { q = 1, p = 2 } }, c = "x" })
    assert.equal('{"a":{"x":{"p":2,"q":1},"y":[3,1,2],"z":1},"b":1,"c":"x"}', (s:gsub("%s+", "")))
  end)

  it("is independent of insertion order", function()
    local t1, t2 = {}, {}
    for i = 1, 60 do t1["k" .. i] = i end
    for i = 60, 1, -1 do t2["k" .. i] = i end
    assert.equal(json.encode(t1), json.encode(t2))
  end)
end)
