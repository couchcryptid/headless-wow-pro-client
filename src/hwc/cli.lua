-- Command line entry point. Only --help exists so far.
local USAGE = [[
Usage: hwc [options]

Headless WoW-Pro client: loads the real WoW-Pro addon under LuaJIT.

Options:
  -h, --help    Show this help
]]

local M = {}

function M.main(args)
  for _, a in ipairs(args) do
    if a == "-h" or a == "--help" then
      io.stdout:write(USAGE)
      return 0
    end
  end
  io.stderr:write(USAGE)
  return 2
end

os.exit(M.main(arg))
