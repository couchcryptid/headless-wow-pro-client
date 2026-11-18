-- Help text rendered from command declarations. Pure: no io or os.
local help = {}

local INLINE_CHOICES = 5
local MIN_COLUMN = 8

local GLOBALS = {
  { "-h, --help", "Show help." },
  { "--version", "Print the version." },
  { "-q, --quiet", "Print results only." },
  { "-v, --verbose", "Print progress detail." },
}

local function pad(s, width)
  return s .. string.rep(" ", width - #s)
end

local function option_label(opt)
  if opt.flag then
    return "--" .. opt.name
  end
  return "--" .. opt.name .. " " .. (opt.metavar or "VALUE")
end

local function option_text(opt)
  local parts = {}
  if opt.help then
    parts[#parts + 1] = opt.help
  end
  if opt.required then
    parts[#parts + 1] = "(required)"
  end
  if opt.default_text then
    parts[#parts + 1] = "(default: " .. opt.default_text .. ")"
  end
  if opt.choices then
    local list = opt.choices()
    if #list <= INLINE_CHOICES then
      parts[#parts + 1] = "One of: " .. table.concat(list, ", ") .. "."
    elseif opt.see then
      parts[#parts + 1] = "See " .. opt.see .. "."
    end
  elseif opt.see then
    parts[#parts + 1] = "See " .. opt.see .. "."
  end
  return table.concat(parts, " ")
end

local function column(rows)
  local width = MIN_COLUMN
  for _, r in ipairs(rows) do
    width = math.max(width, #r[1])
  end
  return width + 2
end

local function render_rows(out, rows)
  local width = column(rows)
  for _, r in ipairs(rows) do
    if r[2] == "" then
      out[#out + 1] = "  " .. r[1]
    else
      out[#out + 1] = "  " .. pad(r[1], width) .. r[2]
    end
  end
end

function help.command(decl)
  local usage = decl.usage and (" " .. decl.usage) or ""
  local out = { "Usage: hwc " .. decl.name .. usage, "" }
  out[#out + 1] = decl.description or decl.summary
  local rows = {}
  for _, opt in ipairs(decl.options or {}) do
    rows[#rows + 1] = { option_label(opt), option_text(opt) }
  end
  if #rows > 0 then
    out[#out + 1] = ""
    out[#out + 1] = "Options:"
    render_rows(out, rows)
  end
  for _, note in ipairs(decl.notes or {}) do
    out[#out + 1] = ""
    out[#out + 1] = note
  end
  return table.concat(out, "\n") .. "\n"
end

function help.usage(decls)
  local out = { "Usage: hwc <command> [options]", "", "Commands:" }
  local rows = {}
  for _, d in ipairs(decls) do
    if not d.hidden then
      rows[#rows + 1] = { d.name, d.summary or "" }
    end
  end
  render_rows(out, rows)
  out[#out + 1] = ""
  out[#out + 1] = "Global options:"
  render_rows(out, GLOBALS)
  out[#out + 1] = ""
  out[#out + 1] = "Run hwc help <command> for its options."
  return table.concat(out, "\n") .. "\n"
end

return help
