-- Groups the signals of many RunLogs into findings (design spec §7.2): one
-- finding per suspected defect across all characters, with a stable id, a
-- severity, the affected race/class combos and root-cause links.
--
-- Grouping key: gid \0 action \0 name \0 (qid or "") \0 (ordinal or "") \0 signal.
-- The ordinal (Ruling AA) is the step's source ordinal: the n-th line of the guide
-- file with that action, name and quest id, counted over every line whoever loads
-- it (guide_source.line_in), so two distinct lines such as two `F Stormwind` steps
-- are two findings, the same line read by different classes is one, and a guide
-- edit that only moves lines keeps the id. lua-error and missing-global group on
-- the message / global name instead (a harness lua-error apart from an addon one).
-- The id is FNV-1a 32 over that key. Everything is sorted before it is returned,
-- so the result does not depend on RunLog order (determinism).
local bit = require("bit")

local group = {}

-- 32-bit FNV-1a as 8 lowercase hex. The multiply by the prime 16777619
-- (2^24 + 403) is done as a shift plus a small product to stay exact in doubles.
function group.fnv1a32(s)
  local h = 0x811c9dc5
  for i = 1, #s do
    h = bit.bxor(h, s:byte(i)) % 4294967296
    h = (bit.lshift(h, 24) % 4294967296 + h * 403) % 4294967296
  end
  return bit.tohex(h, 8)
end

-- Severities (spec §7.2): every §7.1 signal is named; an unknown signal raises instead
-- of silently defaulting. Dungeon accepts WoWPro's Skip Dungeon Quests completes are
-- run info (RunLog.dungeon_skips), not signals, so they have no entry here.
local SEVERITY = {
  ["never-shown-accept"] = "high", ["hidden-use-step"] = "high", ["orphan-turnin"] = "high", ["accept-refused"] = "high",
  ["wrong-race-class"] = "high", ["log-full"] = "high",
  ["lua-error"] = "high", ["below-level"] = "medium-high",
  ["did-not-advance"] = "medium", stuck = "medium", ["manual-completion"] = "medium",
  ["rep-faction-unmet"] = "medium",
  ["leftover-quests"] = "low", ["missing-global"] = "low",
}
local SEVERITY_ORDER = { "high", "medium-high", "medium", "low" }
local SEVERITY_RANK = {}
for i, s in ipairs(SEVERITY_ORDER) do SEVERITY_RANK[s] = i end
local REFUSALS = { ["accept-refused"] = true, ["log-full"] = true }
local FOLLOWS_REFUSAL = { ["orphan-turnin"] = true, ["did-not-advance"] = true, ["leftover-quests"] = true }

local professions = require("hwc.world.professions")

function group.combo(log)
  local c = log.character or {}
  -- Sorted so the same set of professions is always the same combo.
  local names = {}
  for i, n in ipairs(c.professions or {}) do names[i] = n end
  table.sort(names)
  return string.format("%s %s %s", tostring(c.race), tostring(c.class), professions.token(names))
end

-- Second sort key when two RunLogs share a combo: their professions, joined.
local function profs(log)
  return table.concat((log.character or {}).professions or {}, ",")
end

local function key_of(s)
  if s.signal == "lua-error" then
    return table.concat({ "lua-error", s.reason == "harness" and "harness" or "addon", tostring(s.message) }, "\0")
  elseif s.signal == "missing-global" then
    return table.concat({ "missing-global", tostring(s.global) }, "\0")
  end
  local sig = s.signal
  if sig == "manual-completion" and s.expected then sig = sig .. ":expected" end
  return table.concat({ tostring(s.gid or ""), tostring(s.action or ""), tostring(s.name or ""),
    tostring(s.qid or ""), tostring(s.ordinal or ""), sig }, "\0")
end

local function new_finding(s, key)
  local f = {
    id = "F-" .. group.fnv1a32(key), signal = s.signal, file = s.file, line = s.line, gid = s.gid,
    action = s.action, name = s.name, qid = s.qid, why = s.why, before = s.before, after = s.after,
    qname = s.qname, grind = s.grind, use = s.use, loot = s.loot, level = s.level, log = s.log, confidence = s.confidence, rep = s.rep,
    faction = s.faction, faction_name = s.faction_name, combos = {}, causes = {}, reasons = {},
  }
  if s.signal == "lua-error" then
    f.name, f.message, f.stack = s.message, s.message, s.stack
    f.harness = s.reason == "harness" or nil
  elseif s.signal == "missing-global" then
    f.name = s.global
  elseif s.signal == "manual-completion" and s.expected then
    f.expected = true
  end
  if not f.expected then
    f.severity = SEVERITY[s.signal] or error("findings: unknown signal " .. tostring(s.signal))
  end
  return f
end

