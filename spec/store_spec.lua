local lfs = require("lfs")
local store = require("hwc.store")

local function tmpdir()
  local d = os.tmpname()
  os.remove(d)
  assert(lfs.mkdir(d))
  return d
end

local function write(path, text)
  local f = assert(io.open(path, "wb"))
  f:write(text)
  f:close()
end

local function read(path)
  local f = assert(io.open(path, "rb"))
  local t = f:read("*a")
  f:close()
  return t
end

describe("store", function()
  local dir
  before_each(function() dir = tmpdir() end)
  after_each(function() os.execute("rm -rf '" .. dir .. "'") end)

  describe("place", function()
    it("moves the stage into a free target", function()
      assert(lfs.mkdir(dir .. "/stage"))
      write(dir .. "/stage/new", "n")
      assert.is_true(store.place(dir .. "/stage", dir .. "/target"))
      assert.equal("n", read(dir .. "/target/new"))
      assert.is_false(store.exists(dir .. "/stage"))
    end)

    it("moves a broken existing target aside and replaces it", function()
      assert(lfs.mkdir(dir .. "/target"))
      write(dir .. "/target/old", "o")
      assert(lfs.mkdir(dir .. "/stage"))
      write(dir .. "/stage/new", "n")
      assert.is_true(store.place(dir .. "/stage", dir .. "/target"))
      assert.equal("n", read(dir .. "/target/new"))
      assert.is_false(store.exists(dir .. "/target/old"))
      assert.is_false(store.exists(dir .. "/stage.old"))
    end)

    it("restores the old target when the rename fails", function()
      assert(lfs.mkdir(dir .. "/target"))
      write(dir .. "/target/old", "o")
      local ok, err = store.place(dir .. "/missing-stage", dir .. "/target")
      assert.is_nil(ok)
      assert.truthy(err:find("hwc: cannot install", 1, true))
      assert.equal("o", read(dir .. "/target/old"))
    end)
  end)

  it("write_active writes the value and a newline", function()
    store.write_active(dir .. "/active", "v1")
    assert.equal("v1\n", read(dir .. "/active"))
    assert.is_false(store.exists(dir .. "/active.tmp"))
  end)

  it("write_active raises with the path when it cannot write", function()
    local ok, err = pcall(store.write_active, dir .. "/nope/active", "v1")
    assert.is_false(ok)
    assert.truthy(err:find("hwc: cannot write " .. dir .. "/nope/active: ", 1, true))
  end)
end)
