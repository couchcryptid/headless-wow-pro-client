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

-- Runs a frame script. With an on_error hook (the client's error handler),
-- an error is reported and the caller carries on, as in the client.
local function run_script(owner, fn, ...)
  if not owner.on_error then return fn(...) end
  xpcall(fn, owner.on_error, ...)
end

local function ensure_ticker(self)
  local s = self._s
  if s.ticker then return end
  s.ticker = s.owner.clock:add_ticker(function(elapsed)
    local fn = s.scripts.OnUpdate
    if fn and self:IsVisible() then run_script(s.owner, fn, self, elapsed) end
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
function Frame:SetSize(w, h) self._s.width, self._s.height = w, h; return self end
function Frame:SetWidth(w) self._s.width = w; return self end
function Frame:SetHeight(h) self._s.height = h; return self end
function Frame:GetWidth() return self._s.width or 0 end
function Frame:GetHeight() return self._s.height or 0 end
function Frame:GetSize() return self:GetWidth(), self:GetHeight() end
function Frame:SetChecked(v) self._s.checked = v and true or false end
function Frame:GetChecked() return self._s.checked end

-- Layout state the loaded engine/UI files read back (WoWPro_Frames.lua,
-- WoWPro_RowUpdate.lua). There is no renderer, so nothing computes a screen
-- rect (GetTop/GetLeft/... are nil, as for an unlaid-out frame) and font
-- strings measure 0.
function Frame:SetFrameLevel(n) self._s.level = n; return self end
function Frame:GetFrameLevel()
  if self._s.level then return self._s.level end
  local p = self._s.parent
  return p and p:GetFrameLevel() + 1 or 0
end
function Frame:SetScale(n) self._s.scale = n; return self end
function Frame:GetScale() return self._s.scale or 1 end
function Frame:GetEffectiveScale()
  local p = self._s.parent
  return self:GetScale() * (p and p:GetEffectiveScale() or 1)
end
function Frame:SetPoint(...)
  local pts = self._s.points or {}
  self._s.points = pts
  pts[#pts + 1] = { n = select("#", ...), ... }
  return self
end
function Frame:SetAllPoints(rel) self:ClearAllPoints(); self:SetPoint("TOPLEFT", rel, "TOPLEFT"); self:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT"); return self end
function Frame:ClearAllPoints() self._s.points = nil; return self end
function Frame:GetNumPoints() return self._s.points and #self._s.points or 0 end
function Frame:GetPoint(i)
  local pt = self._s.points and self._s.points[i or 1]
  if not pt then return nil end
  return unpack(pt, 1, pt.n)
end
function Frame:GetTop() return nil end
function Frame:GetBottom() return nil end
function Frame:GetLeft() return nil end
function Frame:GetRight() return nil end
function Frame:GetStringHeight() return 0 end
function Frame:GetStringWidth() return 0 end
function Frame:IsMouseOver() return false end
function Frame:Enable() self._s.disabled = false; return self end
function Frame:Disable() self._s.disabled = true; return self end
function Frame:SetEnabled(v) self._s.disabled = not v; return self end
function Frame:IsEnabled() return not self._s.disabled end
function Frame:SetAttribute(k, v) self._s.attrs = self._s.attrs or {}; self._s.attrs[k] = v; return self end
function Frame:GetAttribute(k) return self._s.attrs and self._s.attrs[k] end
function Frame:SetValue(v) self._s.value = v; return self end
function Frame:SetMinMaxValues(lo, hi) self._s.range = { lo, hi }; return self end
function Frame:GetMinMaxValues()
  local r = self._s.range
  if not r then return 0, 0 end
  return r[1], r[2]
end
function Frame:GetValue() return self._s.value end
function Frame:SetTexture(t) self._s.texture = t; return self end
function Frame:GetTexture() return self._s.texture end
function Frame:SetFont(...) self._s.font = { n = select("#", ...), ... }; return self end
function Frame:GetFont()
  local f = self._s.font
  if not f then return nil end
  return unpack(f, 1, f.n)
end
function Frame:SetTextColor(r, g, b, a) self._s.color = { r, g, b, a or 1 }; return self end
function Frame:GetTextColor()
  local c = self._s.color or { 1, 1, 1, 1 }
  return c[1], c[2], c[3], c[4]
end

-- Anything else: Create* makes a child mock; an unknown getter (Get/Is/Has/Can)
-- returns nil and is reported once through on_missing; the rest return the frame.
Frame.__index = function(self, key)
  local method = rawget(Frame, key)
  if method ~= nil then return method end
  if type(key) ~= "string" or not key:match("^%u") then return nil end
  if key:match("^Create") then
    return function(me)
      return new_frame(me._s.owner, key:sub(7), nil, me)
    end
  end
  -- Set<Slot>Texture(path) creates (once) a texture region that Get<Slot>Texture returns
  local slot = key:match("^Set(%u%a*)Texture$")
  if slot then
    return function(me, tex)
      local regions = me._s.regions or {}
      me._s.regions = regions
      regions[slot] = regions[slot] or new_frame(me._s.owner, "Texture", nil, me)
      regions[slot]._s.texture = tex
      return me
    end
  end
  slot = key:match("^Get(%u%a*)Texture$")
  if slot then
    return function(me) return me._s.regions and me._s.regions[slot] end
  end
  if key:match("^Get") or key:match("^Is%u") or key:match("^Has%u") or key:match("^Can%u") then
    return function(me)
      local owner = me._s.owner
      if owner.on_missing and not owner._missed[key] then
        owner._missed[key] = true
        owner.on_missing("Frame:" .. key)
      end
      return nil
    end
  end
  return function(me) return me end
end

local Frames = {}
Frames.__index = Frames

-- on_error (optional): called with the error of a failing OnEvent/OnUpdate
-- script; without it, script errors propagate.
-- on_missing (optional): called once per unknown getter name ("Frame:GetX").
function M.new(clock, on_error, on_missing)
  return setmetatable({ clock = clock, on_error = on_error, on_missing = on_missing,
                        _missed = {}, _regs = {}, _named = {} }, Frames)
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
      if handler then run_script(self, handler, r.frame, event, ...) end
    end
  end
end

return M
