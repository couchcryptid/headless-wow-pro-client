-- RFC 4180 CSV reader for the wago.tools DB2 exports.
local M = {}

local function fail(line, problem)
  error(("hwc: csv: line %d: %s"):format(line, problem), 0)
end

-- Splits text into records of string fields. Quoted fields may hold commas,
-- newlines and "" escapes; CRLF and LF both end a record.
local function records(text)
  local out, row, line = {}, {}, 1
  local pos, len = 1, #text
  while pos <= len do
    local field
    if text:sub(pos, pos) == '"' then
      local start_line = line
      local parts = {}
      pos = pos + 1
      while true do
        local q = text:find('"', pos, true)
        if not q then fail(start_line, "unterminated quote") end
        local chunk = text:sub(pos, q - 1)
        parts[#parts + 1] = chunk
        for _ in chunk:gmatch("\n") do line = line + 1 end
        if text:sub(q + 1, q + 1) == '"' then
          parts[#parts + 1] = '"'
          pos = q + 2
        else
          pos = q + 1
          break
        end
      end
      field = table.concat(parts)
      local nxt = text:sub(pos, pos)
      if nxt ~= "" and nxt ~= "," and nxt ~= "\n" and nxt ~= "\r" then
        fail(line, "unexpected text after closing quote")
      end
    else
      local stop = text:find("[,\r\n]", pos) or (len + 1)
      field = text:sub(pos, stop - 1)
      pos = stop
    end
    row[#row + 1] = field
    local c = text:sub(pos, pos)
    if c == "," then
      pos = pos + 1
      if pos > len then row[#row + 1] = "" end
    else
      if c == "\r" then pos = pos + 1 end
      if text:sub(pos, pos) == "\n" then pos = pos + 1 end
      if c ~= "" then line = line + 1 end
      out[#out + 1] = row
      row = {}
    end
  end
  if #row > 0 then out[#out + 1] = row end
  return out
end

-- csv.parse(text) -> { header = {string}, rows = {{string}} }
function M.parse(text)
  local recs = records(text)
  local header = table.remove(recs, 1) or {}
  return { header = header, rows = recs }
end

return M
