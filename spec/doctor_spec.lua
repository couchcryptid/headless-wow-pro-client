local lfs = require("lfs")
local dkjson = require("dkjson")
local doctor = require("hwc.doctor")
local release = require("hwc.questie.release")

local function tmpdir()
  local d = os.tmpname()
  os.remove(d)
  assert(lfs.mkdir(d))
  return d
end

local function write(path, text)
  local dir = path:match("^(.*)/[^/]+$")
  local cur = ""
  for p in dir:gmatch("[^/]+") do
    cur = cur .. "/" .. p
    lfs.mkdir(cur)
  end
  local f = assert(io.open(path, "wb"))
  f:write(text)
  f:close()
end

-- A canned GitHub whose newest Forever release is `tag`.
local function fake_github(tag)
  local rel = {
    tag_name = tag, draft = false, prerelease = false, target_commitish = "abcdef1234567",
    assets = {
      { name = "release.json", browser_download_url = "https://x.test/release.json" },
      { name = "QuestieDB-Forever.zip", browser_download_url = "https://x.test/z.zip", size = 1 },
    },
  }
  local manifest = { releases = { { filename = "QuestieDB-Forever.zip", metadata = { { flavor = "Forever" } } } } }
  return function(url)
    if url == release.API .. "/releases?per_page=30" then return { rel } end
    if url == "https://x.test/release.json" then return manifest end
    return nil, "unexpected " .. url
  end
end

-- A minimal valid Forever table install under root/forever/<build>.
local function write_forever(root, build)
  local convert = require("hwc.forever.convert")
  for _, spec in ipairs(convert.TABLES) do
    write(root .. "/forever/" .. build .. "/" .. spec.name .. ".json", '{"columns":[],"rows":[]}')
  end
  write(root .. "/forever/" .. build .. "/.hwc-release.json", '{"build":"' .. build .. '","tables":{}}')
  write(root .. "/forever/active", build .. "\n")
end

