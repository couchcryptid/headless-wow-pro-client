-- Canonical findings JSON document, format 2 (design spec §5). Pure: no I/O.
-- The single source of truth for the HTML page: every fact and every piece of
-- wording is here, so the page only sorts, filters, counts and lays out.
local text = require("hwc.findings.text")

local report = {}

report.FORMAT = 2

-- dkjson encodes an empty table as []: maps that may be empty are marked.
local ARRAY = { __jsontype = "array" }
local OBJECT = { __jsontype = "object" }

-- What the simulation doesn't model: "About this run".
report.GAPS = {
  "rested XP",
  "Forever Boosted Rest from campfires",
  "party XP for non-elites (spec §5.5)",
  "dungeon runs and instance XP (spec §3)",
  -- QuestieDB's objective rows have no counts: they come from its quest text or the counts file.
  "objective counts in neither QuestieDB's quest text nor the counts file are taken as 1, so kills and kill XP may run short",
  -- Ruling AC: kill vs talk-to is a heuristic (kills.objective_kills).
  "talk-to NPC objectives may be credited as kills",
  -- Catalog:quest_rewards: QuestieDB has no reward counts and no choice/fixed split.
  "quest rewards give one of each item QuestieDB lists, choice rewards included",
  -- Subzones (Anvilmar, Kharanos, ...) come only from R steps; IZ-gated class-training notes may stay hidden.
  "subzones are known only from R steps; steps gated on a subzone by IZ may stay hidden",
  -- Design 2026-11-18-reputation §3, §4.5: no kill, item turn-in or encounter reputation.
  "reputation is gained from quest rewards only (no kills, item turn-ins or encounters)",
}

-- Harness notices are about the client's WoW API stubs, arrival data or emulation, not guides: kept out of
-- every count and shown only in their own folded section.
function report.is_harness(f)
  return f.signal == "missing-global" or f.signal == "arrival-data-gap" or f.signal == "emulation-gap"
    or (f.signal == "lua-error" and f.harness == true)
end
local is_harness = report.is_harness

-- Counted findings feed every count; harness notices and expected manual
-- clicks sit in their own folds.
function report.counted(f)
  return f.severity ~= nil and not f.expected and not is_harness(f)
end
local counted = report.counted

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

local function plural(n, word, words)
  return n .. " " .. (n == 1 and word or (words or word .. "s"))
end

-- The context text.sentence needs.
function report.context(findings, header)
  local by_id = {}
  for _, f in ipairs(findings) do by_id[f.id] = f end

  local single
  local combos = header and header.matrix and header.matrix.combos
  if combos then
    local seen, n, only = {}, 0, nil
    for _, c in ipairs(combos) do
      if not seen[c] then seen[c] = true; n = n + 1; only = c end
    end
    if n == 1 then single = text.character(only) end
  end
  return { by_id = by_id, single = single }
end

---------------------------------------------------------------------------
-- Guide levels and level flags (design spec §4.4)
---------------------------------------------------------------------------

local FLAG_RULES = {
  { rule = "enter-under",
    fires = function(g, l) return l.enter and g.start_level and l.enter < g.start_level end },
  { rule = "leave-under",
    fires = function(g, l) return l.finished and l.leave and g.end_level and l.leave < g.end_level end },
  { rule = "enter-over",
    fires = function(g, l) return l.enter and g.end_level and l.enter > g.end_level end },
}

