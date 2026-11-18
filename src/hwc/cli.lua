-- Command line entry point. Requirable: main(args, out, err, env) returns an
-- exit status; bin/hwc performs the exit. Each command is a declaration plus a
-- handler (src/hwc/cli/commands.lua).

local M = {}

-- hwc run's closing line: the two files it wrote.
function M.wrote_line(stem)
  return "hwc: wrote " .. stem .. ".html and " .. stem .. ".json\n"
end

-- A findings file's stem: date, scope, then the hash of the findings JSON text.
function M.stem_name(date, scope, doc)
  return date .. "-" .. scope .. "-" .. require("hwc.findings.group").fnv1a32(doc)
end

local function strip(msg) return (tostring(msg):gsub("^hwc: ", "")) end

-- The WoW-Pro folder hwc runs in: root and start, or nil and a usage message.
local function locate(env)
  local source = require("hwc.source")
  local start = source.start_dir({ pwd = env.pwd, cwd = env.cwd })
  local root, ferr = source.find(start)
  if not root then return nil, nil, strip(ferr) end
  return root, start
end

-- Parses rest against decl, finds the WoW-Pro folder when the command needs
-- one, then runs the handler. A Lua error escaping the handler exits 1.
local function dispatch(decl, rest, u, env)
  local commands = require("hwc.cli.commands")
  local ctx = { ui = u, env = env }
  if decl.passthrough then
    ctx.opts = { positionals = rest, filters = {} }
  else
    local opts, perr = require("hwc.cli.args").parse(decl, rest)
    if not opts then return commands.usage_error(u, perr, decl.name) end
    ctx.opts = opts
  end
  if decl.needs_folder then
    local root, start, ferr = locate(env)
    if not root then return commands.usage_error(u, ferr, decl.name) end
    ctx.root, ctx.start = root, start
  end
  local ok, res = pcall(decl.run, ctx)
  if not ok then
    u:error(strip(res))
    return 1
  end
  return res
end

-- env = { pwd, cwd, home, hwc_home, tty, width, clock }: where hwc runs, the
-- user's home, whether stderr is a terminal (and its width; nil measures it) and
-- the wall clock, each defaulting to the process's own (specs pass their own;
-- tty defaults to false).
function M.main(argv, out, err, env)
  out, err = out or io.stdout, err or io.stderr
  argv = argv or {}
  env = env or {}
  env = {
    pwd = env.pwd or os.getenv("PWD"),
    cwd = env.cwd or require("lfs").currentdir(),
    -- false (specs) stands for an unset HOME
    home = env.home == nil and os.getenv("HOME") or env.home,
    hwc_home = env.hwc_home == nil and os.getenv("HWC_HOME") or env.hwc_home,
    tty = env.tty or false,
    width = env.width,
    clock = env.clock or os.time,
  }
  local commands = require("hwc.cli.commands")
  local g = require("hwc.cli.args").globals(argv)
  local u = require("hwc.ui").new({ out = out, err = err, level = g.level, tty = env.tty, width = env.width })
  if g.version or g.command == "version" then return dispatch(commands.find("version"), {}, u, env) end
  if g.help and g.command and g.command ~= "help" then
    return dispatch(commands.find("help"), { g.command }, u, env)
  end
  if not g.command then
    if #g.rest > 0 and not g.help then
      return commands.usage_error(u, "unknown option " .. g.rest[1])
    end
    return dispatch(commands.find("help"), {}, u, env)
  end
  local decl = commands.find(g.command)
  if not decl then return commands.unknown(u, g.command) end
  return dispatch(decl, g.rest, u, env)
end

return M
