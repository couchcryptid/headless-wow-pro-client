-- hwc doctor [--json]: check LuaJIT, rocks, tools, the WoW-Pro folder, QuestieDB
-- and the supplement. Exit 1 when a check failed. Needs no WoW-Pro folder.
local update = require("hwc.cli.update")

return {
  name = "doctor",
  summary = "Check LuaJIT, rocks, tools, the WoW-Pro folder, that the addon loads, QuestieDB and the supplement",
  usage = "[--json]",
  description = "Check LuaJIT, rocks, tools, the WoW-Pro folder, that the addon loads, QuestieDB and the supplement.",
  options = {
    { name = "json", flag = true, help = "Print the report as JSON." },
  },
  notes = { "Exit status: 0 when every check passes or warns, 1 when one fails." },
  run = function(ctx)
    if not update.store_root(ctx) then return 2 end
    local doctor = require("hwc.doctor")
    local report = doctor.run(ctx.env)
    ctx.ui:result(ctx.opts.json and (doctor.json(report) .. "\n") or doctor.text(report))
    return report.failed and 1 or 0
  end,
}
