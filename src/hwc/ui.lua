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

-- TIOCGWINSZ differs by OS: _IOR('t', 104, struct winsize) on the BSDs and macOS.
local TIOCGWINSZ = { OSX = 0x40087468, BSD = 0x40087468, Linux = 0x5413 }

-- The terminal's width in columns: the window size of stderr, else $COLUMNS,
-- else 80.
function ui.width()
  local ok, ffi = pcall(require, "ffi")
  local req = ok and TIOCGWINSZ[ffi.os]
  if req then
    pcall(ffi.cdef, [[
      struct hwc_winsize { unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel; };
      int ioctl(int, unsigned long, ...);
    ]])
    local called, cols = pcall(function()
      -- An array, so the vararg receives a pointer, not the struct by value.
      local ws = ffi.new("struct hwc_winsize[1]")
      if ffi.C.ioctl(2, req, ws) == 0 then return ws[0].ws_col end
    end)
    if called and cols and cols > 0 then return tonumber(cols) end
  end
  local env = tonumber(os.getenv("COLUMNS") or "")
  if env and env > 0 then return math.floor(env) end
  return 80
end

-- text cut to at most `cols` UTF-8 code points, ending in … when cut. Columns
-- are counted as code points: progress text holds no wide characters.
function ui.fit(text, cols)
  if cols < 1 then return "" end
  local starts = {}
  for i = 1, #text do
    local b = text:byte(i)
    if b < 0x80 or b >= 0xC0 then starts[#starts + 1] = i end
  end
  if #starts <= cols then return text end
  return text:sub(1, starts[cols] - 1) .. "…"
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
    width = opts.width, -- nil: measured at each draw, so a resize is followed
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

-- The progress text as drawn on a terminal: one column short of its width, so
-- it never wraps (a wrapped line can't be cleared with \r).
function Ui:_fit(text)
  return ui.fit(text, (self.width or ui.width()) - 1)
end

-- Write a line to stderr without corrupting a progress line on a terminal.
function Ui:_line(text)
  if self.tty and self.shown then
    self.err:write(CLEAR, text, CLEAR, self:_fit(self.last))
  else
    self.err:write(text)
  end
  flush(self.err)
end

function Ui:result(text)
  -- stdout and stderr share the terminal: clear the progress line first.
  if self.tty and self.shown then self:done() end
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
    self.err:write(self.shown and CLEAR or "\r", self:_fit(text))
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
