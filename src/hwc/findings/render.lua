-- Human-first findings markdown (design spec §4.1–§4.9). Pure: no I/O.
--
-- Page order (§4.1):
--   # <characters>: N findings, M follow from others   title, then the run line
--   > - warning                                         only when one applies (§4.3)
--   ## Start here                                       top 5 primary findings (§4.4)
--   ## At a glance                                      severity and file tables (§4.5)
--   ## Guide files / ## Addon code                      findings by file, line order (§4.6)
--   ## Harness notices / ## Expected manual clicks      folded (§4.9)
--   ## About this run                                   provenance and gaps (§4.9)
--
-- Every finding outside the folds ends in exactly one "Triage: _pending_" line,
-- the slot /triage fills in place. Harness notices and expected manual clicks
-- are left out of every count and section above the folds. Wording comes from
-- text.lua; this module only lays it out. Every list is sorted by a total order.
local text = require("hwc.findings.text")
local report = require("hwc.findings.report")

local render = {}

render.GAPS = {
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

local SEVERITY_ORDER = { "high", "medium-high", "medium", "low" }
local GUIDE_PREFIX = "WoWPro_Leveling/"
local START_HERE_MAX = 5
local NOT_REPRODUCIBLE = "uncommitted changes; this run may not be reproducible from its commit."
local SUPPLEMENT_NOTE = "Camping 101 quests aren't recognised, so profession variants match their baselines."

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function one_line(s)
  return (tostring(s):gsub("[\r\n]+", " "))
end

-- Inline code that can't be broken by its content: one line, backticks -> '.
local function code(s)
  return "`" .. one_line(s):gsub("`", "'") .. "`"
end

local function plural(n, word, words)
  return n .. " " .. (n == 1 and word or (words or word .. "s"))
end

local function basename(path)
  return (path:match("([^/]+)$") or path)
end

local function is_guide(file)
  return file ~= nil and file:sub(1, #GUIDE_PREFIX) == GUIDE_PREFIX
end

-- Guide files are named by basename (their directory is in the file heading);
-- addon files keep their short repo path, where the basename alone is ambiguous.
local function location(f)
  if not f.file then return nil end
  local where = is_guide(f.file) and basename(f.file) or f.file
  if f.line then where = where .. ":" .. f.line end
  return where
end

local function counted(f)
  return f.severity ~= nil and not f.expected and not report.is_harness(f)
end

-- A title as markdown: one line, escaped for headings and link text.
local function title_of(f) return text.md_text(one_line(text.title(f))) end

local function link(f) return "[" .. title_of(f) .. "](#" .. text.anchor(f.id) .. ")" end

-- A detached checkout reports its branch as "HEAD"; say what that means.
local function branch_label(branch)
  if branch == "HEAD" then return "detached" end
  return "branch " .. code(branch)
end

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

local function distinct_sorted(list)
  local seen, out = {}, {}
  for _, v in ipairs(list or {}) do
    if not seen[v] then seen[v] = true; out[#out + 1] = v end
  end
  table.sort(out)
  return out
end

-- Matrix combos as display labels, sorted after mapping.
local function characters(combos)
  local out = {}
  for i, c in ipairs(combos) do out[i] = text.character(c) end
  return distinct_sorted(out)
end

local function file_anchor(file)
  if not file then return "file-without-a-file" end
  return "file-" .. file:lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
end

local function file_heading(file)
  return file and basename(file) or "Without a file"
end

-- Findings this root explains: every counted finding reachable through causes,
-- cycle-guarded.
local function descendants(f, by_id)
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

-- Order within a file (§4.6): line (line-less last), then signal, then id.
local function by_line(a, b)
  if (a.line == nil) ~= (b.line == nil) then return b.line == nil end
  if (a.line or 0) ~= (b.line or 0) then return (a.line or 0) < (b.line or 0) end
  if a.signal ~= b.signal then return a.signal < b.signal end
  return a.id < b.id
end

local function by_file(a, b)
  if (a == false) ~= (b == false) then return b == false end
  if a == false then return false end
  return a < b
end

local function file_then_line(a, b)
  if a.file ~= b.file then return by_file(a.file or false, b.file or false) end
  return by_line(a, b)
end

---------------------------------------------------------------------------
-- Sections
---------------------------------------------------------------------------

-- The title counts follow-on findings (those with caused_by) rather than
-- claiming "root causes": a finding with no caused_by link is only primary.
local function title_lines(out, header, combos, n_findings, n_follow)
  local label
  if #combos == 1 then
    label = text.character(combos[1])
  elseif #combos > 1 then
    local races = {}
    for i, c in ipairs(combos) do races[i] = (text.character(c):gsub(" %b()$", ""):match("^(.*) %S+$") or c) end
    label = #combos .. " characters (" .. table.concat(distinct_sorted(races), ", ") .. ")"
  else
    label = "Findings"
  end
  if n_findings == 0 then
    out[#out + 1] = "# " .. label .. ": no findings"
  else
    local s = "# " .. label .. ": " .. plural(n_findings, "finding")
    if n_follow > 0 then
      s = s .. ", " .. n_follow .. (n_follow == 1 and " follows" or " follow") .. " from others"
    end
    out[#out + 1] = s
  end
  out[#out + 1] = ""

  local parts = {}
  if header.date then parts[#parts + 1] = one_line(header.date) end
  local a = header.addon or {}
  if a.branch or a.commit then
    local s = "WoW-Pro"
    if a.branch then s = s .. " " .. (a.branch == "HEAD" and "detached" or code(a.branch)) end
    if a.commit then s = s .. " @ " .. code(tostring(a.commit):sub(1, 7)) end
    parts[#parts + 1] = s
  end
  if #combos > 0 then parts[#parts + 1] = plural(#combos, "character") end
  if header.scope then parts[#parts + 1] = code(header.scope) end
  if #parts > 0 then
    out[#out + 1] = table.concat(parts, " · ")
    out[#out + 1] = ""
  end
end

local function warning_lines(out, header, main)
  local warn = {}
  if (header.addon or {}).dirty == true then warn[#warn + 1] = "The WoW-Pro checkout had " .. NOT_REPRODUCIBLE end
  if (header.client or {}).dirty == true then warn[#warn + 1] = "The client checkout had " .. NOT_REPRODUCIBLE end
  local catalog = header.catalog or {}
  for _, name in ipairs(sorted_keys(catalog)) do
    if catalog[name].present == false then
      local s = "Catalog source " .. code(name) .. " was missing."
      if name == "supplement" then s = s .. " " .. SUPPLEMENT_NOTE end
      warn[#warn + 1] = s
    end
  end
  local unverified = 0
  for _, f in ipairs(main) do if f.confidence == "unverified" then unverified = unverified + 1 end end
  if unverified * 2 > #main then
    warn[#warn + 1] = unverified .. " of " .. #main
      .. " findings rest on quest data not checked against a second source."
  end
  if #warn == 0 then return end
  for _, w in ipairs(warn) do out[#out + 1] = "> - " .. w end
  out[#out + 1] = ""
end

local function start_here_lines(out, main, by_id)
  out[#out + 1] = "## Start here"
  out[#out + 1] = ""
  if #main == 0 then
    out[#out + 1] = "Nothing found."
    out[#out + 1] = ""
    return
  end
  local roots = {}
  for _, f in ipairs(main) do
    if not f.caused_by then roots[#roots + 1] = { f = f, n = descendants(f, by_id) } end
  end
  table.sort(roots, function(x, y)
    local a, b = x.f, y.f
    local ra, rb = text.SEVERITY[a.severity].rank, text.SEVERITY[b.severity].rank
    if ra ~= rb then return ra < rb end
    if x.n ~= y.n then return x.n > y.n end
    if (a.file == nil) ~= (b.file == nil) then return b.file == nil end
    if (a.file or "") ~= (b.file or "") then return (a.file or "") < (b.file or "") end
    if (a.line or 0) ~= (b.line or 0) then return (a.line or 0) < (b.line or 0) end
    return a.id < b.id
  end)
  out[#out + 1] = "These findings have the most other findings following from them. Fixing one may also clear those."
  out[#out + 1] = ""
  for i = 1, math.min(START_HERE_MAX, #roots) do
    local f, n = roots[i].f, roots[i].n
    local s = string.format("%d. %s %s", i, text.SEVERITY[f.severity].marker, link(f))
    local tail = {}
    if n > 0 then tail[#tail + 1] = "explains " .. n .. " more" end
    local where = location(f)
    if where then tail[#tail + 1] = code(where) end
    if #tail > 0 then s = s .. ": " .. table.concat(tail, " · ") end
    out[#out + 1] = s
  end
  out[#out + 1] = ""
end

local function cell(n) return n > 0 and tostring(n) or "" end

local function row(cells) return "| " .. table.concat(cells, " | ") .. " |" end

local function glance_lines(out, main, sections)
  out[#out + 1] = "## At a glance"
  out[#out + 1] = ""
  local roots, follow = {}, {}
  for _, f in ipairs(main) do
    local t = f.caused_by and follow or roots
    t[f.severity] = (t[f.severity] or 0) + 1
  end
  out[#out + 1] = "| | Primary | Follow-on | Total |"
  out[#out + 1] = "|---|---|---|---|"
  for _, sev in ipairs(SEVERITY_ORDER) do
    local r, fo = roots[sev] or 0, follow[sev] or 0
    if r + fo > 0 then
      local s = text.SEVERITY[sev]
      out[#out + 1] = row({ s.marker .. " " .. s.word, cell(r), cell(fo), cell(r + fo) })
    end
  end
  out[#out + 1] = ""

  local head = { "File" }
  for _, sev in ipairs(SEVERITY_ORDER) do head[#head + 1] = text.SEVERITY[sev].marker .. " " .. text.SEVERITY[sev].word end
  out[#out + 1] = row(head)
  out[#out + 1] = "|---|---|---|---|---|"
  for _, section in ipairs(sections) do
    for _, group in ipairs(section.files) do
      local n = {}
      for _, f in ipairs(group.findings) do n[f.severity] = (n[f.severity] or 0) + 1 end
      local cells = { "[" .. file_heading(group.file or nil) .. "](#" .. file_anchor(group.file or nil) .. ")" }
      for _, sev in ipairs(SEVERITY_ORDER) do cells[#cells + 1] = cell(n[sev] or 0) end
      out[#out + 1] = row(cells)
    end
  end
  out[#out + 1] = ""
end

local function engine_fold(out, f, matrix)
  out[#out + 1] = "<details><summary>Engine detail · " .. f.id .. "</summary>"
  out[#out + 1] = ""
  out[#out + 1] = "- Signal: " .. code(f.signal)
  if f.why and f.why ~= "" then out[#out + 1] = "- Engine said: " .. code(f.why) end
  local reasons = distinct_sorted(f.reasons)
  if #reasons > 0 then
    local list = {}
    for i, r in ipairs(reasons) do list[i] = code(r) end
    out[#out + 1] = (#list == 1 and "- Reason: " or "- Reasons: ") .. table.concat(list, ", ")
  end
  if f.log and #f.log > 0 then
    local ids = {}
    for i, q in ipairs(f.log) do ids[i] = tostring(q) end
    out[#out + 1] = "- Quest log: " .. table.concat(ids, ", ")
  end
  if #matrix > 1 and f.combos and #f.combos > 0 then
    local _, dropped = text.combos(f.combos, matrix)
    if dropped then out[#out + 1] = "- All characters: " .. table.concat(characters(f.combos), ", ") end
  end
  if f.signal == "lua-error" then
    if f.message then out[#out + 1] = "- Message: " .. code(f.message) end
    if f.stack then out[#out + 1] = "- Stack: " .. code(f.stack) end
  end
  out[#out + 1] = "</details>"
  out[#out + 1] = ""
end

local function meta_line(f)
  local parts = { text.SEVERITY[f.severity].word }
  if f.line then parts[#parts + 1] = "line " .. f.line end
  if f.qid then parts[#parts + 1] = "quest " .. f.qid end
  -- A below-level signal fires after the grind, so its level is the grind's
  -- target, not where the guide reached the accept: the sentence says it.
  if f.level and f.signal ~= "below-level" then parts[#parts + 1] = "level " .. f.level end
  if f.confidence == "unverified" then parts[#parts + 1] = "unverified quest data" end
  return table.concat(parts, " · ")
end

local function neighbour(n)
  return n and n.name and n.name ~= "" and one_line(text.step(n.action, n.name)) or nil
end

local function finding_lines(out, f, ctx, matrix)
  out[#out + 1] = string.format('#### %s %s <a id="%s"></a>', text.SEVERITY[f.severity].marker, title_of(f),
    text.anchor(f.id))
  out[#out + 1] = meta_line(f)
  out[#out + 1] = ""
  local sentence = text.sentence(f, ctx)
  if sentence ~= "" then
    out[#out + 1] = one_line(sentence)
    out[#out + 1] = ""
  end

  -- Follow-on findings are compact: the sentence already names the parent.
  if not f.caused_by then
    local bullets = {}
    local before, after = neighbour(f.before), neighbour(f.after)
    if before or after then
      local steps = {}
      if before then steps[#steps + 1] = before end
      steps[#steps + 1] = "*this step*"
      if after then steps[#steps + 1] = after end
      bullets[#bullets + 1] = "- **Between steps:** " .. table.concat(steps, " → ")
    end
    -- Direct children in reading order (file, line), so the list follows the guide.
    local kids = {}
    for _, id in ipairs(distinct_sorted(f.causes)) do
      if ctx.by_id[id] then kids[#kids + 1] = ctx.by_id[id] end
    end
    table.sort(kids, file_then_line)
    local children = text.links(kids)
    if #children > 0 then bullets[#bullets + 1] = "- **Also blocks:** " .. table.concat(children, ", ") end
    if #matrix > 1 and f.combos and #f.combos > 0 then
      bullets[#bullets + 1] = "- **Affects:** " .. (text.combos(f.combos, matrix))
    end
    if f.grind and f.grind.kills and f.grind.to then
      bullets[#bullets + 1] = "- **Ground:** " .. f.grind.kills .. " kills to reach level " .. f.grind.to
    end
    if #bullets > 0 then
      for _, b in ipairs(bullets) do out[#out + 1] = b end
      out[#out + 1] = ""
    end
  end

  engine_fold(out, f, matrix)
  out[#out + 1] = "Triage: _pending_"
  out[#out + 1] = ""
end

-- Guide files, then addon code; files by path (file-less last), findings by line.
local function file_sections(main)
  local sections = {
    { title = "Guide files", by = {}, files = {} },
    { title = "Addon code", by = {}, files = {} },
  }
  for _, f in ipairs(main) do
    local s = is_guide(f.file) and sections[1] or sections[2]
    local key = f.file or false
    if not s.by[key] then
      s.by[key] = { file = key, findings = {} }
      s.files[#s.files + 1] = s.by[key]
    end
    table.insert(s.by[key].findings, f)
  end
  local out = {}
  for _, s in ipairs(sections) do
    table.sort(s.files, function(a, b) return by_file(a.file, b.file) end)
    for _, g in ipairs(s.files) do table.sort(g.findings, by_line) end
    if #s.files > 0 then out[#out + 1] = s end
  end
  return out
end

local function findings_lines(out, sections, ctx, matrix)
  for _, s in ipairs(sections) do
    out[#out + 1] = "## " .. s.title
    out[#out + 1] = ""
    for _, g in ipairs(s.files) do
      local file = g.file or nil
      out[#out + 1] = string.format('### %s <a id="%s"></a>', file_heading(file), file_anchor(file))
      if file then out[#out + 1] = code(file) end
      out[#out + 1] = ""
      for _, f in ipairs(g.findings) do finding_lines(out, f, ctx, matrix) end
    end
  end
end

local function harness_lines(out, harness)
  if #harness == 0 then return end
  local globals, errors = {}, {}
  for _, f in ipairs(harness) do
    local t = f.signal == "missing-global" and globals or errors
    t[#t + 1] = f
  end
  local function by_name(a, b)
    local x, y = tostring(a.name or a.message or ""), tostring(b.name or b.message or "")
    if x ~= y then return x < y end
    return a.id < b.id
  end
  table.sort(globals, by_name)
  table.sort(errors, by_name)
  out[#out + 1] = "## Harness notices"
  out[#out + 1] = ""
  local counts = {}
  if #globals > 0 then counts[#counts + 1] = plural(#globals, "missing global") end
  if #errors > 0 then counts[#counts + 1] = plural(#errors, "harness error") end
  out[#out + 1] = "<details><summary>" .. table.concat(counts, " and ")
    .. ": gaps in this client's WoW API stubs, not guide bugs</summary>"
  out[#out + 1] = ""
  for _, f in ipairs(globals) do out[#out + 1] = "- " .. code(f.name or "") .. " · " .. f.id end
  for _, f in ipairs(errors) do
    out[#out + 1] = "- " .. code((tostring(f.message or f.name or "")):match("^[^\n]*")) .. " · " .. f.id
  end
  out[#out + 1] = "</details>"
  out[#out + 1] = ""
end

local function expected_lines(out, expected)
  if #expected == 0 then return end
  table.sort(expected, file_then_line)
  out[#out + 1] = "## Expected manual clicks"
  out[#out + 1] = ""
  out[#out + 1] = "<details><summary>" .. plural(#expected, "step") .. " the client clicked off by design "
    .. "(notes, repair-or-restock stops, guide ends)</summary>"
  out[#out + 1] = ""
  for _, f in ipairs(expected) do
    local parts = {}
    local where = location(f)
    if where then parts[#parts + 1] = code(where) end
    local step = text.step(f.action, f.name)
    if step then parts[#parts + 1] = one_line(step) end
    out[#out + 1] = "- " .. table.concat(parts, " ") .. " · " .. f.id
  end
  out[#out + 1] = "</details>"
  out[#out + 1] = ""
end

local function state(dirty)
  if dirty == true then return "uncommitted changes" end
  if dirty == false then return "clean" end
  return nil
end

local function catalog_lines(out, catalog)
  local names = sorted_keys(catalog or {})
  if #names == 0 then return end
  out[#out + 1] = "- Catalog:"
  for _, name in ipairs(names) do
    local s = catalog[name]
    local parts = { s.present == false and "missing" or "present" }
    if s.commit then parts[#parts + 1] = "commit " .. code(s.commit) end
    if type(s.sha256) == "string" then parts[#parts + 1] = "sha256 " .. code(s.sha256:sub(1, 12)) end
    if s.path then parts[#parts + 1] = code(s.path) end
    out[#out + 1] = "  - " .. code(name) .. ": " .. table.concat(parts, " · ")
    if type(s.sha256) == "table" then
      -- the questie source hashes several files: one per line, sorted by name
      for _, file in ipairs(sorted_keys(s.sha256)) do
        out[#out + 1] = "    - " .. code(file) .. " " .. code(tostring(s.sha256[file]):sub(1, 12))
      end
    end
  end
end

local function about_lines(out, header, combos)
  out[#out + 1] = "## About this run"
  out[#out + 1] = ""
  local a = header.addon
  if a then
    local parts = {}
    if a.path then parts[#parts + 1] = code(a.path) end
    if a.branch then parts[#parts + 1] = branch_label(a.branch) end
    if a.commit then parts[#parts + 1] = "commit " .. code(a.commit) end
    parts[#parts + 1] = state(a.dirty)
    if #parts > 0 then out[#out + 1] = "- WoW-Pro: " .. table.concat(parts, " · ") end
  end
  local c = header.client
  if c then
    local parts = {}
    if c.branch then parts[#parts + 1] = branch_label(c.branch) end
    if c.commit then parts[#parts + 1] = "commit " .. code(c.commit) end
    parts[#parts + 1] = state(c.dirty)
    if #parts > 0 then out[#out + 1] = "- Client: " .. table.concat(parts, " · ") end
  end
  if #combos > 0 then out[#out + 1] = "- Characters: " .. table.concat(characters(combos), ", ") end
  if header.rank then
    out[#out + 1] = "- Guide rank: " .. code(header.rank) .. " (WoWPro's setting for which optional steps are shown)"
  end
  catalog_lines(out, header.catalog)
  out[#out + 1] = "- What the simulation doesn't model:"
  for _, g in ipairs(header.gaps or render.GAPS) do out[#out + 1] = "  - " .. one_line(g) end
  if header.paths_relative_to then
    out[#out + 1] = "- Paths relative to: " .. code(header.paths_relative_to)
  end
  out[#out + 1] = ""
end

function render.markdown(findings, header)
  header = header or {}
  local ctx = report.context(findings, header)
  local combos = distinct_sorted((header.matrix or {}).combos)

  local main, harness, expected = {}, {}, {}
  local n_follow = 0
  for _, f in ipairs(findings) do
    if report.is_harness(f) then
      harness[#harness + 1] = f
    elseif counted(f) then
      main[#main + 1] = f
      if f.caused_by then n_follow = n_follow + 1 end
    else
      expected[#expected + 1] = f
    end
  end

  local out = {}
  title_lines(out, header, combos, #main, n_follow)
  warning_lines(out, header, main)
  start_here_lines(out, main, ctx.by_id)
  if #main > 0 then
    local sections = file_sections(main)
    glance_lines(out, main, sections)
    findings_lines(out, sections, ctx, combos)
  end
  harness_lines(out, harness)
  expected_lines(out, expected)
  about_lines(out, header, combos)

  return (table.concat(out, "\n"):gsub("\n+$", "")) .. "\n"
end

return render
