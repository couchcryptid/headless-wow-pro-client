-- Stateful frame mock and event bus. Real state: shown/hidden, parent,
-- scripts, registered events, text, checked. Everything visual is a
-- chainable no-op so the addon's UI code runs without a renderer.
local M = {}

local Frame = {}

local function new_frame(owner, ftype, name, parent)
  local f = { _s = { owner = owner, ftype = ftype, name = name, parent = parent,
                     shown = true, scripts = {}, text = "", checked = false } }
  return setmetatable(f, Frame)
end

local function ensure_ticker(self)
  local s = self._s
  if s.ticker then return end
  s.ticker = s.owner.clock:add_ticker(function(elapsed)
    local fn = s.scripts.OnUpdate
    if fn and self:IsVisible() then fn(self, elapsed) end
  end)
end

local function drop_ticker(self)
  local s = self._s
  if s.ticker then s.ticker.cancel(); s.ticker = nil end
end

function Frame:RegisterEvent(event)
  local regs = self._s.owner._regs
  for _, r in ipairs(regs) do
    if r.frame == self and r.event == event then return end
  end
  regs[#regs + 1] = { frame = self, event = event }
end

function Frame:RegisterAllEvents()
  self:RegisterEvent(true)
end

function Frame:UnregisterEvent(event)
  local regs = self._s.owner._regs
  for i = #regs, 1, -1 do
    if regs[i].frame == self and regs[i].event == event then table.remove(regs, i) end
  end
end

function Frame:UnregisterAllEvents()
  local regs = self._s.owner._regs
  for i = #regs, 1, -1 do
    if regs[i].frame == self then table.remove(regs, i) end
  end
end

function Frame:IsEventRegistered(event)
  for _, r in ipairs(self._s.owner._regs) do
    if r.frame == self and (r.event == event or r.event == true) then return true end
  end
  return false
end

function Frame:SetScript(name, fn)
  self._s.scripts[name] = fn
  if name == "OnUpdate" then
    if fn then ensure_ticker(self) else drop_ticker(self) end
  end
end

function Frame:GetScript(name)
  return self._s.scripts[name]
end

function Frame:HookScript(name, fn)
  local prev = self._s.scripts[name]
  if prev then
    self._s.scripts[name] = function(...)
      prev(...)
      return fn(...)
    end
  else
    self._s.scripts[name] = fn
  end
  if name == "OnUpdate" then ensure_ticker(self) end
end

function Frame:Show() self._s.shown = true end
function Frame:Hide() self._s.shown = false end
function Frame:IsShown() return self._s.shown end

function Frame:IsVisible()
  local f = self
  while f do
    if not f._s.shown then return false end
    f = f._s.parent
  end
  return true
end

function Frame:SetParent(parent) self._s.parent = parent end
function Frame:GetParent() return self._s.parent end
function Frame:GetName() return self._s.name end
function Frame:SetText(text) self._s.text = text end
function Frame:GetText() return self._s.text end
function Frame:SetChecked(v) self._s.checked = v and true or false end
function Frame:GetChecked() return self._s.checked end

-- Anything else: Create* makes a child mock, the rest return the frame.
Frame.__index = function(self, key)
  local method = rawget(Frame, key)
  if method ~= nil then return method end
  if type(key) ~= "string" or not key:match("^%u") then return nil end
  if key:match("^Create") then
    return function(me)
      return new_frame(me._s.owner, key:sub(7), nil, me)
    end
  end
  return function(me) return me end
end

local Frames = {}
Frames.__index = Frames

function M.new(clock)
  return setmetatable({ clock = clock, _regs = {}, _named = {} }, Frames)
end

function Frames:create(ftype, name, parent, _template)
  local f = new_frame(self, ftype, name, parent)
  if name then self._named[name] = f end
  return f
end

function Frames:get(name)
  return self._named[name]
end

function Frames:shown(frame)
  return frame:IsVisible()
end

function Frames:fire(event, ...)
  local snapshot = {}
  for i, r in ipairs(self._regs) do snapshot[i] = r end
  local seen = {}
  for _, r in ipairs(snapshot) do
    if (r.event == event or r.event == true) and not seen[r.frame] then
      seen[r.frame] = true
      local handler = r.frame._s.scripts.OnEvent
      if handler then handler(r.frame, event, ...) end
    end
  end
end

return M
