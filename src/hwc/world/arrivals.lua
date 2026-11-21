-- First-party arrival facts (design spec 2026-11-19-arrival-emulation-design.md, section 2).
-- Hand-checked in game, never read from the guide or from Wowhead. Every entry carries
-- `checked`: who saw it and when ("user, 2026-11-19: ..."); a bare "unverified" marks a guess.
-- Positions (x, y) are percent, as in the game's coordinate readout; convert to fractions
-- where they are consumed. Captures (`hwc arrivals capture-script`) fill the empty lists.
local arrivals = {}

-- node name -> { subzone, checked }: the subzone a taxi node's arrival lands in.
arrivals.subzones = {}

-- { npc, bind, zone, subzone, map_id, x, y, checked }: innkeepers whose hearth binds there.
arrivals.inns = {}

-- { kind = "boat"|"portal"|"teleport", from = {map_id,x,y}|nil, spell = id|nil,
--   zone, subzone, map_id, x, y, checked }: where a crossing leaves the player.
arrivals.crossings = {}

-- race key (Player.RACES) -> the capital taxi node name, as written in Forever's
-- TaxiNodes (build 1.60.1.70959).
-- checked = "user, 2026-11-19: capital node learned; names from Forever TaxiNodes 1.60.1.70959"
-- false = known to start with no node learned; a race with no entry (nil) is unknown,
-- a start-node-unknown notice (spec section 11).
-- Skyborne: the hub Valanaar has no flight master (no Valanaar node in Forever TaxiNodes).
-- SkyborneAlliance: user, 2026-11-20: High Order Skyborne start with Stormwind learned (in game).
-- SkyborneHorde: unverified — assumed Thunder Bluff, a standard Horde capital (user, 2026-11-20);
-- confirm in game.
-- Future `crossings` to capture in game (no entries until the landings are captured): the
-- Skyborne leave Valanaar's harbour by skycutter ship, Alliance to Dalaran from 64.9, 80.9
-- and Horde to Thunder Bluff from 58.2, 79.5 (user, 2026-11-19).
arrivals.start_nodes = {
  Dwarf    = "Ironforge, Dun Morogh",
  Gnome    = "Ironforge, Dun Morogh",
  Human    = "Stormwind, Elwynn",
  NightElf = "Rut'theran Village, Teldrassil",
  Orc      = "Orgrimmar, Durotar",
  Troll    = "Orgrimmar, Durotar",
  Tauren   = "Thunder Bluff, Mulgore",
  Undead   = "Undercity, Tirisfal",
  SkyborneAlliance = "Stormwind, Elwynn",
  SkyborneHorde    = "Thunder Bluff, Mulgore", -- unverified, see above
}

-- race key -> { bind, zone, subzone, map_id, x, y, checked }: the starting hearth bind.
arrivals.start_bind = {}

-- How the taxi map lists nodes; not yet checked in game.
arrivals.taxi_map = { lists_undiscovered = true, order = "id", checked = "unverified" }

local function nonempty_string(v) return type(v) == "string" and v ~= "" end

local REQUIRED = {
  subzone = { subzone = "string" },
  inn = { npc = "number", bind = "string", zone = "string", subzone = "string",
    map_id = "number", x = "number", y = "number" },
  crossing = { kind = "string", zone = "string", subzone = "string",
    map_id = "number", x = "number", y = "number" },
  start_bind = { bind = "string", zone = "string", subzone = "string",
    map_id = "number", x = "number", y = "number" },
}

local CROSSING_KINDS = { boat = true, portal = true, teleport = true }

-- Why an entry of `kind` (subzone, inn, crossing, start_bind) is unusable, or nil.
function arrivals.problem(kind, entry)
  local req = REQUIRED[kind]
  if not req then return "unknown arrival kind: " .. tostring(kind) end
  if type(entry) ~= "table" then return kind .. " entry is not a table" end
  local names = {}
  for field in pairs(req) do names[#names + 1] = field end
  table.sort(names)
  for _, field in ipairs(names) do
    local want, v = req[field], entry[field]
    -- subzone may be "": GetSubZoneText() returns that where no subzone applies.
    if type(v) ~= want or (want == "string" and v == "" and field ~= "subzone") then
      return kind .. " needs " .. want .. " " .. field
    end
  end
  if kind == "crossing" then
    if not CROSSING_KINDS[entry.kind] then
      return "crossing kind must be boat, portal or teleport"
    end
    -- Spec section 6: a teleport is found by its spell, a boat or portal by its departure.
    if entry.kind == "teleport" then
      if type(entry.spell) ~= "number" then return "teleport crossing needs number spell" end
    else
      local f = entry.from
      if type(f) ~= "table" or type(f.map_id) ~= "number" or type(f.x) ~= "number" or type(f.y) ~= "number" then
        return entry.kind .. " crossing needs from = { map_id, x, y } (numbers)"
      end
    end
  end
  if not nonempty_string(entry.checked) then
    return kind .. " needs checked (who saw it, and when)"
  end
  return nil
end

return arrivals
