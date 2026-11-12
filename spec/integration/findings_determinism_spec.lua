-- Two separate `bin/hwc run` processes (fresh LuaJIT string-hash seeds) write
-- byte-identical findings markdown for the same inputs and --date (design spec
-- §9, Ruling B). Pending without the addon checkout or pinned catalog.
-- Slow: busted --tags=slow spec/integration/findings_determinism_spec.lua
local flow = dofile("spec/helpers/world_engine_flow.lua")
local lfs = require("lfs")

local function shell(cmd)
  local p = assert(io.popen(cmd, "r"))
  local out = p:read("*a")
  local ok, _, code = p:close()
  return out, (ok == true or ok == 0) and 0 or code
end

local function slurp(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

describe("findings determinism across processes #slow", function()
  local why = flow.absent()
  if why then
    pending(why)
    return
  end

  it("two bin/hwc run processes give byte-identical findings and clean stderr", function()
    local base = os.tmpname()
    os.remove(base)
    local md = {}
    for i = 1, 2 do
      local dir = base .. "-" .. i
      local errfile = dir .. ".err"
      local _, code = shell(string.format(
        "bin/hwc run --race Dwarf --class WARRIOR --stop-level 6 --date 2026-11-12 --addon '%s' --out '%s' 2>'%s'",
        flow.ADDON, dir, errfile))
      local stderr = slurp(errfile)
      os.remove(errfile)
      assert.equal(0, code, stderr)
      assert.is_nil(stderr:match("harness"), stderr)
      assert.is_nil(stderr:match("hwc:"), stderr)
      local path = dir .. "/2026-11-12-Dwarf-WARRIOR-baseline.md"
      assert.equal("file", lfs.attributes(path, "mode"), "missing " .. path)
      md[i] = slurp(path)
    end
    assert.is_true(#md[1] > 0)
    assert.equal(md[1], md[2])
  end)
end)
