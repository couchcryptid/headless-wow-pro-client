-- Every command's declaration, in the order the top-level usage lists them
-- (design §4). A declaration is { name, summary, usage, description, options,
-- positionals, notes, check, hidden, passthrough, needs_folder, run(ctx) }; see
-- args.lua and help.lua for the fields they read.
local commands = {}

-- Command name -> module under hwc.cli, where the two differ. The stubs share
-- one module; run is declared below until its own module lands.
local MODULE = { help = "help_cmd", boot = "stubs", matrix = "stubs", sync = "stubs" }

local ORDER = { "init", "doctor", "update", "run", "diff", "quest", "list", "version", "help", "boot", "matrix", "sync" }

-- Temporary: run still goes through cli.lua's legacy path, which takes these
-- options. This declaration only gives it a usage line and help.
local RUN = {
  name = "run",
  summary = "Play one character along the guide chain; write findings and its run log",
  usage = "--class CLASS [--race RACE] [--variant V] [options]",
  description = "Play one character along the guide chain; write findings and its run log.\n"
    .. "Run it from a WoW-Pro folder (the one holding WoWPro/WoWPro.toc) or below it.",
  options = {
    { name = "class", metavar = "CLASS", required = true, help = "Player class token, e.g. WARRIOR." },
    { name = "race", metavar = "RACE", default_text = "Dwarf", help = "Player race.", see = "hwc list races" },
    { name = "variant", metavar = "V", default_text = "baseline",
      help = "Profession variant: baseline, secondary, alch-herb, bs-mining, lw-skin, eng-ench, tailoring." },
    { name = "include", metavar = "PATTERN", help = "Glob on guide paths; repeatable, last match wins." },
    { name = "exclude", metavar = "PATTERN", help = "Glob on guide paths; repeatable, last match wins." },
    { name = "date", metavar = "D", default_text = "today", help = "Findings date, YYYY-MM-DD." },
    { name = "out", metavar = "DIR", default_text = "~/.hwc/findings", help = "Findings directory." },
    { name = "relative-to", metavar = "DIR", default_text = "current directory",
      help = "Every path in the output is written relative to DIR." },
  },
  notes = { 'See README "Choosing guides" for the filter rules.' },
}

local function load(name)
  if name == "run" then return RUN end
  local mod = require("hwc.cli." .. (MODULE[name] or name))
  return MODULE[name] == "stubs" and mod[name] or mod
end

commands.list = {}
for i, name in ipairs(ORDER) do commands.list[i] = load(name) end

-- The declaration named `name`, hidden ones included; nil when there is none.
function commands.find(name)
  for _, d in ipairs(commands.list) do
    if d.name == name then return d end
  end
end

-- Usage error output: the message, then where to read more. Returns exit 2.
function commands.usage_error(ui, msg, name)
  ui:error(msg)
  ui.err:write("see hwc " .. (name and (name .. " ") or "") .. "--help\n")
  return 2
end

-- "unknown command: hwc rnu (did you mean run?)"; suggestions come only from
-- visible commands, so a stub is never offered. Returns exit 2.
function commands.unknown(ui, name)
  local names = {}
  for _, d in ipairs(commands.list) do
    if not d.hidden then names[#names + 1] = d.name end
  end
  local near = require("hwc.cli.args").suggest(name, names)
  local msg = "unknown command: hwc " .. name .. (near and (" (did you mean " .. near .. "?)") or "")
  return commands.usage_error(ui, msg)
end

return commands
