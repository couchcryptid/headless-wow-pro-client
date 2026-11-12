-- Groups the signals of many RunLogs into findings (design spec §7.2): one
-- finding per suspected defect across all characters, with a stable id, a
-- severity, the affected race/class combos and root-cause links.
--
-- Grouping key: gid \0 action \0 name \0 (qid or "") \0 signal. lua-error and
-- missing-global group on the message / global name instead (a harness lua-error
-- apart from an addon one). The id is FNV-1a 32 over that key, so it survives a
-- guide edit that only moves the line. Everything is sorted before it is
-- returned, so the result does not depend on RunLog order (determinism).
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

group.DUNGEON_ROOT = {
  signal = "engine-dungeon-skip", severity = "high", name = "EnableDungeons auto-completes DUNGEON accepts",
  file = "WoWPro/WoWPro_Broker.lua", line = 2588,
}

-- Severities (spec §7.2): every §7.1 signal plus engine-dungeon-skip is named; an
-- unknown signal raises instead of silently defaulting.
local SEVERITY = {
  ["never-shown-accept"] = "high", ["orphan-turnin"] = "high", ["accept-refused"] = "high",
  ["wrong-race-class"] = "high", ["log-full"] = "high", ["engine-dungeon-skip"] = "high",
  ["lua-error"] = "high", ["below-level"] = "medium-high",
  ["did-not-advance"] = "medium", stuck = "medium", ["manual-completion"] = "medium",
  ["leftover-quests"] = "low", ["missing-global"] = "low",
}
local REFUSALS = { ["accept-refused"] = true, ["log-full"] = true }
local FOLLOWS_REFUSAL = { ["orphan-turnin"] = true, ["did-not-advance"] = true, ["leftover-quests"] = true }

local function combo(log)
  local c = log.character or {}
  return string.format("%s %s %s", tostring(c.race), tostring(c.class), log.variant or "baseline")
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
    tostring(s.qid or ""), sig }, "\0")
end

local function new_finding(s, key)
  local f = {
    id = "F-" .. group.fnv1a32(key), signal = s.signal, file = s.file, line = s.line, gid = s.gid,
    action = s.action, name = s.name, qid = s.qid, why = s.why, before = s.before, after = s.after,
    level = s.level, log = s.log, confidence = s.confidence, combos = {}, causes = {}, reasons = {},
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

local function link_roots(findings)
  local by_id = {}
  for _, f in ipairs(findings) do by_id[f.id] = f end
  local refusals, hidden = {}, {}
  for _, f in ipairs(findings) do
    if f.qid and REFUSALS[f.signal] then refusals[f.qid] = refusals[f.qid] or {}; table.insert(refusals[f.qid], f) end
    if f.qid and f.signal == "never-shown-accept" then hidden[f.qid] = hidden[f.qid] or {}; table.insert(hidden[f.qid], f) end
  end
  local root
  for _, f in ipairs(findings) do
    if f.signal == "never-shown-accept" then
      for _, r in ipairs(f.reasons) do
        if r == "engine-dungeon-skip" then
          if not root then
            root = {}
            for k, v in pairs(group.DUNGEON_ROOT) do root[k] = v end
            root.id = "F-" .. group.fnv1a32("engine-dungeon-skip")
            root.combos, root.causes, root.reasons = {}, {}, {}
          end
          by_id[root.id] = root
          link(f, root, by_id)
          break
        end
      end
    end
  end
  for _, f in ipairs(findings) do
    if f.qid and FOLLOWS_REFUSAL[f.signal] then
      local r = pick(refusals[f.qid])
      if r then link(f, r, by_id) end
    elseif f.signal == "never-shown-accept" and f.why then
      -- The engine's only format (WoWPro_Broker.lua:2292):
      -- "NextStep:PRE&(%s): A mandatory prereq was not met: %s". Only the id after
      -- "not met:" counts; a why without that phrase links nothing.
      local n = tonumber(f.why:match("not met:%s*(%d+)"))
      local target = n and (pick(refusals[n]) or pick(hidden[n]))
      if target and target ~= f then link(f, target, by_id) end
    end
  end
  if root then
    local seen = {}
    for _, f in ipairs(findings) do
      if f.caused_by == root.id then
        for _, c in ipairs(f.combos) do seen[c] = true end
      end
    end
    root.combos = sorted_unique(seen)
    findings[#findings + 1] = root
  end
end

function group.findings(runlogs)
  local groups, order = {}, {}
  for _, log in ipairs(runlogs) do
    local c = combo(log)
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
  table.sort(findings, function(a, b)
    if (a.file or "") ~= (b.file or "") then return (a.file or "") < (b.file or "") end
    if (a.line or 0) ~= (b.line or 0) then return (a.line or 0) < (b.line or 0) end
    if a.signal ~= b.signal then return a.signal < b.signal end
    return a.id < b.id
  end)
  return findings
end

return group
