-- S3-style include/exclude selection of WoW-Pro guide files (guide-filters
-- design). Globs: * any run (including "/"), ? one char, [abc] / [!abc] classes.
-- Everything else is literal, so Lua pattern magic is escaped on translation.
local lfs = require("lfs")
local paths = require("hwc.paths")

local M = {}

local MAGIC = "[%^%$%(%)%%%.%[%]%*%+%-%?]"

local function escape_literal(c)
  return (c:gsub(MAGIC, "%%%0"))
end

-- Glob -> anchored Lua pattern.
local function translate(glob)
  local out, i, n = { "^" }, 1, #glob
  while i <= n do
    local c = glob:sub(i, i)
    if c == "*" then
      out[#out + 1] = ".*"
    elseif c == "?" then
      out[#out + 1] = "."
    elseif c == "[" then
      local j = i + 1
      local negate = glob:sub(j, j) == "!"
      if negate then j = j + 1 end
      local first = j
      -- a "]" directly after "[" or "[!" is a member, not the terminator
      local close = glob:find("]", first + 1, true)
      if close then
        local body = glob:sub(first, close - 1)
        -- escape every Lua class-magic char except "-", which keeps range meaning
        body = body:gsub("[%^%%%]%[]", "%%%0")
        out[#out + 1] = "[" .. (negate and "^" or "") .. body .. "]"
        i = close
      else
        out[#out + 1] = "%["
      end
    else
      out[#out + 1] = escape_literal(c)
    end
    i = i + 1
  end
  out[#out + 1] = "$"
  return table.concat(out)
end

function M.compile(glob)
  local pat = translate(glob)
  return function(rel)
    return rel:find(pat) ~= nil
  end
end

-- Wrap each glob character of a literal path in [ ] so it matches itself.
local function escape_glob(s)
  return (s:gsub("[%*%?%[%]]", "[%0]"))
end

local function starts_with_path(p)
  return p:sub(1, 2) == "./" or p:sub(1, 3) == "../" or p:sub(1, 1) == "/"
end

function M.resolve(pattern, root, start)
  if not starts_with_path(pattern) then return pattern end
  root = paths.normalize(root)
  local abs = paths.resolve(pattern, start)
  local rel
  if abs == root then
    rel = ""
  elseif abs:sub(1, #root + 1) == root .. "/" then
    rel = abs:sub(#root + 2)
  else
    return nil, "hwc: pattern " .. pattern .. " is outside the WoW-Pro folder " .. root
  end

  local mode = lfs.attributes(abs, "mode")
  if mode == "directory" then
    if rel == "" then return "*" end
    return escape_glob(rel) .. "/*"
  elseif mode == "file" then
    return escape_glob(rel)
  end
  -- Not on disk: keep it as a glob relative to the root.
  if rel == "" then return "*" end
  return rel
end

function M.select(files, list)
  local included = {}
  for _, f in ipairs(files) do included[f] = true end
  local unmatched = {}
  for _, filter in ipairs(list) do
    local match = M.compile(filter.pattern)
    local hit = false
    for _, f in ipairs(files) do
      if match(f) then
        hit = true
        included[f] = (filter.kind == "include") or nil
      end
    end
    if filter.kind == "include" and not hit then
      unmatched[#unmatched + 1] = filter.raw
    end
  end
  return included, unmatched
end

return M
