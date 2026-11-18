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

-- hwc runs from the WoW-Pro folder; one guide keeps the run short (no level stop).
local REPO = lfs.currentdir()
local RUN = "cd '%s' && '" .. REPO .. "/bin/hwc' run --race Dwarf --class WARRIOR"
  .. " --exclude '*' --include '*01_12_Dun_Morogh*' --date 2026-11-12"
local STEM_PATTERN = "^2026%-11%-12%-Dwarf%-WARRIOR%-baseline%-filtered%-%x%x%x%x%x%x%x%x%.json$"

-- The one findings .json in dir: its name carries the content hash.
local function findings_json(dir)
  local found = {}
  for name in lfs.dir(dir) do
    if name:match(STEM_PATTERN) then found[#found + 1] = name end
  end
  assert.equal(1, #found, "expected one findings .json in " .. dir)
  return dir .. "/" .. found[1], found[1]
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
    local html, js, names = {}, {}, {}
    for i = 1, 2 do
      local dir = base .. "-" .. i
      local errfile = dir .. ".err"
      local _, code = shell(string.format(
        RUN .. " --out '%s' 2>'%s'",
        flow.ADDON, dir, errfile))
      local stderr = slurp(errfile)
      os.remove(errfile)
      assert.equal(0, code, stderr)
      assert.is_nil(stderr:match("harness"), stderr)
      assert.is_nil(stderr:match("hwc:"), stderr)
      local jpath, name = findings_json(dir)
      names[i] = name
      js[i] = slurp(jpath)
      local path = jpath:gsub("%.json$", ".html")
      assert.equal("file", lfs.attributes(path, "mode"), "missing " .. path)
      html[i] = slurp(path)
    end
    assert.is_true(#html[1] > 0)
    assert.equal(html[1], html[2])
    assert.is_true(#js[1] > 0)
    assert.equal(js[1], js[2])
    assert.equal(names[1], names[2])
  end)

  it("writes no absolute addon path or cwd under --out", function()
    local dir = os.tmpname()
    os.remove(dir)
    local _, code = shell(string.format(
      RUN .. " --out '%s' 2>/dev/null",
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

  it("rewrites the WoW-Pro folder against a --relative-to that is not the cwd", function()
    local cwd = lfs.currentdir()
    local rel = "local/addon/main"
    if lfs.attributes(cwd .. "/" .. rel .. "/WoWPro/WoWPro.toc", "mode") == nil then
      pending("no addon checkout at " .. rel)
      return
    end
    local abs = cwd .. "/" .. rel
    local base = cwd .. "/local/addon"
    local dir = os.tmpname()
    os.remove(dir)
    local _, code = shell(string.format(
      RUN .. " --relative-to '%s' --out '%s' 2>/dev/null",
      abs, base, dir))
    assert.equal(0, code)
    local doc = require("dkjson").decode(slurp((findings_json(dir))))
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
