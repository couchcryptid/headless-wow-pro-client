-- Human-first findings markdown (design spec §4.1–§4.9).
local group = require("hwc.findings.group")
local render = require("hwc.findings.render")

local function runlog(race, class, signals)
  return { character = { race = race, class = class, professions = {} }, rank = 2, steps = {},
    signals = signals, guides = {} }
end

local GUIDE = "WoWPro_Leveling/Forever/Alliance/01_12_Dun_Morogh.lua"

local function sigs()
  return {
    { signal = "did-not-advance", gid = "G1", file = GUIDE, line = 40, action = "T", name = "Report", qid = 314,
      why = "w", level = 3, log = { 314, 5 }, before = { name = "b", action = "A" }, after = { name = "c" },
      confidence = "verified" },
    { signal = "accept-refused", gid = "G1", file = GUIDE, line = 10, action = "A", name = "Pre", qid = 96629,
      reason = "prerequisite", confidence = "unverified", before = { name = "Earlier", action = "T" },
      after = { name = "Later", action = "A" } },
    { signal = "never-shown-accept", gid = "G1", file = GUIDE, line = 20, action = "A", name = "Next", qid = 5,
      why = "PRE&(x): A mandatory prereq was not met: 96629" },
    { signal = "manual-completion", gid = "G1", file = GUIDE, line = 50, action = "H", name = "Hearth", expected = true },
    { signal = "lua-error", message = "boom\nsecond line", stack = "x.lua:1" },
    { signal = "lua-error", message = "harness boom", reason = "harness" },
    { signal = "missing-global", global = "FACTION_HORDE" },
  }
end

local function header()
  return { scope = "Dwarf-WARRIOR-baseline", date = "2026-11-12",
    addon = { path = "../WoW-Pro-Guides", branch = "main", commit = "64fe6b3aabbccddeeff00112233445566778899", dirty = false },
    catalog = { questie = { path = "local/questie", present = true,
      sha256 = "deadbeef0123456789abcdef0123456789abcdef", commit = "d57637f" } },
    client = { commit = "c0ffee1234567890", dirty = false }, matrix = { combos = { "Dwarf WARRIOR baseline" } },
    rank = 2, paths_relative_to = "headless-wow-pro-client" }
end

local function md(logs, h) return render.markdown(group.findings(logs), h or header()) end

local function count(s, pat)
  local n = 0
  for _ in s:gmatch(pat) do n = n + 1 end
  return n
end

local function plain(s, needle) return s:find(needle, 1, true) end

-- A hand-built finding; render takes group's shape, so tests can set fields directly.
local function finding(n, fields)
  local f = { id = string.format("F-%08x", n), signal = "did-not-advance", severity = "medium",
    file = GUIDE, line = n, action = "A", name = "Q" .. n, combos = { "Dwarf WARRIOR baseline" },
    causes = {}, reasons = {} }
  for k, v in pairs(fields or {}) do f[k] = v end
  return f
end

