local addon_info = require("hwc.addon_info")

local function sh(cmd)
  assert(os.execute(cmd .. " >/dev/null 2>&1"))
end

describe("addon_info.read", function()
  local dir

  before_each(function()
    dir = os.tmpname()
    os.remove(dir)
    sh("mkdir -p '" .. dir .. "'")
    sh("git -C '" .. dir .. "' init")
    sh("git -C '" .. dir .. "' config user.email t@example.com")
    sh("git -C '" .. dir .. "' config user.name t")
    sh("git -C '" .. dir .. "' config commit.gpgsign false")
    local f = assert(io.open(dir .. "/a.txt", "w"))
    f:write("a\n")
    f:close()
    sh("git -C '" .. dir .. "' add a.txt")
    sh("git -C '" .. dir .. "' commit -m init")
  end)

  after_each(function()
    os.execute("rm -rf '" .. dir .. "'")
  end)

  it("reports branch, 40-hex commit and a clean tree", function()
    local info = addon_info.read(dir)
    assert.truthy(info.commit:match("^%x+$") and #info.commit == 40)
    assert.is_true(info.branch == "main" or info.branch == "master")
    assert.is_false(info.dirty)
  end)

  it("reports dirty when an untracked file exists", function()
    local f = assert(io.open(dir .. "/b.txt", "w"))
    f:write("b\n")
    f:close()
    assert.is_true(addon_info.read(dir).dirty)
  end)
end)