local function flags_of(g)
  local flags = setmetatable({}, ARRAY)
  for _, combo in ipairs(sorted_keys(g.levels)) do
    for _, r in ipairs(FLAG_RULES) do
      if r.fires(g, g.levels[combo]) then flags[#flags + 1] = { combo = combo, rule = r.rule } end
    end
  end
  table.sort(flags, function(a, b)
    if a.combo ~= b.combo then return a.combo < b.combo end
    return a.rule < b.rule
  end)
  return flags
end

-- header.guides: every guide played, merged across characters by first
-- appearance walking the entries in order. entries is
-- { { combo = label, guide_levels = log.guide_levels }, ... }.
function report.guides(entries)
  local out, by_gid = setmetatable({}, ARRAY), {}
  for _, e in ipairs(entries) do
    for _, l in ipairs(e.guide_levels or {}) do
      local g = by_gid[l.gid]
      if not g then
        g = { file = l.file, gid = l.gid, start_level = l.start_level, end_level = l.end_level, levels = {} }
        by_gid[l.gid] = g
        out[#out + 1] = g
      end
      if l.last_line and (not g.last_line or l.last_line > g.last_line) then g.last_line = l.last_line end
      g.levels[e.combo] = { enter = l.enter, leave = l.leave, finished = l.finished }
    end
  end
  for _, g in ipairs(out) do g.flags = flags_of(g) end
  return out
end

---------------------------------------------------------------------------
-- Warnings (the header's warning lines)
---------------------------------------------------------------------------
-- Only what changes how every finding below reads: the page shows these above
-- the findings and the CLI prints them on stderr. Everything else is placed
-- where it's read: a dirty checkout on the page's run line and in About this
-- run, level flags on the guide map, the unverified count in About this run.

-- QuestieDB is the only quest source: without it no quest has XP, level or objectives.
local function catalog_warnings(warn, catalog)
  local q = (catalog or {}).questie
  if q and q.present == false then
    warn[#warn + 1] = "QuestieDB was missing, so no quest had XP, a level or objectives: treat every finding as suspect."
  end
end

-- A race a filtered matrix skipped played nothing: say so up front, not only in About this run.
local function skipped_races_warning(warn, races)
  if not races or #races == 0 then return end
  warn[#warn + 1] = plural(#races, "race") .. " reached no included guide and "
    .. (#races == 1 and "was" or "were") .. " skipped: " .. table.concat(races, ", ") .. "."
end

function report.warnings(header)
  local warn = setmetatable({}, ARRAY)
  catalog_warnings(warn, header.catalog)
  skipped_races_warning(warn, header.skipped_races)
  return warn
end

---------------------------------------------------------------------------
-- Notes: the run facts "About this run" explains, as finished plain sentences
---------------------------------------------------------------------------

local function ids(list) return table.concat(list, ", ") end

-- Quests from jumped guides were never done, so findings next to a jump can be its noise.
function report.jumped_note(jumped)
  if not jumped or #jumped == 0 then return nil end
  return "Jumped guides: " .. #jumped .. " (" .. ids(jumped) .. "). Their quests were never done, so "
    .. "prerequisite, turn-in and leftover-quest findings after a jump may come from it."
end

-- WoWPro's Skip Dungeon Quests option. This client doesn't run dungeons, so the DUNGEON
-- accepts it completes unshown are expected and stated here instead of as findings.
function report.dungeons_note(d)
  if not d or d.skip == nil then return nil end
  local s = "Skip dungeon quests: " .. (d.skip and "on" or "off") .. " (WoWPro's EnableDungeons)"
  local n = d.skipped or 0
  if n > 0 then
    s = s .. ". This client doesn't run dungeons, so the " .. plural(n, "dungeon accept") .. " WoWPro skipped "
      .. (n == 1 and "isn't listed as a finding" or "aren't listed as findings")
  end
  return s .. "."
end

-- Quests taken in the guide the run stopped in and still in the log with no turn-in
-- step reached (RunLog.carried): the run ended before it could tell whether they're defects.
function report.carried_note(carried)
  if not carried or #carried == 0 then return nil end
  local quests = {}
  for i, c in ipairs(carried) do
    quests[i] = (c.qname and c.qname ~= "") and (text.with_part(c.qname, c.chain) .. " (" .. tostring(c.qid) .. ")")
      or text.quest_ref(c.qid)
  end
  return "Taken in the guide the run stopped in and still in the log, which that guide or the next may turn in "
    .. "after the run's end, so not findings: " .. plural(#carried, "quest") .. ": " .. ids(quests) .. "."
end

function report.rank_note(rank)
  if rank == nil then return nil end
  return "Guide rank: " .. tostring(rank) .. " (WoWPro's setting for which optional steps are shown)."
end

-- Patterns print on one line: a newline in a pattern must not break the sentence.
local function one_line(v) return (tostring(v):gsub("[\r\n]+", " ")) end

-- The --include / --exclude filters, in the order given (the last match wins).
function report.filters_note(filters)
  if not filters or #filters == 0 then return nil end
  local parts = {}
  for i, f in ipairs(filters) do parts[i] = "--" .. f.kind .. ' "' .. one_line(f.pattern) .. '"' end
  return "Filters: " .. table.concat(parts, ", ") .. "."
end

-- With filters, the guides the run actually played.
function report.played_note(played)
  if not played or #played == 0 then return nil end
  return "Guides played: " .. ids(played) .. "."
end

-- Guides an --include matched that no character reached.
function report.unreached_note(unreached)
  if not unreached or #unreached == 0 then return nil end
  return "Included but never reached: " .. ids(unreached) .. "."
end

-- Races a filtered matrix skipped because their chain reached no included guide.
function report.skipped_races_note(races)
  if not races or #races == 0 then return nil end
  return "Races that reached no included guide: " .. ids(races) .. "."
end

-- Counted findings whose quest data is incomplete in QuestieDB (no XP, level, name
-- or objective count) or that a heuristic raised (catalog Quest.confidence,
-- Driver:confidence); nil when there are none.
function report.unverified_note(findings)
  local n, unverified = 0, 0
  for _, f in ipairs(findings or {}) do
    if counted(f) then
      n = n + 1
      if f.confidence == "unverified" then unverified = unverified + 1 end
    end
  end
  if unverified == 0 then return nil end
  return "Unverified findings: " .. unverified .. " of " .. n .. ". Their quest's data is incomplete (no XP, "
    .. "level or name in QuestieDB, or an objective count assumed or guessed), or a heuristic raised them."
end

function report.notes(header, findings)
  return setmetatable({
    unverified = report.unverified_note(findings),
    filters = report.filters_note(header.filters),
    played = report.played_note(header.played),
    unreached = report.unreached_note(header.unreached),
    skipped_races = report.skipped_races_note(header.skipped_races),
    jumped = report.jumped_note(header.jumped),
    dungeons = report.dungeons_note(header.dungeons),
    carried = report.carried_note(header.carried),
    rank = report.rank_note(header.rank),
  }, OBJECT)
end

-- The folded sections' descriptions; the page puts the count in front.
report.FOLDS = {
  harness = "gaps in this client's WoW API stubs, arrival data or emulation, not guide bugs",
  expected = "the client clicked off by design (notes, repair-or-restock stops, guide ends)",
}

-- The guide map's level-flag rules (spec §4.4), for the flag tooltips.
report.FLAG_RULES = {
  ["enter-under"] = "Entered below the guide's start level",
  ["leave-under"] = "Left below the guide's end level",
  ["enter-over"] = "Entered above the guide's end level",
}

---------------------------------------------------------------------------
-- The document
---------------------------------------------------------------------------

-- Counted findings a primary finding explains: every counted finding reachable
-- through causes, cycle-guarded.
local function explains(f, by_id)
  local seen, stack, n = { [f.id] = true }, { f }, 0
  while #stack > 0 do
    local cur = table.remove(stack)
    for _, id in ipairs(cur.causes or {}) do
      local child = by_id[id]
      if child and not seen[id] then
        seen[id] = true
        if counted(child) then n = n + 1 end
        stack[#stack + 1] = child
      end
    end
  end
  return n
end

local function tally(map, key, f)
  local by_sev = map[key] or {}
  map[key] = by_sev
  local t = by_sev[f.severity] or { primary = 0, follow = 0 }
  by_sev[f.severity] = t
  if f.caused_by then t.follow = t.follow + 1 else t.primary = t.primary + 1 end
end

local function summarize(findings)
  local s = { findings = 0, roots = 0, by_severity = setmetatable({}, OBJECT), by_signal = setmetatable({}, OBJECT),
    by_file = setmetatable({}, OBJECT), by_combo = setmetatable({}, OBJECT) }
  for _, f in ipairs(findings) do
    if counted(f) then
      s.findings = s.findings + 1
      if not f.caused_by then s.roots = s.roots + 1 end
      s.by_severity[f.severity] = (s.by_severity[f.severity] or 0) + 1
      s.by_signal[f.signal] = (s.by_signal[f.signal] or 0) + 1
      -- A finding with no file has no file row; the totals above still count it.
      if f.file then tally(s.by_file, f.file, f) end
      for _, c in ipairs(f.combos or {}) do tally(s.by_combo, c, f) end
    end
  end
  return s
end

local function labels(header)
  local combos = setmetatable({}, OBJECT)
  for _, c in ipairs(((header or {}).matrix or {}).combos or {}) do combos[c] = text.character(c) end
  local severities = {}
  for sev, s in pairs(text.SEVERITY) do severities[sev] = s.word end
  return { signals = text.SIGNALS, actions = text.VERBS, combos = combos, stops = text.STOPS,
    severities = severities, folds = report.FOLDS, flags = report.FLAG_RULES }
end

local function finding_json(f, ctx)
  local copy = {}
  for k, v in pairs(f) do
    if type(v) == "table" and next(v) == nil then v = setmetatable({}, ARRAY) end
    copy[k] = v
  end
  copy.step = setmetatable({ action = f.action, name = f.name }, OBJECT)
  copy.title = text.title(f)
  copy.sentence = text.sentence(f, ctx)
  if not f.caused_by then copy.explains = explains(f, ctx.by_id) end
  return copy
end

-- The header is copied, not changed: gaps and warnings are added to the copy.
function report.build(findings, header)
  header = header or {}
  local ctx = report.context(findings, header)
  local out = setmetatable({}, ARRAY)
  for _, f in ipairs(findings) do out[#out + 1] = finding_json(f, ctx) end
  local h = {}
  for k, v in pairs(header) do h[k] = v end
  -- The run's own assumptions (header.assumptions, e.g. inferred starting reputation)
  -- follow the static gaps in a fresh list; report.GAPS is never changed.
  local gaps = {}
  for i, g in ipairs(report.GAPS) do gaps[i] = g end
  for _, g in ipairs(header.assumptions or {}) do gaps[#gaps + 1] = g end
  h.gaps = gaps
  h.assumptions = nil
  h.warnings = report.warnings(header)
  h.notes = report.notes(header, findings)
  return { format = report.FORMAT, header = h, labels = labels(header), summary = summarize(findings), findings = out }
end

return report
