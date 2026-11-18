-- hwc help [command]: the top-level usage, or one command's help. The
-- dispatcher also runs this for `hwc <command> --help`.
local help = require("hwc.cli.help")

return {
  name = "help",
  summary = "Show the usage, or one command's help",
  usage = "[COMMAND]",
  description = "Show the usage, or one command's options and notes.",
  positionals = { min = 0, max = 1, noun = "command" },
  run = function(ctx)
    local commands = require("hwc.cli.commands")
    local name = ctx.opts.positionals[1]
    if not name then
      ctx.ui:result(help.usage(commands.list))
      return 0
    end
    local decl = commands.find(name)
    if not decl then return commands.unknown(ctx.ui, name) end
    -- A stub always prints its one line, help or not.
    if decl.passthrough then return decl.run(ctx) end
    ctx.ui:result(help.command(decl))
    return 0
  end,
}
