-- Trims the Forever client table CSVs to the columns hwc reads and types them.
local csv = require("hwc.forever.csv")

local M = {}

-- Kept columns per table (spec section 1). Names stay strings; the rest are numbers.
M.TABLES = {
  { name = "TaxiNodes", keep = { "ID", "Name_lang", "ContinentID", "Flags", "Pos_0", "Pos_1" } },
  { name = "UiMap", keep = { "ID", "Name_lang", "ParentUiMapID", "Type" } },
  { name = "UiMapAssignment",
    keep = { "UiMapID", "MapID", "AreaID", "Region_0", "Region_1", "Region_3", "Region_4" } },
  { name = "AreaTable", keep = { "ID", "AreaName_lang", "ParentAreaID", "ContinentID" } },
  { name = "WMOAreaTable", keep = { "AreaName_lang", "AreaTableID" } },
}

local function find_table(name)
  for _, spec in ipairs(M.TABLES) do
    if spec.name == name then return spec end
  end
  error(("hwc: forever: unknown table %s"):format(tostring(name)), 0)
end

local function is_name(col)
  return col:match("_lang$") ~= nil
end

-- convert.table(name, text) -> { columns = {string}, rows = {{...}} }
function M.table(name, text)
  local spec = find_table(name)
  local parsed = csv.parse(text)
  local index = {}
  for i, h in ipairs(parsed.header) do index[h] = i end
  for _, col in ipairs(spec.keep) do
    if not index[col] then
      error(("hwc: forever: %s: missing column %s"):format(name, col), 0)
    end
  end
  local rows = {}
  for n, raw in ipairs(parsed.rows) do
    local row = {}
    for i, col in ipairs(spec.keep) do
      local cell = raw[index[col]]
      if cell == nil then
        error(("hwc: forever: %s: row %d: missing value for %s"):format(name, n, col), 0)
      end
      if is_name(col) then
        row[i] = cell
      else
        local v = tonumber(cell)
        if v == nil then
          error(("hwc: forever: %s: row %d: %s is not a number: %q"):format(name, n, col, cell), 0)
        end
        row[i] = v
      end
    end
    rows[n] = row
  end
  return { columns = spec.keep, rows = rows }
end

return M
