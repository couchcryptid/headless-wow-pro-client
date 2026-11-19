-- hwc update [--tag TAG] [--build VERSION]: install the newest QuestieDB Forever
-- release (or TAG) and the Forever client tables (or VERSION), and make both active. Works on ~/.hwc, so it needs no WoW-Pro folder.
local update = {
  name = "update",
  summary = "Install the newest QuestieDB release and Forever client tables and make them active",
  usage = "[--tag TAG] [--build VERSION]",
  description = "Install the newest QuestieDB Forever release (or --tag TAG) and the newest Forever client\n"
    .. "tables (or --build VERSION) into ~/.hwc and make them active.",
  options = {
    { name = "tag", metavar = "TAG", help = "A QuestieDB release tag, e.g. v1.1.3.", default_text = "newest" },
    { name = "build", metavar = "VERSION", help = "A Forever client build, e.g. 1.16.1.64321.", default_text = "newest" },
  },
}

local function strip(msg) return (tostring(msg):gsub("^hwc: ", "")) end
update.strip = strip

-- The ~/.hwc store root, or nil after writing the error (the caller exits 2).
function update.store_root(ctx)
  local root, err = require("hwc.questie.home").root({ hwc_home = ctx.env.hwc_home, home = ctx.env.home })
  if not root then ctx.ui:error(strip(err)) end
  return root
end

-- The result lines of an install: what changed, then each release skipped.
function update.report(ui, res)
  if res.already then
    ui:result("QuestieDB " .. res.to .. " already installed; active\n")
  else
    ui:result("QuestieDB " .. (res.from or "none") .. " \226\134\146 " .. res.to
      .. " (build " .. tostring(res.build):sub(1, 7) .. ")\n")
  end
  for _, tag in ipairs(res.skipped or {}) do ui:result("skipped " .. tag .. ": no Forever build\n") end
end

-- The result line of the Forever tables install.
function update.report_forever(ui, res)
  if res.already then
    ui:result("Forever tables " .. res.to .. " already installed; active\n")
  else
    ui:result("Forever tables " .. (res.from or "none") .. " \226\134\146 " .. res.to .. "\n")
  end
end

-- Show curl's progress bar only when a person is watching and not --quiet.
function update.download_mode(ui)
  return (ui.tty and ui.level ~= "quiet") and "terminal" or "capture"
end

function update.run(ctx)
  local root = update.store_root(ctx)
  if not root then return 2 end
  local mode = update.download_mode(ctx.ui)
  local res, err = require("hwc.questie.install").sync(root, { tag = ctx.opts.tag, download_mode = mode })
  if not res then
    ctx.ui:error(strip(err))
    return 1
  end
  update.report(ctx.ui, res)
  local fres, ferr = require("hwc.forever.install").sync(root, { build = ctx.opts.build, download_mode = mode })
  if not fres then
    ctx.ui:error(strip(ferr))
    return 1
  end
  update.report_forever(ctx.ui, fres)
  return 0
end

return update
