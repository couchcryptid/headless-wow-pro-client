-- Declaration-driven argument parsing. Pure: no io or os. Error messages carry
-- no "hwc: " prefix; the dispatcher adds that and the "see ... --help" line.
local args = {}

-- Pulls -h/--help, --version, -q/-v out of argv. The first remaining
-- non-option word is the command; rest is everything else, in order.
function args.globals(argv)
  local g = { rest = {}, level = "normal" }
  local ended = false
  for _, a in ipairs(argv) do
    if ended then
      g.rest[#g.rest + 1] = a
    elseif a == "--" then
      ended = true
      g.rest[#g.rest + 1] = a
    elseif a == "-h" or a == "--help" then
      g.help = true
    elseif a == "--version" then
      g.version = true
    elseif a == "-q" or a == "--quiet" then
      g.level = "quiet"
    elseif a == "-v" or a == "--verbose" then
      g.level = "verbose"
    elseif not g.command and a:sub(1, 1) ~= "-" then
      g.command = a
    else
      g.rest[#g.rest + 1] = a
    end
  end
  return g
end

local function distance(a, b)
  local prev = {}
  for j = 0, #b do
    prev[j] = j
  end
  for i = 1, #a do
    local cur = { [0] = i }
    for j = 1, #b do
      local cost = a:sub(i, i) == b:sub(j, j) and 0 or 1
      cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
    end
    prev = cur
  end
  return prev[#b]
end

-- Nearest name within edit distance 2; ties go to the earlier name.
function args.suggest(word, names)
  local best, best_d = nil, 3
  for _, name in ipairs(names) do
    local d = distance(word, name)
    if d < best_d then
      best, best_d = name, d
    end
  end
  return best
end

local function find_option(decl, name)
  for _, o in ipairs(decl.options or {}) do
    if o.name == name then
      return o
    end
  end
end

-- Canonical spelling of value among the option's choices, or nil, message.
local function canonical_choice(opt, value)
  local list = opt.choices()
  local lower = value:lower()
  for _, c in ipairs(list) do
    if c:lower() == lower then
      return c
    end
  end
  local noun = (opt.metavar or opt.name):lower()
  return nil,
    string.format("--%s %s is not a %s; %ss: %s", opt.name, value, noun, noun, table.concat(list, ", "))
end

local function store(opts, opt, value)
  local v = value
  if opt.choices then
    local c, err = canonical_choice(opt, value)
    if not c then
      return err
    end
    v = c
  end
  if opt.validate then
    local c, err = opt.validate(v)
    if c == nil then
      return err
    end
    v = c
  end
  if opt.filter then
    opts.filters[#opts.filters + 1] = { kind = opt.name, raw = v }
  end
  opts[opt.name] = v
end

local function count_error(decl, n)
  local p = decl.positionals or { min = 0, max = 0 }
  if n >= p.min and n <= p.max then
    return nil
  end
  local want = p.min == p.max and tostring(p.min) or (p.min .. "-" .. p.max)
  return string.format("hwc %s needs %s %s, got %d", decl.name, want, p.noun or "arguments", n)
end

function args.parse(decl, rest)
  local opts = { positionals = {}, filters = {} }
  local i, n = 1, #rest
  local only_positional = false
  while i <= n do
    local a = rest[i]
    if only_positional or a:sub(1, 2) ~= "--" then
      opts.positionals[#opts.positionals + 1] = a
    elseif a == "--" then
      only_positional = true
    else
      local name, inline = a:match("^%-%-([^=]+)=(.*)$")
      name = name or a:sub(3)
      local opt = find_option(decl, name)
      if not opt then
        return nil, string.format("unknown option --%s for hwc %s", name, decl.name)
      end
      if opt.flag then
        if inline then
          return nil, string.format("--%s takes no value", name)
        end
        opts[name] = true
      else
        local value = inline
        if value == nil then
          value = rest[i + 1]
          if value == nil or value:sub(1, 2) == "--" then
            return nil, string.format("--%s needs a value", name)
          end
          i = i + 1
        end
        local err = store(opts, opt, value)
        if err then
          return nil, err
        end
      end
    end
    i = i + 1
  end
  for _, opt in ipairs(decl.options or {}) do
    if opt.required and opts[opt.name] == nil then
      return nil, "missing --" .. opt.name
    end
  end
  local cerr = count_error(decl, #opts.positionals)
  if cerr then
    return nil, cerr
  end
  if decl.check then
    local err = decl.check(opts)
    if err then
      return nil, err
    end
  end
  return opts
end

return args
