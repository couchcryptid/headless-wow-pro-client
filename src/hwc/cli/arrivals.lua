-- hwc arrivals capture-script [taxi|landing|bind]: prints one /run line to paste into the WoW Forever chat
-- box, to capture the first-party facts that go into src/hwc/world/arrivals.lua. Needs no WoW-Pro folder and no
-- network. WoW runs /run with the client's Lua 5.1; the chat box takes at most 255 characters a line.
local arrivals = {}

local MAX_LINE = 255

-- Mode -> the Lua (without the /run prefix) the user pastes. One value per print, each labelled.
local SCRIPTS = {
  taxi = 'for i=1,NumTaxiNodes() do print("taxi",i,TaxiNodeName(i),TaxiNodeGetType(i)) end',
  landing = 'local m=C_Map.GetBestMapForUnit("player") '
    .. 'local x,y=C_Map.GetPlayerMapPosition(m,"player"):GetXY() print("zone",GetZoneText()) print("subzone",GetSubZoneText()) print("map",m) '
    .. 'print("x%",format("%.2f",x*100)) print("y%",format("%.2f",y*100))',
  bind = 'print("bind",GetBindLocation())',
}

local MODES = { "taxi", "landing", "bind" }

-- The /run line for mode; nil for an unknown mode. Pure.
function arrivals.script(mode)
  local body = SCRIPTS[mode]
  return body and ("/run " .. body) or nil
end

arrivals.MAX_LINE = MAX_LINE

arrivals.name = "arrivals"
arrivals.summary = "Print in-game capture scripts for arrival facts"
arrivals.usage = "capture-script [taxi|landing|bind]"
arrivals.description = "Print a /run line to paste into the WoW Forever chat box, capturing facts for src/hwc/world/arrivals.lua."
arrivals.positionals = { min = 1, max = 2, noun = "capture-script [MODE]" }
arrivals.notes = {
  "Modes:\n"
    .. "  taxi     at a flight master with the taxi map open: each node's slot, name and type.\n"
    .. "  landing  right after a flight, boat, portal or hearth arrives: zone, subzone, map and position.\n"
    .. "  bind     right after setting the hearthstone: the bind location.\n"
    .. "See the README's \"Arrival facts\" section for where the values go.",
}
arrivals.check = function(opts)
  local p = opts.positionals
  if p[1] ~= "capture-script" then return "arrivals needs capture-script (arrivals capture-script [taxi|landing|bind])" end
  if p[2] and not SCRIPTS[p[2]] then
    return "unknown capture mode: " .. p[2] .. " (one of " .. table.concat(MODES, ", ") .. ")"
  end
end

function arrivals.run(ctx)
  ctx.ui:result(arrivals.script(ctx.opts.positionals[2] or "taxi") .. "\n")
  return 0
end

return arrivals
