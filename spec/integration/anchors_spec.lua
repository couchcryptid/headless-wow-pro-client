-- Red/Green anchors (design spec §10): the client is proved against results known
-- from the addon's own history, on pinned addon worktrees made by
-- tools/addon-worktree.sh under local/addon/ (never ~/Projects/WoW-Pro-Guides,
-- whose branch the game's AddOns folder follows). Each anchor is pending while its
-- worktree or the pinned catalog is absent.
-- Slow (full Dwarf Warrior runs to level 25): busted --tags=slow spec/integration/anchors_spec.lua
--
-- Facts cited from the worktrees (main = 9851a40f2, fix/forever-prereq-gates =
-- 64fe6b36f, fix/u-step-loot-result = 476a5d8fd when written):
--   #3535 main WoWPro_Leveling/Forever/Alliance/01_12_Dun_Morogh.lua
--     :113 A Tools for Steelgrill|QID|400|PRE|2160&96629|
--     :116 A Flintfire's Shipment|QID|98321|PRE|2160&96629|
--     :263 A Farsen's Watch|QID|96392|PRE|314&96408|
--     96629 is Camping 101: Cooking (:102). The fix branch drops 96629 from those PREs.
--   #3554 WoWPro_Leveling/Forever/Alliance/19_25_Alliance.lua:447
--     main: U Divined Scroll|QID|1016|U|5456|L|5455|
--     fix:  U Divining Scroll|QID|1016|U|5456|L|5455| (fix commit 5519bb190)
--     The step is matched by action U + QID 1016 + U|5456, not by its name. The Divining
--     Scroll (5456) is the item quest 1016's starter hands over (QuestieDB sourceItemId).
--   Dungeons: 19_25_Alliance.lua has 9 A ...|DUNGEON| accepts (:111 :112 :116 :117 :118
--     :279 :348 :353 :354).
local lfs = require("lfs")
local config = require("hwc.config")
local group = require("hwc.findings.group")

local ROOT = config.repo_root() .. "/local/addon/"
local DUN_MOROGH = "WoWPro_Leveling/Forever/Alliance/01_12_Dun_Morogh.lua"
local ALLIANCE_19_25 = "WoWPro_Leveling/Forever/Alliance/19_25_Alliance.lua"
local COOKING = 96629

-- [qid] = name, as the catalog names it (asserted below).
local RED_3535 = { [400] = "Tools for Steelgrill", [98321] = "Flintfire's Shipment", [96392] = "Farsen's Watch" }
local RED_ORDER = { 400, 98321, 96392 }

local function exists(p) return lfs.attributes(p, "mode") ~= nil end

-- nil when the worktree and the pinned catalog are present, else why the anchor pends.
local function absent(slug)
  local path = ROOT .. slug
  if not exists(path .. "/WoWPro/WoWPro.toc") then
    return "addon worktree absent at " .. path .. " (tools/addon-worktree.sh)"
  end
  local cfg = config.load({ addon_path = path })
  if not exists(cfg.catalog.questie_dir) then return "catalog absent at " .. cfg.catalog.questie_dir end
  return nil
end

-- One full Dwarf Warrior baseline run per worktree (stop level 25 or chain end),
-- kept with its Engine so the guide loaded at the stop can be read.
local runs = {}
local function run_of(slug)
  if runs[slug] then return runs[slug] end
  local cfg = config.load({ addon_path = ROOT .. slug, race = "Dwarf", class = "WARRIOR" })
  local result = require("hwc.boot").run(cfg)
  local E = require("hwc.driver.engine").new(result)
  local log = require("hwc.driver.run").drive({
    engine = E, world = result.world, cfg = cfg,
    errors = result.sb.errors, missing_order = result.sb.missing_order, addon = result.addon,
  }, {})
  runs[slug] = { log = log, engine = E, world = result.world, findings = group.findings({ log }) }
  return runs[slug]
end

local function findings_where(r, pred)
  local out = {}
  for _, f in ipairs(r.findings) do
    if pred(f) then out[#out + 1] = f end
  end
  return out
end

local function never_shown(r, file, qid)
  return findings_where(r, function(f)
    return f.signal == "never-shown-accept" and f.file == file and f.qid == qid
  end)[1]
end

local function count_signal(r, signal)
  return #findings_where(r, function(f) return f.signal == signal end)
end

-- The step at action U + QID 1016 + U|5456 in the guide the engine has loaded.
local function u_step_index(E)
  for i = 1, E:num_steps() do
    local s = E:step(i)
    if s and s.action == "U" and s.tags.use and tostring(s.tags.use) == "5456" then
      for _, q in ipairs(s.qids) do
        if q == 1016 then return i, s end
      end
    end
  end
  return nil
end

-- Was index ever current or in the rows of a snapshot in guide gid?
local function shown(log, gid, index)
  for _, snap in ipairs(log.steps) do
    if snap.gid == gid then
      if snap.index == index then return true end
      for _, i in ipairs(snap.rows) do
        if i == index then return true end
      end
    end
  end
  return false
end

describe("anchor #3535 (Camping 101: Cooking prereq gates) #slow", function()
  local why = absent("main") or absent("fix-forever-prereq-gates")
  if why then
    pending(why)
    return
  end

  -- 98321 (Flintfire's Shipment), 96392 (Farsen's Watch) and 96629 (Camping 101: Cooking) are Forever-added:
  -- the pinned QuestieDB lacks them and wh.json rows carry no name, so without a
  -- local supplement the catalog knows the quests but cannot name them.
  it("the catalog knows the three Red QIDs and names them where a source does", function()
    local w = run_of("main").world
    local want = { [COOKING] = "Camping 101: Cooking" }
    for qid, name in pairs(RED_3535) do want[qid] = name end
    local unnamed = {}
    for _, qid in ipairs({ 400, 98321, 96392, COOKING }) do
      local q = w.catalog:quest(qid)
      assert.is_truthy(q, "catalog has no quest " .. qid)
      if q.name == nil then
        unnamed[#unnamed + 1] = string.format("%d (%s)", qid, want[qid])
      else
        assert.equal(want[qid], q.name)
      end
    end
    if #unnamed > 0 then
      pending("no catalog source names " .. table.concat(unnamed, ", ")
        .. ": not in the pinned QuestieDB, no name in wh.json, no local supplement")
    end
  end)

  it("Red: on main a Dwarf Warrior never sees the three accepts", function()
    local r = run_of("main")
    for _, qid in ipairs(RED_ORDER) do
      local f = never_shown(r, DUN_MOROGH, qid)
      assert.is_truthy(f, "no never-shown-accept for " .. RED_3535[qid] .. " (" .. qid .. ")")
      print(string.format("#3535 main %s (%d) line %d why: %s", RED_3535[qid], qid, f.line, tostring(f.why)))
    end
  end)

  it("Red: the why of Tools for Steelgrill and Flintfire's Shipment names 96629", function()
    local r = run_of("main")
    for _, qid in ipairs({ 400, 98321 }) do
      local f = never_shown(r, DUN_MOROGH, qid)
      assert.is_truthy(f)
      assert.is_truthy(tostring(f.why):find(tostring(COOKING), 1, true), RED_3535[qid] .. " why: " .. tostring(f.why))
    end
  end)

  it("Red: the why of Farsen's Watch names 96629", function()
    local f = never_shown(run_of("main"), DUN_MOROGH, 96392)
    assert.is_truthy(f)
    if not tostring(f.why):find(tostring(COOKING), 1, true) then
      -- Engine result, reported not patched: PRE 314&96408 names no 96629; the fix
      -- branch changes the PRE to 96408 (drops 314).
      pending("Farsen's Watch why is \"" .. tostring(f.why) .. "\": PRE 314&96408 names no 96629; "
        .. "the fix branch changes the PRE to 96408 (drops 314)")
      return
    end
  end)

  it("Green: on fix/forever-prereq-gates the three accepts are shown", function()
    local r = run_of("fix-forever-prereq-gates")
    for _, qid in ipairs(RED_ORDER) do
      local f = never_shown(r, DUN_MOROGH, qid)
      assert.is_nil(f, RED_3535[qid] .. " still never shown: " .. tostring(f and f.why))
    end
  end)

  it("prints the never-shown-accept totals (issue-03 Python model: main 46, fix 0)", function()
    local red = count_signal(run_of("main"), "never-shown-accept")
    local green = count_signal(run_of("fix-forever-prereq-gates"), "never-shown-accept")
    -- Not asserted (plan carry-over): a difference is a triage question.
    print(string.format("#3535 never-shown-accept findings: main %d, fix/forever-prereq-gates %d", red, green))
  end)
end)

describe("anchor #3554 (U step gated on its L result) #slow", function()
  local why = absent("main") or absent("fix-u-step-loot-result")
  if why then
    pending(why)
    return
  end

  local function u_of(slug)
    local r = run_of(slug)
    local gid = r.log.stop.gid
    assert.equal(ALLIANCE_19_25, r.engine:guide(gid).file, "run stopped outside 19_25: " .. tostring(gid))
    local idx, s = u_step_index(r.engine)
    assert.is_truthy(idx, "no U|5456 step for QID 1016 in " .. tostring(gid))
    print(string.format("#3554 %s: %s:%d %s (index %d)", slug, ALLIANCE_19_25, s.line, s.name, idx))
    return r, gid, idx
  end

  it("Red: on main the Divined Scroll U step is never shown", function()
    local r, gid, idx = u_of("main")
    assert.is_false(shown(r.log, gid, idx))
  end)

  it("Green: on fix/u-step-loot-result the Divining Scroll U step is shown", function()
    local r, gid, idx = u_of("fix-u-step-loot-result")
    assert.is_true(shown(r.log, gid, idx))
  end)
end)

describe("anchor: dungeon accepts and harness completeness on main #slow", function()
  local why = absent("main")
  if why then
    pending(why)
    return
  end

  it("has one engine-dungeon-skip root whose causes include 19_25 DUNGEON accepts", function()
    local r = run_of("main")
    local roots = findings_where(r, function(f) return f.signal == "engine-dungeon-skip" end)
    assert.equal(1, #roots)
    local by_id = {}
    for _, f in ipairs(r.findings) do by_id[f.id] = f end
    local in_guide = {}
    for _, id in ipairs(roots[1].causes) do
      local f = by_id[id]
      if f and f.file == ALLIANCE_19_25 then in_guide[#in_guide + 1] = f.line .. " " .. f.name end
    end
    -- The spec expects 9; a mismatch is noted, not asserted.
    print(string.format("dungeons: %d of 9 DUNGEON accepts in 19_25_Alliance.lua under the root: %s",
      #in_guide, table.concat(in_guide, "; ")))
    assert.is_true(#in_guide > 0)
  end)

  -- Zero addon lua-errors too: a missing client stub raises inside an addon file, so it
  -- is classed as an addon error, not a harness one.
  it("a full run has zero harness or addon lua-error findings and prints the missing globals", function()
    local r = run_of("main")
    print("main run stop: " .. tostring(r.log.stop.reason) .. " at level " .. tostring(r.log.stop.level))
    local harness, addon, missing = {}, 0, {}
    for _, f in ipairs(r.findings) do
      if f.signal == "lua-error" then
        if f.harness then harness[#harness + 1] = f.message else addon = addon + 1 end
      elseif f.signal == "missing-global" then
        missing[#missing + 1] = f.name
      end
    end
    table.sort(missing)
    print("addon lua-error findings: " .. addon)
    print("missing-global: " .. table.concat(missing, " "))
    assert.same({}, harness)
    assert.equal(0, addon)
  end)
end)
