-- Canonical JSON: object keys sorted at every nesting level, arrays in order.
-- LuaJIT randomises string hashing per process, so pairs order (and with it
-- dkjson's default key order) differs between runs; sorting restores determinism.
local dkjson = require("dkjson")

local M = {}

local function collect(v, keys, seen)
  if type(v) ~= "table" or seen[v] then return end
  seen[v] = true
  for k, child in pairs(v) do
    if type(k) == "string" then keys[k] = true end
    collect(child, keys, seen)
  end
end

function M.encode(value, opts)
  local keys, seen = {}, {}
  collect(value, keys, seen)
  local order = {}
  for k in pairs(keys) do order[#order + 1] = k end
  table.sort(order)
  local o = { keyorder = order }
  for k, v in pairs(opts or {}) do o[k] = v end
  return dkjson.encode(value, o)
end

return M
