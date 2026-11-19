-- hwc init: download QuestieDB (latest Forever release) and the Forever client
-- tables into ~/.hwc unless active, then print the doctor report. Needs no WoW-Pro folder.
local update = require("hwc.cli.update")

return {
  name = "init",
  summary = "Download QuestieDB and the Forever client tables into ~/.hwc and check the setup",
  description = "Download QuestieDB (latest Forever release) and the Forever client tables into ~/.hwc\n"
    .. "unless installed,\n"
    .. "then run hwc doctor.",
  run = function(ctx)
    local root = update.store_root(ctx)
    if not root then return 2 end
    local res, err = require("hwc.questie.install").init(root, nil, { download_mode = update.download_mode(ctx.ui) })
    if not res then
      ctx.ui:error(update.strip(err))
      return 1
    end
    if res.already then
      ctx.ui:result("QuestieDB " .. tostring(require("hwc.questie.home").active(root)) .. " already installed\n")
    else
      update.report(ctx.ui, res.sync_result)
    end
    local fres, ferr = require("hwc.forever.install").init(root, nil, { download_mode = update.download_mode(ctx.ui) })
    if not fres then
      ctx.ui:error(update.strip(ferr))
      return 1
    end
    if fres.already then
      ctx.ui:result("Forever tables " .. tostring(require("hwc.forever.home").active(root)) .. " already installed\n")
    else
      update.report_forever(ctx.ui, fres.sync_result)
    end
    local doctor = require("hwc.doctor")
    ctx.ui:result(doctor.text(doctor.run(ctx.env)))
    return 0
  end,
}
