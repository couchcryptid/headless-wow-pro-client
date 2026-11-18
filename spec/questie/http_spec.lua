local http = require("hwc.questie.http")

describe("http.sha256", function()
  local path

  before_each(function()
    path = os.tmpname()
    local f = assert(io.open(path, "wb"))
    f:write("abc")
    f:close()
  end)
  after_each(function() os.remove(path) end)

  local ABC = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

  local function with_tools(has, fn)
    local real = http.has_tool
    http.has_tool = function(name) return has[name] end
    local ok, a, b = pcall(fn)
    http.has_tool = real
    assert(ok, a)
    return a, b
  end

  it("uses shasum when it exists", function()
    if not http.has_tool("shasum") then return pending("shasum not installed") end
    assert.are.equal(ABC, with_tools({ shasum = true }, function() return http.sha256(path) end))
  end)

  it("falls back to sha256sum when shasum is absent", function()
    if not http.has_tool("sha256sum") then return pending("sha256sum not installed") end
    assert.are.equal(ABC, with_tools({}, function() return http.sha256(path) end))
  end)
end)
