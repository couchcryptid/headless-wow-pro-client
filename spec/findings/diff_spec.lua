local diff = require("hwc.findings.diff")

local DWARF, GNOME = "Dwarf WARRIOR baseline", "Gnome MAGE baseline"

local function doc(opts)
  opts = opts or {}
  return {
    format = 2,
    header = {
      addon = { git = true, branch = opts.branch or "main", commit = opts.commit or "aaaaaaa", dirty = opts.dirty or false },
      catalog = opts.catalog or { questie = { tag = "v1.1.2", build = "e1652ce" }, supplement = { present = false } },
      client = { commit = opts.client or "c1" },
      matrix = { combos = opts.combos or { DWARF, GNOME } },
      filters = opts.filters,
      paths_relative_to = opts.relative_to or "WoW-Pro-Guides",
    },
    findings = opts.findings or {},
  }
end

local function f(id, combos, extra)
  local t = {
    id = id, combos = combos, severity = "high", signal = "never-shown-accept",
    title = id, file = "WoWPro_Leveling/Forever/Alliance/01_12_Dun_Morogh.lua", line = 10,
  }
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end

local function without_severity(id, combos)
  local t = f(id, combos)
  t.severity = nil
  return t
end

local function codes(r)
  local out = {}
  for _, w in ipairs(r.warnings) do out[#out + 1] = w.code end
  return out
end

describe("diff.compare", function()
  it("puts ids only in OLD under fixed and only in NEW under new", function()
    local r = diff.compare(doc({ findings = { f("F-1", { DWARF }) } }), doc({ findings = { f("F-2", { DWARF }) } }))
    assert.equal(1, r.counts.fixed)
    assert.equal(1, r.counts.new)
    assert.equal("F-1", r.fixed[1].id)
    assert.equal("F-2", r.new[1].id)
  end)

  it("counts a finding in both with the same combos as unchanged", function()
    local r = diff.compare(doc({ findings = { f("F-1", { DWARF }) } }), doc({ findings = { f("F-1", { DWARF }) } }))
    assert.equal(1, r.counts.unchanged)
    assert.same({}, r.fixed); assert.same({}, r.new); assert.same({}, r.partly_fixed); assert.same({}, r.spread)
    assert.equal(0, diff.exit_code(r))
  end)

  it("marks fewer characters in NEW as partly fixed", function()
    local r = diff.compare(doc({ findings = { f("F-1", { DWARF, GNOME }) } }), doc({ findings = { f("F-1", { DWARF }) } }))
    assert.equal(1, r.counts.partly_fixed)
    assert.same({ GNOME }, r.partly_fixed[1].fixed_for)
    assert.same({ DWARF }, r.partly_fixed[1].still)
    assert.same({ DWARF }, r.partly_fixed[1].combos)
  end)

  it("marks more characters in NEW as spread", function()
    local r = diff.compare(doc({ findings = { f("F-1", { DWARF }) } }), doc({ findings = { f("F-1", { DWARF, GNOME }) } }))
    assert.same({ GNOME }, r.spread[1].added_for)
    assert.equal(1, diff.exit_code(r))
  end)

  it("ignores harness, expected and severity-less findings", function()
    local r = diff.compare(doc(), doc({ findings = {
      f("F-1", { DWARF }, { signal = "missing-global" }),
      f("F-2", { DWARF }, { expected = true }),
      without_severity("F-3", { DWARF }),
    } }))
    assert.equal(0, r.counts.new)
    assert.equal(0, diff.exit_code(r))
  end)

  it("compares only shared characters and warns about the rest", function()
    local r = diff.compare(
      doc({ findings = { f("F-1", { GNOME }) } }),
      doc({ combos = { DWARF } }))
    assert.equal(0, r.counts.fixed)
    assert.same({ DWARF }, r.shared)
    local w
    for _, x in ipairs(r.warnings) do if x.code == "combos" then w = x end end
    assert.is_truthy(w)
    assert.matches("Gnome Mage", w.message)
    assert.matches("OLD", w.message)
  end)

  it("treats a finding without combos as on every character", function()
    local r = diff.compare(
      doc({ findings = { f("F-1", { DWARF }) } }),
      doc({ findings = { f("F-1", nil) } }))
    assert.equal(1, r.counts.spread)
    assert.same({ GNOME }, r.spread[1].added_for)
  end)

  it("returns nil and a message when no characters are shared", function()
    local r, err = diff.compare(doc({ combos = { DWARF } }), doc({ combos = { GNOME } }))
    assert.is_nil(r)
    assert.matches("no shared characters", err)
  end)

  it("rejects a format other than 2", function()
    local bad = doc(); bad.format = 1
    local r, err = diff.compare(bad, doc())
    assert.is_nil(r)
    assert.matches("format", err)
  end)

  it("sorts by severity, file, line, then id", function()
    local r = diff.compare(doc(), doc({ findings = {
      f("F-b", { DWARF }, { line = 5 }),
      f("F-a", { DWARF }, { line = 5 }),
      f("F-c", { DWARF }, { severity = "low" }),
      f("F-d", { DWARF }, { line = 2 }),
    } }))
    local ids = {}
    for _, x in ipairs(r.new) do ids[#ids + 1] = x.id end
    assert.same({ "F-d", "F-a", "F-b", "F-c" }, ids)
  end)

  it("copies the run identities from header.addon", function()
    local r = diff.compare(doc({ branch = "x", commit = "bbbbbbb" }), doc())
    assert.equal("x", r.runs.old.branch)
    assert.equal("bbbbbbb", r.runs.old.commit)
    assert.equal("main", r.runs.new.branch)
  end)

  describe("warnings", function()
    it("warns for each header mismatch", function()
      local base = doc({ commit = "bbbbbbb" })
      local function only(new, old)
        local r = diff.compare(old or base, new)
        return codes(r)
      end
      assert.same({ "questie" }, only(doc({ catalog = { questie = { tag = "v1.1.3", build = "9b01f2a" }, supplement = { present = false } } })))
      assert.same({ "supplement" }, only(doc({ catalog = { questie = { tag = "v1.1.2", build = "e1652ce" }, supplement = { present = true } } })))
      assert.same({ "filters" }, only(doc({ filters = { { kind = "include", pattern = "x" } } })))
      assert.same({ "relative-to" }, only(doc({ relative_to = "elsewhere" })))
      assert.same({ "client" }, only(doc({ client = "c2" })))
      assert.same({ "same-commit" }, only(doc({ commit = "bbbbbbb" })))
      assert.same({ "dirty-old" }, codes(diff.compare(doc({ dirty = true, commit = "b" }), doc())))
      assert.same({ "dirty-new" }, codes(diff.compare(doc({ commit = "b" }), doc({ dirty = true }))))
    end)

    it("does not warn when filters are nil on one side and empty on the other", function()
      local r = diff.compare(doc({ filters = nil, commit = "b" }), doc({ filters = {} }))
      assert.same({}, r.warnings)
    end)
  end)
end)
