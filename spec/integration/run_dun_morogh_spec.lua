-- Integration: the driver plays a Dwarf Warrior through Dun Morogh with the
-- real, unmodified engine until the engine autoloads the next guide (design
-- spec §4.4, §10). Pending without the pinned addon worktree or an installed
-- QuestieDB. Slow (a full guide): busted --tags=slow.
--
-- Runs against a pinned worktree made by tools/addon-worktree.sh, like the anchors,
-- not ~/Projects/WoW-Pro-Guides: the Rhapsody Malt check below asserts a guide bug
-- the addon later fixed (0640e4083 turned the C step into a B step), so it needs a
-- fixed addon commit with that step reachable. fix/forever-prereq-gates
-- (64fe6b36f) is one: it still has the C step (:112) and accepts the PRE chain
-- 282 -> 420 that gates Beer Basted Boar Ribs. main (9851a40f2) has the C step but
-- no A for 282 or 420, so 384 is never shown there and the C step is unreachable.
local flow = dofile("spec/helpers/world_engine_flow.lua")
local ADDON = require("hwc.config").repo_root() .. "/local/addon/fix-forever-prereq-gates"

local function signals(log, name)
  local out = {}
  for _, s in ipairs(log.signals) do
    if s.signal == name then out[#out + 1] = s end
  end
  return out
end

describe("driver.run against the real engine #slow", function()
  local why = flow.absent()
  if not why and require("lfs").attributes(ADDON .. "/WoWPro/WoWPro.toc", "mode") == nil then
    why = "addon worktree absent at " .. ADDON .. " (tools/addon-worktree.sh)"
  end
  if why then
    pending(why)
    return
  end

  -- The run plays the chain to its last line (no level stop), so max_guides = 2
  -- is the stop that ends it once the engine autoloads the next guide.
  local log
  local function get()
    if log then return log end
    local cfg = require("hwc.config").load({ addon_path = ADDON, race = "Dwarf", class = "WARRIOR" })
    log = require("hwc.driver.run").character(cfg, { max_guides = 2 })
    return log
  end

  it("Dwarf Warrior plays Dun Morogh to the next guide", function()
    local l = get()
    assert.equal("ClassicDunMorogh0112", l.guides[1])
    -- guides[2] is Dun Morogh's nextGID as the engine itself resolves it
    local E = require("hwc.driver.engine").new(flow.boot("Dwarf", "WARRIOR"))
    local next_gid = E:guide("ClassicDunMorogh0112").next_gid
    assert.is_string(next_gid)
    assert.equal(next_gid, l.guides[2])
    assert.equal("max-guides", l.stop.reason)
    assert.equal(2, l.rank)
  end)

  it("records did-not-advance for the Rhapsody Malt C step (QID 384, spec §10)", function()
    local malt
    for _, s in ipairs(signals(get(), "did-not-advance")) do
      if s.qid == 384 and s.action == "C" and s.name == "Beer Basted Boar Ribs" then malt = malt or s end
    end
    assert.is_truthy(malt, "no did-not-advance for the Rhapsody Malt C step (QID 384)")
  end)

  it("records no harness lua-error", function()
    for _, s in ipairs(signals(get(), "lua-error")) do
      assert.is_nil(s.reason, "harness lua-error: " .. tostring(s.message))
    end
  end)
end)
