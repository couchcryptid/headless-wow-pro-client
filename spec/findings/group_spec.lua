-- Findings grouping (design spec §7.2): one finding per suspected defect across
-- characters, stable ids, severities and root-cause links.
local group = require("hwc.findings.group")

local function runlog(race, class, signals, variant)
  return { character = { race = race, class = class, professions = {} }, variant = variant,
    rank = 2, steps = {}, signals = signals, guides = {} }
end

local function dna(extra)
  local s = { signal = "did-not-advance", gid = "G1", file = "WoWPro_Leveling/Alliance/Dun.lua", line = 40,
    action = "T", name = "Report to Grull", qid = 314, why = "w", level = 3, log = { 314 },
    before = { name = "a" }, after = { name = "b" }, confidence = "verified" }
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end

local function by_signal(fs, sig)
  local out = {}
  for _, f in ipairs(fs) do if f.signal == sig then out[#out + 1] = f end end
  return out
end

describe("group.fnv1a32", function()
  it("matches the FNV-1a 32-bit test vectors", function()
    assert.equal("811c9dc5", group.fnv1a32(""))
    assert.equal("e40c292c", group.fnv1a32("a"))
  end)
end)

describe("group.findings", function()
  it("groups the same signal of two characters into one finding listing both combos", function()
    local fs = group.findings({
      runlog("Gnome", "MAGE", { dna() }),
      runlog("Dwarf", "WARRIOR", { dna({ why = "first" }) }),
    })
    assert.equal(1, #fs)
    local f = fs[1]
    assert.same({ "Dwarf WARRIOR baseline", "Gnome MAGE baseline" }, f.combos)
    assert.equal("first", f.why) -- from the first combo in sorted order
    assert.equal("medium", f.severity)
    assert.truthy(f.id:match("^F%-%x%x%x%x%x%x%x%x$"))
  end)

  it("passes grind, qname and neighbour actions through to the finding", function()
    local sig = { signal = "below-level", gid = "G1", file = "f", line = 1, action = "A", name = "L", qid = 412,
      qname = "Pre", grind = { kills = 4, to = 6 }, before = { name = "b", action = "T" },
      after = { name = "c", action = "C" } }
    local f = group.findings({ runlog("Dwarf", "WARRIOR", { sig }) })[1]
    assert.same({ kills = 4, to = 6 }, f.grind)
    assert.equal("Pre", f.qname)
    assert.same({ name = "b", action = "T" }, f.before)
    assert.same({ name = "c", action = "C" }, f.after)
  end)

  it("keeps the id when the line changes", function()
    local a = group.findings({ runlog("Dwarf", "WARRIOR", { dna({ line = 40 }) }) })[1]
    local b = group.findings({ runlog("Dwarf", "WARRIOR", { dna({ line = 99 }) }) })[1]
    assert.equal(a.id, b.id)
    assert.equal(99, b.line)
  end)

  -- Ruling AA: the step's source ordinal separates distinct same-key lines.
  it("gives two same-name F Stormwind lines two findings", function()
    local f1 = dna({ action = "F", name = "Stormwind", qid = nil, line = 118, ordinal = 1 })
    local f2 = dna({ action = "F", name = "Stormwind", qid = nil, line = 225, ordinal = 2 })
    local fs = group.findings({ runlog("Dwarf", "WARRIOR", { f1, f2 }) })
    assert.equal(2, #fs)
    assert.same({ 118, 225 }, { fs[1].line, fs[2].line })
    assert.are_not.equal(fs[1].id, fs[2].id)
  end)

  it("keeps the id when lines shift but the ordinal holds, across characters", function()
    local a = group.findings({ runlog("Dwarf", "WARRIOR", { dna({ line = 40, ordinal = 2 }) }) })[1]
    local b = group.findings({
      runlog("Dwarf", "WARRIOR", { dna({ line = 45, ordinal = 2 }) }),
      runlog("Dwarf", "PALADIN", { dna({ line = 45, ordinal = 2 }) }),
    })
    assert.equal(1, #b)
    assert.equal(a.id, b[1].id)
    assert.same({ "Dwarf PALADIN baseline", "Dwarf WARRIOR baseline" }, b[1].combos)
  end)

  it("uses the variant in combos, defaulting to baseline", function()
    local fs = group.findings({ runlog("Dwarf", "WARRIOR", { dna() }, "mining") })
    assert.same({ "Dwarf WARRIOR mining" }, fs[1].combos)
  end)

  it("links a refusal and the never-shown accept naming its quest both ways", function()
    local refused = { signal = "accept-refused", gid = "G1", file = "f.lua", line = 10, action = "A",
      name = "Pre", qid = 96629, reason = "prerequisite" }
    local hidden = { signal = "never-shown-accept", gid = "G1", file = "f.lua", line = 20, action = "A",
      name = "Next", qid = 555, why = "PRE&(x): A mandatory prereq was not met: 96629" }
    local fs = group.findings({ runlog("Dwarf", "WARRIOR", { refused, hidden }) })
    local r, h = by_signal(fs, "accept-refused")[1], by_signal(fs, "never-shown-accept")[1]
    assert.equal("high", r.severity)
    assert.equal("high", h.severity)
    assert.equal(r.id, h.caused_by)
    assert.same({ h.id }, r.causes)
  end)

  it("links turn-ins and did-not-advance on a refused quest to the refusal", function()
    local refused = { signal = "log-full", gid = "G1", file = "f.lua", line = 10, action = "A", name = "x", qid = 7 }
    local orphan = { signal = "orphan-turnin", gid = "G1", file = "f.lua", line = 30, action = "T", name = "y", qid = 7 }
    local fs = group.findings({ runlog("Dwarf", "WARRIOR", { refused, orphan, dna({ qid = 7 }) }) })
    local r = by_signal(fs, "log-full")[1]
    assert.equal(r.id, by_signal(fs, "orphan-turnin")[1].caused_by)
    assert.equal(r.id, by_signal(fs, "did-not-advance")[1].caused_by)
    assert.equal(2, #r.causes)
  end)

  it("links a follow-on to the refusal on its own line before one elsewhere on the quest", function()
    local r1 = { signal = "accept-refused", gid = "G1", file = "f.lua", line = 10, action = "A", name = "x", qid = 7,
      ordinal = 1 }
    local r2 = { signal = "accept-refused", gid = "G1", file = "f.lua", line = 50, action = "A", name = "x", qid = 7,
      ordinal = 2 }
    local d2 = dna({ file = "f.lua", line = 50, action = "A", name = "x", qid = 7, ordinal = 2 })
    local fs = group.findings({ runlog("Dwarf", "WARRIOR", { r1, r2, d2 }) })
    local on50
    for _, f in ipairs(by_signal(fs, "accept-refused")) do if f.line == 50 then on50 = f end end
    assert.equal(on50.id, by_signal(fs, "did-not-advance")[1].caused_by)
  end)

  -- A leftover-quests signal sits on the turn-in step the run passed (driver.run
  -- leftovers), so the finding on that step is why the quest is still in the log.
  it("links a leftover quest to the finding on its turn-in step", function()
    local d = dna({ file = "f.lua", line = 30, qid = 7 })
    local left = { signal = "leftover-quests", gid = "G1", file = "f.lua", line = 30, action = "T",
      name = "Report to Grull", qid = 7 }
    local fs = group.findings({ runlog("Dwarf", "WARRIOR", { d, left }) })
    local parent = by_signal(fs, "did-not-advance")[1]
    assert.equal(parent.id, by_signal(fs, "leftover-quests")[1].caused_by)
  end)

  -- Skipped dungeon accepts are run info (RunLog.dungeon_skips), never signals, so
  -- there is no engine-dungeon-skip root and no such signal.
  it("raises on the retired engine-dungeon-skip signal", function()
    assert.has_error(function()
      group.findings({ runlog("Dwarf", "WARRIOR", { { signal = "engine-dungeon-skip" } }) })
    end)
  end)

  it("links a prereq-hidden accept only to the quest after 'not met:'", function()
    local function acc(sig, line, qid, why)
      return { signal = sig, gid = "G1", file = "f.lua", line = line, action = "A", name = "n" .. line, qid = qid, why = why }
    end
    local fs = group.findings({ runlog("Dwarf", "WARRIOR", {
      acc("accept-refused", 1, 1234), acc("accept-refused", 2, 5678),
      acc("never-shown-accept", 3, 9, "NextStep:PRE&(1234&5678): A mandatory prereq was not met: 5678"),
      acc("never-shown-accept", 4, 10, "PRE&(1234): other 1234 text but nothing unmet"),
    }) })
    local function at(line) for _, f in ipairs(fs) do if f.line == line then return f end end end
    assert.equal(at(2).id, at(3).caused_by)
    assert.same({ at(3).id }, at(2).causes)
    assert.same({}, at(1).causes)
    assert.is_nil(at(4).caused_by)
  end)

  it("never creates a longer causal cycle", function()
    local function nsa(line, qid, why)
      return { signal = "never-shown-accept", gid = "G", file = "f", line = line, action = "A", name = "n" .. line, qid = qid, why = why }
    end
    local fs = group.findings({ runlog("Dwarf", "WARRIOR", {
      nsa(1, 1, "PRE&(x): A mandatory prereq was not met: 2"),
      nsa(2, 2, "PRE&(x): A mandatory prereq was not met: 3"),
      nsa(3, 3, "PRE&(x): A mandatory prereq was not met: 1"),
    }) })
    local by = {}
    for _, f in ipairs(fs) do by[f.id] = f end
    for _, f in ipairs(fs) do
      local seen, a = {}, f
      while a do
        assert.is_nil(seen[a.id]); seen[a.id] = true
        a = a.caused_by and by[a.caused_by]
      end
    end
  end)

  describe("cross-signal root causes", function()
    local function turnin(qid, line, gid)
      return dna({ qid = qid, line = line, gid = gid or "G1", action = "T", reason = "incomplete" })
    end
    local function use_step(qid, line, gid)
      return { signal = "hidden-use-step", gid = gid or "G1", file = "f.lua", line = line, action = "U",
        name = "Use", qid = qid, use = 1, loot = 2 }
    end
    local function accept(qid, line, prereq)
      return { signal = "never-shown-accept", gid = "G1", file = "f.lua", line = line, action = "A",
        name = "Next", qid = qid, why = "NextStep:PRE&(" .. prereq .. "): A mandatory prereq was not met: " .. prereq }
    end
    local function refusal(qid, line)
      return { signal = "accept-refused", gid = "G1", file = "f.lua", line = line, action = "A",
        name = "Pre", qid = qid, reason = "prerequisite" }
    end
    local function hidden_accept(qid, line)
      return { signal = "never-shown-accept", gid = "G1", file = "f.lua", line = line, action = "A", name = "Hid", qid = qid }
    end
    local function find(fs, sig, qid)
      for _, f in ipairs(fs) do if f.signal == sig and f.qid == qid then return f end end
    end

    it("links a never-shown-accept to the incomplete turn-in of its prerequisite", function()
      local fs = group.findings({ runlog("Dwarf", "WARRIOR", { turnin(95213, 40), accept(95214, 50, 95213) }) })
      local t, a = find(fs, "did-not-advance", 95213), find(fs, "never-shown-accept", 95214)
      assert.equal(t.id, a.caused_by)
    end)

    it("links a never-shown-accept to a hidden-use-step of its prerequisite", function()
      local fs = group.findings({ runlog("Dwarf", "WARRIOR", { use_step(1016, 40), accept(1017, 50, 1016) }) })
      local u, a = find(fs, "hidden-use-step", 1016), find(fs, "never-shown-accept", 1017)
      assert.equal(u.id, a.caused_by)
    end)

    it("links an incomplete turn-in to a hidden-use-step for the same quest in the same guide", function()
      local fs = group.findings({ runlog("Dwarf", "WARRIOR", { use_step(1016, 30), turnin(1016, 40) }) })
      assert.equal(find(fs, "hidden-use-step", 1016).id, find(fs, "did-not-advance", 1016).caused_by)
      local other = group.findings({ runlog("Dwarf", "WARRIOR", { use_step(1016, 30), turnin(1016, 40, "G2") }) })
      assert.is_nil(find(other, "did-not-advance", 1016).caused_by)
    end)

    it("prefers refusal, then hidden-use-step, then incomplete turn-in, then hidden accept", function()
      local function parent_signal(signals)
        local fs = group.findings({ runlog("Dwarf", "WARRIOR", signals) })
        local a = find(fs, "never-shown-accept", 50)
        local by = {}
        for _, f in ipairs(fs) do by[f.id] = f end
        return a.caused_by and by[a.caused_by].signal
      end
      local function set(...)
        local out = { accept(50, 90, 7) }
        for _, s in ipairs({ ... }) do out[#out + 1] = s end
        return out
      end
      local r, u, t, h = refusal(7, 10), use_step(7, 20), turnin(7, 30), hidden_accept(7, 40)
      assert.equal("accept-refused", parent_signal(set(r, u, t, h)))
      assert.equal("hidden-use-step", parent_signal(set(u, t, h)))
      assert.equal("did-not-advance", parent_signal(set(t, h)))
      assert.equal("never-shown-accept", parent_signal(set(h)))
    end)
  end)

  it("raises on an unknown signal", function()
    assert.has_error(function() group.findings({ runlog("Dwarf", "WARRIOR", { { signal = "bogus" } }) }) end)
  end)


  it("maps severities and keeps expected manual completions out of the severity ladder", function()
    local sigs = {
      { signal = "below-level", gid = "G", file = "f", line = 1, action = "A", name = "a", qid = 1 },
      { signal = "leftover-quests", gid = "G", file = "f", qid = 2 },
      { signal = "stuck", gid = "G", file = "f", line = 3, action = "C", name = "s", reason = "settle-limit" },
      { signal = "manual-completion", gid = "G", file = "f", line = 4, action = "C", name = "m", expected = false },
      { signal = "manual-completion", gid = "G", file = "f", line = 5, action = "H", name = "h", expected = true },
      { signal = "lua-error", message = "boom", stack = "x.lua:1" },
      { signal = "missing-global", global = "FooBar" },
    }
    local fs = group.findings({ runlog("Dwarf", "WARRIOR", sigs) })
    local sev = {}
    for _, f in ipairs(fs) do sev[#sev + 1] = f.signal .. ":" .. tostring(f.severity) .. ":" .. tostring(f.expected) end
    table.sort(sev)
    assert.same({
      "below-level:medium-high:nil", "leftover-quests:low:nil", "lua-error:high:nil",
      "manual-completion:medium:nil", "manual-completion:nil:true", "missing-global:low:nil",
      "stuck:medium:nil",
    }, sev)
  end)

  it("groups harness lua-errors apart from addon lua-errors", function()
    local fs = group.findings({ runlog("Dwarf", "WARRIOR", {
      { signal = "lua-error", message = "boom" },
      { signal = "lua-error", message = "boom", reason = "harness" },
    }) })
    assert.equal(2, #fs)
  end)

  it("collects sorted unique reasons and sorts by file, line, signal, id", function()
    local fs = group.findings({
      runlog("Dwarf", "WARRIOR", { dna({ reason = "zeta" }), dna({ line = 5, qid = 9, file = "A.lua" }) }),
      runlog("Gnome", "MAGE", { dna({ reason = "alpha" }) }),
    })
    assert.equal("A.lua", fs[1].file)
    assert.same({ "alpha", "zeta" }, fs[2].reasons)
  end)

  -- Final review minor 1: severity rank first, file-less findings last within it.
  it("sorts by severity rank, then file (file-less last), line, signal, id", function()
    local fs = group.findings({ runlog("Dwarf", "WARRIOR", {
      { signal = "leftover-quests", gid = "G1", file = "A.lua", qid = 5 },
      dna({ file = "Z.lua", line = 9 }),
      { signal = "lua-error", message = "boom" },
      { signal = "never-shown-accept", gid = "G1", file = "Z.lua", line = 3, action = "A", name = "N", qid = 6 },
      { signal = "below-level", gid = "G1", file = "B.lua", line = 1, action = "A", name = "L", qid = 7 },
      { signal = "missing-global", global = "Foo" },
      { signal = "manual-completion", gid = "G1", file = "A.lua", line = 1, action = "N", name = "x", expected = true },
    }) })
    local got = {}
    for _, f in ipairs(fs) do got[#got + 1] = f.signal .. "@" .. tostring(f.file) end
    assert.same({ "never-shown-accept@Z.lua", "lua-error@nil", "below-level@B.lua", "did-not-advance@Z.lua",
      "leftover-quests@A.lua", "missing-global@nil", "manual-completion@A.lua" }, got)
  end)
end)
