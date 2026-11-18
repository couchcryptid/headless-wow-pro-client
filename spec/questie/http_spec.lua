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

describe("http.sh", function()
  local cmd = "echo out; echo boom >&2; exit 3"

  it("captures stderr text and the exit code", function()
    local body, code, errtext = http.sh(cmd, "capture")
    assert.are.equal("out\n", body)
    assert.are.equal(3, code)
    assert.are.equal("boom\n", errtext)
  end)

  it("discards stderr by default and returns no errtext", function()
    local body, code, errtext = http.sh(cmd)
    assert.are.equal("out\n", body)
    assert.are.equal(3, code)
    assert.is_nil(errtext)
    local _, _, explicit = http.sh(cmd, "discard")
    assert.is_nil(explicit)
  end)

  it("leaves stderr alone in terminal mode", function()
    local body, code, errtext = http.sh("echo out; exit 0", "terminal")
    assert.are.equal("out\n", body)
    assert.are.equal(0, code)
    assert.is_nil(errtext)
  end)
end)

-- Port 1 refuses connections locally, so curl fails with its own message and
-- no spec touches the network.
describe("curl failures", function()
  local url = "http://127.0.0.1:1/x"

  it("get_json reports curl's last stderr line", function()
    local v, err = http.get_json(url)
    assert.is_nil(v)
    assert.is_truthy(err:find("^hwc: GET " .. url:gsub("%p", "%%%0") .. " failed: curl: %(7%)"))
  end)

  it("download reports curl's last stderr line when capturing", function()
    local path = os.tmpname()
    local ok, err = http.download(url, path, "capture")
    os.remove(path)
    assert.is_nil(ok)
    assert.is_truthy(err:find("^hwc: download " .. url:gsub("%p", "%%%0") .. " failed: curl: %(7%)"))
  end)
end)
