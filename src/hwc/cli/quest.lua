-- hwc quest <id>: a quest from the catalog (QuestieDB and the counts file), with its sources, as JSON. Needs no
-- WoW-Pro folder.
return {
  name = "quest",
  summary = "Print a quest from the catalog, with its sources, as JSON",
  usage = "<id>",
  description = "Print a quest from the catalog (QuestieDB and the objective counts file), with its sources, as JSON.",
  positionals = { min = 1, max = 1, noun = "id" },
  check = function(opts)
    if not tonumber(opts.positionals[1]) then return "quest needs a numeric id" end
  end,
  run = function(ctx)
    local id = tonumber(ctx.opts.positionals[1])
    local cfg = require("hwc.config").load({})
    local cat = require("hwc.catalog").load(cfg)
    local quest = cat:quest(id)
    if not quest then
      ctx.ui:error("quest " .. id .. " is in no catalog source")
      return 1
    end
    ctx.ui:result(require("hwc.json").encode({ quest = quest, sources = cat.sources }, { indent = true }) .. "\n")
    return 0
  end,
}