describe("doctor", function()
  local root, cwd, counts, env, deps

  local function by_id(report)
    local out = {}
    for _, c in ipairs(report.checks) do out[c.id] = c end
    return out
  end

  before_each(function()
    root, cwd = tmpdir(), tmpdir()
    counts = tmpdir() .. "/counts.json"
    env = { pwd = cwd, cwd = cwd, home = "/nonexistent-home", hwc_home = root }
    write(root .. "/questie/active", "v1.1.2\n")
    write(root .. "/questie/v1.1.2/QuestieDB/QuestieDB_Forever.toc",
      "## X-Flavor: Forever\n## X-Mode: baked\n## X-BUILD-COMMIT: abcdef1234567\n## X-Contract-Version: 4\nfile.lua\n")
    write_forever(root, "1.16.1.64321")
    deps = {
      get_json = fake_github("v1.1.2"),
      has_tool = function() return true end,
      require_ok = function() return true end,
      counts_path = counts,
      luajit_version = "LuaJIT 2.1.1700000000",
    }
  end)

  it("reports a healthy install with no failures, in order", function()
    local report = doctor.run(env, deps)
    assert.is_false(report.failed, doctor.text(report))
    local c = by_id(report)
    assert.are.equal("ok", c.questie.status)
    assert.is_truthy(c.questie.detail:find("v1.1.2 (build abcdef1)", 1, true))
    assert.are.equal("ok", c["questie-toc"].status)
    assert.are.equal("contract 4-4 includes 4", c["questie-contract"].detail)
    assert.are.equal("up to date (v1.1.2)", c["questie-upstream"].detail)
    assert.are.equal("warn", c.wowpro.status)
    assert.are.equal("warn", c.counts.status)
    local order = {}
    for i, x in ipairs(report.checks) do order[i] = x.id end
    assert.are.same({ "luajit", "rocks", "tools", "wowpro", "addon", "questie", "questie-toc",
      "questie-contract", "questie-upstream", "forever", "counts" }, order)
  end)

  it("warns, and still reports everything, when upstream is unreachable", function()
    deps.get_json = function() return nil, "hwc: GET failed" end
    local report = doctor.run(env, deps)
    local c = by_id(report)
    assert.are.equal("warn", c["questie-upstream"].status)
    assert.is_truthy(c["questie-upstream"].detail:find("could not check upstream", 1, true))
    assert.are.equal(11, #report.checks)
    assert.is_false(report.failed)
  end)

  it("fails a broken active install and skips the dependent checks", function()
    os.remove(root .. "/questie/v1.1.2/QuestieDB/QuestieDB_Forever.toc")
    local report = doctor.run(env, deps)
    local c = by_id(report)
    assert.are.equal("fail", c.questie.status)
    assert.are.equal("hwc update --tag v1.1.2", c.questie.fix)
    assert.is_nil(c["questie-toc"])
    assert.is_nil(c["questie-contract"])
    assert.is_nil(c["questie-upstream"])
    assert.is_true(report.failed)
  end)

  it("forever ok shows the build", function()
    local c = by_id(doctor.run(env, deps))
    assert.are.equal("ok", c.forever.status)
    assert.is_truthy(c.forever.detail:find("1.16.1.64321", 1, true))
  end)

  it("forever missing fails with fix hwc update", function()
    os.remove(root .. "/forever/active")
    local report = doctor.run(env, deps)
    local c = by_id(report)
    assert.are.equal("fail", c.forever.status)
    assert.are.equal("none installed", c.forever.detail)
    assert.are.equal("hwc update", c.forever.fix)
    assert.is_true(report.failed)
  end)

  it("forever fails a build with a missing table", function()
    os.remove(root .. "/forever/1.16.1.64321/UiMap.json")
    local c = by_id(doctor.run(env, deps))
    assert.are.equal("fail", c.forever.status)
    assert.is_truthy(c.forever.detail:find("UiMap.json", 1, true))
    assert.are.equal("hwc update", c.forever.fix)
  end)

  it("fails with hwc init when nothing is installed", function()
    os.remove(root .. "/questie/active")
    local c = by_id(doctor.run(env, deps))
    assert.are.equal("none installed", c.questie.detail)
    assert.are.equal("hwc init", c.questie.fix)
  end)

  it("still returns a report when HOME and HWC_HOME are unset", function()
    env.hwc_home, env.home = nil, nil
    local report = doctor.run(env, deps)
    local c = by_id(report)
    assert.are.equal("fail", c.questie.status)
    assert.is_truthy(c.questie.detail:find("HOME is not set", 1, true))
    assert.is_true(report.failed)
  end)

  it("warns when a newer release is available", function()
    deps.get_json = fake_github("v1.1.3")
    local c = by_id(doctor.run(env, deps))
    assert.are.equal("warn", c["questie-upstream"].status)
    assert.are.equal("v1.1.2 → v1.1.3 available", c["questie-upstream"].detail)
    assert.are.equal("hwc update", c["questie-upstream"].fix)
  end)

  it("fails the TOC check on a wrong flavor", function()
    write(root .. "/questie/v1.1.2/QuestieDB/QuestieDB_Forever.toc", "## X-Flavor: Vanilla\n## X-Mode: baked\n")
    local c = by_id(doctor.run(env, deps))
    assert.are.equal("fail", c["questie-toc"].status)
    assert.are.equal("hwc update --tag v1.1.2", c["questie-toc"].fix)
  end)

  it("fails an unsupported contract", function()
    write(root .. "/questie/v1.1.2/QuestieDB/QuestieDB_Forever.toc",
      "## X-Flavor: Forever\n## X-Mode: baked\n## X-Contract-Version: 9\n")
    local c = by_id(doctor.run(env, deps))
    assert.are.equal("fail", c["questie-contract"].status)
    assert.is_truthy(c["questie-contract"].detail:find("does not include 4", 1, true))
  end)

  it("fails tools when unzip is missing", function()
    deps.has_tool = function(name) return name ~= "unzip" end
    local report = doctor.run(env, deps)
    assert.are.equal("fail", by_id(report).tools.status)
    assert.is_true(report.failed)
  end)

  it("passes tools with sha256sum alone and fails with no checksum tool", function()
    deps.has_tool = function(name) return name ~= "shasum" end
    assert.are.equal("ok", by_id(doctor.run(env, deps)).tools.status)
    deps.has_tool = function(name) return name == "curl" or name == "unzip" end
    local c = by_id(doctor.run(env, deps)).tools
    assert.are.equal("fail", c.status)
    assert.is_truthy(c.detail:find("shasum or sha256sum", 1, true))
  end)

  it("fails rocks when lfs is missing and warns when only busted is", function()
    deps.require_ok = function(m) return m ~= "lfs" end
    assert.are.equal("fail", by_id(doctor.run(env, deps)).rocks.status)
    deps.require_ok = function(m) return m ~= "busted" end
    local c = by_id(doctor.run(env, deps))
    assert.are.equal("warn", c.rocks.status)
    assert.are.equal("luarocks --lua-version 5.1 install busted", c.rocks.fix)
  end)

  it("fails luajit that is not 2.1", function()
    deps.luajit_version = "LuaJIT 2.0.5"
    assert.are.equal("fail", by_id(doctor.run(env, deps)).luajit.status)
  end)

  it("finds the WoW-Pro folder", function()
    write(cwd .. "/WoWPro/WoWPro.toc", "## Version: 1\n")
    assert.are.equal("ok", by_id(doctor.run(env, deps)).wowpro.status)
  end)

  it("validates the objective counts file", function()
    local entry = { kind = "item", id = 750, count = 8 }
    write(counts, dkjson.encode({ quests = { ["179"] = { objectives = { entry } } } }))
    local c = by_id(doctor.run(env, deps)).counts
    assert.are.equal("fail", c.status)
    assert.is_truthy(c.detail:find("quest 179 has no source", 1, true))
    write(counts, dkjson.encode({ quests = { ["179"] = { source = "in game", objectives = { entry } } } }))
    assert.are.equal("ok", by_id(doctor.run(env, deps)).counts.status)
    write(counts, "{nope")
    assert.are.equal("fail", by_id(doctor.run(env, deps)).counts.status)
  end)

  it("renders text and json", function()
    local report = doctor.run(env, deps)
    local text = doctor.text(report)
    assert.is_truthy(text:find("ok   luajit: ", 1, true))
    assert.is_truthy(text:find("warn counts: ", 1, true))
    local decoded = dkjson.decode(doctor.json(report))
    assert.are.equal(false, decoded.failed)
    assert.are.equal(11, #decoded.checks)
  end)

  describe("addon check", function()
    local function boot_result(over)
      local r = {
        files_loaded = 42, files_failed = {}, errors = {}, missing_order = {},
        guide = { gid = "X", loaded = true, active_step = "Kill Boars" },
        steps = { { index = 1, action = "A", step = "Get the quest" } },
      }
      for k, v in pairs(over or {}) do r[k] = v end
      return r
    end

    before_each(function()
      write(cwd .. "/WoWPro/WoWPro.toc", "## Version: 1\n")
      deps.boot_run = function() return boot_result() end
    end)

    it("skips, without failing, when there is no WoW-Pro folder", function()
      os.remove(cwd .. "/WoWPro/WoWPro.toc")
      local report = doctor.run(env, deps)
      local c = by_id(report).addon
      assert.are.equal("skip", c.status)
      assert.is_false(report.failed)
      assert.is_truthy(doctor.text(report):find("skip addon: ", 1, true))
      local decoded = dkjson.decode(doctor.json(report))
      assert.are.equal("skip", decoded.checks[5].status)
    end)

    it("is ok when the addon loads with a guide", function()
      local c = by_id(doctor.run(env, deps)).addon
      assert.are.equal("ok", c.status)
      assert.are.equal('42 files loaded, active step "A Get the quest"', c.detail)
    end)

    it("warns on harness errors only", function()
      deps.boot_run = function()
        return boot_result({
          errors = { { msg = "src/hwc/stubs.lua:3: attempt to call global 'Foo'" } },
          missing_order = { "Foo", "Bar" },
        })
      end
      local c = by_id(doctor.run(env, deps)).addon
      assert.are.equal("warn", c.status)
      assert.are.equal("1 harness Lua errors, 2 missing globals", c.detail)
      assert.are.equal("these are gaps in hwc's WoW API stubs; findings still work", c.fix)
    end)

    it("fails on an addon error and names the first", function()
      deps.boot_run = function()
        return boot_result({ errors = { { msg = "WoWPro.lua:9: boom\nstack traceback" } } })
      end
      local report = doctor.run(env, deps)
      local c = by_id(report).addon
      assert.are.equal("fail", c.status)
      assert.are.equal("1 addon Lua errors", c.detail)
      assert.is_truthy(c.fix:find("WoWPro.lua:9: boom", 1, true))
      assert.is_nil(c.fix:find("traceback", 1, true))
      assert.is_true(report.failed)
    end)

    it("fails when no guide loaded", function()
      deps.boot_run = function() return boot_result({ guide = { loaded = false } }) end
      local c = by_id(doctor.run(env, deps)).addon
      assert.are.equal("fail", c.status)
      assert.are.equal("no guide loaded", c.detail)
      assert.are.equal("check the WoW-Pro folder is a complete checkout", c.fix)
    end)

    it("fails, not crashes, when boot raises", function()
      deps.boot_run = function() error("kaboom\nmore", 0) end
      local report = doctor.run(env, deps)
      local c = by_id(report).addon
      assert.are.equal("fail", c.status)
      assert.are.equal("kaboom", c.detail)
      assert.is_true(report.failed)
    end)
  end)

  it("tells you to cd into the WoW-Pro folder", function()
    assert.are.equal("cd into your WoW-Pro folder for hwc run", by_id(doctor.run(env, deps)).wowpro.fix)
  end)

  it("defaults has_tool to a real shell lookup", function()
    deps.has_tool = nil
    local c = by_id(doctor.run(env, deps))
    assert.are.equal("ok", c.tools.status) -- curl and unzip exist on dev machines
  end)
end)
