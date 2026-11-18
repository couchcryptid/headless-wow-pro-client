-- hwc run (design §4.3): play one character along the guide chain, then write
-- its findings and run log (run_output.lua). Progress goes to stderr through
-- ui; the summary (summary.lua) and the wrote line go to stdout.
local Player = require("hwc.world.player")
local professions = require("hwc.world.professions")

local function races()
  local out = {}
  for name in pairs(Player.RACES) do out[#out + 1] = name end
  table.sort(out)
  return out
end

-- Every class token any race can play, sorted.
local function classes()
  local seen, out = {}, {}
  for _, r in pairs(Player.RACES) do
    for _, c in ipairs(r.classes) do
      if not seen[c] then seen[c] = true; out[#out + 1] = c end
    end
  end
  table.sort(out)
  return out
end

-- The date names the output files: anything but YYYY-MM-DD (e.g. ../x) would
-- change the write path.
local function valid_date(v)
  if v:match("^%d%d%d%d%-%d%d%-%d%d$") then return v end
  return nil, "--date needs YYYY-MM-DD"
end

local decl = {
  name = "run",
  summary = "Play one character along the guide chain; write findings and its run log",
  usage = "--race RACE --class CLASS [--professions LIST] [options]",
  description = "Play one character along the guide chain; write findings and its run log.\n"
    .. "Run it from a WoW-Pro folder (the one holding WoWPro/WoWPro.toc) or below it.",
  needs_folder = true,
  options = {
    { name = "race", metavar = "RACE", required = true, choices = races, help = "Player race.",
      see = "hwc list races" },
    { name = "class", metavar = "CLASS", required = true, choices = classes, help = "Player class.",
      see = "hwc list classes RACE" },
    { name = "professions", metavar = "LIST", validate = professions.parse, default_text = "none",
      help = "What the character knows from the start, e.g. herbalism,skinning.", see = "hwc list professions" },
    { name = "include", metavar = "PATTERN", filter = true, help = "Glob on guide paths; repeatable, last match wins." },
    { name = "exclude", metavar = "PATTERN", filter = true, help = "Glob on guide paths; repeatable, last match wins." },
    { name = "date", metavar = "D", validate = valid_date, default_text = "today", help = "Findings date, YYYY-MM-DD." },
    { name = "out", metavar = "DIR", default_text = "~/.hwc/findings", help = "Findings directory." },
    { name = "relative-to", metavar = "DIR", default_text = "current directory",
      help = "Every path in the output is written relative to DIR." },
  },
  notes = {
    "--professions takes at most two primary professions. Cooking can't be named:\n"
      .. "every character learns it from the guide (Camping 101: Cooking).",
    'See README "Choosing guides" for the filter rules.',
    "Example: hwc run --race Dwarf --class WARRIOR --professions herbalism,skinning",
  },
  check = function(opts)
    if not Player.can_play(opts.race, opts.class) then
      return string.format("%s can't be a %s in Forever; %s classes: %s", opts.race, opts.class, opts.race,
        table.concat(Player.classes_for(opts.race), ", "))
    end
  end,
}

local function strip(msg) return (tostring(msg):gsub("^hwc: ", "")) end

-- Resolves opts.filters against the WoW-Pro folder and selects the guides they
-- keep. Returns nil when no filter is given, the selection { filters, guides
-- (the TOC's), included ({ [gid] = true }) }, or false and a usage message for a
-- bad pattern, an --include matching no guide, or no guide left. Raises (exit 1)
-- when the Leveling TOC cannot be read.
local function select_guides(opts, root, start)
  if #opts.filters == 0 then return nil end
  local filters = require("hwc.filters")
  local list = {}
  for i, f in ipairs(opts.filters) do
    local pattern, rerr = filters.resolve(f.raw, root, start)
    if not pattern then return false, strip(rerr) end
    f.pattern = pattern
    list[i] = { kind = f.kind, pattern = pattern, raw = f.raw }
  end
  local guides = require("hwc.driver.guide_source").toc_guides(root)
  local files, seen = {}, {}
  for _, g in ipairs(guides) do
    if not seen[g.rel] then seen[g.rel] = true; files[#files + 1] = g.rel end
  end
  local set, unmatched = filters.select(files, list)
  if #unmatched > 0 then
    local msgs = {}
    for i, raw in ipairs(unmatched) do msgs[i] = '--include "' .. raw .. '" matches no guide' end
    return false, table.concat(msgs, "; ")
  end
  local included, any = {}, false
  for _, g in ipairs(guides) do
    if set[g.rel] then included[g.gid] = true; any = true end
  end
  if not any then return false, "no guide left after filters" end
  return { filters = opts.filters, guides = guides, included = included }
end

local function clock_text(seconds)
  seconds = math.max(0, math.floor(seconds))
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function guide_name(file) return (tostring(file):match("([^/]+)$") or ""):gsub("%.lua$", "") end

-- Turns driver progress events into ui:progress lines and jump details, and
-- keeps each guide's start time for the verbose timings.
local function new_progress(ui, label, clock)
  local p = { started = clock(), level = Player.START_LEVEL, guides = {} }
  local function line(now)
    local g = p.guides[#p.guides]
    if not g then return end
    ui:progress(string.format("%s · %s (guide %d) · level %d · %s", label, g.name, g.index, p.level,
      clock_text(now - p.started)))
  end
  function p.event(e)
    local now = clock()
    if e.kind == "guide" then
      p.guides[#p.guides + 1] = { name = guide_name(e.file), index = e.index, started = now }
    elseif e.kind == "level" then
      p.level = e.level
    elseif e.kind == "jump" then
      ui:detail("jumped over " .. table.concat(e.passed or {}, ", ") .. " (excluded)"
        .. (e.to == nil and "; no included guide follows" or ""))
      return
    end
    line(now)
  end
  -- The run's wall time, then each guide's: the time until the next guide opened.
  function p.timings()
    local now = clock()
    local out = { "wall time: " .. clock_text(now - p.started) .. " total" }
    for i, g in ipairs(p.guides) do
      local finished = p.guides[i + 1] and p.guides[i + 1].started or now
      out[#out + 1] = string.format("wall time: %s %s (guide %d)", clock_text(finished - g.started), g.name, g.index)
    end
    return out
  end
  return p
end

-- Plays the character and writes its findings. Returns the exit status, or nil
-- and a usage message.
local function play(ctx)
  local opts, ui = ctx.opts, ctx.ui
  local config = require("hwc.config")
  local text = require("hwc.findings.text")
  local selection, serr = select_guides(opts, ctx.root, ctx.start)
  if selection == false then return nil, serr end
  local list = opts.professions or {}
  -- Read before anything is played or written: a missing template must not leave
  -- a .json (or run log) with no .html beside it.
  local template = require("hwc.findings.html").template()
  local cfg = config.load({
    addon_path = ctx.root, race = opts.race, class = opts.class,
    professions = professions.skills(list),
    -- Resolved once, so the run reads one QuestieDB version throughout.
    catalog = { questie_dir = config.default_questie_dir() },
  })
  ui:detail("catalog questie: " .. tostring(cfg.catalog.questie_dir or "none"))
  ui:detail("catalog supplement: " .. tostring(cfg.catalog.supplement))
  local label = text.character(string.format("%s %s %s", opts.race, opts.class, professions.token(list)))
  local progress = new_progress(ui, label, ctx.env.clock)
  local log = require("hwc.driver.run").character(cfg, {
    included = selection and selection.included, on_progress = progress.event,
  })
  if selection and #(log.guides or {}) == 0 then
    ui:done()
    return nil, label .. " reaches no included guide"
  end
  local name = opts.race .. "-" .. opts.class .. (professions.stem(list) and ("-" .. professions.stem(list)) or "")
  local stem, rep = require("hwc.cli.run_output").write({
    log = log, scope = selection and (name .. "-filtered") or name, file_name = name,
    date = opts.date or os.date("%Y-%m-%d"), outdir = opts.out or (ctx.env.home .. "/.hwc/findings"),
    start = ctx.start, relative_to = opts["relative-to"], template = template, selection = selection,
  })
  ui:done()
  for _, w in ipairs(rep.header.warnings or {}) do ui:warn(w) end
  for _, t in ipairs(progress.timings()) do ui:detail(t) end
  if ui.level ~= "quiet" then
    local lines = require("hwc.cli.summary").lines(rep)
    if #lines > 0 then ui:result(table.concat(lines, "\n") .. "\n") end
  end
  ui:result(require("hwc.cli").wrote_line(stem))
  return 0
end

function decl.run(ctx)
  local usage_error = require("hwc.cli.commands").usage_error
  -- --out defaults under $HOME: without one, say so rather than fail on a nil path.
  if not ctx.opts.out and not (ctx.env.home and ctx.env.home ~= "") then
    return usage_error(ctx.ui, "HOME is not set; pass --out DIR", "run")
  end
  local ok, code, uerr = pcall(play, ctx)
  -- A progress line must not stay on the terminal under an error.
  ctx.ui:done()
  if not ok then error(code, 0) end
  if code == nil then return usage_error(ctx.ui, uerr, "run") end
  return code
end

return decl
