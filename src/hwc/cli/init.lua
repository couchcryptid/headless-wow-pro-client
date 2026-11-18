-- hwc init: download QuestieDB (latest Forever release) into ~/.hwc unless one is
-- active, then print the doctor report. Needs no WoW-Pro folder.
local update = require("hwc.cli.update")

return {
  name = "init",
  summary = "Download QuestieDB (latest Forever release) into ~/.hwc and check the setup",
  description = "Download QuestieDB (latest Forever release) into ~/.hwc unless one is installed,\n"
    .. "then run hwc doctor.",
  run = function(ctx)
    local root = update.store_root(ctx)
    if not root then return 2 end
    local res, err = require("hwc.questie.install").init(root)
    if not res then
      ctx.ui:error(update.strip(err))
      return 1
    end
    if res.already then
      ctx.ui:result("QuestieDB " .. tostring(require("hwc.questie.home").active(root)) .. " already installed\n")
    else
      update.report(ctx.ui, res.sync_result)
    end
    local doctor = require("hwc.doctor")
    ctx.ui:result(doctor.text(doctor.run(ctx.env)))
    return 0
  end,
}
