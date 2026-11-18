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
  -- Ruling AB: the Forever-added Camping 101 quests have no name in any catalog source.
  "Camping 101 quests are recognised only by name from the local supplement (no catalog source names them); without it, profession variants equal baselines",
  -- Ruling AC: kill vs talk-to is a heuristic (kills.objective_kills).
  "talk-to NPC objectives may be credited as kills",
  -- Catalog:quest_rewards: QuestieDB has no reward counts and no choice/fixed split.
  "quest rewards give one of each item QuestieDB lists, choice rewards included",
  -- Subzones (Anvilmar, Kharanos, ...) come only from R steps; IZ-gated class-training notes may stay hidden.
  "subzones are known only from R steps; steps gated on a subzone by IZ may stay hidden",
}

local NOT_REPRODUCIBLE = "uncommitted changes; this run may not be reproducible from its commit."
local SUPPLEMENT_NOTE = "Camping 101 quests aren't recognised, so profession variants match their baselines."

-- Harness notices are about the client's WoW API stubs, not guides: kept out of
-- every count and shown only in their own folded section.
function report.is_harness(f)
  return f.signal == "missing-global" or (f.signal == "lua-error" and f.harness == true)
end
local is_harness = report.is_harness

-- Counted findings feed every count; harness notices and expected manual
-- clicks sit in their own folds.
local function counted(f)
  return f.severity ~= nil and not f.expected and not is_harness(f)
end

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

local function plural(n, word, words)
  return n .. " " .. (n == 1 and word or (words or word .. "s"))
end

local function lowest(cur, f)
  if not cur or f.id < cur.id then return f end
  return cur
end

-- The context text.sentence needs.
-- by_qid mirrors group.lua link_roots: a refusal (accept-refused / log-full)
-- wins over a never-shown-accept, lowest id within each.
function report.context(findings, header)
  local by_id, refusal, hidden = {}, {}, {}
  for _, f in ipairs(findings) do
    by_id[f.id] = f
    if f.qid then
      if f.signal == "accept-refused" or f.signal == "log-full" then
        refusal[f.qid] = lowest(refusal[f.qid], f)
      elseif f.signal == "never-shown-accept" then
        hidden[f.qid] = lowest(hidden[f.qid], f)
      end
    end
  end
  local by_qid = {}
  for q, f in pairs(hidden) do by_qid[q] = f end
  for q, f in pairs(refusal) do by_qid[q] = f end

  local single
  local combos = header and header.matrix and header.matrix.combos
  if combos then
    local seen, n, only = {}, 0, nil
    for _, c in ipairs(combos) do
      if not seen[c] then seen[c] = true; n = n + 1; only = c end
    end
    if n == 1 then single = text.character(only) end
  end
  return { by_id = by_id, by_qid = by_qid, single = single }
end

---------------------------------------------------------------------------
-- Guide levels and level flags (design spec §4.4)
---------------------------------------------------------------------------

-- Rule order is the warning-line order.
local FLAG_RULES = {
  { rule = "enter-under", says = "entered under-levelled",
    fires = function(g, l) return l.enter and g.start_level and l.enter < g.start_level end },
  { rule = "leave-under", says = "left under-levelled",
    fires = function(g, l) return l.finished and l.leave and g.end_level and l.leave < g.end_level end },
  { rule = "enter-over", says = "entered over-levelled",
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

local function checkout_warnings(warn, header)
  local a = header.addon or {}
  if a.git ~= false and a.dirty == true then warn[#warn + 1] = "The WoW-Pro checkout had " .. NOT_REPRODUCIBLE end
  if (header.client or {}).dirty == true then warn[#warn + 1] = "The client checkout had " .. NOT_REPRODUCIBLE end
end

local function catalog_warnings(warn, catalog)
  for _, name in ipairs(sorted_keys(catalog or {})) do
    if catalog[name].present == false then
      local s = "Catalog source " .. name .. " was missing."
      if name == "supplement" then s = s .. " " .. SUPPLEMENT_NOTE end
      warn[#warn + 1] = s
    end
  end
end

local function unverified_warning(warn, findings)
  local n, unverified = 0, 0
  for _, f in ipairs(findings) do
    if counted(f) then
      n = n + 1
      if f.confidence == "unverified" then unverified = unverified + 1 end
    end
  end
  if unverified * 2 > n then
    warn[#warn + 1] = unverified .. " of " .. n .. " findings rest on quest data not checked against a second source."
  end
end

-- One line per rule that fires, counting guides (not characters).
local function level_warnings(warn, guides)
  for _, r in ipairs(FLAG_RULES) do
    local n = 0
    for _, g in ipairs(guides or {}) do
      for _, fl in ipairs(g.flags or {}) do
        if fl.rule == r.rule then n = n + 1; break end
      end
    end
    if n > 0 then warn[#warn + 1] = plural(n, "guide") .. " " .. r.says end
  end
end

function report.warnings(header, findings)
  local warn = setmetatable({}, ARRAY)
  checkout_warnings(warn, header)
  catalog_warnings(warn, header.catalog)
  unverified_warning(warn, findings)
  level_warnings(warn, header.guides)
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
    quests[i] = (c.qname and c.qname ~= "") and ('"' .. c.qname .. '" (' .. tostring(c.qid) .. ")")
      or ("quest " .. tostring(c.qid))
  end
  return "Taken in the guide the run stopped in and still in the log, which that guide or the next may turn in "
    .. "after the run's end, so not findings: " .. plural(#carried, "quest") .. ": " .. ids(quests) .. "."
end

function report.rank_note(rank)
  if rank == nil then return nil end
  return "Guide rank: " .. tostring(rank) .. " (WoWPro's setting for which optional steps are shown)."
end

function report.notes(header)
  return setmetatable({
    jumped = report.jumped_note(header.jumped),
    dungeons = report.dungeons_note(header.dungeons),
    carried = report.carried_note(header.carried),
    rank = report.rank_note(header.rank),
  }, OBJECT)
end

-- The folded sections' descriptions; the page puts the count in front.
report.FOLDS = {
  harness = "gaps in this client's WoW API stubs, not guide bugs",
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
  h.gaps = report.GAPS
  h.warnings = report.warnings(header, findings)
  h.notes = report.notes(header)
  return { format = report.FORMAT, header = h, labels = labels(header), summary = summarize(findings), findings = out }
end

return report
