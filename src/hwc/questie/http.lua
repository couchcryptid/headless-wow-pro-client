-- The only module that shells out to curl and unzip. Everything else takes
-- these functions as injected deps, so unit specs never touch the network.
local dkjson = require("dkjson")

local M = {}

local ACCEPT = "Accept: application/vnd.github+json"

function M.quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Runs a shell command, returns its stdout, its exit code and (capture mode)
-- its stderr text. The exit code is echoed by the shell because
-- popen():close() reports it differently across LuaJIT builds.
-- stderr_mode: "discard" (default) drops stderr, "capture" returns it as the
-- third value, "terminal" leaves it attached to the terminal.
local function sh(cmd, stderr_mode)
  stderr_mode = stderr_mode or "discard"
  local redirect, errfile = "", nil
  if stderr_mode == "discard" then
    redirect = " 2>/dev/null"
  elseif stderr_mode == "capture" then
    errfile = os.tmpname()
    redirect = " 2>" .. M.quote(errfile)
  end
  local p = io.popen("(" .. cmd .. ")" .. redirect .. "; echo \"__hwc_exit=$?\"", "r")
  local errtext
  local function finish()
    if errfile then
      local f = io.open(errfile, "rb")
      if f then
        errtext = f:read("*a") or ""
        f:close()
      else
        errtext = ""
      end
      os.remove(errfile)
    end
  end
  if not p then
    finish()
    return nil, -1, errtext
  end
  local out = p:read("*a") or ""
  p:close()
  finish()
  local body, code = out:match("^(.*)__hwc_exit=(%d+)%s*$")
  if not body then return out, -1, errtext end
  return body, tonumber(code), errtext
end
M.sh = sh

-- The last non-empty line of curl's stderr, trimmed; nil when there is none.
local function last_line(errtext)
  local last
  for line in tostring(errtext or ""):gmatch("[^\r\n]+") do
    local t = line:match("^%s*(.-)%s*$")
    if t ~= "" then last = t end
  end
  return last
end

local function failure(what, url, code, errtext)
  local line = last_line(errtext)
  if line then return "hwc: " .. what .. " " .. url .. " failed: " .. line end
  return "hwc: " .. what .. " " .. url .. " failed (curl exit " .. code .. ")"
end

function M.get_json(url)
  local body, code, errtext = sh("curl -fsSL --max-time 15 -H " .. M.quote(ACCEPT) .. " " .. M.quote(url), "capture")
  if code ~= 0 then
    return nil, failure("GET", url, code, errtext)
  end
  local value = dkjson.decode(body)
  if type(value) ~= "table" then
    return nil, "hwc: GET " .. url .. " returned invalid JSON"
  end
  return value
end

-- mode "terminal" shows curl's progress bar and error on the terminal;
-- anything else is silent and reports curl's error text in the message.
function M.download(url, path, mode)
  local terminal = mode == "terminal"
  local flags = terminal and "-fL -#" or "-fsSL"
  local _, code, errtext = sh("curl " .. flags .. " --max-time 300 -o " .. M.quote(path) .. " " .. M.quote(url),
    terminal and "terminal" or "capture")
  if code ~= 0 then
    if terminal then
      return nil, "hwc: download " .. url .. " failed (curl exit " .. code .. "; see curl's message above)"
    end
    return nil, failure("download", url, code, errtext)
  end
  return true
end

function M.unzip(zip, dest)
  local _, code = sh("unzip -q -o " .. M.quote(zip) .. " -d " .. M.quote(dest))
  if code ~= 0 then
    return nil, "hwc: unzip " .. zip .. " failed (exit " .. code .. ")"
  end
  return true
end

function M.has_tool(name)
  local _, code = sh("command -v " .. M.quote(name))
  return code == 0
end

function M.sha256(path)
  -- shasum ships with macOS and perl; sha256sum with coreutils. Both print
  -- "<hex>  <path>", so the first field is the digest either way.
  local tool = M.has_tool("shasum") and "shasum -a 256" or "sha256sum"
  local out, code = sh(tool .. " " .. M.quote(path))
  local hex = code == 0 and out:match("^(" .. ("%x"):rep(64) .. ")%s")
  if not hex then return nil, "hwc: cannot checksum " .. path end
  return hex
end

return M
