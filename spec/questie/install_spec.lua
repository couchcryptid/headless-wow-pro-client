local lfs = require("lfs")
local dkjson = require("dkjson")
local home = require("hwc.questie.home")
local release = require("hwc.questie.release")
local install = require("hwc.questie.install")

local function fixture(name)
  local f = assert(io.open("spec/fixtures/questie/" .. name, "rb"))
  local v = dkjson.decode(f:read("*a"))
  f:close()
  return v
end

local function exists(path) return lfs.attributes(path, "mode") ~= nil end

local function stage_dirs(root)
  local out = {}
  if not exists(root .. "/questie") then return out end
  for name in lfs.dir(root .. "/questie") do
    if name:match("^%.stage%-") then out[#out + 1] = name end
  end
  return out
end

describe("install", function()
  local root, calls, toc, contract, zip_bytes, github

  local function fake_deps(overrides)
    local deps = {
      get_json = function(url)
        calls.get_json = calls.get_json + 1
        local v = github[url]
        if v == nil then return nil, "hwc: GET " .. url .. " failed (curl exit 22)" end
        return v
      end,
      download = function(_, path)
        calls.download = calls.download + 1
        local f = assert(io.open(path, "wb"))
        f:write(("x"):rep(zip_bytes))
        f:close()
        return true
      end,
      unzip = function(_, dest)
        calls.unzip = calls.unzip + 1
        os.execute("mkdir -p '" .. dest .. "/QuestieDB/src'")
        local t = assert(io.open(dest .. "/QuestieDB/QuestieDB_Forever.toc", "wb"))
        t:write(toc, "file.lua\n")
        t:close()
        local c = assert(io.open(dest .. "/QuestieDB/src/config.lua", "wb"))
        c:write(contract)
        c:close()
        return true
      end,
    }
    for k, v in pairs(overrides or {}) do deps[k] = v end
    return deps
  end

  before_each(function()
    root = os.tmpname()
    os.remove(root)
    calls = { get_json = 0, download = 0, unzip = 0 }
    toc = "## X-Flavor: Forever\n## X-Mode: baked\n"
    contract = "config.contractVersion = 4\nconfig.minSupportedContract = 4\n"
    zip_bytes = 10
    local list = fixture("releases.json")
    github = {
      [release.API .. "/releases?per_page=30"] = list,
      ["https://example.test/v1.1.2/release.json"] = fixture("release-v1.1.2.json"),
      ["https://example.test/v1.1.3/release.json"] = fixture("release-v1.1.3.json"),
    }
    for _, rel in ipairs(list) do github[release.API .. "/releases/tags/" .. rel.tag_name] = rel end
  end)
  after_each(function() os.execute("rm -rf '" .. root .. "'") end)

  it("syncs a fresh root to v1.1.2", function()
    local res = assert(install.sync(root, {}, fake_deps()))
    assert.is_nil(res.from)
    assert.are.equal("v1.1.2", res.to)
    assert.are.equal("ddddddd", res.build)
    assert.is_false(res.already)
    assert.are.same({ "v1.1.3" }, res.skipped)
    assert.are.equal("v1.1.2", home.active(root))
    local rel = home.read_release(root, "v1.1.2")
    assert.are.equal("v1.1.2", rel.tag)
    assert.are.equal(10, rel.size)
    assert.is_truthy(rel.sha256:match("^%x+$") and #rel.sha256 == 64)
    assert.is_truthy(rel.downloaded_at:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$"))
    assert.is_false(exists(home.version_dir(root, "v1.1.2") .. "/asset.zip"))
    assert.are.same({}, stage_dirs(root))
  end)

  it("fails and leaves no release file when the close of .hwc-release.json fails", function()
    local real = io.open
    io.open = function(path, mode)
      local f, err = real(path, mode)
      if f and tostring(path):find(".hwc-release.json", 1, true) then
        local h = f
        return { write = function(_, ...) return h:write(...) end,
          close = function() h:close(); return nil, "No space left on device" end }
      end
      return f, err
    end
    local ok, res, err = pcall(install.sync, root, {}, fake_deps())
    io.open = real
    assert.is_true(ok)
    assert.is_nil(res)
    assert.is_truthy(err:find("No space left on device", 1, true))
    assert.is_nil(home.active(root))
  end)

  it("reports already, with no download, when the version is installed", function()
    assert(install.sync(root, {}, fake_deps()))
    local downloads = calls.download
    local res = assert(install.sync(root, {}, fake_deps()))
    assert.is_true(res.already)
    assert.are.equal("v1.1.2", res.from)
    assert.are.equal("ddddddd", res.build)
    assert.are.equal(downloads, calls.download)
  end)

  it("reinstalls over a broken version dir", function()
    assert(install.sync(root, {}, fake_deps()))
    os.remove(home.version_dir(root, "v1.1.2") .. "/QuestieDB/QuestieDB_Forever.toc")
    local res = assert(install.sync(root, {}, fake_deps()))
    assert.is_false(res.already)
    assert.is_true(exists(home.version_dir(root, "v1.1.2") .. "/QuestieDB/QuestieDB_Forever.toc"))
    assert.are.same({}, stage_dirs(root))
  end)

  describe("a failing sync to v1.1.3", function()
    before_each(function()
      assert(install.sync(root, {}, fake_deps()))
      github["https://example.test/v1.1.3/release.json"] = fixture("release-v1.1.3-forever.json")
    end)

    local function assert_untouched(res, err)
      assert.is_nil(res)
      assert.is_string(err)
      assert.are.equal("v1.1.2", home.active(root))
      assert.is_false(exists(home.version_dir(root, "v1.1.3")))
      assert.are.same({}, stage_dirs(root))
    end

    it("leaves things alone when download raises", function()
      assert_untouched(install.sync(root, {}, fake_deps({
        download = function() error("boom") end,
      })))
    end)

    it("leaves things alone when unzip fails", function()
      assert_untouched(install.sync(root, {}, fake_deps({
        unzip = function() return nil, "hwc: unzip failed" end,
      })))
    end)

    it("leaves things alone on the wrong flavor", function()
      toc = "## X-Flavor: Vanilla\n## X-Mode: baked\n"
      assert_untouched(install.sync(root, {}, fake_deps()))
    end)

    it("leaves things alone on a size mismatch", function()
      zip_bytes = 7
      assert_untouched(install.sync(root, {}, fake_deps()))
    end)

    it("leaves things alone on an unsupported contract", function()
      contract = "config.contractVersion = 6\nconfig.minSupportedContract = 5\n"
      local res, err = install.sync(root, {}, fake_deps())
      assert_untouched(res, err)
      assert.is_truthy(err:find("QuestieDB contract 5-6 does not include 4", 1, true))
    end)
  end)

  it("returns a get_json failure unchanged", function()
    local err = "hwc: GET https://api.github.com/x failed (curl exit 22)"
    local res, e = install.sync(root, {}, fake_deps({ get_json = function() return nil, err end }))
    assert.is_nil(res)
    assert.are.equal(err, e)
    assert.is_nil(home.active(root))
  end)

  it("returns nil, err when active cannot be written", function()
    assert(install.sync(root, {}, fake_deps()))
    os.remove(root .. "/questie/active")
    assert(lfs.mkdir(root .. "/questie/active"))
    local res, err = install.sync(root, { tag = "v1.1.2" }, fake_deps())
    assert.is_nil(res)
    assert.is_truthy(err:match("^hwc: cannot write "))
  end)

  it("returns nil, err for a non-version tag instead of raising", function()
    local res, err = install.sync(root, { tag = "preview" }, fake_deps())
    assert.is_nil(res)
    assert.are.equal("hwc: questie: preview is not a version tag (vX.Y.Z)", err)
  end)

  it("removes a freshly installed dir when active cannot be written", function()
    assert(lfs.mkdir(root))
    assert(lfs.mkdir(root .. "/questie"))
    assert(lfs.mkdir(root .. "/questie/active"))
    local res, err = install.sync(root, {}, fake_deps())
    assert.is_nil(res)
    assert.is_truthy(err:match("^hwc: cannot write "))
    assert.is_false(exists(home.version_dir(root, "v1.1.2")))
    assert.are.same({}, stage_dirs(root))
  end)

  it("keeps a pre-existing dir when active cannot be written on the already path", function()
    assert(install.sync(root, {}, fake_deps()))
    os.remove(root .. "/questie/active")
    assert(lfs.mkdir(root .. "/questie/active"))
    local res = install.sync(root, {}, fake_deps())
    assert.is_nil(res)
    assert.is_true(exists(home.version_dir(root, "v1.1.2")))
  end)

  it("init re-syncs when the active version no longer verifies", function()
    assert(install.sync(root, {}, fake_deps()))
    local toc_path = home.version_dir(root, "v1.1.2") .. "/QuestieDB/QuestieDB_Forever.toc"
    local f = assert(io.open(toc_path, "wb"))
    f:write("## X-Flavor: Vanilla\n## X-Mode: baked\nfile.lua\n")
    f:close()
    local before = calls.get_json
    local res = assert(install.init(root, fake_deps()))
    assert.is_false(res.already)
    assert.is_true(calls.get_json > before)
  end)

  it("init is a no-op with a good active version", function()
    assert(install.sync(root, {}, fake_deps()))
    local before = calls.get_json
    local res = assert(install.init(root, fake_deps()))
    assert.is_true(res.already)
    assert.are.equal(before, calls.get_json)
  end)

  it("init syncs when nothing is installed", function()
    local res = assert(install.init(root, fake_deps()))
    assert.is_false(res.already)
    assert.are.equal("v1.1.2", res.sync_result.to)
  end)

  it("passes opts.download_mode to deps.download", function()
    local seen
    assert(install.sync(root, { download_mode = "terminal" }, fake_deps({
      download = function(_, path, mode)
        seen = mode
        local f = assert(io.open(path, "wb"))
        f:write(("x"):rep(zip_bytes))
        f:close()
        return true
      end,
    })))
    assert.are.equal("terminal", seen)
  end)

  it("init forwards opts.download_mode to sync", function()
    local seen
    assert(install.init(root, fake_deps({
      download = function(_, path, mode)
        seen = mode
        local f = assert(io.open(path, "wb"))
        f:write(("x"):rep(zip_bytes))
        f:close()
        return true
      end,
    }), { download_mode = "capture" }))
    assert.are.equal("capture", seen)
  end)
end)
