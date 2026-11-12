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

  it("keeps the id when the line changes", function()
    local a = group.findings({ runlog("Dwarf", "WARRIOR", { dna({ line = 40 }) }) })[1]
    local b = group.findings({ runlog("Dwarf", "WARRIOR", { dna({ line = 99 }) }) })[1]
    assert.equal(a.id, b.id)
    assert.equal(99, b.line)
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

  it("links three dungeon skips under one engine-dungeon-skip root", function()
    local sigs = {}
    for i = 1, 3 do
      sigs[i] = { signal = "never-shown-accept", gid = "G" .. i, file = "d.lua", line = i, action = "A",
        name = "Dungeon " .. i, qid = 900 + i, reason = "engine-dungeon-skip" }
    end
    local fs = group.findings({ runlog("Dwarf", "WARRIOR", sigs) })
    local roots = by_signal(fs, "engine-dungeon-skip")
    assert.equal(1, #roots)
    local root = roots[1]
    assert.equal("high", root.severity)
    assert.equal("EnableDungeons auto-completes DUNGEON accepts", root.name)
    assert.equal("WoWPro/WoWPro_Broker.lua", root.file)
    assert.equal(2588, root.line)
    assert.equal(3, #root.causes)
    for _, f in ipairs(by_signal(fs, "never-shown-accept")) do assert.equal(root.id, f.caused_by) end
  end)

  it("makes no root without dungeon skips", function()
    assert.equal(0, #by_signal(group.findings({ runlog("Dwarf", "WARRIOR", { dna() }) }), "engine-dungeon-skip"))
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
end)
