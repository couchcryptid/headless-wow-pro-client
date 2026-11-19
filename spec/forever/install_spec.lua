local lfs = require("lfs")
local home = require("hwc.forever.home")
local install = require("hwc.forever.install")
local convert = require("hwc.forever.convert")
local dkjson = require("dkjson")

local function exists(path) return lfs.attributes(path, "mode") ~= nil end

local function read(path)
  local f = assert(io.open(path, "rb"))
  local t = f:read("*a")
  f:close()
  return t
end

local function stage_dirs(root)
  local out = {}
  if not exists(root .. "/forever") then return out end
  for name in lfs.dir(root .. "/forever") do
    if name:match("^%.stage%-") then out[#out + 1] = name end
  end
  return out
end

describe("forever install", function()
  local root, calls, builds

  local function fake_deps(overrides)
    local deps = {
      get_json = function(url)
        calls.get_json = calls.get_json + 1
        if url == install.BUILDS_URL then return builds end
        return nil, "unexpected " .. url
      end,
      download = function(url, path)
        calls.download = calls.download + 1
        calls.urls[#calls.urls + 1] = url
        local name = url:match("/db2/(%w+)/csv")
        local f = assert(io.open(path, "wb"))
        f:write(read("spec/fixtures/forever/" .. name .. ".csv"))
        f:close()
        return true
      end,
      sha256 = function() return ("a"):rep(64) end,
    }
    for k, v in pairs(overrides or {}) do deps[k] = v end
    return deps
  end

  before_each(function()
    root = os.tmpname()
    os.remove(root)
    assert(lfs.mkdir(root))
    calls = { get_json = 0, download = 0, urls = {} }
    builds = { wowf = { { version = "1.16.1.64321" }, { version = "1.16.0.64000" } } }
  end)
  after_each(function() os.execute("rm -rf '" .. root .. "'") end)

  it("installs the newest wowf build and makes it active", function()
    local res = assert(install.sync(root, {}, fake_deps()))
    assert.same({ to = "1.16.1.64321", already = false }, { to = res.to, already = res.already })
    assert.is_nil(res.from)
    assert.equal("1.16.1.64321", home.active(root))
    local dir = home.dir(root, "1.16.1.64321")
    assert.is_true(install.verify(dir))
    assert.equal(#convert.TABLES, calls.download)
    assert.equal("https://wago.tools/db2/TaxiNodes/csv?build=1.16.1.64321", calls.urls[1])
    local rel = dkjson.decode(read(dir .. "/.hwc-release.json"))
    assert.equal("1.16.1.64321", rel.build)
    assert.equal(("a"):rep(64), rel.tables.UiMap.sha256)
    local ui = dkjson.decode(read(dir .. "/UiMap.json"))
    assert.equal(rel.tables.UiMap.rows, #ui.rows)
    assert.equal("ID", ui.columns[1])
    assert.is_false(exists(dir .. "/UiMap.csv"))
    assert.same({}, stage_dirs(root))
  end)

  it("--build pins the version", function()
    local res = assert(install.sync(root, { build = "1.16.0.64000" }, fake_deps()))
    assert.equal("1.16.0.64000", res.to)
    assert.equal("1.16.0.64000", home.active(root))
    assert.equal(0, calls.get_json)
    assert.truthy(calls.urls[1]:find("build=1.16.0.64000", 1, true))
  end)

  it("an installed, verified build is already, with no download", function()
    assert(install.sync(root, {}, fake_deps()))
    calls.download = 0
    home.set_active(root, "1.16.0.64000")
    local res = assert(install.sync(root, {}, fake_deps()))
    assert.is_true(res.already)
    assert.equal("1.16.0.64000", res.from)
    assert.equal(0, calls.download)
    assert.equal("1.16.1.64321", home.active(root))
  end)

  it("a failed download leaves active unchanged and no stage dir", function()
    assert(install.sync(root, { build = "1.16.0.64000" }, fake_deps()))
    local n = 0
    local deps = fake_deps({
      download = function(url, path, mode)
        n = n + 1
        if n == 3 then return nil, "hwc: download " .. url .. " failed" end
        return fake_deps().download(url, path, mode)
      end,
    })
    local res, err = install.sync(root, {}, deps)
    assert.is_nil(res)
    assert.truthy(err:find("failed", 1, true))
    assert.equal("1.16.0.64000", home.active(root))
    assert.same({}, stage_dirs(root))
    assert.is_false(exists(home.dir(root, "1.16.1.64321")))
  end)

  it("a CSV missing a kept column fails with the table named", function()
    local deps = fake_deps({
      download = function(url, path)
        local f = assert(io.open(path, "wb"))
        f:write("ID,Other\n1,2\n")
        f:close()
        return true
      end,
    })
    local res, err = install.sync(root, {}, deps)
    assert.is_nil(res)
    assert.truthy(err:find("hwc: forever: TaxiNodes: missing column", 1, true))
    assert.is_nil(home.active(root))
    assert.same({}, stage_dirs(root))
  end)

  it("a bad build string is refused before any path is built", function()
    for _, bad in ipairs({ "../x", "1.2.3", "1.2.3.4/../..", "" }) do
      local res, err = install.sync(root, { build = bad }, fake_deps())
      assert.is_nil(res)
      assert.equal("hwc: forever: bad build " .. bad, err)
    end
    builds = { wowf = { { version = "../../etc" } } }
    local res, err = install.sync(root, {}, fake_deps())
    assert.is_nil(res)
    assert.truthy(err:find("bad build", 1, true))
    assert.equal(0, calls.download)
    assert.is_false(exists(root .. "/forever"))
  end)

  it("reports an empty builds list", function()
    builds = { wowf = {} }
    local res, err = install.sync(root, {}, fake_deps())
    assert.is_nil(res)
    assert.truthy(err:find("no wowf build", 1, true))
  end)

  it("verify fails when a table JSON is missing", function()
    assert(install.sync(root, {}, fake_deps()))
    local dir = home.dir(root, "1.16.1.64321")
    os.remove(dir .. "/AreaTable.json")
    local ok, err = install.verify(dir)
    assert.is_nil(ok)
    assert.truthy(err:find("AreaTable.json is missing", 1, true))
  end)

  it("init is already when active verifies, else syncs", function()
    local res = assert(install.init(root, fake_deps()))
    assert.is_false(res.already)
    assert.equal("1.16.1.64321", res.sync_result.to)
    assert.is_true(assert(install.init(root, fake_deps())).already)
  end)

  it("home.active_dir reports none installed and broken", function()
    assert.same({ nil, "none installed" }, { home.active_dir(root) })
    home.set_active(root, "1.16.1.64321")
    assert.same({ nil, "broken: 1.16.1.64321" }, { home.active_dir(root) })
  end)
end)