describe("render.markdown", function()
  local out = md({ runlog("Dwarf", "WARRIOR", sigs()) })
  local fs = group.findings({ runlog("Dwarf", "WARRIOR", sigs()) })

  it("title line counts findings and those that follow from others", function()
    -- 4 counted findings (did-not-advance, accept-refused, never-shown, addon lua-error);
    -- never-shown follows from the refusal.
    assert.truthy(out:find("^# Dwarf Warrior: 4 findings, 1 follows from others\n"))
    assert.falsy(plain(out, "root cause"))
    assert.truthy(plain(out, "\n2026-11-12 · WoW-Pro `main` @ `64fe6b3` · 1 character · `Dwarf-WARRIOR-baseline`\n"))
  end)

  it("one Triage: _pending_ per non-expected, non-harness finding", function()
    local n = 0
    for _, f in ipairs(fs) do
      if not f.expected and not f.harness and f.signal ~= "missing-global" then n = n + 1 end
    end
    assert.equal(4, n)
    assert.equal(n, count(out, "\nTriage: _pending_\n"))
  end)

  it("follow-on findings are compact", function()
    local child
    for _, f in ipairs(fs) do if f.signal == "never-shown-accept" then child = f end end
    assert.truthy(child.caused_by)
    local anchor = "<a id=\"f-" .. child.id:sub(3):lower() .. "\"></a>"
    local s = assert(plain(out, anchor))
    local block = out:sub(s, (out:find("\nTriage: _pending_\n", s, true)))
    assert.truthy(plain(block, "Follows from ["))
    assert.falsy(plain(block, "**Between steps:**"))
    -- the root keeps its bullets and lists its children
    local root = assert(plain(out, "<a id=\"f-" .. child.caused_by:sub(3):lower() .. "\"></a>"))
    local rblock = out:sub(root, (out:find("\nTriage: _pending_\n", root, true)))
    assert.truthy(plain(rblock, "- **Between steps:** Turn in \"Earlier\" → *this step* → Accept \"Later\"\n"))
    assert.truthy(plain(rblock, "- **Also blocks:** ["))
  end)

  it("findings sit under their file heading in line order", function()
    local h = assert(plain(out, "## Guide files\n\n### 01_12_Dun_Morogh.lua"))
    assert.truthy(plain(out, "\n`" .. GUIDE .. "`\n"))
    local a = assert(plain(out, " · line 10", h))
    local b = assert(plain(out, " · line 20", h))
    local c = assert(plain(out, " · line 40", h))
    assert.truthy(a < b and b < c)
    local addon = assert(plain(out, "## Addon code\n"))
    assert.truthy(c < addon)
    assert.truthy(plain(out, "Lua error: boom", addon))
  end)

  it("no none or n/a values", function()
    assert.falsy(out:find(": none\n", 1, true))
    assert.falsy(out:find(": n/a\n", 1, true))
    assert.falsy(out:find("\n- none", 1, true))
    local empty = render.markdown({}, { scope = "s" })
    assert.falsy(empty:find(": none\n", 1, true))
    assert.falsy(empty:find(": n/a\n", 1, true))
    assert.falsy(empty:find("\n- none", 1, true))
  end)

  it("engine fold neutralises backticks", function()
    local f = finding(1, { why = "bad `x` here\nmore", severity = "medium" })
    local o = render.markdown({ f }, header())
    assert.truthy(plain(o, "<details><summary>Engine detail · F-00000001</summary>\n\n"))
    assert.truthy(plain(o, "- Engine said: `bad 'x' here more`\n"))
    assert.truthy(plain(o, "- Signal: `did-not-advance`\n"))
    assert.truthy(plain(o, "\n</details>\n\nTriage: _pending_\n"))
  end)

  it("harness summary omits a zero count", function()
    local g = finding(1, { signal = "missing-global", name = "TomTom" })
    local e = finding(2, { signal = "lua-error", harness = true, message = "stub boom" })
    assert.truthy(plain(render.markdown({ g }, header()),
      "<details><summary>1 missing global: gaps in this client's WoW API stubs, not guide bugs</summary>"))
    assert.truthy(plain(render.markdown({ e }, header()),
      "<details><summary>1 harness error: gaps in this client's WoW API stubs, not guide bugs</summary>"))
  end)

  it("harness notices are folded and keep ids", function()
    local s = assert(plain(out, "## Harness notices\n\n<details><summary>1 missing global and 1 harness error: "
      .. "gaps in this client's WoW API stubs, not guide bugs</summary>\n\n"))
    for _, f in ipairs(fs) do
      if f.harness or f.signal == "missing-global" then assert.truthy(plain(out, f.id, s)) end
    end
    assert.truthy(plain(out, "- `FACTION_HORDE` · F-", s))
    assert.truthy(plain(out, "- `harness boom` · F-", s))
    -- not counted anywhere above the fold
    assert.falsy(plain(out:sub(1, s), "FACTION_HORDE"))
  end)

  it("expected manual clicks are folded", function()
    local s = assert(plain(out, "## Expected manual clicks\n\n<details><summary>1 step the client clicked off by design"))
    local id
    for _, f in ipairs(fs) do if f.expected then id = f.id end end
    assert.truthy(plain(out, "- `01_12_Dun_Morogh.lua:50` Hearth to \"Hearth\" · " .. id .. "\n", s))
    assert.falsy(plain(out:sub(1, s), "Hearth"))
    -- no line: the file name alone
    local e = finding(9, { expected = true, action = "N", name = "Read me" })
    e.severity, e.line = nil, nil
    local o = render.markdown({ e }, header())
    assert.truthy(plain(o, "- `01_12_Dun_Morogh.lua` Note: \"Read me\" · F-00000009\n"))
  end)

  it("warnings appear only when warranted", function()
    assert.falsy(out:find("\n>", 1, true))
    local h = header()
    h.addon.dirty = true
    assert.truthy(plain(render.markdown({}, h), "\n> - The WoW-Pro checkout had uncommitted changes; "
      .. "this run may not be reproducible from its commit.\n"))
    h = header()
    h.client.dirty = true
    assert.truthy(plain(render.markdown({}, h), "\n> - The client checkout had uncommitted changes; "
      .. "this run may not be reproducible from its commit.\n"))
    h = header()
    h.catalog.supplement = { present = false, path = "local/supplement.lua" }
    assert.truthy(plain(render.markdown({}, h), "\n> - Catalog source `supplement` was missing. Camping 101 quests "
      .. "aren't recognised, so profession variants match their baselines.\n"))
    h = header()
    h.catalog.other = { present = false }
    assert.truthy(plain(render.markdown({}, h), "\n> - Catalog source `other` was missing.\n"))
    local list = { finding(1, { confidence = "unverified" }), finding(2, { confidence = "unverified" }),
      finding(3, { confidence = "verified" }) }
    assert.truthy(plain(render.markdown(list, header()),
      "\n> - 2 of 3 findings rest on quest data not checked against a second source.\n"))
    list[2].confidence = "verified"
    assert.falsy(render.markdown(list, header()):find("\n>", 1, true))
  end)

  it("About this run names the base by its last segment only", function()
    assert.truthy(plain(out, "\n- Paths relative to: `headless-wow-pro-client`\n"))
    local h = header()
    h.paths_relative_to = nil
    assert.falsy(plain(render.markdown({}, h), "Paths relative to"))
  end)

  it("zero findings renders Nothing found.", function()
    local o = render.markdown({}, header())
    assert.truthy(plain(o, "## Start here\n\nNothing found.\n"))
    assert.falsy(plain(o, "## At a glance"))
    assert.falsy(plain(o, "## Guide files"))
    assert.falsy(plain(o, "## Addon code"))
    assert.truthy(plain(o, "## About this run"))
  end)

  it("About this run shortens hashes to 12 and lists questie files on separate lines", function()
    local s = assert(plain(out, "## About this run\n"))
    assert.truthy(plain(out, "- WoW-Pro: `../WoW-Pro-Guides` · branch `main` · commit "
      .. "`64fe6b3aabbccddeeff00112233445566778899` · clean\n", s))
    assert.truthy(plain(out, "- Client: commit `c0ffee1234567890` · clean\n", s))
    assert.truthy(plain(out, "- Characters: Dwarf Warrior\n", s))
    assert.truthy(plain(out, "- Guide rank: `2`", s))
    assert.truthy(plain(out, "  - `questie`: present · commit `d57637f` · sha256 `deadbeef0123` · `local/questie`\n", s))
    assert.falsy(plain(out, "deadbeef01234", s))
    assert.truthy(plain(out, "  - rested XP\n", s))
    local h = header()
    h.catalog.questie.sha256 = { ["b.lua"] = "2222222222222222", ["a.lua"] = "1111111111111111" }
    local o = render.markdown({}, h)
    assert.truthy(plain(o, "  - `questie`: present · commit `d57637f` · `local/questie`\n"
      .. "    - `a.lua` `111111111111`\n    - `b.lua` `222222222222`\n"))
  end)

  it("every F- id appears", function()
    for _, f in ipairs(fs) do assert.truthy(plain(out, f.id), f.id) end
  end)

  it("ends with exactly one trailing newline and no carriage returns", function()
    assert.truthy(out:match("[^\n]\n$"))
    assert.falsy(out:find("\r", 1, true))
  end)

  it("is identical when the RunLog arrays are shuffled or reversed", function()
    local a = runlog("Dwarf", "WARRIOR", sigs())
    local b = runlog("Gnome", "MAGE", sigs())
    local h = header()
    h.matrix.combos = { "Gnome MAGE baseline", "Dwarf WARRIOR baseline" }
    local base = md({ a, b }, h)
    assert.equal(base, md({ b, a }, h))
    local rev = sigs()
    local shuffled = {}
    for i = #rev, 1, -1 do shuffled[#shuffled + 1] = rev[i] end
    assert.equal(base, md({ runlog("Gnome", "MAGE", shuffled), runlog("Dwarf", "WARRIOR", sigs()) }, h))
    assert.truthy(base:find("^# 2 characters %(Dwarf, Gnome%): 4 findings, 1 follows from others\n"))
  end)

  it("start here ranks by descendant count and caps at 5", function()
    local list, n = {}, 0
    for r = 0, 6 do
      n = n + 1
      local root = finding(n, { severity = "high", signal = "accept-refused", line = 100 + r })
      list[#list + 1] = root
      for _ = 1, r do
        n = n + 1
        local child = finding(n, { caused_by = root.id, line = 200 + n })
        root.causes[#root.causes + 1] = child.id
        list[#list + 1] = child
      end
    end
    local o = render.markdown(list, header())
    local s = assert(plain(o, "## Start here\n"))
    local e = assert(plain(o, "## At a glance\n"))
    local section = o:sub(s, e)
    assert.equal(5, count(section, "\n%d%. "))
    local prev = 0
    for i, r in ipairs({ 6, 5, 4, 3, 2 }) do
      local line = string.format("\n%d. 🔴 [", i)
      local p = assert(plain(section, line), line)
      assert.truthy(p > prev)
      prev = p
      assert.truthy(plain(section, string.format("explains %d more · `01_12_Dun_Morogh.lua:%d`\n", r, 100 + r), p))
    end
    assert.falsy(plain(section, "explains 0 more"))
  end)

  it("counts descendants through the whole chain and survives a cycle", function()
    local a = finding(1, { severity = "high" })
    local b = finding(2, { caused_by = a.id })
    local c = finding(3, { caused_by = b.id })
    a.causes, b.causes, c.causes = { b.id }, { c.id }, { a.id }
    local o = render.markdown({ a, b, c }, header())
    assert.truthy(plain(o, "explains 2 more"))
  end)

  it("renders At a glance with blank zero cells and file links", function()
    local s = assert(plain(out, "## At a glance\n"))
    assert.truthy(plain(out, "| | Primary | Follow-on | Total |\n|---|---|---|---|\n", s))
    assert.truthy(plain(out, "| 🔴 High | 2 | 1 | 3 |\n", s))
    assert.truthy(plain(out, "| 🟡 Medium | 1 |  | 1 |\n", s))
    assert.truthy(plain(out, "| File | 🔴 High | 🟠 Medium-high | 🟡 Medium | ⚪ Low |\n", s))
    assert.truthy(plain(out, "| [01_12_Dun_Morogh.lua](#", s))
  end)

  it("renders the dungeon root, its links and the de-duplicated matrix", function()
    local dsig = {}
    for i = 1, 2 do
      dsig[i] = { signal = "never-shown-accept", gid = "G" .. i, file = GUIDE, line = i, action = "A",
        name = "D" .. i, qid = 900 + i, reason = "engine-dungeon-skip" }
    end
    local h = header()
    h.addon.dirty = nil
    h.matrix.combos = { "Gnome MAGE baseline", "Gnome MAGE baseline" }
    local o = render.markdown(group.findings({ runlog("Dwarf", "WARRIOR", dsig) }), h)
    assert.truthy(o:find("^# Gnome Mage: 3 findings, 2 follow from others\n"))
    assert.truthy(plain(o, "1. 🔴 [EnableDungeons auto-completes dungeon accepts](#f-"))
    assert.truthy(plain(o, "explains 2 more · `WoWPro/WoWPro_Broker.lua:2588`\n"))
    assert.truthy(plain(o, "### WoWPro_Broker.lua"))
    assert.truthy(plain(o, "Dungeon quest \"D1\" is skipped"))
    assert.equal(3, count(o, "\nTriage: _pending_\n"))
    assert.truthy(plain(o, "- WoW-Pro: `../WoW-Pro-Guides` · branch `main` · commit "
      .. "`64fe6b3aabbccddeeff00112233445566778899`\n"))
    assert.truthy(plain(o, "- Characters: Gnome Mage\n"))
    assert.falsy(o:find("\n>", 1, true))
  end)

  it("puts the full combo list in the fold when the summary drops detail", function()
    local matrix = {}
    for _, v in ipairs({ "baseline", "a" }) do matrix[#matrix + 1] = "Dwarf HUNTER " .. v end
    for _, c in ipairs({ "Gnome MAGE baseline", "Gnome PRIEST baseline", "Dwarf PRIEST baseline",
      "Gnome ROGUE baseline" }) do matrix[#matrix + 1] = c end
    local h = header()
    h.matrix.combos = matrix
    -- "(all 2 variants)" hides the variant names: the fold lists them.
    local f = finding(1, { combos = { "Dwarf HUNTER baseline", "Dwarf HUNTER a" } })
    local o = render.markdown({ f }, h)
    assert.truthy(plain(o, "- **Affects:** Dwarf Hunter (all 2 variants)\n"))
    assert.truthy(plain(o, "- All characters: Dwarf Hunter, Dwarf Hunter (a)\n"))
    -- "all N characters" is complete: no list in the fold.
    f.combos = matrix
    o = render.markdown({ f }, h)
    assert.truthy(plain(o, "- **Affects:** all 6 characters\n"))
    assert.falsy(plain(o, "All characters:"))
  end)

  it("titles, Start here and the severity table claim no diagnosis", function()
    local a = finding(1, { severity = "high" })
    local o = render.markdown({ a }, header())
    assert.truthy(o:find("^# Dwarf Warrior: 1 finding\n"))
    assert.truthy(plain(o, "## Start here\n\nThese findings have the most other findings following from them. "
      .. "Fixing one may also clear those.\n"))
    assert.falsy(plain(o, "root cause"))
  end)

  it("labels Night Elf characters by display name", function()
    local h = header()
    h.matrix.combos = { "NightElf WARRIOR baseline" }
    assert.truthy(render.markdown({}, h):find("^# Night Elf Warrior: no findings\n"))
    h.matrix.combos = { "NightElf WARRIOR baseline", "Dwarf WARRIOR baseline" }
    local o = render.markdown({ finding(1, { combos = { "NightElf WARRIOR baseline" } }) }, h)
    assert.truthy(o:find("^# 2 characters %(Dwarf, Night Elf%): 1 finding\n"))
    assert.truthy(plain(o, "- **Affects:** all except Dwarf Warrior\n"))
    assert.truthy(plain(o, "- Characters: Dwarf Warrior, Night Elf Warrior\n"))
  end)

  it("escapes markdown in headings and Start here links", function()
    local f = finding(1, { signal = "lua-error", severity = "high", file = "WoWPro/W.lua",
      message = "W.lua:3: '<eof>' expected near ']'" })
    local o = render.markdown({ f }, header())
    local esc = "Lua error: W.lua:3: '&lt;eof&gt;' expected near '\\]'"
    assert.truthy(plain(o, "#### 🔴 " .. esc .. " <a id=\"f-00000001\"></a>\n"))
    assert.truthy(plain(o, "1. 🔴 [" .. esc .. "](#f-00000001)"))
  end)

  it("tells same-title children apart in Also blocks", function()
    local root = finding(1, { severity = "high", signal = "accept-refused", reasons = { "prerequisite" } })
    local a = finding(2, { caused_by = root.id, name = "Same", qid = 20 })
    local b = finding(3, { caused_by = root.id, name = "Same", qid = 30 })
    root.causes = { a.id, b.id }
    local o = render.markdown({ root, a, b }, header())
    assert.truthy(plain(o, "- **Also blocks:** [\"Same\" doesn't advance (quest 20, line 2)](#f-00000002), "
      .. "[\"Same\" doesn't advance (quest 30, line 3)](#f-00000003)\n"))
  end)

  it("says detached for a checkout on HEAD", function()
    local h = header()
    h.addon.branch = "HEAD"
    h.client.branch = "HEAD"
    local o = render.markdown({}, h)
    assert.truthy(plain(o, "\n2026-11-12 · WoW-Pro detached @ `64fe6b3` · 1 character"))
    assert.truthy(plain(o, "- WoW-Pro: `../WoW-Pro-Guides` · detached · commit `64fe6b3aabbccddeeff00112233445566778899`"))
    assert.truthy(plain(o, "- Client: detached · commit `c0ffee1234567890`"))
    assert.falsy(plain(o, "HEAD"))
  end)

  it("writes the meta line and ground bullet", function()
    local f = finding(1, { signal = "below-level", severity = "medium-high", qid = 77, level = 4,
      confidence = "unverified", grind = { kills = 12, to = 6 } })
    local o = render.markdown({ f }, header())
    -- below-level: the signal's level is the grind's target, so the meta line drops it
    assert.truthy(plain(o, "\nMedium-high · line 1 · quest 77 · unverified quest data\n"))
    local d = render.markdown({ finding(2, { level = 4 }) }, header())
    assert.truthy(plain(d, "\nMedium · line 2 · level 4\n"))
    assert.truthy(plain(o, "- **Ground:** 12 kills to reach level 6\n"))
    assert.truthy(plain(o, "#### 🟠 \"Q1\" is offered below its level <a id=\"f-00000001\"></a>\n"))
  end)
end)
