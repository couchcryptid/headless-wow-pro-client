-- Compares two decoded findings documents (format 2) by finding id (design spec
-- findings-diff §4.2, §4.3, §4.5). Pure: no I/O; the CLI reads the files.
--
-- Only counted findings take part (not harness, not expected, severity present),
-- and only on the characters both runs share. The result lists what was fixed,
-- what is new, what was fixed for some characters only and what spread to more.
local report = require("hwc.findings.report")
local text = require("hwc.findings.text")
local json = require("hwc.json")

local diff = {}

local function array(t) return setmetatable(t, { __jsontype = "array" }) end

local function counted(f)
  return f.severity ~= nil and not f.expected and not report.is_harness(f)
end

local function set_of(list)
  local s = {}
  for _, v in ipairs(list or {}) do s[v] = true end
  return s
end

local function sorted_list(set)
  local l = {}
  for k in pairs(set) do l[#l + 1] = k end
  table.sort(l)
  return l
end

local function combos_of(doc)
  local m = doc.header and doc.header.matrix
  return m and m.combos or {}
end

-- A finding's combos cut to `shared`; a finding without combos is on every
-- character of its run, so on every shared one.
local function cut(f, own_combos, shared)
  local out = {}
  for _, c in ipairs(f.combos or own_combos) do
    if shared[c] then out[c] = true end
  end
  return out
end

-- id -> { finding, set } for the counted findings with a shared character left.
local function index(doc, shared)
  local own = combos_of(doc)
  local by_id = {}
  for _, f in ipairs(doc.findings or {}) do
    if counted(f) then
      local set = cut(f, own, shared)
      if next(set) then by_id[f.id] = { finding = f, set = set } end
    end
  end
  return by_id
end

local function copy_with(f, set, extra)
  local c = {}
  for k, v in pairs(f) do c[k] = v end
  c.combos = sorted_list(set)
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end

local function rank(f)
  local s = text.SEVERITY[f.severity]
  return s and s.rank or math.huge
end

local function before(a, b)
  if rank(a) ~= rank(b) then return rank(a) < rank(b) end
  if a.file ~= b.file then return tostring(a.file) < tostring(b.file) end
  if a.line ~= b.line then return (a.line or 0) < (b.line or 0) end
  return tostring(a.id) < tostring(b.id)
end

local function side(doc)
  local a = doc.header and doc.header.addon or {}
  return { branch = a.branch, commit = a.commit, dirty = a.dirty, git = a.git, version = a.version }
end

local function warnings_for(old, new, shared)
  local oh, nh = old.header or {}, new.header or {}
  local out = {}
  local function warn(code, args)
    out[#out + 1] = { code = code, message = text.DIFF_WARNINGS[code](args or {}) }
  end

  local oq = oh.catalog and oh.catalog.questie or {}
  local nq = nh.catalog and nh.catalog.questie or {}
  if oq.tag ~= nq.tag or oq.build ~= nq.build then
    warn("questie", { old_tag = oq.tag, old_build = oq.build, new_tag = nq.tag, new_build = nq.build })
  end

  local os_ = oh.catalog and oh.catalog.supplement or {}
  local ns = nh.catalog and nh.catalog.supplement or {}
  if (os_.present or false) ~= (ns.present or false) or os_.sha256 ~= ns.sha256 then warn("supplement") end

  if json.encode(oh.filters or {}) ~= json.encode(nh.filters or {}) then warn("filters") end

  for _, spec in ipairs({ { "OLD", combos_of(old) }, { "NEW", combos_of(new) } }) do
    local extras = {}
    for _, c in ipairs(spec[2]) do
      if not shared[c] then extras[#extras + 1] = c end
    end
    if #extras > 0 then warn("combos", { side = spec[1], combos = extras }) end
  end

  if oh.paths_relative_to ~= nh.paths_relative_to then
    warn("relative-to", { old = oh.paths_relative_to, new = nh.paths_relative_to })
  end

  local oc = oh.client and oh.client.commit
  local nc = nh.client and nh.client.commit
  if oc ~= nc then warn("client", { old = oc, new = nc }) end

  local oa, na = oh.addon or {}, nh.addon or {}
  if oa.commit ~= nil and oa.commit == na.commit and not oa.dirty and not na.dirty then
    warn("same-commit", { commit = oa.commit })
  end
  if oa.dirty then warn("dirty-old") end
  if na.dirty then warn("dirty-new") end
  return out
end

function diff.compare(old, new)
  if type(old) ~= "table" or type(new) ~= "table" or old.format ~= 2 or new.format ~= 2 then
    return nil, "not comparable: findings files must be format 2"
  end
  local in_new = set_of(combos_of(new))
  local shared_set, shared = {}, {}
  for _, c in ipairs(combos_of(old)) do
    if in_new[c] and not shared_set[c] then shared_set[c] = true; shared[#shared + 1] = c end
  end
  table.sort(shared)
  if #shared == 0 then return nil, "not comparable: no shared characters" end

  local o, n = index(old, shared_set), index(new, shared_set)
  local r = {
    runs = { old = side(old), new = side(new) },
    shared = shared,
    warnings = warnings_for(old, new, shared_set),
    fixed = {}, new = {}, partly_fixed = {}, spread = {},
    counts = { fixed = 0, new = 0, partly_fixed = 0, spread = 0, unchanged = 0 },
  }

  for id, oe in pairs(o) do
    local ne = n[id]
    if not ne then
      r.fixed[#r.fixed + 1] = copy_with(oe.finding, oe.set)
    else
      local gone, added = {}, {}
      for c in pairs(oe.set) do if not ne.set[c] then gone[c] = true end end
      for c in pairs(ne.set) do if not oe.set[c] then added[c] = true end end
      if next(added) then
        r.spread[#r.spread + 1] = copy_with(ne.finding, ne.set, { added_for = sorted_list(added) })
      elseif next(gone) then
        r.partly_fixed[#r.partly_fixed + 1] = copy_with(ne.finding, ne.set,
          { fixed_for = sorted_list(gone), still = sorted_list(ne.set) })
      else
        r.counts.unchanged = r.counts.unchanged + 1
      end
    end
  end
  for id, ne in pairs(n) do
    if not o[id] then r.new[#r.new + 1] = copy_with(ne.finding, ne.set) end
  end

  for _, key in ipairs({ "fixed", "new", "partly_fixed", "spread" }) do
    table.sort(r[key], before)
    r.counts[key] = #r[key]
    array(r[key])
  end
  array(r.shared); array(r.warnings)
  return r
end

function diff.exit_code(result)
  return (result.counts.new + result.counts.spread > 0) and 1 or 0
end

return diff
