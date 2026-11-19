-- Generates the shared format-2 findings fixtures, spec/fixtures/findings/{single,matrix,empty}.json.
-- They are the contract between Lua (busted) and TypeScript (Vitest): both read the same files.
--   luajit tools/report-fixtures.lua
-- spec/findings/fixtures_spec.lua fails when a committed file differs from what this builds.
--
-- Everything is synthetic and fixed (no clock, no git, no catalog), so the output is byte-stable.
-- build() is pure; only the script entry at the bottom writes files.
local root = (arg and arg[0] or ""):match("^(.*)/tools/[^/]*$")
if root == nil and arg and arg[0] and arg[0]:match("^tools/") then root = "." end
if root then
  -- The same paths bin/hwc sets: this repo's src, then the user's LuaRocks tree (dkjson, lfs).
  local rocks = (os.getenv("HOME") or "") .. "/.luarocks"
  package.path = root .. "/src/?.lua;" .. root .. "/src/?/init.lua;" .. rocks .. "/share/lua/5.1/?.lua;"
    .. rocks .. "/share/lua/5.1/?/init.lua;" .. package.path
  package.cpath = rocks .. "/lib/lua/5.1/?.so;" .. package.cpath
end

local group = require("hwc.findings.group")
local report = require("hwc.findings.report")
local json = require("hwc.json")

local fixtures = {}

local DWARF_WARRIOR = "Dwarf WARRIOR none"
local GNOME_MAGE = "Gnome MAGE none"
local GNOME_PRIEST = "Gnome PRIEST none"

-- Guide files, named like the real ones under the WoW-Pro checkout.
local DUN_1_5 = "WoWPro_Leveling/Guides/Alliance/Dun_1_5.lua"
local DUN_5_11 = "WoWPro_Leveling/Guides/Alliance/Dun_5_11.lua"
local DUN_11_14 = "WoWPro_Leveling/Guides/Alliance/Dun_11_14.lua"
local WES_12_15 = "WoWPro_Leveling/Guides/Alliance/Wes_12_15.lua"

local function runlog(race, class, signals, guide_levels, extra)
  local log = { character = { race = race, class = class, professions = {} }, rank = 2, steps = {},
    signals = signals, guides = {}, guide_levels = guide_levels }
  for k, v in pairs(extra or {}) do log[k] = v end
  return log
end

local function levels(gid, file, start_level, end_level, enter, leave, finished, last_line)
  return { gid = gid, file = file, start_level = start_level, end_level = end_level,
    enter = enter, leave = leave, finished = finished, last_line = last_line }
end

-- A fixed header: a git addon at a fixed commit, a clean client, one date.
-- extra adds run facts (filters, played, unreached, skipped_races).
local function header(scope, combos, guide_entries, stop, extra)
  local h = {
    scope = scope, date = "2026-01-01", paths_relative_to = "headless-wow-pro-client",
    addon = { git = true, branch = "master", commit = "0123456789abcdef0123456789abcdef01234567",
      dirty = false, path = "../WoW-Pro-Guides", version = "1.0" },
    client = { commit = "89abcdef0123456789abcdef0123456789abcdef", dirty = false },
    matrix = { combos = combos }, rank = 2,
    guides = report.guides(guide_entries), stop = stop,
  }
  for k, v in pairs(extra or {}) do h[k] = v end
  return h
end

-- relink, when given, edits the grouped findings' links before the report is built.
-- extra: more header facts, as header() takes them.
local function document(scope, logs, combos, stop, relink, extra)
  local entries = {}
  for i, l in ipairs(logs) do entries[i] = { combo = combos[i], guide_levels = l.guide_levels or {} } end
  local findings = group.findings(logs)
  if relink then relink(findings) end
  local doc = report.build(findings, header(scope, combos, entries, stop, extra))
  return json.encode(doc, { indent = true }) .. "\n"
end

---------------------------------------------------------------------------
-- single: one combo, about 25 findings
---------------------------------------------------------------------------

