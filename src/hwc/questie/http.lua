-- The only module that shells out to curl and unzip. Everything else takes
-- these functions as injected deps, so unit specs never touch the network.
local dkjson = require("dkjson")

local M = {}

local ACCEPT = "Accept: application/vnd.github+json"

function M.quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Runs a shell command, returns its stdout and its exit code. The exit code is
-- echoed by the shell because popen():close() reports it differently across
-- LuaJIT builds.
local function sh(cmd)
  local p = io.popen("(" .. cmd .. ") 2>/dev/null; echo \"__hwc_exit=$?\"", "r")
  if not p then return nil, -1 end
  local out = p:read("*a") or ""
  p:close()
  local body, code = out:match("^(.*)__hwc_exit=(%d+)%s*$")
  if not body then return out, -1 end
  return body, tonumber(code)
end

function M.get_json(url)
  local body, code = sh("curl -fsSL --max-time 15 -H " .. M.quote(ACCEPT) .. " " .. M.quote(url))
  if code ~= 0 then
    return nil, "hwc: GET " .. url .. " failed (curl exit " .. code .. ")"
  end
  local value = dkjson.decode(body)
  if type(value) ~= "table" then
    return nil, "hwc: GET " .. url .. " returned invalid JSON"
  end
  return value
end

function M.download(url, path)
  local _, code = sh("curl -fsSL --max-time 300 -o " .. M.quote(path) .. " " .. M.quote(url))
  if code ~= 0 then
    return nil, "hwc: download " .. url .. " failed (curl exit " .. code .. ")"
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

function M.sha256(path)
  local out, code = sh("shasum -a 256 " .. M.quote(path))
  local hex = code == 0 and out:match("^(" .. ("%x"):rep(64) .. ")%s")
  if not hex then return nil, "hwc: cannot checksum " .. path end
  return hex
end

return M
