-- Reads `## Key: value` metadata lines from a QuestieDB TOC. The real file is
-- ~17 MB, so parse reads it in one go and caches per process.
local lfs = require("lfs")

local M = {}

local cache = {}

local function fail(path) error("hwc: questie: cannot read " .. path, 0) end

-- Returns key, value for a `## Key: value` line (CR already stripped), else nil.
local function meta(line)
  return line:match("^##%s*([^:]-)%s*:%s*(.-)%s*$")
end

function M.parse(path)
  local attr = lfs.attributes(path)
  if not attr then fail(path) end
  local key = path .. attr.size .. attr.modification
  if cache[key] then return cache[key] end
  local f = io.open(path, "rb")
  if not f then fail(path) end
  local text = f:read("*a")
  f:close()
  local out = {}
  for line in text:gmatch("[^\n]+") do
    if line:sub(1, 2) == "##" then
      local k, v = meta((line:gsub("\r$", "")))
      if k and k ~= "" then out[k] = v end
    end
  end
  cache[key] = out
  return out
end

function M.header(path)
  local f = io.open(path, "rb")
  if not f then fail(path) end
  local out = {}
  for line in f:lines() do
    line = line:gsub("\r$", "")
    if line:sub(1, 2) == "##" then
      local k, v = meta(line)
      if k and k ~= "" then out[k] = v end
    elseif line:match("%S") and line:sub(1, 1) ~= "#" then
      break
    end
  end
  f:close()
  return out
end

return M
