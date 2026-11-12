-- Integration: the real, unmodified WoW-Pro engine advances through Dun
-- Morogh's first quest when the simulated world changes and the client's
-- events fire (design spec §5.2). Pending without the addon checkout or the
-- pinned Questie catalog (local-only data).
local flow = dofile("spec/helpers/world_engine_flow.lua")

local CLASS_NAME = { WARRIOR = "Warrior", MAGE = "Mage" }

-- The guide line after `T Dwarven Outfitters`, found by content: the first
-- step line whose |C| and |R| tags (if any) admit this character.
local function step_after_turn_in(race, class)
  local f = assert(io.open(flow.GUIDE, "r"))
  local seen_t = false
  for line in f:lines() do
    if not seen_t then
      seen_t = line:match("^T Dwarven Outfitters|QID|179|") ~= nil
    elseif line:match("^%a ") then
      local c = line:match("|C|([^|]*)|")
      local rc = line:match("|R|([^|]*)|")
      if (not c or c:find(CLASS_NAME[class], 1, true)) and (not rc or rc:find(race, 1, true)) then
        f:close()
        local action, step, qid = line:match("^(%a) ([^|]*)|QID|(%d+)|")
        return { action = action, step = step, qid = qid }
      end
    end
  end
  f:close()
  error("no step after T Dwarven Outfitters for " .. race .. " " .. class)
end

local function harness_errors(r) return require("hwc.boot").harness_errors(r) end

local function print_addon_errors(r)
  local boot = require("hwc.boot")
  for _, e in ipairs(r.errors) do
    if not boot.is_harness_error(e) then io.stderr:write("[addon error] ", e.msg, "\n") end
  end
end

local function completes_dwarven_outfitters(race, class)
  local r, snap = flow.run(race, class)
  print_addon_errors(r)
  local env = r.sb.env

  assert.same({ action = "A", step = "Dwarven Outfitters", qid = "179" },
    { action = snap.boot.action, step = snap.boot.step, qid = snap.boot.qid })

  assert.is_truthy(snap.accept.completed, "A step not completed after accept")
  assert.same({ action = "C", step = "Dwarven Outfitters", qid = "179" },
    { action = snap.accept.current.action, step = snap.accept.current.step, qid = snap.accept.current.qid })

  assert.is_truthy(snap.progress.completed, "C step not completed after 8 x item 750")
  assert.same({ action = "T", step = "Dwarven Outfitters", qid = "179" },
    { action = snap.progress.current.action, step = snap.progress.current.step, qid = snap.progress.current.qid })

  assert.is_truthy(snap.turn_in.completed, "T step not completed after turn-in")
  assert.equal(80, r.world.player.xp)
  assert.is_true(env.C_QuestLog.IsQuestFlaggedCompleted(179))
  local cur = snap.turn_in.current
  assert.same(step_after_turn_in(race, class), { action = cur.action, step = cur.step, qid = cur.qid })

  assert.same({}, harness_errors(r))
  for i, s in ipairs(snap.settles) do
    assert.is_false(s.hit_limit, "settle " .. i .. " hit its limit")
  end
end

local function events_in_process(race, class)
  local repo = require("hwc.config").repo_root()
  local rocks = os.getenv("HOME") .. "/.luarocks"
  local cmd = "LUA_PATH='" .. repo .. "/src/?.lua;" .. repo .. "/src/?/init.lua;" .. rocks
    .. "/share/lua/5.1/?.lua;" .. rocks .. "/share/lua/5.1/?/init.lua;;' LUA_CPATH='" .. rocks
    .. "/lib/lua/5.1/?.so;;' /opt/homebrew/bin/luajit '" .. repo .. "/spec/helpers/world_engine_events.lua' '"
    .. repo .. "' " .. race .. " " .. class .. " 2>&1"
  local p = assert(io.popen(cmd))
  local out = p:read("*a")
  p:close()
  -- stderr is merged so a crash shows its trace in the assertion message
  assert(out:match('^{"errors"'), "determinism driver failed:\n" .. out)
  return out
end

describe("world + real engine", function()
  local why = flow.absent()
  if why then
    pending(why)
    return
  end

  it("Dwarf Warrior completes Dwarven Outfitters with the real engine", function()
    completes_dwarven_outfitters("Dwarf", "WARRIOR")
  end)

  it("Gnome Mage completes Dwarven Outfitters with the real engine", function()
    completes_dwarven_outfitters("Gnome", "MAGE")
  end)

  for _, who in ipairs({ { "Dwarf", "WARRIOR" }, { "Gnome", "MAGE" } }) do
    it("gives identical events, engine snapshots and errors in two processes: " .. who[1] .. " " .. who[2], function()
      local a = events_in_process(who[1], who[2])
      local b = events_in_process(who[1], who[2])
      assert.matches("quest_turn_in", a)
      assert.matches('"snapshots"', a)
      assert.equal(a, b)
    end)
  end
end)
