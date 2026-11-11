-- Loader for the pinned QuestieDB Forever data files (design spec §6).
--
-- Each file is third-party Lua. It runs as a chunk inside a sandbox env that
-- holds only QuestieDB, a QuestieLoader that hands out module tables, and the
-- pure Lua 5.1 builtins; any other global read (io, os, require, load*, ...)
-- raises an error naming the file. The big row tables live in
-- `QuestieDB.<x>Data` as a string of Lua source ("return {...}"), which is run
-- in a second, empty env. Field order is taken from each file's own
-- `QuestieDB.<x>Keys` table, never hard-coded.
local M = {}

local DATA_FILES = {
  { kind = "quest", file = "foreverQuestDB.lua", keys = "questKeys", data = "questData" },
  { kind = "npc", file = "foreverNpcDB.lua", keys = "npcKeys", data = "npcData" },
  { kind = "item", file = "foreverItemDB.lua", keys = "itemKeys", data = "itemData" },
  { kind = "object", file = "foreverObjectDB.lua", keys = "objectKeys", data = "objectData" },
}
-- Order matters: later rows win, so the traces file comes after the classic one.
local XP_FILES = { "xpDB-classic.lua", "xpDB-traces.lua" }

local SAFE = { "pairs", "ipairs", "next", "type", "tostring", "tonumber", "select", "unpack", "string", "table", "math" }

local function fail(file, msg)
  error("hwc: catalog: " .. file .. ": " .. tostring(msg), 0)
end

local function read(path)
  local f = io.open(path, "rb")
  if not f then fail(path, "cannot read file") end
  local text = f:read("*a")
  f:close()
  return text
end

local function strict_env(base)
  local env = base or {}
  return setmetatable(env, {
    __index = function(_, name) error("undefined global '" .. tostring(name) .. "'", 2) end,
  })
end

local function run(path, text, env)
  local fn, err = loadstring(text, "@" .. path)
  if not fn then fail(path, err) end
  setfenv(fn, env)
  local ok, res = pcall(fn)
  if not ok then fail(path, res) end
  return res
end

-- Fresh env per file; `modules` is shared so the xp files see the same QuestXP.
local function file_env(modules)
  local env = { QuestieDB = modules.QuestieDB }
  for _, name in ipairs(SAFE) do env[name] = _G[name] end
  env.QuestieLoader = {
    ImportModule = function(_, name)
      modules[name] = modules[name] or {}
      return modules[name]
    end,
  }
  return strict_env(env)
end

-- LuaJIT rejects a chunk with more than 65536 constants, which the big row
-- tables exceed. Rows are one per line ("[id] = {...},"), so run the data
-- string in batches of whole rows (a line not starting a row continues the
-- previous one) and merge the results.
local BATCH_ROWS = 1500

local function run_rows(path, text)
  local body = text:match("^%s*return%s*{(.*)}%s*$")
  if not body then fail(path, "data string is not a 'return {...}' table") end
  local rows, merged, count = {}, {}, 0
  local function flush()
    if count == 0 then return end
    local part = run(path, "return {" .. table.concat(rows, "\n") .. "}", strict_env({}))
    if type(part) ~= "table" then fail(path, "data batch did not return a table") end
    for id, row in pairs(part) do merged[id] = row end
    rows, count = {}, 0
  end
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do
    if line:match("^%s*%[%d+%]%s*=") then
      if count >= BATCH_ROWS then flush() end
      rows[#rows + 1] = line
      count = count + 1
    elseif #rows > 0 then
      rows[#rows] = rows[#rows] .. "\n" .. line
    end
  end
  flush()
  return merged
end

-- id -> record with named fields, decoded on first access from the positional row.
local function decoder(rows, keys)
  local cache = {}
  return setmetatable({}, {
    __index = function(_, id)
      if cache[id] then return cache[id] end
      local row = rows[id]
      if not row then return nil end
      local rec = { id = id }
      for name, idx in pairs(keys) do rec[name] = row[idx] end
      cache[id] = rec
      return rec
    end,
  })
end

local function parse_sums(dir)
  local f = io.open(dir .. "/SHA256SUMS", "r")
  if not f then return nil end
  local sums = {}
  for line in f:lines() do
    local hash, name = line:match("^(%x+)%s+%*?(.+)$")
    if hash then sums[name] = hash end
  end
  f:close()
  return sums
end

function M.load(dir)
  local modules = { QuestieDB = {} }
  local keys, rows = {}, {}
  for _, spec in ipairs(DATA_FILES) do
    local path = dir .. "/" .. spec.file
    local qdb = {}
    modules.QuestieDB = qdb
    run(path, read(path), file_env(modules))
    if type(qdb[spec.keys]) ~= "table" then fail(path, spec.keys .. " not defined") end
    if type(qdb[spec.data]) ~= "string" then fail(path, spec.data .. " not defined") end
    keys[spec.kind] = qdb[spec.keys]
    rows[spec.kind] = run_rows(path, qdb[spec.data])
    if type(rows[spec.kind]) ~= "table" then fail(path, spec.data .. " did not return a table") end
  end

  local xp_modules = { QuestieDB = {} }
  for _, file in ipairs(XP_FILES) do
    local path = dir .. "/" .. file
    run(path, read(path), file_env(xp_modules))
  end
  local xp = (xp_modules.QuestXP or {}).db or {}

  return {
    quests = decoder(rows.quest, keys.quest),
    npcs = decoder(rows.npc, keys.npc),
    items = decoder(rows.item, keys.item),
    objects = decoder(rows.object, keys.object),
    rows = rows,
    xp = xp,
    keys = keys,
    sha256 = parse_sums(dir),
  }
end

return M
