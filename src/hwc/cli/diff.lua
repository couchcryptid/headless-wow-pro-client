-- hwc diff OLD.json NEW.json [--json]: compare two findings files. Needs no
-- WoW-Pro folder. Exit 0 when nothing is new, 1 when something is (or a run
-- stopped early), 2 when the input can't be compared.
local lfs = require("lfs")

local decl = {
  name = "diff",
  summary = "Compare two findings files: fixed, new, partly fixed",
  usage = "OLD.json NEW.json [--json]",
  description = "Compare two findings files by finding id, on the characters both runs share:\n"
    .. "what was fixed, what is new, what was fixed for some characters only and what spread.",
  positionals = { min = 2, max = 2, noun = "files" },
  options = {
    { name = "json", flag = true, help = "Print the comparison as JSON." },
  },
  notes = {
    "Exit status: 0 when nothing is new, 1 when something is new or spread or a run\n"
      .. "stopped early, 2 when the files can't be compared.",
  },
}

local function is_table(v) return type(v) == "table" end

-- Why a format-2 document's body can't be read, or nil. Only the parts
-- diff.compare and diff.render walk are checked; format is compare's to judge.
local function body_problem(d)
  if d.format ~= 2 then return nil end
  local h = d.header
  if h ~= nil and not is_table(h) then return "header is not an object" end
  local m = h and h.matrix
  if m ~= nil and not is_table(m) then return "header.matrix is not an object" end
  if m and m.combos ~= nil and not is_table(m.combos) then return "header.matrix.combos is not a list" end
  if d.findings ~= nil and not is_table(d.findings) then return "findings is not a list" end
  local severity = require("hwc.findings.text").SEVERITY
  for i, f in ipairs(d.findings or {}) do
    if not is_table(f) then return "finding " .. i .. " is not an object" end
    if f.combos ~= nil and not is_table(f.combos) then return "finding " .. i .. " has combos that are not a list" end
    if f.severity ~= nil and not severity[f.severity] then
      return "finding " .. i .. " has an unknown severity " .. tostring(f.severity)
    end
  end
end

-- The decoded document at path, or nil and a message.
local function read(path)
  if path:lower():match("%.html$") then return nil, path .. " is the report page; use the .json beside it" end
  if lfs.attributes(path, "mode") ~= "file" then return nil, "cannot read " .. path end
  local f = io.open(path, "r")
  if not f then return nil, "cannot read " .. path end
  local text = f:read("*a")
  f:close()
  local ok, decoded = pcall(require("dkjson").decode, text)
  if not ok or not is_table(decoded) then return nil, path .. " is not valid JSON" end
  local problem = body_problem(decoded)
  if problem then return nil, path .. " is not a valid findings file: " .. problem end
  return decoded
end

function decl.run(ctx)
  local usage_error = require("hwc.cli.commands").usage_error
  local docs = {}
  for i, path in ipairs(ctx.opts.positionals) do
    local d, err = read(path)
    if not d then return usage_error(ctx.ui, err, "diff") end
    docs[i] = d
  end
  local diff = require("hwc.findings.diff")
  local ok, result, cerr, text, code = pcall(function()
    local r, e = diff.compare(docs[1], docs[2])
    if not r then return nil, e end
    local body = ctx.opts.json and (require("hwc.json").encode(r, { indent = true }) .. "\n") or diff.render(r)
    return r, nil, body, diff.exit_code(r)
  end)
  if not ok then
    -- Inputs were checked above, so this is a bug in hwc, not in the files.
    local first = tostring(result):match("^[^\n]*"):gsub("^[^:]*:%d+: ", "")
    ctx.ui:error("internal error: " .. first .. " (please report it)")
    return 2
  end
  if not result then return usage_error(ctx.ui, cerr, "diff") end
  ctx.ui:result(text)
  return code
end

return decl
