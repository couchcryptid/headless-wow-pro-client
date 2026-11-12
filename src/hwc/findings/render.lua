-- Canonical findings markdown (design spec §7.2). This layout is a contract the
-- /triage skill reads; keep it grep-friendly and stable.
--
--   # Findings: <scope>
--   - Date / Scope / Addon / Catalog / Client / Matrix / Rank: one "- Key: value" line each
--   - Gaps: a "- Gaps:" line followed by "  - <gap>" lines
--   ## Summary          two tables: per signal, per severity (sorted)
--   ## Findings
--   ### F-xxxxxxxx      one section per finding (sorted file, line, signal, id)
--   - Severity: / Signal: / Location: / Step: / Quest: / Why: / Combos: /
--     Before: / After: / Level: / Quest log: / Confidence: / Caused by: /
--     Causes: / Reasons:      (always present, "none" when empty)
--   Triage:             an empty block, exactly one line, for /triage to fill
--   ## Expected manual completions
--   - F-xxxxxxxx file:line action name (combos)   (no severity, no Triage block)
--
-- Lines end in "\n"; the output ends with exactly one trailing newline.
local render = {}

render.GAPS = {
  "rested XP",
  "Forever Boosted Rest from campfires",
  "party XP for non-elites (spec §5.5)",
  "dungeon runs and instance XP (spec §3)",
}

local SEVERITY_ORDER = { "high", "medium-high", "medium", "low" }

local function one_line(s)
  return (tostring(s):gsub("[\r\n]+", " "))
end

local function join(list)
  if not list or #list == 0 then return "none" end
  return table.concat(list, ", ")
end

local function yes_no(b)
  if b == nil then return "unknown" end
  return b and "dirty" or "clean"
end

local function catalog_lines(sources, out)
  local names = {}
  for name in pairs(sources or {}) do names[#names + 1] = name end
  table.sort(names)
  if #names == 0 then
    out[#out + 1] = "- Catalog: none"
    return
  end
  out[#out + 1] = "- Catalog:"
  for _, name in ipairs(names) do
    local s = sources[name]
    local parts = { "present=" .. tostring(s.present) }
    if s.commit then parts[#parts + 1] = "commit=" .. s.commit end
    if s.sha256 then parts[#parts + 1] = "sha256=" .. s.sha256 end
    if s.path then parts[#parts + 1] = "path=" .. s.path end
    out[#out + 1] = string.format("  - %s: %s", name, table.concat(parts, " "))
  end
end

local function location(f)
  if not f.file then return "none" end
  return f.file .. (f.line and (":" .. f.line) or "")
end

local function step_text(f)
  if not f.action and not f.name then return "none" end
  return one_line(((f.action or "") .. " " .. (f.name or "")):gsub("^ ", ""))
end

local function neighbour(n)
  return n and n.name and one_line(n.name) or "none"
end

local function quest_log(log)
  if not log then return "none" end
  local ids = {}
  for i, q in ipairs(log) do ids[i] = tostring(q) end
  return #ids == 0 and "empty" or table.concat(ids, ", ")
end

local function confidence(f)
  if f.confidence == "unverified" then return "unverified quest data" end
  return f.confidence or "n/a"
end

local function finding_lines(f, out)
  out[#out + 1] = "### " .. f.id
  out[#out + 1] = ""
  out[#out + 1] = "- Severity: " .. f.severity
  out[#out + 1] = "- Signal: " .. f.signal .. (f.harness and " (harness)" or "")
  out[#out + 1] = "- Location: " .. location(f)
  out[#out + 1] = "- Step: " .. step_text(f)
  out[#out + 1] = "- Quest: " .. tostring(f.qid or "none")
  out[#out + 1] = "- Why: " .. (f.why and one_line(f.why) or "none")
  out[#out + 1] = "- Combos: " .. join(f.combos)
  out[#out + 1] = "- Before: " .. neighbour(f.before)
  out[#out + 1] = "- After: " .. neighbour(f.after)
  out[#out + 1] = "- Level: " .. tostring(f.level or "n/a")
  out[#out + 1] = "- Quest log: " .. quest_log(f.log)
  out[#out + 1] = "- Confidence: " .. confidence(f)
  out[#out + 1] = "- Caused by: " .. (f.caused_by or "none")
  out[#out + 1] = "- Causes: " .. join(f.causes)
  out[#out + 1] = "- Reasons: " .. join(f.reasons)
  out[#out + 1] = ""
  out[#out + 1] = "Triage:"
  out[#out + 1] = ""
end

local function table_lines(title, rows, out)
  out[#out + 1] = "| " .. title .. " | Count |"
  out[#out + 1] = "|---|---|"
  for _, r in ipairs(rows) do out[#out + 1] = string.format("| %s | %d |", r[1], r[2]) end
  out[#out + 1] = ""
end

function render.markdown(findings, header)
  header = header or {}
  local out = {}
  out[#out + 1] = "# Findings: " .. one_line(header.scope or "unnamed")
  out[#out + 1] = ""
  out[#out + 1] = "- Date: " .. tostring(header.date or "unknown")
  out[#out + 1] = "- Scope: " .. one_line(header.scope or "unnamed")
  local a = header.addon or {}
  out[#out + 1] = string.format("- Addon: %s (branch %s, commit %s, %s)", tostring(a.path), tostring(a.branch),
    tostring(a.commit), yes_no(a.dirty))
  catalog_lines(header.catalog, out)
  out[#out + 1] = "- Client: " .. tostring((header.client or {}).commit or "unknown")
  local combos = {}
  local seen = {}
  for _, c in ipairs((header.matrix or {}).combos or {}) do
    if not seen[c] then seen[c] = true; combos[#combos + 1] = c end
  end
  table.sort(combos)
  out[#out + 1] = "- Matrix: " .. join(combos)
  out[#out + 1] = "- Rank: " .. tostring(header.rank or 2)
  out[#out + 1] = "- Gaps:"
  for _, g in ipairs(header.gaps or render.GAPS) do out[#out + 1] = "  - " .. g end
  out[#out + 1] = ""

  local main, expected = {}, {}
  local by_signal, by_sev = {}, {}
  for _, f in ipairs(findings) do
    if f.expected then
      expected[#expected + 1] = f
    else
      main[#main + 1] = f
      by_signal[f.signal] = (by_signal[f.signal] or 0) + 1
      by_sev[f.severity] = (by_sev[f.severity] or 0) + 1
    end
  end

  out[#out + 1] = "## Summary"
  out[#out + 1] = ""
  local rows = {}
  for sig, n in pairs(by_signal) do rows[#rows + 1] = { sig, n } end
  table.sort(rows, function(x, y) return x[1] < y[1] end)
  table_lines("Signal", rows, out)
  rows = {}
  for _, sev in ipairs(SEVERITY_ORDER) do
    if by_sev[sev] then rows[#rows + 1] = { sev, by_sev[sev] } end
  end
  table_lines("Severity", rows, out)

  out[#out + 1] = "## Findings"
  out[#out + 1] = ""
  if #main == 0 then out[#out + 1] = "None."; out[#out + 1] = "" end
  for _, f in ipairs(main) do finding_lines(f, out) end

  out[#out + 1] = "## Expected manual completions"
  out[#out + 1] = ""
  if #expected == 0 then out[#out + 1] = "None." end
  for _, f in ipairs(expected) do
    out[#out + 1] = string.format("- %s %s %s (%s)", f.id, location(f), step_text(f), join(f.combos))
  end

  return table.concat(out, "\n"):gsub("\n+$", "") .. "\n"
end

return render
