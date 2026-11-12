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
    local md, js = {}, {}
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
      local jpath = dir .. "/2026-11-12-Dwarf-WARRIOR-baseline.json"
      assert.equal("file", lfs.attributes(jpath, "mode"), "missing " .. jpath)
      js[i] = slurp(jpath)
    end
    assert.is_true(#md[1] > 0)
    assert.equal(md[1], md[2])
    assert.is_true(#js[1] > 0)
    assert.equal(js[1], js[2])
  end)

  it("writes no absolute addon path or cwd under --out", function()
    local dir = os.tmpname()
    os.remove(dir)
    local _, code = shell(string.format(
      "bin/hwc run --race Dwarf --class WARRIOR --stop-level 6 --date 2026-11-12 --addon '%s' --out '%s' 2>/dev/null",
      flow.ADDON, dir))
    assert.equal(0, code)
    local cwd = lfs.currentdir()
    local files = 0
    local function walk(d)
      for name in lfs.dir(d) do
        if name ~= "." and name ~= ".." then
          local p = d .. "/" .. name
          if lfs.attributes(p, "mode") == "directory" then
            walk(p)
          else
            files = files + 1
            local text = slurp(p)
            assert.is_nil(text:find(flow.ADDON, 1, true), "addon path in " .. p)
            assert.is_nil(text:find(cwd, 1, true), "cwd in " .. p)
          end
        end
      end
    end
    walk(dir)
    assert.is_true(files >= 3)
  end)

  it("rewrites a relative --addon against a --relative-to that is not the cwd", function()
    local cwd = lfs.currentdir()
    local abs = flow.ADDON
    local rel = "local/addon/main"
    if lfs.attributes(cwd .. "/" .. rel .. "/WoWPro/WoWPro.toc", "mode") == nil then
      pending("no addon checkout at " .. rel)
      return
    end
    abs = cwd .. "/" .. rel
    local base = cwd .. "/local/addon"
    local dir = os.tmpname()
    os.remove(dir)
    local _, code = shell(string.format(
      "bin/hwc run --race Dwarf --class WARRIOR --stop-level 6 --date 2026-11-12 --addon '%s' --relative-to '%s' --out '%s' 2>/dev/null",
      rel, base, dir))
    assert.equal(0, code)
    local doc = require("dkjson").decode(slurp(dir .. "/2026-11-12-Dwarf-WARRIOR-baseline.json"))
    local hdr = doc.header or doc
    assert.equal("main", hdr.addon.path)
    assert.equal("addon", hdr.paths_relative_to)
    local function walk(d)
      for name in lfs.dir(d) do
        if name ~= "." and name ~= ".." then
          local p = d .. "/" .. name
          if lfs.attributes(p, "mode") == "directory" then
            walk(p)
          else
            local text = slurp(p)
            assert.is_nil(text:find(abs, 1, true), "addon path in " .. p)
            assert.is_nil(text:find(cwd, 1, true), "cwd in " .. p)
          end
        end
      end
    end
    walk(dir)
  end)
end)
