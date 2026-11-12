-- Spec helper: drives the real WoW-Pro engine through Dun Morogh's first quest
-- (Dwarven Outfitters, 179) by changing the simulated world and firing the
-- events the client fires (design spec §5.2). Shared by world_engine_spec and
-- the separate-process determinism driver (world_engine_events.lua).
--
-- The harness only changes the world and fires events; it never writes engine
-- state. Every engine decision below is the addon's own.
local M = {}

M.ADDON = os.getenv("HOME") .. "/Projects/WoW-Pro-Guides"
M.GUIDE = M.ADDON .. "/WoWPro_Leveling/Forever/Alliance/01_12_Dun_Morogh.lua"
M.QID = 179
M.ITEM = 750
M.SETTLE_MAX_VIRTUAL = 60

local lfs = require("lfs")

local function exists(path) return lfs.attributes(path, "mode") ~= nil end

-- nil when both the addon checkout and the pinned Questie catalog are present,
-- otherwise the reason the integration specs are pending.
function M.absent()
  if not exists(M.ADDON .. "/WoWPro/WoWPro.toc") then return "addon checkout absent at " .. M.ADDON end
  local cfg = require("hwc.config").load({ addon_path = M.ADDON })
  if not exists(cfg.catalog.questie_dir) then return "catalog absent at " .. cfg.catalog.questie_dir end
  return nil
end

function M.boot(race, class)
  local cfg = require("hwc.config").load({ addon_path = M.ADDON, race = race, class = class })
  return require("hwc.boot").run(cfg)
end

-- Fire a client event through the frame mock, as boot does.
function M.fire(sb, ...)
  sb:call(sb.frames.fire, sb.frames, ...)
end

-- Settle the virtual clock. Same read-only lockdown predicate as boot: the
-- engine's own OnUpdate handler (WoWPro_Broker.lua:4840-4874) clears it.
function M.settle(sb)
  local env = sb.env
  return sb.clock:settle({
    max_virtual = M.SETTLE_MAX_VIRTUAL,
    busy = function()
      local w = rawget(env, "WoWPro")
      return type(w) == "table" and w.LockdownTimer ~= nil
    end,
  })
end

-- The step the engine itself treats as current: the first row after the
-- sticky rows (the addon's own lookup, WoWPro_Events.lua:742, 752, 776, 786).
function M.current(env)
  local W = env.WoWPro
  local row = W.rows[W:GetActiveStickyCount() + 1]
  local i = row and row.index
  return { index = i, action = i and W.action[i], step = i and W.step[i], qid = i and W.QID[i] }
end

function M.completion(env, index)
  local gid = env.WoWProDB.char.currentguide
  return env.WoWProCharDB.Guide[gid].completion[index]
end

local function log_index(world, qid)
  for i, e in ipairs(world.log:entries()) do
    if e.id == qid then return i end
  end
  return nil
end

-- Event sequences (design spec §5.2), each checked against the handlers:
--   QUEST_ACCEPTED(qlidx, qid)  WoWPro_Events.lua:783-793 (args read at :784)
--   QUEST_LOG_UPDATE            WoWPro_Events.lua:881-905: PopulateQuestLog's
--                               diff drives AutoCompleteQuestUpdate (AutoComplete.lua:317-399)
--   BAG_UPDATE                  WoWPro.lua:615, bucketed into AutoCompleteLoot (AutoComplete.lua:251-277)
--   QUEST_TURNED_IN(qid, xp, money)  WoWPro_Events.lua:772-781 sets CompletingQuest and
--                               calls AutoCompleteQuestUpdate(qid) (:780), whose AutoComplete
--                               branch completes the T step (AutoComplete.lua:356-366); the
--                               following QUEST_LOG_UPDATE's diff sets missingQuest
--                               (Broker.lua:4103-4115) for the turn-in branch (AutoComplete.lua:339-347)
function M.accept(r, qid)
  local ok, reason = r.world.log:accept(qid)
  assert(ok, "accept " .. qid .. ": " .. tostring(reason))
  M.fire(r.sb, "QUEST_ACCEPTED", log_index(r.world, qid), qid)
  M.fire(r.sb, "QUEST_LOG_UPDATE")
  return M.settle(r.sb)
end

function M.progress(r, qid, index, amount, item)
  assert(r.world.log:progress(qid, index, amount), "progress " .. qid)
  if item then r.world.player:add_item(item, amount) end
  M.fire(r.sb, "QUEST_LOG_UPDATE")
  M.fire(r.sb, "BAG_UPDATE", 0)
  return M.settle(r.sb)
end

-- Returns the settle result and the levels gained.
function M.turn_in(r, qid)
  local ok, reason, xp, levels = r.world.log:turn_in(qid)
  assert(ok, "turn in " .. qid .. ": " .. tostring(reason))
  M.fire(r.sb, "QUEST_TURNED_IN", qid, xp, 0)
  M.fire(r.sb, "QUEST_LOG_UPDATE")
  -- The addon has no level-up handler (design spec §5.2): force an update.
  if levels and levels > 0 then r.sb:call(r.sb.env.WoWPro.UpdateGuide, r.sb.env.WoWPro, "sim:level") end
  return M.settle(r.sb), levels
end

-- The whole Dwarven Outfitters flow; returns the boot result plus snapshots
-- of the engine after each settled sequence.
function M.run(race, class)
  local r = M.boot(race, class)
  local env = r.sb.env
  local snap = { settles = {} }
  snap.boot = M.current(env)

  snap.settles[#snap.settles + 1] = M.accept(r, M.QID)
  snap.accept = { completed = M.completion(env, snap.boot.index), current = M.current(env) }

  snap.c_index = snap.accept.current.index
  snap.settles[#snap.settles + 1] = M.progress(r, M.QID, 1, 8, M.ITEM)
  snap.progress = { completed = M.completion(env, snap.c_index), current = M.current(env) }

  snap.t_index = snap.progress.current.index
  local s, levels = M.turn_in(r, M.QID)
  snap.settles[#snap.settles + 1] = s
  snap.turn_in = { completed = M.completion(env, snap.t_index), current = M.current(env), levels = levels }
  return r, snap
end

return M
