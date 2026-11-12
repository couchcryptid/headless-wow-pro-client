-- Read-only adapter over the running WoW-Pro engine (design spec §5.2). The
-- driver and step actions look at the engine only through here. Nothing in
-- this module writes env.WoWPro.* or SavedVariables; the only engine calls it
-- makes are the player equivalents complete_manual and update_guide.
local guide_source = require("hwc.driver.guide_source")

local Engine = {}
Engine.__index = Engine

Engine.SETTLE_MAX_VIRTUAL = 60

-- Per-index tag arrays copied into Step.tags: engine key per tag, as
-- DefineTag(tag, key, ...) names them (WoWPro_Parser.lua:460-590).
Engine.TAG_KEYS = {
  "questtext", -- QO   Parser:511
  "use",       -- U    :529
  "lootitem",  -- L    :491
  "zone",      -- Z    :483
  "map",       -- M    :481
  "level",     -- LVL  :547
  "elite",     -- ELITE:516
  "noncombat", -- NC   :521
  "dungeon",   -- DUNGEON:527
  "prof",      -- P    :548
  "spell",     -- SPELL:553
  "note",      -- N    :586
  "optional",  -- O    :464
  "sticky",    -- S    :572
  "unsticky",  -- US   :571
  "rank",      -- RANK :588
  "target",    -- T    :528
}

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

-- sb:call returns false on a raised error, else true followed by the
-- function's results. Returns ok, first result.
local function call(sb, fn, ...)
  local ok, value = sb:call(fn, ...)
  return ok, value
end

function Engine.new(result)
  return setmetatable({ sb = result.sb, result = result, env = result.sb.env }, Engine)
end

function Engine:W() return self.env.WoWPro end

function Engine:fire(event, ...)
  local sb = self.sb
  sb:call(sb.frames.fire, sb.frames, event, ...)
end

-- Same read-only lockdown predicate as boot: the engine's own OnUpdate handler
-- (WoWPro_Broker.lua:4840-4874) clears LockdownTimer.
function Engine:settle()
  local env = self.env
  return self.sb.clock:settle({
    max_virtual = Engine.SETTLE_MAX_VIRTUAL,
    busy = function()
      local w = rawget(env, "WoWPro")
      return type(w) == "table" and w.LockdownTimer ~= nil
    end,
  })
end

function Engine:gid()
  local db = rawget(self.env, "WoWProDB")
  return db and db.char and db.char.currentguide or nil
end

function Engine:source_index()
  local path = self.result.addon and self.result.addon.path
  if not path then return nil end
  self._index = self._index or guide_source.index(path)
  return self._index
end

function Engine:guide(gid)
  gid = gid or self:gid()
  local W = self:W()
  local g = W.Guides and W.Guides[gid] or {}
  local next_gid
  -- NextGuide pops the guide stack when nextGID is nil (PopCurrentGuide may
  -- mutate), so only resolve it when the registry names one (Broker:777-808).
  if g.nextGID then
    local ok, value = call(self.sb, W.NextGuide, W, gid)
    if ok then next_gid = value end
  end
  local char = rawget(self.env, "WoWProCharDB")
  local saved = char and char.Guide and char.Guide[gid]
  local index = self:source_index()
  return {
    gid = gid, startlevel = g.startlevel, endlevel = g.endlevel, next_gid = next_gid,
    file = index and index[gid] or nil, done = saved and saved.done,
  }
end

-- QID is a string; several ids join with ^ or & (the engine splits on "^&":
-- WoWPro_Parser.lua:321, 1028; Broker:254-258 QidMapReduce("^","&")).
local function split_qids(s)
  local out = {}
  if type(s) ~= "string" then return out end
  for part in s:gmatch("[^%^&]+") do
    local n = tonumber(part)
    if n then out[#out + 1] = n end
  end
  return out
end

function Engine:step(i)
  local W = self:W()
  local qids = split_qids(W.QID and W.QID[i])
  local tags = {}
  for _, key in ipairs(Engine.TAG_KEYS) do
    local arr = W[key]
    if type(arr) == "table" and arr[i] ~= nil then tags[key] = copy(arr[i]) end
  end
  local gid = self:gid()
  local step = {
    index = i, gid = gid, action = W.action and W.action[i], name = W.step and W.step[i],
    qid = W.QID and W.QID[i], qids = qids, tags = tags,
  }
  local index = self:source_index()
  local file = index and index[gid]
  if file then
    local occurrence = 1
    for j = 1, i - 1 do
      if W.action[j] == step.action and W.step[j] == step.name
        and split_qids(W.QID and W.QID[j])[1] == qids[1] then
        occurrence = occurrence + 1
      end
    end
    step.line = guide_source.line_of(self.result.addon.path, file, step, occurrence)
  end
  return step
end

-- The newest error the sandbox recorded (the failed call put it there).
function Engine:last_error()
  local errs = self.sb.errors
  local e = errs and errs[#errs]
  return e and e.msg or "engine call failed"
end

-- Returns the count, or nil, err when the addon call raised. A failed call must
-- never read as 0 (that would treat a sticky row as the current step).
function Engine:sticky_count()
  local W = self:W()
  local ok, n = call(self.sb, W.GetActiveStickyCount, W)
  if not ok then return nil, self:last_error() end
  return n or 0
end

-- The step the engine itself treats as current: the first row after the sticky
-- rows (WoWPro_Events.lua:742, 752, 776, 786). Returns nil when there is none,
-- or nil, err when the sticky-count call failed.
function Engine:current()
  local W = self:W()
  local sticky, err = self:sticky_count()
  if not sticky then return nil, err end
  local row = W.rows[sticky + 1]
  return row and row.index and self:step(row.index) or nil
end

function Engine:rows()
  local W = self:W()
  local sticky, err = self:sticky_count()
  if not sticky then return nil, err end
  local out = {}
  for n, row in ipairs(W.rows) do
    local visible = row.IsVisible == nil or row:IsVisible()
    if visible and row.index then
      local s = self:step(row.index)
      s.sticky = n <= sticky
      out[#out + 1] = s
    end
  end
  return out
end

function Engine:num_steps()
  local W = self:W()
  local n = 0
  for k in pairs(W.action or {}) do if type(k) == "number" and k > n then n = k end end
  return n
end

-- gid defaults to the current guide; the driver passes the guide it is closing
-- (WoWProCharDB.Guide[gid].completion outlives the switch to the next guide).
function Engine:completed(i, gid)
  gid = gid or self:gid()
  local char = rawget(self.env, "WoWProCharDB")
  local saved = char and char.Guide and char.Guide[gid]
  return saved and saved.completion and saved.completion[i] and true or false
end

function Engine:why(i)
  local why = self:W().why
  return why and why[i] or nil
end

-- Player equivalent of right-clicking the step (WoWPro_Broker.lua:3857).
-- Returns true, or false, err when the addon raised (the error is also in
-- sb.errors; the driver records it as a finding and carries on).
function Engine:complete_manual(i)
  local W = self:W()
  if not call(self.sb, W.CompleteStep, i, "Right-Click") then return false, self:last_error() end
  return true
end

-- Same return contract as complete_manual.
function Engine:update_guide()
  local W = self:W()
  if not call(self.sb, W.UpdateGuide, W, "sim:level") then return false, self:last_error() end
  return true
end

-- The engine's own rank lookup for the current guide (WoWPro_Broker.lua:602-618).
function Engine:rank()
  local W = self:W()
  local ok, rank = call(self.sb, W.GuideRank, self:gid())
  if not ok then return nil, self:last_error() end
  return rank
end

return Engine
