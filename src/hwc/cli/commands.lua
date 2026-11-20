-- Every command's declaration, in the order the top-level usage lists them
-- (design §4). A declaration is { name, summary, usage, description, options,
-- positionals, notes, check, hidden, passthrough, needs_folder, run(ctx) }; see
-- args.lua and help.lua for the fields they read.
local commands = {}

-- Command name -> module under hwc.cli, where the two differ. The stubs share
-- one module.
local MODULE = { help = "help_cmd", boot = "stubs", matrix = "stubs", sync = "stubs" }

local ORDER = { "init", "doctor", "update", "run", "diff", "quest", "arrivals", "list", "version", "help", "boot", "matrix", "sync" }

local function load(name)
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
