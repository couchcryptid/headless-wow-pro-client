-- Canonical findings markdown (design spec §7.2).
local group = require("hwc.findings.group")
local render = require("hwc.findings.render")

local function runlog(race, class, signals)
  return { character = { race = race, class = class, professions = {} }, rank = 2, steps = {},
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
  }
end

local function header()
  return { scope = "dwarf-gnome-1-25", date = "2026-11-12",
    addon = { path = "/addon", branch = "main", commit = "abc123", dirty = false },
    catalog = { questie = { path = "/q", present = true, sha256 = "deadbeef", commit = "d57637f" } },
    client = { commit = "c0ffee" }, matrix = { combos = { "Gnome MAGE baseline", "Dwarf WARRIOR baseline" } },
    rank = 2 }
end

local function md(logs) return render.markdown(group.findings(logs), header()) end

local function count(s, pat)
  local n = 0
  for _ in s:gmatch(pat) do n = n + 1 end
  return n
end

describe("render.markdown catalog sha256 table", function()
  it("renders a per-file sha256 table sorted by file name (the questie source)", function()
    local h = header()
    h.catalog.questie.sha256 = { ["b.lua"] = "22", ["a.lua"] = "11" }
    local out = render.markdown(group.findings({ runlog("Dwarf", "WARRIOR", {}) }), h)
    assert.truthy(out:find("sha256=a.lua:11,b.lua:22", 1, true))
  end)
end)

describe("render.markdown", function()
  local out = md({ runlog("Dwarf", "WARRIOR", sigs()) })

  it("has the header lines and the gaps", function()
    assert.truthy(out:find("Rank: 2", 1, true))
    assert.truthy(out:find("Date: 2026-11-12", 1, true))
    assert.truthy(out:find("rested XP", 1, true))
    assert.truthy(out:find("instance XP", 1, true))
    assert.truthy(out:find("Gnome MAGE baseline", 1, true))
  end)

  -- Final review minor 9: the Client line flags a dirty hwc tree like the Addon line.
  it("flags the client tree clean, dirty or unknown", function()
    local h = header()
    h.client = { commit = "c0ffee", dirty = true }
    assert.truthy(render.markdown({}, h):find("\n%- Client: c0ffee %(dirty%)\n"))
    h.client.dirty = false
    assert.truthy(render.markdown({}, h):find("\n%- Client: c0ffee %(clean%)\n"))
    h.client.dirty = nil
    assert.truthy(render.markdown({}, h):find("\n%- Client: c0ffee %(unknown%)\n"))
  end)

  -- Rulings AB and AC: the known false-finding sources are named in the header.
  it("names the nameless Camping 101 and talk-to NPC gaps", function()
    assert.truthy(out:find("  - Camping 101 quests are recognised only by name from the local supplement " ..
      "(no catalog source names them); without it, profession variants equal baselines\n", 1, true))
    assert.truthy(out:find("  - talk-to NPC objectives may be credited as kills\n", 1, true))
  end)

  it("has one Triage: block per non-expected finding", function()
    local fs = group.findings({ runlog("Dwarf", "WARRIOR", sigs()) })
    local n = 0
    for _, f in ipairs(fs) do if not f.expected then n = n + 1 end end
    assert.equal(n, count(out, "\nTriage:\n"))
    assert.equal(n, count(out, "\n### F%-%x%x%x%x%x%x%x%x\n"))
  end)

  it("lists every field, links and the expected manual completions", function()
    assert.truthy(out:find("- Severity: high", 1, true))
    assert.truthy(out:find("- Caused by: F-", 1, true))
    assert.truthy(out:find("- Causes: F-", 1, true))
    assert.truthy(out:find("- Confidence: unverified quest data", 1, true))
    assert.truthy(out:find("## Expected manual completions", 1, true))
    assert.truthy(out:find("Hearth", 1, true))
    assert.falsy(out:find("boom\nsecond", 1, true)) -- one line per field
  end)

  it("ends with exactly one trailing newline and no carriage returns", function()
    assert.truthy(out:match("[^\n]\n$"))
    assert.falsy(out:find("\r", 1, true))
  end)

  it("is identical when the RunLog arrays are shuffled or reversed", function()
    local a = runlog("Dwarf", "WARRIOR", sigs())
    local b = runlog("Gnome", "MAGE", sigs())
    local base = md({ a, b })
    assert.equal(base, md({ b, a }))
    local rev = sigs()
    local shuffled = {}
    for i = #rev, 1, -1 do shuffled[#shuffled + 1] = rev[i] end
    assert.equal(base, md({ runlog("Gnome", "MAGE", shuffled), runlog("Dwarf", "WARRIOR", sigs()) }))
  end)

  it("renders the dungeon root, its links, unknown dirty and de-duplicated matrix", function()
    local dsig = {}
    for i = 1, 2 do
      dsig[i] = { signal = "never-shown-accept", gid = "G" .. i, file = "d.lua", line = i, action = "A",
        name = "D" .. i, qid = 900 + i, reason = "engine-dungeon-skip" }
    end
    local h = header()
    h.addon.dirty = nil
    h.matrix.combos = { "Gnome MAGE baseline", "Gnome MAGE baseline" }
    local o = render.markdown(group.findings({ runlog("Dwarf", "WARRIOR", dsig) }), h)
    assert.truthy(o:find("EnableDungeons auto-completes DUNGEON accepts", 1, true))
    assert.truthy(o:find("WoWPro/WoWPro_Broker.lua:2588", 1, true))
    assert.truthy(o:find("| engine-dungeon-skip | 1 |", 1, true))
    assert.equal(3, count(o, "\nTriage:\n"))
    assert.truthy(o:find("unknown)", 1, true))
    assert.truthy(o:find("- Matrix: Gnome MAGE baseline\n", 1, true))
  end)
end)