-- A step signal in one of the guides; extra fields override.
local function sig(signal, gid, file, line, action, name, qid, extra)
  local s = { signal = signal, gid = gid, file = file, line = line, action = action, name = name, qid = qid,
    ordinal = 1, confidence = "verified" }
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end

local function single_signals()
  local G1, G2, G3 = "Dun Morogh 1-5", "Dun Morogh 5-11", "Dun Morogh 11-14"
  local s = {}
  local function add(x) s[#s + 1] = x end

  -- Guide G1: a refused quest (96393) with a chain of follow-ons.
  -- accept-refused 96393 (high) <- never-shown-accept 93 (high, waits on 96393)
  --                                  <- never-shown-accept 94 (high, waits on 93): a two-level chain.
  -- The refused quest's turn-in also fails to advance: a follow-on in another severity (medium).
  add(sig("accept-refused", G1, DUN_1_5, 12, "A", "Rites of the Dun Morogh", 96393,
    { reason = "prerequisite", confidence = "unverified" }))
  add(sig("never-shown-accept", G1, DUN_1_5, 30, "A", "A Warrior's Welcome", 93,
    { why = "NextStep:PRE&(96393): A mandatory prereq was not met: 96393" }))
  add(sig("never-shown-accept", G1, DUN_1_5, 44, "A", "The Warrior's Path", 94,
    { why = "NextStep:PRE&(93): A mandatory prereq was not met: 93" }))
  add(sig("did-not-advance", G1, DUN_1_5, 60, "T", "Rites of the Dun Morogh", 96393,
    { reasons = nil, reason = "not-in-log", why = "step still current", level = 3, log = { 314 },
      before = { name = "Talk to Grull", action = "C" }, after = { name = "Kill Frostmane", action = "C" } }))
  -- A hidden use step, and the incomplete turn-in that follows from it (high -> medium).
  add(sig("hidden-use-step", G1, DUN_1_5, 100, "U", "Use the Healing Salve", 200, { use = "5000", loot = { [5001] = 2 } }))
  add(sig("did-not-advance", G1, DUN_1_5, 110, "T", "Salve for the Wounded", 200,
    { reason = "incomplete", level = 4, log = { 200 } }))
  add(sig("below-level", G1, DUN_1_5, 150, "A", "A Dwarf's Burden", 300,
    { qname = "Rites of Passage", grind = { kills = 4, to = 6 }, before = { name = "Skin the Boar", action = "C" },
      after = { name = "Return to Thorgas", action = "T" }, why = "level 4, quest needs 5" }))
  add(sig("wrong-race-class", G1, DUN_1_5, 170, "A", "Mage Training", 310, { reason = "class" }))
  -- Expected manual click: carries no severity and sits after the counted findings.
  add(sig("manual-completion", G1, DUN_1_5, 215, "H", "Hearth to Kharanos", nil, { expected = true }))

  -- Guide G2.
  -- A follow-on in another file: its cause is the G1 refusal, so in Guide order it nests
  -- under a card in the Dun_1_5 section and must name its own file.
  add(sig("never-shown-accept", G2, DUN_5_11, 25, "A", "Ironforge Calls", 95,
    { why = "NextStep:PRE&(96393): A mandatory prereq was not met: 96393" }))
  add(sig("manual-completion", G2, DUN_5_11, 33, "C", "Scout the Ridge", 410, { level = 6, log = { 410 } }))
  add(sig("orphan-turnin", G2, DUN_5_11, 51, "T", "Beer Run", 420, {}))
  add(sig("log-full", G2, DUN_5_11, 70, "A", "Troll Menace", 430, { level = 7, log = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25 } }))
  add(sig("did-not-advance", G2, DUN_5_11, 90, "T", "Troll Menace", 430, { reason = "not-in-log", level = 7, log = { 1 } }))
  add(sig("did-not-advance", G2, DUN_5_11, 120, "T", "Forging a Blade", 440,
    { reason = "requires-skill", level = 8, log = { 440 } }))
  add(sig("did-not-advance", G2, DUN_5_11, 130, "C", "Hunt the Dire Wolf", 450, { level = 8, log = { 450 } }))
  add(sig("leftover-quests", G2, DUN_5_11, 150, "T", "Rumours in Kharanos", 460,
    { qname = "Rumours in Kharanos", reason = "not-turned-in" }))
  add(sig("leftover-quests", G2, DUN_5_11, 160, "T", "Ore for Ironforge", 470, { qname = "Ore for Ironforge" }))
  add(sig("stuck", G2, DUN_5_11, 175, "R", "Run to Ironforge", nil, { reason = "same-step", level = 10 }))

  -- Guide G3 (600 lines): two findings 3 lines apart, closer than 1% of its length, so their pins touch.
  add(sig("never-shown-accept", G3, DUN_11_14, 300, "A", "Gnome Trouble", 500, {}))
  add(sig("below-level", G3, DUN_11_14, 303, "A", "Deep Digging", 510,
    { qname = "Gnome Trouble", before = { name = "Mine the Vein", action = "C" }, after = { name = "Report", action = "T" } }))
  add(sig("did-not-advance", G3, DUN_11_14, 520, "C", "Clear the Tunnel", 520, { level = 13, log = { 520 } }))
  -- Linked below (single_relink) to the harness missing global: a counted finding under an uncounted cause.
  add(sig("leftover-quests", G3, DUN_11_14, 560, "T", "Tunnel Rats", 530, { qname = "Tunnel Rats" }))

  -- Not guide findings: a Lua error with no file, one with a file, and the one harness item (a missing global).
  add({ signal = "lua-error", message = "attempt to index a nil value (field 'frame')",
    stack = "WoWPro.lua:410: in function 'NextStep'\nWoWPro_Broker.lua:88: in function <WoWPro_Broker.lua:70>" })
  add({ signal = "lua-error", gid = G2, file = DUN_5_11, line = 99,
    message = "bad argument #1 to 'strsplit' (string expected, got nil)", stack = "WoWPro_Leveling.lua:12: in main chunk" })
  add({ signal = "missing-global", global = "GetNumGroupMembers" })
  -- Arrival emulation: a data gap (a harness notice) and an arrival did-not-advance.
  add({ signal = "arrival-data-gap", reason = "start-node-unknown", key = "Gnome" })
  add(sig("did-not-advance", G3, DUN_11_14, 580, "R", "Stormwind", nil,
    { reason = "arrival-mismatch", named = { name = "Stormwind", tz = "1453; Stormwind City" },
      arrived = { zone = "Elwynn Forest", subzone = "Goldshire" }, resolved_by = "zone" }))
  return s
