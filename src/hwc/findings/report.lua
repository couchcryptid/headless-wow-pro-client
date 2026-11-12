-- Canonical findings JSON document (design spec §5). Pure: no I/O.
local text = require("hwc.findings.text")

local report = {}

report.FORMAT = 1

local ARRAY = { __jsontype = "array" }

-- Harness notices are about the client's WoW API stubs, not guides: kept out of
-- every count and shown only in their own folded section.
function report.is_harness(f)
  return f.signal == "missing-global" or (f.signal == "lua-error" and f.harness == true)
end
local is_harness = report.is_harness

local function lowest(cur, f)
  if not cur or f.id < cur.id then return f end
  return cur
end

-- The context text.sentence needs; the markdown renderer builds the same one.
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

function report.build(findings, header)
  local ctx = report.context(findings, header)
  local summary = { findings = 0, roots = 0, by_severity = {}, by_signal = {} }
  local out = setmetatable({}, ARRAY)
  for _, f in ipairs(findings) do
    local copy = {}
    for k, v in pairs(f) do
      if type(v) == "table" and next(v) == nil then v = setmetatable({}, ARRAY) end
      copy[k] = v
    end
    copy.title = text.title(f)
    copy.sentence = text.sentence(f, ctx)
    out[#out + 1] = copy
    if f.severity and not f.expected and not is_harness(f) then
      summary.findings = summary.findings + 1
      if not f.caused_by then summary.roots = summary.roots + 1 end
      summary.by_severity[f.severity] = (summary.by_severity[f.severity] or 0) + 1
      summary.by_signal[f.signal] = (summary.by_signal[f.signal] or 0) + 1
    end
  end
  return { format = report.FORMAT, header = header, summary = summary, findings = out }
end

return report
