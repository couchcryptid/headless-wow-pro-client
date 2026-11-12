local Engine = require("hwc.driver.engine")

local function snapshot(t)
  local s = {}
  for k, v in pairs(t) do s[k] = v end
  return s
end

local function fake()
  local calls = {}
  local W = {
    action = { "A", "C", "T", "A" },
    step = { "Foo", "Foo", "Bar", "Baz" },
    QID = { "179", "179", "179^180", "181" },
    questtext = { nil, "Kill 8", nil, nil },
    lootitem = { nil, { [750] = 8 }, nil, nil },
    why = { nil, "because", nil, nil },
    rows = {
      { index = 1 }, { index = 2 }, { index = 3 }, { index = 4 },
    },
    Guides = { G = { startlevel = 1, endlevel = 12, nextGID = "H" } },
  }
  W.GetActiveStickyCount = function() return 2 end
  W.NextGuide = function(_, gid) return "Next:" .. gid end
  W.GuideRank = function(gid) return 2, "Global" end
  W.CompleteStep = function(...) calls[#calls + 1] = { ... } end
  W.UpdateGuide = function(_, from) calls[#calls + 1] = { "update", from } end
  local env = {
    WoWPro = W,
    WoWProDB = { char = { currentguide = "G" } },
    WoWProCharDB = { Guide = { G = { completion = { [1] = true }, done = false } } },
  }
  local sb = { env = env }
  -- mirrors Sandbox:call: false on error, else true plus the results
  function sb:call(fn, ...)
    local res = { pcall(fn, ...) }
    if not res[1] then return false end
    return unpack(res, 1, table.maxn(res))
  end
  return { sb = sb }, calls
end

describe("driver.engine", function()
  it("current() skips the sticky rows", function()
    local r = fake()
    local E = Engine.new(r)
    assert.equal(3, E:current().index)
    assert.equal("T", E:current().action)
  end)

  it("splits multi-QID steps into integers and keeps single ones", function()
    local E = Engine.new((fake()))
    assert.same({ 179, 180 }, E:step(3).qids)
    assert.same({ 179 }, E:step(1).qids)
    assert.equal("179^180", E:step(3).qid)
  end)

  it("copies tags as the engine parsed them", function()
    local E = Engine.new((fake()))
    local s = E:step(2)
    assert.equal("Kill 8", s.tags.questtext)
    assert.same({ [750] = 8 }, s.tags.lootitem)
    assert.is_nil(s.tags.use)
    assert.is_nil(s.line)
  end)

  it("marks sticky rows", function()
    local E = Engine.new((fake()))
    local rows = E:rows()
    assert.equal(4, #rows)
    assert.same({ true, true, false, false }, { rows[1].sticky, rows[2].sticky, rows[3].sticky, rows[4].sticky })
  end)

  it("reads completion, why, gid, guide, rank and step count through", function()
    local E = Engine.new((fake()))
    assert.is_true(E:completed(1))
    assert.is_false(E:completed(2))
    assert.equal("because", E:why(2))
    assert.is_nil(E:why(1))
    assert.equal("G", E:gid())
    assert.equal(4, E:num_steps())
    assert.equal(2, E:rank())
    local g = E:guide("G")
    assert.same({ 1, 12, "Next:G", false }, { g.startlevel, g.endlevel, g.next_gid, g.done })
  end)

  it("returns a nil next_gid without calling NextGuide when the guide names none", function()
    local r = fake()
    r.sb.env.WoWPro.Guides.G.nextGID = nil
    r.sb.env.WoWPro.NextGuide = function() error("must not be called") end
    assert.is_nil(Engine.new(r):guide("G").next_gid)
  end)

  it("complete_manual and update_guide make the player-equivalent calls", function()
    local r, calls = fake()
    local E = Engine.new(r)
    E:complete_manual(4)
    E:update_guide()
    assert.same({ 4, "Right-Click" }, calls[1])
    assert.same({ "update", "sim:level" }, calls[2])
  end)

  it("never writes env.WoWPro", function()
    local r = fake()
    local W = r.sb.env.WoWPro
    local before = snapshot(W)
    local E = Engine.new(r)
    E:current(); E:rows(); E:step(2); E:guide("G"); E:completed(1); E:why(2); E:rank(); E:num_steps()
    assert.same(before, snapshot(W))
    assert.same({ [750] = 8 }, W.lootitem[2])
  end)

  describe("when the addon call fails", function()
    -- sb:call returns false and the sandbox has recorded the error
    local function failing(name)
      local r = fake()
      r.sb.errors = { { msg = "boom in " .. name } }
      local real = r.sb.call
      r.sb.call = function(self, fn, ...)
        if fn == r.sb.env.WoWPro[name] then return false end
        return real(self, fn, ...)
      end
      return Engine.new(r)
    end

    it("current() and rows() return nil, err rather than assuming 0 sticky rows", function()
      local E = failing("GetActiveStickyCount")
      assert.same({ nil, "boom in GetActiveStickyCount" }, { E:current() })
      local rows, err = E:rows()
      assert.is_nil(rows)
      assert.equal("boom in GetActiveStickyCount", err)
    end)

    it("rank() returns nil, err", function()
      local rank, err = failing("GuideRank"):rank()
      assert.is_nil(rank)
      assert.equal("boom in GuideRank", err)
    end)

    it("complete_manual and update_guide return false, err", function()
      assert.same({ false, "boom in CompleteStep" }, { failing("CompleteStep"):complete_manual(4) })
      assert.same({ false, "boom in UpdateGuide" }, { failing("UpdateGuide"):update_guide() })
    end)

    it("return true on success", function()
      local E = Engine.new((fake()))
      assert.is_true(E:complete_manual(4))
      assert.is_true(E:update_guide())
    end)
  end)

  it("completed() is false when the guide's saved data is absent", function()
    local r = fake()
    r.sb.env.WoWProCharDB.Guide.G = nil
    assert.is_false(Engine.new(r):completed(1))
    r.sb.env.WoWProCharDB.Guide.G = {}
    assert.is_false(Engine.new(r):completed(1))
  end)
end)
