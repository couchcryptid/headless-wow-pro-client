-- User-facing output: results to stdout; progress, warnings and errors to
-- stderr. Levels: quiet < normal < verbose. On a terminal progress redraws
-- in place; otherwise it prints plain lines, skipping consecutive repeats.
local ui = {}

local CLEAR = "\r\27[K"

-- True when file descriptor fd is a terminal. False if FFI is unavailable.
function ui.isatty(fd)
  local ok, ffi = pcall(require, "ffi")
  if not ok then
    return false
  end
  -- cdef errors if the declaration already exists in-process; that is fine.
  pcall(ffi.cdef, "int isatty(int);")
  local called, rc = pcall(function()
    return ffi.C.isatty(fd)
  end)
  return called and rc == 1
end

local Ui = {}
Ui.__index = Ui

function ui.new(opts)
  local tty = opts.tty
  if tty == nil then
    tty = ui.isatty(2)
  end
  return setmetatable({
    out = opts.out or io.stdout,
    err = opts.err or io.stderr,
    level = opts.level or "normal",
    tty = tty,
    shown = false, -- a progress line is currently on the terminal
    last = nil, -- last progress text
  }, Ui)
end

local function flush(f)
  if f.flush then
    f:flush()
  end
end

local function withNewline(text)
  if text:sub(-1) ~= "\n" then
    return text .. "\n"
  end
  return text
end

-- Write a line to stderr without corrupting a progress line on a terminal.
function Ui:_line(text)
  if self.tty and self.shown then
    self.err:write(CLEAR, text, CLEAR, self.last)
  else
    self.err:write(text)
  end
  flush(self.err)
end

function Ui:result(text)
  self.out:write(text)
  flush(self.out)
end

function Ui:info(text)
  if self.level ~= "quiet" then
    self:_line(withNewline(text))
  end
end

function Ui:detail(text)
  if self.level == "verbose" then
    self:_line(withNewline(text))
  end
end

function Ui:warn(text)
  if self.level ~= "quiet" then
    self:_line(withNewline("warning: " .. text))
  end
end

function Ui:error(text)
  self:_line(withNewline("hwc: " .. text))
end

function Ui:progress(text)
  if self.level == "quiet" then
    return
  end
  if self.tty then
    self.err:write(self.shown and CLEAR or "\r", text)
    self.shown = true
  elseif text ~= self.last then
    self.err:write(text, "\n")
  end
  self.last = text
  flush(self.err)
end

function Ui:done()
  if self.tty and self.shown then
    self.err:write(CLEAR)
    flush(self.err)
  end
  self.shown = false
  self.last = nil
end

return ui
