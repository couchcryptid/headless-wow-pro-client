local lfs = require("lfs")
local home = require("hwc.questie.home")

local function mkdirs(path)
  local cur = ""
  for part in path:gmatch("[^/]+") do
    cur = cur .. "/" .. part
    lfs.mkdir(cur)
  end
end

local function touch(path, text)
  local f = assert(io.open(path, "wb"))
  f:write(text or "")
  f:close()
end

describe("home.root", function()
  it("prefers hwc_home", function()
    assert.are.equal("/x", home.root({ hwc_home = "/x", home = "/h" }))
  end)
  it("falls back to home/.hwc", function()
    assert.are.equal("/h/.hwc", home.root({ home = "/h" }))
  end)
  it("reports an unset HOME for false or empty values", function()
    assert.are.same({ nil, "hwc: HOME is not set; set HWC_HOME" }, { home.root({ home = false }) })
    assert.are.same({ nil, "hwc: HOME is not set; set HWC_HOME" }, { home.root({ hwc_home = "", home = "" }) })
  end)
  it("never reads os.getenv when env is given", function()
    local real = os.getenv
    os.getenv = function() error("os.getenv called") end
    local ok, r = pcall(home.root, { home = "/h" })
    os.getenv = real
    assert.is_true(ok)
    assert.are.equal("/h/.hwc", r)
  end)
  it("reads the process environment when env is nil", function()
    local real = os.getenv
    os.getenv = function(k) return ({ HWC_HOME = "/e" })[k] end
    local ok, r = pcall(home.root)
    os.getenv = real
    assert.is_true(ok)
    assert.are.equal("/e", r)
  end)
end)

describe("home store", function()
  local r
  before_each(function()
    r = os.tmpname()
    os.remove(r)
    mkdirs(r)
  end)
  after_each(function() os.execute("rm -rf '" .. r .. "'") end)

  local function install(tag)
    local d = home.version_dir(r, tag)
    mkdirs(d .. "/QuestieDB")
    touch(d .. "/QuestieDB/QuestieDB_Forever.toc", "## Interface: 16001\n")
    return d
  end

  it("version_dir builds root/questie/tag and rejects bad tags", function()
    assert.are.equal(r .. "/questie/v1.1.2", home.version_dir(r, "v1.1.2"))
    assert.has_error(function() home.version_dir(r, "../x") end, "hwc: questie: bad tag ../x")
  end)

  it("active is nil until set_active, then round-trips", function()
    assert.is_nil(home.active(r))
    home.set_active(r, "v1.1.2")
    assert.are.equal("v1.1.2", home.active(r))
    assert.is_nil(lfs.attributes(r .. "/questie/active.tmp"))
  end)

  it("set_active raises and removes the tmp file when close fails", function()
    local r = os.tmpname()
    os.remove(r)
    local real = io.open
    io.open = function(path, mode)
      local f, err = real(path, mode)
      if f and tostring(path):find("active.tmp", 1, true) then
        local h = f
        return { write = function(_, ...) return h:write(...) end,
          close = function() h:close(); return nil, "disk full" end }
      end
      return f, err
    end
    local ok, e = pcall(home.set_active, r, "v1.1.2")
    io.open = real
    assert.is_false(ok)
    assert.are.equal("hwc: cannot write " .. r .. "/questie/active: disk full", e)
    assert.is_nil(lfs.attributes(r .. "/questie/active.tmp", "mode"))
    assert.is_nil(home.active(r))
    os.execute("rm -rf '" .. r .. "'")
  end)

  it("set_active raises a hwc error on an unwritable root", function()
    local ok, err = pcall(home.set_active, "/nonexistent/zz", "v1.1.2")
    assert.is_false(ok)
    assert.is_truthy(err:match("^hwc: cannot write /nonexistent/zz/questie/active: "))
  end)

  it("set_active removes active.tmp when the rename fails", function()
    mkdirs(r .. "/questie/active") -- renaming a file over a directory fails
    local ok, err = pcall(home.set_active, r, "v1.1.2")
    assert.is_false(ok)
    assert.is_truthy(err:match("^hwc: cannot write " .. r:gsub("%p", "%%%0") .. "/questie/active: "))
    assert.is_nil(lfs.attributes(r .. "/questie/active.tmp"))
  end)

  it("active is nil and active_dir none installed when active is a directory", function()
    mkdirs(r .. "/questie/active")
    assert.is_nil(home.active(r))
    assert.are.same({ nil, "none installed" }, { home.active_dir(r) })
  end)

  it("a nil root is treated as nothing installed", function()
    assert.is_nil(home.active(nil))
    assert.are.same({ nil, "none installed" }, { home.active_dir(nil) })
  end)

  it("active is nil for an empty file", function()
    mkdirs(r .. "/questie")
    touch(r .. "/questie/active", "\n")
    assert.is_nil(home.active(r))
  end)

  it("active_dir reports none installed, broken, then the dir", function()
    assert.are.same({ nil, "none installed" }, { home.active_dir(r) })
    home.set_active(r, "v1.1.2")
    assert.are.same({ nil, "broken: v1.1.2" }, { home.active_dir(r) })
    local d = install("v1.1.2")
    assert.are.equal(d, home.active_dir(r))
  end)

  it("installed version-sorts numerically and skips dirs without the TOC", function()
    install("v1.10.0"); install("v1.9.0"); install("v1.2.10"); install("v1.2.9")
    mkdirs(home.version_dir(r, "v9.9.9"))
    assert.are.same({ "v1.2.9", "v1.2.10", "v1.9.0", "v1.10.0" }, home.installed(r))
  end)

  it("installed is empty when nothing exists", function()
    assert.are.same({}, home.installed(r))
  end)

  it("read_release parses .hwc-release.json, nil when absent", function()
    local d = install("v1.1.2")
    assert.is_nil(home.read_release(r, "v1.1.2"))
    touch(d .. "/.hwc-release.json",
      '{"tag":"v1.1.2","asset":"a.zip","size":5,"sha256":"ab","downloaded_at":"t"}')
    local rel = home.read_release(r, "v1.1.2")
    assert.are.equal("a.zip", rel.asset)
    assert.are.equal(5, rel.size)
  end)
end)
