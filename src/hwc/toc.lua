-- Reproduces the client's file load order from a .toc and the .xml files it reaches.
local lfs = require("lfs")
local skiplist = require("hwc.skiplist")

local M = {}

local function exists(path)
  return lfs.attributes(path, "mode") ~= nil
end

local function read_file(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  if s:sub(1, 3) == "\239\187\191" then s = s:sub(4) end
  return s
end

local function dirname(rel)
  return rel:match("^(.*)/[^/]*$") or ""
end

local function join(dir, name)
  if dir == "" then return name end
  return dir .. "/" .. name
end

-- Resolve rel (relative to root) to its on-disk spelling. Each component is looked up in a
-- directory listing (exact match first, else case-insensitive) so the result is right even on
-- case-insensitive filesystems. Returns nil if not found.
local function resolve_case(root, rel)
  local cur = ""
  for comp in rel:gmatch("[^/]+") do
    local ok, iter, dir = pcall(lfs.dir, root .. "/" .. cur)
    if not ok then return nil end
    local found
    for name in iter, dir do
      if name == comp then found = name break end
      if not found and name:lower() == comp:lower() then found = name end
    end
    if not found then return nil end
    cur = join(cur, found)
  end
  return cur
end

local function normalize(rel)
  -- collapse "." and ".." so rel stays relative to the root
  local parts = {}
  for comp in rel:gmatch("[^/]+") do
    if comp == ".." then parts[#parts] = nil
    elseif comp ~= "." then parts[#parts + 1] = comp end
  end
  return table.concat(parts, "/")
end

function M.files(addon_root, toc_relpath, game)
  if addon_root:sub(1, 1) ~= "/" then addon_root = lfs.currentdir() .. "/" .. addon_root end
  local entries = {}
  local toc_dir = dirname(toc_relpath)

  local function emit(dir, name, source, stack)
    local rel = normalize(join(dir, (name:gsub("\\", "/"):gsub("%[Game%]", game))))
    local on_disk = resolve_case(addon_root, rel)
    if not on_disk then
      entries[#entries + 1] = {
        path = addon_root .. "/" .. rel, rel = rel, source = source, skipped = "missing on disk",
      }
      return
    end
    rel = on_disk
    local reason = skiplist.reason(rel)
    if rel:lower():match("%.xml$") and not reason then
      if stack[rel] then error("hwc.toc: XML include cycle at " .. rel, 0) end
      stack[rel] = true
      -- the client ignores commented-out entries, so strip <!-- ... --> before matching
      local text = read_file(addon_root .. "/" .. rel):gsub("<!%-%-.-%-%->", "")
      local xdir = dirname(rel)
      -- document order across both tags: collect (position, file) pairs
      local refs = {}
      for pos, file in text:gmatch("<Script%s+file=\"()([^\"]+)\"") do refs[#refs + 1] = { pos, file } end
      for pos, file in text:gmatch("<Include%s+file=\"()([^\"]+)\"") do refs[#refs + 1] = { pos, file } end
      table.sort(refs, function(a, b) return a[1] < b[1] end)
      for _, r in ipairs(refs) do emit(xdir, r[2], "xml", stack) end
      stack[rel] = nil
      return
    end
    entries[#entries + 1] = {
      path = addon_root .. "/" .. rel, rel = rel, source = source, skipped = reason or false,
    }
  end

  local text = read_file(addon_root .. "/" .. toc_relpath)
  -- Quirk kept faithful: entries stay in TOC order, so WoWPro_ZoneData_[Game].lua loads
  -- before WoWPro_ZoneData_Patches.lua even though Patches' header says it should be first.
  for line in text:gmatch("[^\r\n]+") do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" and line:sub(1, 1) ~= "#" then
      emit(toc_dir, line, "toc", {})
    end
  end
  return entries
end

return M
