-- Integration: the driver plays a Dwarf Warrior through Dun Morogh with the
-- real, unmodified engine until the engine autoloads the next guide (design
-- spec §4.4, §10). Pending without the addon checkout or the pinned catalog.
-- Slow (a full guide): busted --tags=slow.
local flow = dofile("spec/helpers/world_engine_flow.lua")

local function signals(log, name)
  local out = {}
  for _, s in ipairs(log.signals) do
    if s.signal == name then out[#out + 1] = s end
  end
  return out
end

describe("driver.run against the real engine #slow", function()
  local why = flow.absent()
  if why then
    pending(why)
    return
  end

  -- stop_level 13, not the brief's 12: this Dwarf Warrior reaches level 12 at
  -- guide line ~281 of 303, before the guide ends, so a level-12 stop never
  -- sees the next guide. max_guides = 2 is the stop that ends the run.
  local log
  local function get()
    if log then return log end
    local cfg = require("hwc.config").load({ addon_path = flow.ADDON, race = "Dwarf", class = "WARRIOR" })
    log = require("hwc.driver.run").character(cfg, { stop_level = 13, max_guides = 2 })
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
