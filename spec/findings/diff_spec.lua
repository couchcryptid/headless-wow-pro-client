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
      stop = opts.stop,
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

  it("keeps fixed_for on a spread finding that also lost characters", function()
    local r = diff.compare(
      doc({ combos = { DWARF, GNOME, "Human PRIEST baseline" }, findings = { f("F-1", { DWARF, GNOME }) } }),
      doc({ combos = { DWARF, GNOME, "Human PRIEST baseline" }, findings = { f("F-1", { GNOME, "Human PRIEST baseline" }) } }))
    assert.equal(1, r.counts.spread)
    assert.same({ "Human PRIEST baseline" }, r.spread[1].added_for)
    assert.same({ DWARF }, r.spread[1].fixed_for)
  end)

  it("gives a plain spread finding an empty fixed_for", function()
    local r = diff.compare(doc({ findings = { f("F-1", { DWARF }) } }), doc({ findings = { f("F-1", { DWARF, GNOME }) } }))
    assert.same({}, r.spread[1].fixed_for)
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
    assert.equal("not comparable: OLD is format 1; hwc diff needs format 2", err)
    local r2, err2 = diff.compare(doc(), bad)
    assert.is_nil(r2)
    assert.equal("not comparable: NEW is format 1; hwc diff needs format 2", err2)
  end)

  it("warns about characters only in NEW", function()
    local r = diff.compare(doc({ commit = "b", combos = { DWARF } }), doc({ commit = "c", combos = { DWARF, GNOME } }))
    assert.same({ "combos" }, codes(r))
    assert.matches("only in NEW", r.warnings[1].message)
    assert.matches("Gnome Mage", r.warnings[1].message)
  end)

  describe("early stops", function()
    local errors_stop = { { combo = DWARF, reason = "errors" } }

    it("warns and exits 1 when only NEW stopped early, even with no new findings", function()
      local r = diff.compare(doc({ commit = "b" }), doc({ commit = "c", stop = errors_stop }))
      assert.same({ "stop" }, codes(r))
      assert.matches("Dwarf Warrior", r.warnings[1].message)
      assert.matches("OLD: ran to the end", r.warnings[1].message)
      assert.matches("NEW: Too many addon errors", r.warnings[1].message)
      assert.matches("findings past the stop show as fixed", r.warnings[1].message)
      assert.equal(1, r.stopped_early)
      assert.equal(1, diff.exit_code(r))
    end)

    it("warns but keeps exit 0 when only OLD stopped early", function()
      local r = diff.compare(doc({ commit = "b", stop = errors_stop }), doc({ commit = "c" }))
      assert.same({ "stop" }, codes(r))
      assert.matches("OLD: Too many addon errors", r.warnings[1].message)
      assert.matches("NEW: ran to the end", r.warnings[1].message)
      assert.equal(0, r.stopped_early)
      assert.equal(0, diff.exit_code(r))
    end)

    it("does not warn when both runs stopped the same way", function()
      local r = diff.compare(doc({ commit = "b", stop = errors_stop }), doc({ commit = "c", stop = errors_stop }))
      assert.same({}, codes(r))
      assert.equal(0, r.stopped_early)
      assert.equal(0, diff.exit_code(r))
    end)

    it("ignores a stop on a character that is not shared", function()
      local priest = "Human PRIEST baseline"
      local r = diff.compare(doc({ commit = "b", combos = { DWARF, GNOME } }),
        doc({ commit = "c", combos = { DWARF, priest }, stop = { { combo = priest, reason = "stuck" } } }))
      assert.same({ "combos", "combos" }, codes(r))
      assert.equal(0, r.stopped_early)
      assert.equal(0, diff.exit_code(r))
    end)
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

describe("diff.render", function()
  local function render(old, new)
    local r = assert(diff.compare(old, new))
    return diff.render(r)
  end
  local function lines(s)
    local out = {}
    for l in s:gmatch("([^\n]*)\n") do out[#out + 1] = l end
    return out
  end

  it("names both sides", function()
    local out = render(doc({ commit = "aaaaaaaffff" }), doc({ branch = "fix/x", commit = "bbbbbbbeeee", dirty = true }))
    assert.equal("hwc diff: main@aaaaaaa → fix/x@bbbbbbb (dirty)", lines(out)[1])
    assert.equal("\n", out:sub(-1))
  end)

  it("labels a non-git side by its version", function()
    assert.equal("2026.11.12.A (not a git folder)", diff.side_label({ git = false, version = "2026.11.12.A" }))
  end)

  it("prints warnings, then counts", function()
    local out = render(
      doc({ commit = "b", findings = { f("F-1", { DWARF }), f("F-2", { DWARF }), f("F-3", { DWARF }), f("F-4", { DWARF }) } }),
      doc({ filters = { { kind = "include", pattern = "x" } }, findings = { f("F-2", { DWARF }), f("F-3", { DWARF }), f("F-4", { DWARF }), f("F-5", { DWARF }) } }))
    local w = out:find("warning: different guide filters", 1, true)
    local c = out:find("fixed 1 · new 1 · partly fixed 0 · unchanged 3", 1, true)
    assert.is_truthy(w); assert.is_truthy(c)
    assert.is_true(w < c)
  end)

  it("lists a finding with marker, title, basename and line", function()
    local out = render(doc(), doc({ findings = { f("F-1", { DWARF }, { title = '"Secure the Mountain" is never offered', line = 162 }) } }))
    assert.matches('🔴 "Secure the Mountain" is never offered', out, 1, true)
    assert.matches("01_12_Dun_Morogh.lua:162", out, 1, true)
    assert.is_nil(out:find("WoWPro_Leveling/", 1, true))
  end)

  it("folds follow-ons under their root in the same list", function()
    local out = render(doc({ findings = {
      f("F-1", { DWARF }, { line = 1 }),
      f("F-2", { DWARF }, { line = 2, caused_by = "F-1" }),
      f("F-3", { DWARF }, { line = 3, caused_by = "F-2" }),
    } }), doc())
    assert.matches("(+2 follow-on)", out, 1, true)
    assert.matches("Dun_Morogh.lua:1  (+2 follow-on)", out, 1, true)
    assert.is_nil(out:find("Dun_Morogh.lua:2", 1, true))
    assert.is_nil(out:find("Dun_Morogh.lua:3", 1, true))
  end)

  it("shows who a partly fixed finding was fixed for", function()
    local out = render(
      doc({ findings = { f("F-1", { DWARF, GNOME }), f("F-2", { DWARF }, { line = 20 }) } }),
      doc({ findings = { f("F-1", { DWARF }), f("F-2", { DWARF, GNOME }, { line = 20 }) } }))
    assert.matches("fixed: Gnome Mage · still: Dwarf Warrior", out, 1, true)
    assert.matches("now also: Gnome Mage", out, 1, true)
  end)

  it("shows both sides of a spread finding that also lost characters", function()
    local priest = "Human PRIEST baseline"
    local out = render(
      doc({ combos = { DWARF, GNOME, priest }, findings = { f("F-1", { DWARF, GNOME }) } }),
      doc({ combos = { DWARF, GNOME, priest }, findings = { f("F-1", { GNOME, priest }) } }))
    assert.matches("now also: Human Priest · fixed: Dwarf Warrior", out, 1, true)
  end)

  it("leaves out empty sections", function()
    local out = render(doc({ findings = { f("F-1", { DWARF }) } }), doc())
    assert.matches("Fixed", out, 1, true)
    assert.is_nil(out:find("New", 1, true))
  end)

  it("adds spread to the counts only when there is some", function()
    local out = render(doc({ findings = { f("F-1", { DWARF }) } }), doc({ findings = { f("F-1", { DWARF, GNOME }) } }))
    assert.matches("partly fixed 0 · spread 1 · unchanged 0", out, 1, true)
  end)

  it("says no changes when nothing moved", function()
    local same = {}
    for i = 1, 4 do same[i] = f("F-" .. i, { DWARF }) end
    local out = render(doc({ findings = same }), doc({ findings = same }))
    assert.matches("no changes (4 findings in both)", out, 1, true)
  end)
end)
