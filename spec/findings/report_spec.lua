local group = require("hwc.findings.group")
local report = require("hwc.findings.report")
local json = require("hwc.json")
local dkjson = require("dkjson")

local function runlog(signals)
  return { character = { race = "Dwarf", class = "WARRIOR", professions = {} }, rank = 2, steps = {},
    signals = signals, guides = {} }
end

local function sigs()
  return {
    { signal = "did-not-advance", gid = "G1", file = "a.lua", line = 40, action = "T", name = "Report", qid = 314,
      why = "w", level = 3, log = { 314, 5 }, before = { name = "b" }, after = { name = "c" }, confidence = "verified" },
    { signal = "accept-refused", gid = "G1", file = "a.lua", line = 10, action = "A", name = "Pre", qid = 96629,
      reason = "prerequisite", confidence = "unverified" },
    { signal = "never-shown-accept", gid = "G1", file = "a.lua", line = 20, action = "A", name = "Next", qid = 5,
      why = "PRE&(x): A mandatory prereq was not met: 96629" },
    { signal = "manual-completion", gid = "G1", file = "a.lua", line = 50, action = "H", name = "Hearth", expected = true },
    { signal = "lua-error", message = "boom\nsecond line", stack = "x.lua:1" },
    { signal = "lua-error", message = "hx", reason = "harness" },
  }
end

local function findings() return group.findings({ runlog(sigs()) }) end
local function header() return { scope = "s", matrix = { combos = { "Dwarf WARRIOR baseline" } } } end

describe("report.build", function()
  it("round trips through JSON", function()
    local fs = findings()
    local doc = dkjson.decode(json.encode(report.build(fs, header()), { indent = true }))
    assert.equal(1, doc.format)
    assert.equal(#fs, #doc.findings)
    for i, f in ipairs(doc.findings) do
      assert.equal(fs[i].id, f.id)
      assert.equal(fs[i].signal, f.signal)
      assert.same(fs[i].combos, f.combos)
      assert.is_true(#f.title > 0)
      assert.is_true(#f.sentence > 0)
    end
  end)

  it("encodes zero findings as an empty array", function()
    local s = json.encode(report.build({}, header()))
    assert.truthy(s:find('"findings"%s*:%s*%[%s*%]'))
    assert.equal(0, report.build({}, header()).summary.findings)
  end)

  it("counts non-expected, non-harness findings with a severity", function()
    local fs = findings()
    local doc = report.build(fs, header())
    local n, roots, by_sev, by_sig = 0, 0, {}, {}
    for _, f in ipairs(fs) do
      if f.severity and not f.expected and not (f.harness or f.signal == "missing-global") then
        n = n + 1
        if not f.caused_by then roots = roots + 1 end
        by_sev[f.severity] = (by_sev[f.severity] or 0) + 1
        by_sig[f.signal] = (by_sig[f.signal] or 0) + 1
      end
    end
    assert.is_true(n > 0 and n < #fs)
    assert.equal(n, doc.summary.findings)
    assert.equal(roots, doc.summary.roots)
    assert.same(by_sev, doc.summary.by_severity)
    assert.same(by_sig, doc.summary.by_signal)
    assert.equal(#fs, #doc.findings)
  end)

  it("marks empty lists as arrays without mutating inputs", function()
    local fs = findings()
    local doc = report.build(fs, header())
    local s = json.encode(doc)
    assert.falsy(s:find("{}", 1, true))
    for _, f in ipairs(fs) do assert.is_nil(f.title); assert.is_nil(getmetatable(f.combos)) end
  end)

  it("passes the header through", function()
    local h = header()
    assert.equal(h, report.build({}, h).header)
  end)
end)

describe("report.context", function()
  it("builds by_id, by_qid and single", function()
    local fs = findings()
    local ctx = report.context(fs, header())
    for _, f in ipairs(fs) do assert.equal(f, ctx.by_id[f.id]) end
    assert.equal("accept-refused", ctx.by_qid[96629].signal)
    assert.equal("never-shown-accept", ctx.by_qid[5].signal)
    assert.is_nil(ctx.by_qid[314])
    assert.equal("Dwarf Warrior", ctx.single)
  end)

  it("single is nil for several or duplicated-to-many combos", function()
    local h = { matrix = { combos = { "Dwarf WARRIOR baseline", "Gnome MAGE baseline" } } }
    assert.is_nil(report.context({}, h).single)
    assert.is_nil(report.context({}, {}).single)
    local d = { matrix = { combos = { "Dwarf WARRIOR baseline", "Dwarf WARRIOR baseline" } } }
    assert.equal("Dwarf Warrior", report.context({}, d).single)
  end)
end)
