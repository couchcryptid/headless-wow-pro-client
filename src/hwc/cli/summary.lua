-- The run summary printed on stdout before the wrote line (design §5.2), built
-- from a decoded findings document. Pure: no io or os.
local text = require("hwc.findings.text")
local report = require("hwc.findings.report")

local summary = {}

local HARNESS_NOTE = " (gaps in hwc's stubs, not guide bugs)"

local function plural(n, word, words)
  return n .. " " .. (n == 1 and word or (words or word .. "s"))
end

-- Severity names in text.SEVERITY rank order.
local function ranked_severities()
  local names = {}
  for name in pairs(text.SEVERITY) do names[#names + 1] = name end
  table.sort(names, function(a, b) return text.SEVERITY[a].rank < text.SEVERITY[b].rank end)
  return names
end

-- "  155 high · 6 medium-high", zeros left out; nil when every count is zero.
local function severity_line(by_severity)
  local parts = {}
  for _, name in ipairs(ranked_severities()) do
    local n = by_severity[name] or 0
    if n > 0 then parts[#parts + 1] = n .. " " .. name end
  end
  return #parts > 0 and ("  " .. table.concat(parts, " · ")) or nil
end

-- "  harness: 2 Lua errors, 36 missing globals (...)"; nil when there are none.
-- summary.* leaves harness findings out, so they are counted from the findings.
local function harness_line(findings)
  local errors, globals, gaps = 0, 0, 0
  for _, f in ipairs(findings or {}) do
    if report.is_harness(f) then
      if f.signal == "missing-global" then globals = globals + 1
      elseif f.signal == "arrival-data-gap" then gaps = gaps + 1
      else errors = errors + 1 end
    end
  end
  local parts = {}
  if errors > 0 then parts[#parts + 1] = plural(errors, "Lua error") end
  if globals > 0 then parts[#parts + 1] = plural(globals, "missing global") end
  if gaps > 0 then parts[#parts + 1] = plural(gaps, "arrival data gap") end
  return #parts > 0 and ("  harness: " .. table.concat(parts, ", ") .. HARNESS_NOTE) or nil
end

-- The summary's lines, without newlines. One character per run, so the label
-- is the run's only combo and header.stop has at most its one entry.
function summary.lines(doc)
  local header = doc.header or {}
  local s = doc.summary or {}
  local label = text.character(((header.matrix or {}).combos or {})[1] or "")
  local out = {}
  local n = s.findings or 0
  if n == 0 then
    out[1] = label .. ": no findings"
  else
    out[1] = string.format("%s: %s, %s", label, plural(n, "finding"), plural(s.roots or 0, "root cause"))
    out[#out + 1] = severity_line(s.by_severity or {})
  end
  local stop = (header.stop or {})[1]
  if stop then out[#out + 1] = "  stopped early: " .. (text.STOPS[stop.reason] or tostring(stop.reason)) end
  out[#out + 1] = harness_line(doc.findings)
  return out
end

return summary
