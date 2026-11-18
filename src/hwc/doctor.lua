-- `hwc doctor`: a read-only health report (design spec §4.4). Every check is
-- {id, status = ok|warn|fail, detail, fix?}; `failed` is true if any fail.
local dkjson = require("dkjson")
local json = require("hwc.json")
local home = require("hwc.questie.home")
local tocmeta = require("hwc.questie.tocmeta")
local release = require("hwc.questie.release")
local source = require("hwc.source")
local addon_info = require("hwc.addon_info")

local M = {}

local function default_has_tool(name)
  local r = os.execute("command -v '" .. name .. "' >/dev/null 2>&1")
  return r == true or r == 0 -- LuaJIT returns a status number, 5.2+ a boolean
end

local function default_require_ok(mod)
  return (pcall(require, mod))
end

local function check(id, status, detail, fix)
  return { id = id, status = status, detail = detail, fix = fix }
end

local function check_luajit(deps)
  local v = deps.luajit_version
  if v == nil then
    local jit = rawget(_G, "jit")
    v = jit and jit.version or nil
  end
  if type(v) == "string" and v:sub(1, 10) == "LuaJIT 2.1" then
    return check("luajit", "ok", v)
  end
  return check("luajit", "fail", "LuaJIT 2.1 required, found " .. tostring(v or "none"))
end

