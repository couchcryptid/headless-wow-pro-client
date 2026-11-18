-- make install / uninstall: a symlinked hwc on PATH finds its repo through the link.
-- Shells out, so slow: busted --tags=slow spec/install_spec.lua
local lfs = require("lfs")

local function sh(cmd)
  local p = io.popen(cmd .. " 2>&1")
  local out = p:read("*a")
  local ok, _, code = p:close()
  return out, ok and 0 or code
end

local function repo_root()
  local src = debug.getinfo(1, "S").source:sub(2)
  local dir = src:match("^(.*)/spec/[^/]*$")
  if dir then return dir end
  return lfs.currentdir()
end

describe("make install #slow", function()
  local root, prefix

  setup(function()
    root = repo_root()
    prefix = os.tmpname()
    os.remove(prefix)
    assert(lfs.mkdir(prefix))
  end)

  teardown(function()
    os.execute("rm -rf '" .. prefix .. "'")
  end)

  it("a symlinked hwc prints help", function()
    local _, code = sh("make -C '" .. root .. "' install PREFIX='" .. prefix .. "'")
    assert.equal(0, code)
    local out, hcode = sh("'" .. prefix .. "/bin/hwc' --help")
    assert.equal(0, hcode)
    assert.matches("Usage: hwc", out)

    local _, ucode = sh("make -C '" .. root .. "' uninstall PREFIX='" .. prefix .. "'")
    assert.equal(0, ucode)
    assert.is_nil(lfs.symlinkattributes(prefix .. "/bin/hwc", "mode"))
  end)

  it("uninstall leaves a hwc that points elsewhere", function()
    assert(lfs.mkdir(prefix .. "/bin") or lfs.attributes(prefix .. "/bin"))
    sh("ln -sf /nonexistent '" .. prefix .. "/bin/hwc'")
    sh("make -C '" .. root .. "' uninstall PREFIX='" .. prefix .. "'")
    assert.is_not_nil(lfs.symlinkattributes(prefix .. "/bin/hwc", "mode"))
  end)
end)
