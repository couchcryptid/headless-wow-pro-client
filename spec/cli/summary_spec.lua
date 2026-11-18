-- The run summary printed on stdout before the wrote line (design §5.2).
local summary = require("hwc.cli.summary")

local function fixture(name)
  local f = assert(io.open("spec/fixtures/findings/" .. name, "r"))
  local doc = require("dkjson").decode(f:read("*a"))
  f:close()
  return doc
end

local NOTE = " (gaps in hwc's stubs, not guide bugs)"

describe("summary.lines", function()
  it("counts findings and root causes, then severities in rank order, then harness notices", function()
    assert.same({
      "Dwarf Warrior: 24 findings, 17 root causes",
      "  11 high · 2 medium-high · 8 medium · 3 low",
      "  harness: 1 missing global" .. NOTE,
    }, summary.lines(fixture("single.json")))
  end)

  it("leaves out zero severities, adds the stop reason and both harness counts", function()
    local doc = {
      header = { matrix = { combos = { "Dwarf WARRIOR herbalism,skinning" } },
        stop = { { combo = "Dwarf WARRIOR herbalism,skinning", reason = "errors" } } },
      summary = { findings = 256, roots = 152, by_severity = { high = 155, low = 8 } },
      findings = {
        { signal = "lua-error", harness = true }, { signal = "lua-error", harness = true },
        { signal = "lua-error" },
        { signal = "missing-global" }, { signal = "missing-global" }, { signal = "missing-global" },
      },
    }
    assert.same({
      "Dwarf Warrior (Herbalism, Skinning): 256 findings, 152 root causes",
      "  155 high · 8 low",
      "  stopped early: Too many addon errors",
      "  harness: 2 Lua errors, 3 missing globals" .. NOTE,
    }, summary.lines(doc))
  end)

  it("leaves out a zero harness count and says one finding in the singular", function()
    local doc = {
      header = { matrix = { combos = { "Gnome MAGE none" } } },
      summary = { findings = 1, roots = 1, by_severity = { medium = 1 } },
      findings = { { signal = "lua-error", harness = true } },
    }
    assert.same({
      "Gnome Mage: 1 finding, 1 root cause",
      "  1 medium",
      "  harness: 1 Lua error" .. NOTE,
    }, summary.lines(doc))
  end)

  it("says no findings and has no severity line for an empty run", function()
    local doc = {
      header = { matrix = { combos = { "Dwarf WARRIOR none" } } },
      summary = { findings = 0, roots = 0, by_severity = {} },
      findings = {},
    }
    assert.same({ "Dwarf Warrior: no findings" }, summary.lines(doc))
  end)

  it("reads the empty fixture", function()
    local lines = summary.lines(fixture("empty.json"))
    assert.matches(": no findings$", lines[1])
  end)
end)
