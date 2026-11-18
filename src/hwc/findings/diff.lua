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
        r.spread[#r.spread + 1] = copy_with(ne.finding, ne.set,
          { added_for = sorted_list(added), fixed_for = array(sorted_list(gone)) })
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

local function names(combos)
  local out = {}
  for i, c in ipairs(combos) do out[i] = text.character(c) end
  return table.concat(out, ", ")
end

-- "main@aaaaaaa", "main@aaaaaaa (dirty)", or "2026.11.12.A (not a git folder)".
function diff.side_label(side)
  if side.git == false then
    return tostring(side.version) .. " (not a git folder)"
  end
  local label = tostring(side.branch) .. "@" .. tostring(side.commit):sub(1, 7)
  if side.dirty then label = label .. " (dirty)" end
  return label
end

-- Entries whose caused_by is another entry of the same list fold under their
-- root; the root shows how many descendants it carries.
local function roots_with_follow_ons(list)
  local ids, children = {}, {}
  for _, f in ipairs(list) do ids[f.id] = true end
  for _, f in ipairs(list) do
    if f.caused_by and ids[f.caused_by] then
      local kids = children[f.caused_by] or {}
      kids[#kids + 1] = f.id
      children[f.caused_by] = kids
    end
  end
  local function descendants(id, seen)
    local n = 0
    for _, kid in ipairs(children[id] or {}) do
      if not seen[kid] then
        seen[kid] = true
        n = n + 1 + descendants(kid, seen)
      end
    end
    return n
  end
  local out = {}
  for _, f in ipairs(list) do
    if not (f.caused_by and ids[f.caused_by]) then
      out[#out + 1] = { finding = f, follow_ons = descendants(f.id, { [f.id] = true }) }
    end
  end
  return out
end

local SECTIONS = {
  { key = "fixed", heading = "Fixed" },
  { key = "new", heading = "New" },
  { key = "partly_fixed", heading = "Partly fixed", extra = function(f)
    return "fixed: " .. names(f.fixed_for) .. " · still: " .. names(f.still)
  end },
  { key = "spread", heading = "Spread", extra = function(f)
    local e = "now also: " .. names(f.added_for)
    if f.fixed_for and #f.fixed_for > 0 then e = e .. " · fixed: " .. names(f.fixed_for) end
    return e
  end },
}

local function basename(path)
  return tostring(path):match("([^/]*)$")
end

function diff.render(result)
  local out = {}
  local function add(s) out[#out + 1] = s end
  local c = result.counts

  add("hwc diff: " .. diff.side_label(result.runs.old) .. " → " .. diff.side_label(result.runs.new))
  for _, w in ipairs(result.warnings) do add("warning: " .. w.message) end
  add("")

  if c.fixed + c.new + c.partly_fixed + c.spread == 0 then
    add(string.format("no changes (%d findings in both)", c.unchanged))
    return table.concat(out, "\n") .. "\n"
  end

  local line = string.format("fixed %d · new %d · partly fixed %d", c.fixed, c.new, c.partly_fixed)
  if c.spread > 0 then line = line .. " · spread " .. c.spread end
  add(line .. " · unchanged " .. c.unchanged)

  for _, section in ipairs(SECTIONS) do
    local list = result[section.key]
    if #list > 0 then
      add("")
      add(section.heading)
      for _, entry in ipairs(roots_with_follow_ons(list)) do
        local f = entry.finding
        local row = string.format("  %s %s  %s:%s", text.SEVERITY[f.severity].marker, f.title,
          basename(f.file), tostring(f.line))
        if entry.follow_ons > 0 then row = row .. string.format("  (+%d follow-on)", entry.follow_ons) end
        if section.extra then row = row .. "  " .. section.extra(f) end
        add(row)
      end
    end
  end
  return table.concat(out, "\n") .. "\n"
end

return diff
