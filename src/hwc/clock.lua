-- Virtual clock: replaces real time so a run is deterministic.
-- Timers model C_Timer.After; tickers model frame OnUpdate scripts.
local Clock = {}
Clock.__index = Clock

local START = 1000.0
local DEFAULT_TICK = 1 / 30
local DEFAULT_MAX_VIRTUAL = 30

local M = {}

function M.new()
  return setmetatable({ _now = START, _seq = 0, _timers = {}, _tickers = {} }, Clock)
end

function Clock:now()
  return self._now
end

function Clock:after(delay, fn)
  if delay < 0 then delay = 0 end
  self._seq = self._seq + 1
  self._timers[#self._timers + 1] = { due = self._now + delay, seq = self._seq, fn = fn }
end

function Clock:add_ticker(fn)
  local entry = { fn = fn, active = true }
  self._tickers[#self._tickers + 1] = entry
  return {
    cancel = function()
      entry.active = false
    end,
  }
end

-- Index of the earliest timer (ties broken by insertion order), or nil.
function Clock:_earliest()
  local best
  for i, t in ipairs(self._timers) do
    if not best or t.due < self._timers[best].due
        or (t.due == self._timers[best].due and t.seq < self._timers[best].seq) then
      best = i
    end
  end
  return best
end

function Clock:_run_tickers(elapsed)
  local live = {}
  for _, entry in ipairs(self._tickers) do
    if entry.active then live[#live + 1] = entry end
  end
  self._tickers = live
  -- snapshot: tickers added during a step start on the next one
  local snapshot = {}
  for i, entry in ipairs(live) do snapshot[i] = entry end
  for _, entry in ipairs(snapshot) do
    if entry.active then entry.fn(elapsed) end
  end
end

function Clock:settle(opts)
  opts = opts or {}
  local tick = opts.tick or DEFAULT_TICK
  local max_virtual = opts.max_virtual or DEFAULT_MAX_VIRTUAL
  local start = self._now
  -- busy(): optional predicate for OnUpdate-driven work with no timer queued
  -- (e.g. WoWPro_Broker.lua:4840-4874 lockdown release); frames keep ticking while it holds.
  local busy = opts.busy or function() return false end
  local ran, hit_limit = 0, false

  while #self._timers > 0 or busy() do
    if self._now - start >= max_virtual then
      hit_limit = true
      break
    end
    local idx = self:_earliest()
    local timer = idx and self._timers[idx]
    if not timer then
      self._now = self._now + tick
      self:_run_tickers(tick)
    elseif timer.due > self._now then
      local gap = timer.due - self._now
      if gap <= tick then
        self._now = timer.due
        self:_run_tickers(gap)
      else
        self._now = self._now + tick
        self:_run_tickers(tick)
      end
    else
      table.remove(self._timers, idx)
      ran = ran + 1
      timer.fn()
    end
  end

  return { ran = ran, now = self._now, hit_limit = hit_limit }
end

return M
