-- Quest-log API for the Forever flavor, backed by sb.world.log. WoWPro_CompatUtil.lua:121-208 picks
-- the C_QuestLog paths because the legacy globals (GetQuestLogTitle,
-- GetNumQuestLogEntries) are absent, so only C_QuestLog is stubbed. Every
-- stub reads sb.world.log on each call, never a captured copy.
local M = {}

local OBJECTIVE_TYPE = { item = "item", npc = "monster" }

function M.install(sb)
  local env = sb.env
  local function log() return sb.world.log end
  local function entry_at(i) return log():entries()[i] end

  -- have is the log's own read (Ruling Z: an item objective is the bag count).
  local function objective(e, i)
    local obj = e.quest.objectives[i]
    local have = log():have(e.id, i)
    return {
      text = (obj.text or "") .. ": " .. have .. "/" .. obj.count,
      type = OBJECTIVE_TYPE[obj.kind] or "object",
      finished = have >= obj.count,
      numFulfilled = have,
      numRequired = obj.count,
    }
  end

  -- WoWPro_Broker.lua:4046 (qfrequency compares questInfo.frequency to this on non-retail)
  env.LE_QUEST_FREQUENCY_DAILY = 1
  env.Enum = env.Enum or {}
  env.Enum.QuestFrequency = { Default = 0, Daily = 1, Weekly = 2 }

  -- Broker:4019 (PopulateQuestLog): leader board count for a log index
  env.GetNumQuestLeaderBoards = function(i)
    local e = entry_at(i)
    return e and #e.quest.objectives or 0
  end
  -- Broker:4019 and :4131 (progressbar probe): text, type, finished for objective idx of log index i
  env.GetQuestLogLeaderBoard = function(idx, i)
    local e = entry_at(i)
    if not (e and e.quest.objectives[idx]) then return nil end
    local o = objective(e, idx)
    return o.text, o.type, o.finished
  end
  -- Broker:4028 (progressbar objectives only; none are modelled)
  env.GetQuestProgressBarPercent = function() return 0 end

  env.C_QuestLog = require("hwc.stubs.core").trap(sb, "C_QuestLog", {
    -- CompatUtil:123 (QuestLog_GetInfo); nil for an index past the log ends PopulateQuestLog's loop.
    -- The log has no header rows: the engine path never needs them.
    GetInfo = function(i)
      local e = entry_at(i)
      if not e then return nil end
      return {
        title = e.quest.name or ("Quest " .. e.id), level = e.quest.level, questID = e.id,
        isHeader = false, suggestedGroup = 0, frequency = 0, isHidden = false,
      }
    end,
    -- CompatUtil:173 (QuestLog_GetNumQuestLogEntries); numEntries, numQuests
    GetNumQuestLogEntries = function()
      local n = #log().order
      return n, n
    end,
    -- Broker:4023 (GetQuestObjectives per questID)
    GetQuestObjectives = function(qid)
      local e = log():get(qid)
      local out = {}
      if e then
        for i = 1, #e.quest.objectives do out[i] = objective(e, i) end
      end
      return out
    end,
    -- CompatUtil:181 (QuestLog_IsComplete); not in log -> not complete
    IsComplete = function(qid) return log():is_complete(qid) end,
    -- CompatUtil:184 (QuestLog_IsComplete)
    IsFailed = function() return false end,
    -- CompatUtil:194 (QuestLog_IsQuestFlaggedCompleted); callers pass raw WoWPro.QID[qidx]
    -- strings (AutoComplete.lua:522) and split prereq ids (Broker.lua:2275), so coerce.
    IsQuestFlaggedCompleted = function(qid) return log().history[tonumber(qid)] == true end,
    -- CompatUtil:201 (QuestLog_IsQuestFlaggedCompletedOnAccount)
    IsQuestFlaggedCompletedOnAccount = function() return false end,
    -- CompatUtil:204 (ForAccount fallback)
    IsQuestFlaggedCompletedForAccount = function() return false end,
  })
end

return M
