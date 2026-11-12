-- Integration: boots the real, unmodified WoW-Pro checkout to its first shown steps.
local lfs = require("lfs")

local ADDON = os.getenv("HOME") .. "/Projects/WoW-Pro-Guides"
local present = lfs.attributes(ADDON .. "/WoWPro/WoWPro.toc", "mode") ~= nil

local ACTIONS = { A = true, C = true, T = true, K = true, R = true, N = true, L = true }

local function harness_errors(result)
  return require("hwc.boot").harness_errors(result)
end

local function print_addon_errors(result)
  local boot = require("hwc.boot")
  for _, e in ipairs(result.errors) do
    if not boot.is_harness_error(e) then
      io.stderr:write("[addon error] ", e.msg, "\n")
    end
  end
end

describe("boot.is_harness_error", function()
  local boot = require("hwc.boot")
  it("is raised in harness code, not merely called through it", function()
    assert.is_true(boot.is_harness_error({ msg = ".../client/src/hwc/stubs/core.lua:9: boom", stack = "" }))
    assert.is_true(boot.is_harness_error({ msg = "boom",
      stack = "stack traceback:\n\t[C]: in function 'x'\n\t.../src/hwc/frames.lua:3: in f\n\t.../WoWPro/A.lua:1: in g" }))
    assert.is_false(boot.is_harness_error({ msg = ".../WoWPro/WoWPro.lua:606: boom",
      stack = "stack traceback:\n\t.../WoWPro/WoWPro.lua:606: in f\n\t.../src/hwc/boot.lua:1: in run" }))
  end)
end)

local function boot(race, class)
  local config = require("hwc.config")
  local cfg = config.load({ addon_path = ADDON, race = race, class = class })
  return require("hwc.boot").run(cfg)
end

describe("boot", function()
  if not present then
    pending("addon checkout absent at " .. ADDON)
    return
  end

  local dwarf
  setup(function() dwarf = boot("Dwarf", "WARRIOR") end)

  it("Dwarf Warrior boots into Dun Morogh", function()
    local r = dwarf
    print_addon_errors(r)
    assert.is_truthy(r.addon.commit:match("^%x+$"))
    assert.equal(40, #r.addon.commit)
    assert.equal("ClassicDunMorogh0112", r.guide.gid)
    assert.is_true(r.guide.loaded)
    assert.is_table(r.steps[1])
    assert.is_true(ACTIONS[r.steps[1].action] == true, "first action: " .. tostring(r.steps[1].action))
    local found = false
    for _, s in ipairs(r.steps) do
      if s.action == "A" and s.step == "Dwarven Outfitters" and s.qid == "179" then found = true end
    end
    assert.is_true(found, "A Dwarven Outfitters (179) not among the first steps")
    assert.is_false(r.settle.hit_limit)
    assert.same({}, harness_errors(r))
  end)

  it("fires addon events in client order", function()
    assert.same({ "ADDON_LOADED:WoWPro", "ADDON_LOADED:WoWPro_Leveling", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD" },
      dwarf.addon_events)
  end)

  it("names the Leveling module after its own addon", function()
    assert.equal("WoWPro_Leveling", dwarf.sb.env.WoWPro.Leveling.baseName)
  end)

  it("assigns WoWProCharDB only after WoWPro's files, and loads Leveling after ADDON_LOADED(WoWPro)", function()
    local config = require("hwc.config")
    local cfg = config.load({ addon_path = ADDON, race = "Dwarf", class = "WARRIOR" })
    local seen = {}
    cfg.on_phase = function(name, sb)
      seen[#seen + 1] = name
      local env = sb.env
      if name == "after_stubs" or name == "after_wowpro_files" then
        seen[name] = rawget(env, "WoWProCharDB") == nil
      elseif name == "after_addon_loaded_wowpro" then
        seen[name] = type(rawget(env, "WoWProCharDB")) == "table"
        seen.leveling_absent = rawget(env.WoWPro, "Leveling") == nil
      end
    end
    require("hwc.boot").run(cfg)
    assert.is_true(seen.after_stubs)
    assert.is_true(seen.after_wowpro_files)
    assert.is_true(seen.after_addon_loaded_wowpro)
    assert.is_true(seen.leveling_absent)
  end)

  it("Gnome Mage boots into Dun Morogh", function()
    local r = boot("Gnome", "MAGE")
    print_addon_errors(r)
    assert.equal("ClassicDunMorogh0112", r.guide.gid)
    assert.is_true(r.guide.loaded)
    assert.is_false(r.settle.hit_limit)
    assert.same({}, harness_errors(r))
  end)

  it("captured chat lines carry no wall-clock time", function()
    for _, line in ipairs(dwarf.sb.chat) do
      local stamp = line:match("^(%d%d%d%d%d%d) ")
      if stamp then assert.matches("^0000", stamp) end
    end
  end)

  it("refuses a checkout without git identity", function()
    local config = require("hwc.config")
    local cfg = config.load({ addon_path = ADDON })
    local info = require("hwc.addon_info")
    local real = info.read
    info.read = function() return { branch = "", commit = "", dirty = false } end
    local ok, err = pcall(require("hwc.boot").run, cfg)
    info.read = real
    assert.is_false(ok)
    assert.matches("commit", tostring(err))
  end)
end)