end

-- group.lua never links a finding to an uncounted one today, but the page must cope if it
-- does (filter.ts lifts such a finding; a fold entry must not nest it). Force one such link:
-- the Tunnel Rats leftover (qid 530) follows from the missing global.
local function single_relink(findings)
  local cause, child
  for _, f in ipairs(findings) do
    if f.signal == "missing-global" then cause = f end
    if f.qid == 530 then child = f end
  end
  child.caused_by = cause.id
  cause.causes[#cause.causes + 1] = child.id
  table.sort(cause.causes)
end

function fixtures.single()
  -- G1 is entered under its level, so the page has one enter-under flag; G3 is 600 lines long.
  local gl = {
    levels("Dun Morogh 1-5", DUN_1_5, 1, 5, 1, 5, true, 220),
    levels("Dun Morogh 5-11", DUN_5_11, 5, 11, 4, 11, true, 180),
    levels("Dun Morogh 11-14", DUN_11_14, 11, 14, 11, 14, true, 600),
  }
  local log = runlog("Dwarf", "WARRIOR", single_signals(), gl)
  return document("Dwarf-WARRIOR-baseline", { log }, { DWARF_WARRIOR }, nil, single_relink)
end

---------------------------------------------------------------------------
-- matrix: three combos, two races
---------------------------------------------------------------------------

function fixtures.matrix()
  local G1, G2, G3 = "Dun Morogh 1-5", "Dun Morogh 5-11", "Westfall 12-15"
  local function dna(gid, file, line, qid, name, extra)
    return sig("did-not-advance", gid, file, line, "T", name, qid, extra)
  end
  -- Every combo meets the Burden turn-in; the mage and priest alone meet the others.
  local warrior = runlog("Dwarf", "WARRIOR", {
    dna(G1, DUN_1_5, 60, 314, "Report to Grull", { reason = "incomplete", level = 3, log = { 314 } }),
    sig("never-shown-accept", G2, DUN_5_11, 20, "A", "Beer Run", 421, {}),
  }, {
    levels(G1, DUN_1_5, 1, 5, 1, 5, true, 220),
    levels(G2, DUN_5_11, 5, 11, 5, 11, true, 180),
    levels(G3, WES_12_15, 12, 15, 12, 14, false, 300),
  })
  local mage = runlog("Gnome", "MAGE", {
    dna(G1, DUN_1_5, 60, 314, "Report to Grull", { reason = "incomplete", level = 3, log = { 314 } }),
    sig("wrong-race-class", G1, DUN_1_5, 170, "A", "Warrior Training", 310, { reason = "class" }),
    sig("manual-completion", G2, DUN_5_11, 33, "C", "Scout the Ridge", 410, { level = 7, log = { 410 } }),
  }, {
    levels(G1, DUN_1_5, 1, 5, 1, 5, true, 220),
    levels(G2, DUN_5_11, 5, 11, 7, 11, true, 180),
  })
  -- The priest is boosted past the Westfall guide's levels: an enter-over flag. Westfall: only warrior and priest.
  local priest = runlog("Gnome", "PRIEST", {
    dna(G1, DUN_1_5, 60, 314, "Report to Grull", { reason = "incomplete", level = 3, log = { 314 } }),
    sig("below-level", G3, WES_12_15, 40, "A", "The Defias Brotherhood", 600,
      { qname = "Deliver the Crates", before = { name = "Go", action = "R" }, after = { name = "Wait", action = "T" } }),
  }, {
    levels(G1, DUN_1_5, 1, 5, 1, 5, true, 220),
    levels(G3, WES_12_15, 12, 15, 16, 16, true, 300),
  })
  local combos = { DWARF_WARRIOR, GNOME_MAGE, GNOME_PRIEST }
  -- A filtered matrix: Human starts in Elwynn, which the filters exclude, so it reached no
  -- included guide and was skipped; Loch Modan was included but no character reached it.
  return document("forever-alliance-dwarf-gnome-human-filtered", { warrior, mage, priest }, combos, nil, nil, {
    filters = { { kind = "include", pattern = "WoWPro_Leveling/Guides/Alliance" },
      { kind = "exclude", pattern = "WoWPro_Leveling/Guides/Alliance/Elw_*" } },
    played = { G1, G2, G3 },
    unreached = { "Loch Modan 12-20" },
    skipped_races = { "Human" },
  })
end

---------------------------------------------------------------------------
-- empty: a run that stopped early with nothing found
---------------------------------------------------------------------------

function fixtures.empty()
  local log = runlog("Dwarf", "WARRIOR", {}, {})
  return document("Dwarf-WARRIOR-baseline", { log }, { DWARF_WARRIOR },
    { { combo = "Dwarf WARRIOR none", reason = "iterations" } })
end

-- { [name] = json_text }, pure.
function fixtures.build()
  return { single = fixtures.single(), matrix = fixtures.matrix(), empty = fixtures.empty() }
end

---------------------------------------------------------------------------
-- Script entry: write the files.
---------------------------------------------------------------------------

if arg and arg[0] and arg[0]:match("report%-fixtures%.lua$") and root then
  local dir = root .. "/spec/fixtures/findings"
  os.execute("mkdir -p '" .. dir .. "'")
  for name, text in pairs(fixtures.build()) do
    local f = assert(io.open(dir .. "/" .. name .. ".json", "wb"))
    f:write(text)
    f:close()
    io.write("wrote ", dir, "/", name, ".json\n")
  end
end

return fixtures