local function check_rocks(deps)
  local missing = {}
  for _, mod in ipairs({ "lfs", "dkjson" }) do
    if not deps.require_ok(mod) then missing[#missing + 1] = mod end
  end
  if #missing > 0 then
    return check("rocks", "fail", "missing: " .. table.concat(missing, ", "),
      "luarocks --lua-version 5.1 install " .. missing[1])
  end
  if not deps.require_ok("busted") then
    return check("rocks", "warn", "busted missing (only needed for specs)",
      "luarocks --lua-version 5.1 install busted")
  end
  return check("rocks", "ok", "lfs, dkjson, busted")
end

local function check_tools(deps)
  local missing = {}
  for _, tool in ipairs({ "curl", "unzip" }) do
    if not deps.has_tool(tool) then missing[#missing + 1] = tool end
  end
  if #missing > 0 then
    return check("tools", "fail", "missing: " .. table.concat(missing, ", ") .. " (init/sync need them)")
  end
  return check("tools", "ok", "curl, unzip")
end

local function check_wowpro(env)
  local start = source.start_dir(env.cwd and { pwd = env.pwd, cwd = env.cwd } or nil)
  local dir = source.find(start)
  if not dir then
    return check("wowpro", "warn", "not in a WoW-Pro folder", "cd into your WoW-Pro folder for run/matrix")
  end
  local info = addon_info.read(dir)
  local detail = dir
  if info.git then
    detail = dir .. ": " .. info.branch .. " @ " .. info.commit:sub(1, 7) .. (info.dirty and " (dirty)" or "")
  end
  return check("wowpro", "ok", detail)
end

local function sync_fix(tag) return "hwc sync questie --tag " .. tag end

-- Appends the QuestieDB checks to out; the dependent ones only when the
-- active install is intact.
local function questie_checks(env, deps, out)
  local root, rerr = home.root({ hwc_home = env.hwc_home, home = env.home })
  if not root then
    out[#out + 1] = check("questie", "fail", rerr)
    return
  end
  local dir, derr = home.active_dir(root)
  if not dir then
    local tag = derr:match("^broken: (.+)$")
    out[#out + 1] = check("questie", "fail", derr, tag and sync_fix(tag) or "hwc init")
    return
  end
  local tag = home.active(root)
  local okh, header = pcall(tocmeta.header, dir .. "/QuestieDB/QuestieDB_Forever.toc")
  if not okh then header = {} end
  local rel = home.read_release(root, tag)
  local build = (rel and rel.build) or header["X-BUILD-COMMIT"]
  out[#out + 1] = check("questie", "ok",
    tag .. " (build " .. (build and tostring(build):sub(1, 7) or "unknown") .. ") at " .. dir)

  if header["X-Flavor"] == "Forever" and header["X-Mode"] == "baked" then
    out[#out + 1] = check("questie-toc", "ok", "flavor Forever, mode baked")
  else
    out[#out + 1] = check("questie-toc", "fail",
      ("flavor %s, mode %s (expected Forever, baked)"):format(
        tostring(header["X-Flavor"]), tostring(header["X-Mode"])),
      sync_fix(tag))
  end

  local range, cerr = release.contract_range(dir)
  if not range then
    out[#out + 1] = check("questie-contract", "fail", cerr)
  else
    local ok, msg = release.contract_ok(range)
    if ok then
      out[#out + 1] = check("questie-contract", "ok",
        ("contract %d-%d includes %d"):format(range.min, range.max, release.SUPPORTED_CONTRACT))
    else
      out[#out + 1] = check("questie-contract", "fail", msg)
    end
  end

  local get_json = deps.get_json or require("hwc.questie.http").get_json
  local sel, serr = release.select(get_json, {})
  if not sel then
    out[#out + 1] = check("questie-upstream", "warn", "could not check upstream: " .. tostring(serr))
  elseif sel.tag == tag then
    out[#out + 1] = check("questie-upstream", "ok", "up to date (" .. tag .. ")")
  else
    out[#out + 1] = check("questie-upstream", "warn", tag .. " → " .. sel.tag .. " available", "hwc sync questie")
  end
end

local function check_supplement(deps)
  local path = deps.supplement_path or require("hwc.config").load({}).catalog.supplement
  local f = io.open(path, "rb")
  if not f then
    return check("supplement", "warn", "absent (optional): " .. path)
  end
  local text = f:read("*a")
  f:close()
  local obj, _, jerr = dkjson.decode(text)
  if jerr or type(obj) ~= "table" then
    return check("supplement", "fail", path .. ": invalid JSON" .. (jerr and (": " .. jerr) or ""))
  end
  local quests = obj.quests
  if quests ~= nil and type(quests) ~= "table" then
    return check("supplement", "fail", path .. ": quests is not an object")
  end
  local bad = {}
  for id, entry in pairs(quests or {}) do
    if type(entry) ~= "table" or type(entry.source) ~= "string" or entry.source == "" then
      bad[#bad + 1] = tostring(id)
    end
  end
  if #bad > 0 then
    table.sort(bad)
    return check("supplement", "fail", path .. ": quest " .. table.concat(bad, ", ") .. " has no source")
  end
  return check("supplement", "ok", "present, valid: " .. path)
end

-- env = {pwd, cwd, home, hwc_home}; deps = {get_json, has_tool, require_ok}
-- (plus supplement_path and luajit_version overrides for specs).
function M.run(env, deps)
  env, deps = env or {}, deps or {}
  deps.has_tool = deps.has_tool or default_has_tool
  deps.require_ok = deps.require_ok or default_require_ok
  local checks = {
    check_luajit(deps),
    check_rocks(deps),
    check_tools(deps),
    check_wowpro(env),
  }
  questie_checks(env, deps, checks)
  checks[#checks + 1] = check_supplement(deps)
  local failed = false
  for _, c in ipairs(checks) do
    if c.status == "fail" then failed = true end
  end
  return { checks = checks, failed = failed }
end

local LABEL = { ok = "ok  ", warn = "warn", fail = "FAIL" }

function M.text(report)
  local lines = {}
  for _, c in ipairs(report.checks) do
    local line = LABEL[c.status] .. " " .. c.id .. ": " .. c.detail
    if c.fix then line = line .. " → " .. c.fix end
    lines[#lines + 1] = line
  end
  return table.concat(lines, "\n") .. "\n"
end

function M.json(report)
  return json.encode(report)
end

return M
