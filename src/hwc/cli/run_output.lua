-- Writes one `hwc run`'s findings: DIR/<date>-<scope>-<hash>.json and .html,
-- and the run log under DIR/<date>-<scope>-<hash>/. Every path in the output is
-- rewritten relative to --relative-to (default: the logical start folder, so a
-- symlinked $PWD such as Interface/AddOns stays the base its paths are named from).
local output = {}

local function mkdirs(path)
  local lfs = require("lfs")
  local cur = path:sub(1, 1) == "/" and "" or nil
  for part in path:gmatch("[^/]+") do
    cur = cur and (cur .. "/" .. part) or part
    if lfs.attributes(cur, "mode") == nil then assert(lfs.mkdir(cur)) end
  end
end

local function write_file(path, text)
  local f = assert(io.open(path, "wb"))
  f:write(text)
  f:close()
end

-- The report JSON carries the addon identity through addon_info.json_view.
local function report_json(rep)
  local a = rep.header and rep.header.addon
  if a then rep.header.addon = require("hwc.addon_info").json_view(a) end
  return rep
end

-- Distinct passed gids across the log's jumps, first-seen order; nil when none.
-- Only jumps that land on an included guide count: guides passed after the last
-- included one (to == nil) end the run, so no finding can follow from skipping them.
local function jumped_gids(log)
  local seen, out = {}, {}
  for _, j in ipairs(log.jumps or {}) do
    if j.to ~= nil then
      for _, gid in ipairs(j.passed or {}) do
        if not seen[gid] then seen[gid] = true; out[#out + 1] = gid end
      end
    end
  end
  return #out > 0 and out or nil
end

-- Included guides an --include matched that the log never played, in TOC order
-- (controller Ruling 1). nil when no --include was given or every one was reached.
local function unreached_gids(sel, log)
  local includes = {}
  for _, f in ipairs(sel.filters) do
    if f.kind == "include" then includes[#includes + 1] = require("hwc.filters").compile(f.pattern) end
  end
  if #includes == 0 then return nil end
  local played = {}
  for _, gid in ipairs(log.guides or {}) do played[gid] = true end
  local seen, out = {}, {}
  for _, g in ipairs(sel.guides) do
    if sel.included[g.gid] and not played[g.gid] and not seen[g.gid] then
      for _, match in ipairs(includes) do
        if match(g.rel) then seen[g.gid] = true; out[#out + 1] = g.gid; break end
      end
    end
  end
  return #out > 0 and out or nil
end

-- Distinct gids the log played, first-seen order; nil when none.
local function played_gids(log)
  local seen, out = {}, {}
  for _, gid in ipairs(log.guides or {}) do
    if not seen[gid] then seen[gid] = true; out[#out + 1] = gid end
  end
  return #out > 0 and out or nil
end

-- Quests carried past the end of the run, once each, by id; nil when none.
local function carried_quests(log)
  local carried, by_qid = {}, {}
  for _, c in ipairs(log.carried or {}) do
    if not by_qid[c.qid] then by_qid[c.qid] = true; carried[#carried + 1] = c end
  end
  table.sort(carried, function(a, b) return a.qid < b.qid end)
  return #carried > 0 and carried or nil
end

-- Distinct dungeon guide lines Skip Dungeon Quests skipped.
local function dungeon_skips(log)
  local seen, n = {}, 0
  for _, d in ipairs(log.dungeon_skips or {}) do
    local k = tostring(d.file) .. ":" .. tostring(d.line)
    if not seen[k] then seen[k] = true; n = n + 1 end
  end
  return n
end

-- Roots the output paths are rewritten from: the base, the WoW-Pro folder and
-- each catalog source, in name order.
local function path_roots(base, log)
  local roots = { base }
  if log.addon and log.addon.path then roots[#roots + 1] = log.addon.path end
  local sources = (log.catalog or {}).sources or {}
  local names = {}
  for name in pairs(sources) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    if sources[name].path then roots[#roots + 1] = sources[name].path end
  end
  return roots
end

-- run = { log, scope, date, outdir, start, relative_to, template, file_name,
-- selection = { filters, guides, included } or nil }. Writes the files and
-- returns the stem and the report table (header.warnings included).
function output.write(run)
  local paths = require("hwc.paths")
  local group = require("hwc.findings.group")
  local report = require("hwc.findings.report")
  local json = require("hwc.json")
  local raw, sel = run.log, run.selection
  local cwd = run.start or paths.cwd()
  local base = paths.resolve(run.relative_to or cwd, cwd)
  local roots = path_roots(base, raw)
  local log = paths.rewrite(raw, roots, base, cwd)
  local label = group.combo(raw)
  local client = require("hwc.addon_info").read(require("hwc.config").repo_root(), { tracked_only = true })
  local filters
  if sel then
    filters = {}
    for i, f in ipairs(sel.filters) do filters[i] = { kind = f.kind, pattern = f.pattern } end
  end
  local reason = raw.stop and raw.stop.reason
  -- The header reads the raw log: it is rewritten once, below.
  local header = {
    scope = run.scope, date = run.date, addon = raw.addon, catalog = (raw.catalog or {}).sources,
    client = { commit = client.commit, dirty = client.dirty },
    matrix = { combos = { label } }, rank = raw.rank,
    carried = carried_quests(raw),
    dungeons = raw.skip_dungeons ~= nil and { skip = raw.skip_dungeons, skipped = dungeon_skips(raw) } or nil,
    filters = filters,
    played = filters and played_gids(log) or nil,
    jumped = jumped_gids(log),
    unreached = sel and unreached_gids(sel, log) or nil,
    guides = report.guides({ { combo = label, guide_levels = log.guide_levels or {} } }),
    stop = reason and reason ~= "no-next-guide" and { { combo = label, reason = reason } } or nil,
  }
  header = paths.rewrite(header, roots, base, cwd)
  header.paths_relative_to = base:match("([^/]+)$") or "/"
  local rep = report_json(report.build(group.findings({ log }), header))
  local doc = json.encode(rep, { indent = true }) .. "\n"
  -- The hash is of the findings, so it names the run log too: two runs whose
  -- findings differ never overwrite each other.
  local stem = run.outdir .. "/" .. require("hwc.cli").stem_name(run.date, run.scope, doc)
  mkdirs(stem)
  write_file(stem .. "/" .. run.file_name .. ".json", json.encode(log, { indent = true }) .. "\n")
  write_file(stem .. ".json", doc)
  write_file(stem .. ".html", require("hwc.findings.html").render(doc, run.template))
  return stem, rep
end

return output