local function sorted_unique(set)
  local out = {}
  for v in pairs(set) do out[#out + 1] = v end
  table.sort(out)
  return out
end

-- Sorted list of the distinct ids, lowest id first for a stable pick.
local function pick(list)
  local best
  for _, f in ipairs(list or {}) do
    if not best or f.id < best.id then best = f end
  end
  return best
end

local function link(child, parent, by_id)
  if child.caused_by or child == parent then return end
  -- Refuse a cycle: child must not already be an ancestor of parent.
  local a = parent
  while a do
    if a == child then return end
    a = a.caused_by and by_id[a.caused_by]
  end
  child.caused_by = parent.id
  parent.causes[#parent.causes + 1] = child.id
end

local function has(list, v)
  for _, x in ipairs(list or {}) do if x == v then return true end end
  return false
end

-- Root-cause links (child.caused_by = parent.id, parent.causes lists children):
--   * a follow-on of a refused quest (orphan turn-in, did-not-advance, leftover) -> the refusal;
--   * an incomplete turn-in -> a hidden-use-step for the same quest in the same guide
--     (WoWPro hides the U step until its L items are in bags, so the quest never completes);
--   * a never-shown-accept -> what blocks its unmet prerequisite N, in order of
--     preference: a refusal of N, a hidden-use-step of N, an incomplete turn-in of N,
--     a never-shown-accept of N.
-- Lowest id breaks ties; a link that would close a cycle is refused.
local function link_roots(findings)
  local by_id = {}
  for _, f in ipairs(findings) do by_id[f.id] = f end
  local refusals, hidden, on_line = {}, {}, {}
  local hidden_use, incomplete_turnin = {}, {}
  local function at(f) return tostring(f.file) .. "\0" .. tostring(f.line) .. "\0" .. tostring(f.qid) end
  for _, f in ipairs(findings) do
    if f.qid and REFUSALS[f.signal] then refusals[f.qid] = refusals[f.qid] or {}; table.insert(refusals[f.qid], f) end
    if f.qid and f.signal == "never-shown-accept" then hidden[f.qid] = hidden[f.qid] or {}; table.insert(hidden[f.qid], f) end
    if f.qid and f.signal == "hidden-use-step" then hidden_use[f.qid] = hidden_use[f.qid] or {}; table.insert(hidden_use[f.qid], f) end
    if f.qid and f.signal == "did-not-advance" and f.action == "T" and has(f.reasons, "incomplete") then
      incomplete_turnin[f.qid] = incomplete_turnin[f.qid] or {}; table.insert(incomplete_turnin[f.qid], f)
    end
    if f.qid and f.line and f.signal ~= "leftover-quests" then
      on_line[at(f)] = on_line[at(f)] or {}
      table.insert(on_line[at(f)], f)
    end
  end
  for _, f in ipairs(findings) do
    if f.qid and FOLLOWS_REFUSAL[f.signal] then
      -- The parent on the follow-on's own line first: a quest refused on two lines
      -- has two refusals, and each follow-on belongs to its own.
      local here, refused_here = on_line[at(f)] or {}, {}
      for _, g in ipairs(here) do if REFUSALS[g.signal] then refused_here[#refused_here + 1] = g end end
      -- A leftover quest sits on the turn-in step the run passed (driver.run leftovers):
      -- whatever went wrong on that step is why the quest is still in the log.
      local same_guide_use = {}
      if f.signal == "did-not-advance" and f.action == "T" and has(f.reasons, "incomplete") then
        for _, u in ipairs(hidden_use[f.qid] or {}) do
          if u.gid == f.gid then same_guide_use[#same_guide_use + 1] = u end
        end
      end
      local r = pick(same_guide_use) or pick(refused_here) or (f.signal == "leftover-quests" and pick(here)) or pick(refusals[f.qid])
      if r then link(f, r, by_id) end
    elseif f.signal == "never-shown-accept" and f.why then
      -- The engine's only format (WoWPro_Broker.lua:2292):
      -- "NextStep:PRE&(%s): A mandatory prereq was not met: %s". Only the id after
      -- "not met:" counts; a why without that phrase links nothing.
      local n = tonumber(f.why:match("not met:%s*(%d+)"))
      local target = n and (pick(refusals[n]) or pick(hidden_use[n]) or pick(incomplete_turnin[n]) or pick(hidden[n]))
      if target and target ~= f then link(f, target, by_id) end
    end
  end
end

function group.findings(runlogs)
  local groups, order = {}, {}
  for _, log in ipairs(runlogs) do
    local c = group.combo(log)
    for i, s in ipairs(log.signals or {}) do
      local key = key_of(s)
      local g = groups[key]
      if not g then
        g = { key = key, entries = {} }
        groups[key] = g
        order[#order + 1] = g
      end
      g.entries[#g.entries + 1] = { combo = c, profs = profs(log), idx = i, sig = s }
    end
  end
  local findings = {}
  for _, g in ipairs(order) do
    table.sort(g.entries, function(a, b)
      if a.combo ~= b.combo then return a.combo < b.combo end
      if a.profs ~= b.profs then return a.profs < b.profs end
      if a.idx ~= b.idx then return a.idx < b.idx end
      return tostring(a.sig.why) < tostring(b.sig.why)
    end)
    local f = new_finding(g.entries[1].sig, g.key)
    local combos, reasons = {}, {}
    for _, e in ipairs(g.entries) do
      combos[e.combo] = true
      if e.sig.reason and not (e.sig.signal == "lua-error" and e.sig.reason == "harness") then
        reasons[e.sig.reason] = true
      end
    end
    f.combos, f.reasons = sorted_unique(combos), sorted_unique(reasons)
    findings[#findings + 1] = f
  end
  table.sort(findings, function(a, b) return a.id < b.id end)
  link_roots(findings)
  for _, f in ipairs(findings) do table.sort(f.causes) end
  -- Final review minor 1: severity rank (high first), then file with file-less
  -- findings last, line, signal, id. Ids are unique, so this is a total order.
  -- Expected manual completions carry no severity and sort after low.
  table.sort(findings, function(a, b)
    local ra, rb = SEVERITY_RANK[a.severity] or #SEVERITY_ORDER + 1, SEVERITY_RANK[b.severity] or #SEVERITY_ORDER + 1
    if ra ~= rb then return ra < rb end
    if (a.file == nil) ~= (b.file == nil) then return b.file == nil end
    if (a.file or "") ~= (b.file or "") then return (a.file or "") < (b.file or "") end
    if (a.line or 0) ~= (b.line or 0) then return (a.line or 0) < (b.line or 0) end
    if a.signal ~= b.signal then return a.signal < b.signal end
    return a.id < b.id
  end)
  return findings
end

return group
