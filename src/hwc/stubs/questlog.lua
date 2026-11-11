-- Empty quest log for the Forever flavor. WoWPro_CompatUtil.lua:121-208 picks
-- the C_QuestLog paths because the legacy globals (GetQuestLogTitle,
-- GetNumQuestLogEntries) are absent, so only C_QuestLog is stubbed.
local M = {}

function M.install(sb, _player)
  local env = sb.env
  env.C_QuestLog = {
    -- CompatUtil:123 (QuestLog_GetInfo); nil for any index ends PopulateQuestLog's loop
    GetInfo = function() return nil end,
    -- CompatUtil:173 (QuestLog_GetNumQuestLogEntries); numEntries, numQuests
    GetNumQuestLogEntries = function() return 0, 0 end,
    -- CompatUtil:181 (QuestLog_IsComplete); not in log -> not complete
    IsComplete = function() return false end,
    -- CompatUtil:184 (QuestLog_IsComplete)
    IsFailed = function() return false end,
    -- CompatUtil:194 (QuestLog_IsQuestFlaggedCompleted)
    IsQuestFlaggedCompleted = function() return false end,
    -- CompatUtil:201 (QuestLog_IsQuestFlaggedCompletedOnAccount)
    IsQuestFlaggedCompletedOnAccount = function() return false end,
    -- CompatUtil:204 (ForAccount fallback)
    IsQuestFlaggedCompletedForAccount = function() return false end,
  }
end

return M
