-- Path helpers so findings output never embeds machine-specific absolute paths.
-- Roots (addon checkout, catalog sources, base dir) are rewritten relative to a
-- base dir, including inside free text such as Lua stacks ("@/abs/File.lua:12:").
-- Replacement uses plain string.find because paths contain "-" and "(".
local M = {}

function M.cwd()
  return require("lfs").currentdir()
end

function M.normalize(p)
  local parts = {}
  for seg in p:gmatch("[^/]+") do
    if seg == ".." then
      parts[#parts] = nil
    elseif seg ~= "." then
      parts[#parts + 1] = seg
    end
  end
  return "/" .. table.concat(parts, "/")
end

function M.resolve(p, cwd)
  if p:sub(1, 1) == "/" then return M.normalize(p) end
  return M.normalize(cwd .. "/" .. p)
end

local function split(p)
  local parts = {}
  for seg in p:gmatch("[^/]+") do parts[#parts + 1] = seg end
  return parts
end

function M.relative(p, base)
  local a, b = split(M.normalize(p)), split(M.normalize(base))
  local i = 1
  while i <= #a and i <= #b and a[i] == b[i] do i = i + 1 end
  local out = {}
  for _ = i, #b do out[#out + 1] = ".." end
  for j = i, #a do out[#out + 1] = a[j] end
  if #out == 0 then return "." end
  return table.concat(out, "/")
end

local function boundary(c)
  return c == "" or c == "/" or c == ":" or c == "'" or c == '"'
    or c == ")" or c:match("^%s$") ~= nil
end

local function replace_root(s, root, repl)
  local out, pos = {}, 1
  while true do
    local i, j = s:find(root, pos, true)
    if not i then break end
    if boundary(s:sub(j + 1, j + 1)) then
      out[#out + 1] = s:sub(pos, i - 1)
      out[#out + 1] = repl
    else
      out[#out + 1] = s:sub(pos, j)
    end
    pos = j + 1
  end
  out[#out + 1] = s:sub(pos)
  return table.concat(out)
end

function M.rewrite(value, roots, base, cwd)
  local list, seen_root = {}, {}
  for _, r in ipairs(roots) do
    if type(r) == "string" and r ~= "" then
      local abs = M.resolve(r, cwd)
      if not seen_root[abs] then
        seen_root[abs] = true
        list[#list + 1] = abs
      end
    end
  end
  table.sort(list, function(x, y)
    if #x ~= #y then return #x > #y end
    return x < y
  end)
  local rels = {}
  for _, abs in ipairs(list) do rels[abs] = M.relative(abs, base) end

  local copies = {}
  local function walk(v)
    if type(v) == "string" then
      for _, abs in ipairs(list) do v = replace_root(v, abs, rels[abs]) end
      return v
    elseif type(v) == "table" then
      if copies[v] then return copies[v] end
      local c = {}
      copies[v] = c
      for k, child in pairs(v) do c[k] = walk(child) end
      return c
    end
    return v
  end
  return walk(value)
end

return M
