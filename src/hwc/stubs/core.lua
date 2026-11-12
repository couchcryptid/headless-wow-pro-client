-- Load-time WoW client API for the Forever flavor (TOC 16001). These model
-- the client, never what the addon "should" see.
local M = {}

-- Client global ERR_NEWTAXIPATH (quoted at WoWPro_AutoComplete.lua:96); AutoCompleteGetFP
-- compares UI_INFO_MESSAGE's msg to it (:98). The driver fires the same string.
M.ERR_NEWTAXIPATH = "New flight path discovered!"

local function read_toc_field(cfg, name, field)
  local f = io.open(cfg.addon_path .. "/" .. name .. "/" .. name .. ".toc", "rb")
  if not f then return nil end
  local value
  for line in f:lines() do
    local k, v = line:match("^##%s*([^:]+):%s*(.-)%s*$")
    if k == field then value = v; break end
  end
  f:close()
  return value
end

-- Namespace tables record reads of unstubbed fields as "<ns>.<field>" misses.
local function trap(sb, ns, tbl)
  return setmetatable(tbl, { __index = function(_, field)
    local key = ns .. "." .. tostring(field)
    if not sb.missing[key] then
      sb.missing[key] = true
      sb.missing_order[#sb.missing_order + 1] = key
    end
    return nil
  end })
end

M.trap = trap

function M.install(sb, cfg)
  local env, clock, frames = sb.env, sb.clock, sb.frames
  -- Every player-facing stub reads sb.world.player when called, never a captured copy.
  sb.world = sb.world or require("hwc.world").new(cfg, nil, clock)
  local function player() return sb.world.player end

  -- AceTimer-3.0.lua:30 captures GetTime and C_Timer.After as upvalues at load, so install before any library
  env.GetTime = function() return clock:now() end
  -- The client reports a timer callback's error to the error handler and keeps running.
  -- frames.where tags the error's origin for the handler (sandbox.lua)
  local function fire(fn, ...)
    local prev = frames.where
    frames.where = "timer"
    xpcall(fn, env.geterrorhandler(), ...)
    frames.where = prev
  end
  local function new_timer(delay, fn)
    local t = { cancelled = false }
    function t:Cancel() self.cancelled = true end
    function t:IsCancelled() return self.cancelled end
    clock:after(delay, function() if not t.cancelled then fire(fn, t) end end)
    return t
  end
  env.C_Timer = trap(sb, "C_Timer", {
    After = function(d, f) clock:after(d, function() fire(f) end) end,
    NewTimer = new_timer,
    NewTicker = function(d, f, iterations)
      local t = { cancelled = false }
      local count = 0
      function t:Cancel() self.cancelled = true end
      function t:IsCancelled() return self.cancelled end
      local function arm()
        clock:after(d, function()
          if t.cancelled then return end
          count = count + 1
          fire(f, t)
          if iterations and count >= iterations then t.cancelled = true end
          if not t.cancelled then arm() end
        end)
      end
      arm()
      return t
    end,
  })

  -- Frames: WoW publishes named frames as globals. AceAddon-3.0.lua:38, AceEvent-3.0.lua:23, AceDB-3.0.lua:57 (CreateFrame); WoWPro.lua:56-58 (DEFAULT_CHAT_FRAME:AddMessage)
  env.CreateFrame = function(ftype, name, parent, template)
    local f = frames:create(ftype, name, parent, template)
    if name then env[name] = f end
    return f
  end
  env.UIParent = env.CreateFrame("Frame", "UIParent")
  env.ChatFrame1 = env.CreateFrame("Frame", "ChatFrame1")
  env.DEFAULT_CHAT_FRAME = env.ChatFrame1
  env.ChatFrame1.AddMessage = function(_, msg) sb.chat[#sb.chat + 1] = msg end

  -- WoWPro_Config.lua:1402 (GetBuildInfo); WoWPro.lua:12 and WoWPro_RowUpdate.lua:1306 (GetAddOnMetadata)
  env.GetBuildInfo = function() return "1.16.1", "0", "Nov 1 2026", sb.cfg and sb.cfg.toc_version or 16001 end
  local meta_cache = {}
  local function get_meta(name, field)
    meta_cache[name] = meta_cache[name] or {}
    local c = meta_cache[name]
    if c[field] == nil then c[field] = read_toc_field(cfg, name, field) or false end
    return c[field] or nil
  end
  env.GetAddOnMetadata = get_meta
  env.C_AddOns = trap(sb, "C_AddOns", { GetAddOnMetadata = get_meta })

  -- WoWPro_RowUpdate.lua:1302-1314 and WoWPro_Parser.lua:1075 (UnitName/UnitClass/UnitRace/GetRealmName; AceDB-3.0.lua:254-258 at load)
  -- WoWPro.lua:285 (UnitFactionGroup), :267 (UnitLevel/UnitXP), :979 (UnitXPMax); WoWPro_Broker.lua:3131 (UnitSex); WoWPro_RowUpdate.lua:1311 (GetRealmName)
  env.UnitName = function() return player().name end
  env.GetRealmName = function() return player().realm end
  env.UnitClass = function() local p = player(); return p.class, p.class_token end
  env.UnitRace = function() local p = player(); return p.race, p.race_token end
  env.UnitFactionGroup = function() local p = player(); return p.faction, p.faction end
  env.UnitSex = function() return player().sex end
  env.UnitLevel = function() return player().level end
  env.UnitXP = function() return player().xp end
  env.UnitXPMax = function() return player():xp_max() end

  -- WoWPro_CompatUtil.lua:333-338 (C_Item_GetItemCount prefers the GetItemCount global); WoWPro_Broker.lua:940 and :953 pass item names from step text
  local function item_count(id_or_name) return player():item_count(id_or_name) end
  env.GetItemCount = item_count
  env.C_Item = trap(sb, "C_Item", { GetItemCount = item_count })
  -- WoWPro_CompatUtil.lua:325-331 (C_Item_GetItemInfo prefers the GetItemInfo global). Read by
  -- AutoComplete.lua:210-212 (loot tracker, on every RowUpdate of an L step), Markup.lua:41,
  -- Widgets.lua:317, Broker.lua:859: only name (1), link (2) and texture (10) are used.
  -- Name from the catalog; nil for items it does not know, as the client does for uncached items.
  local QUESTION_MARK_ICON = 134400 -- Interface\Icons\INV_Misc_QuestionMark file id
  env.GetItemInfo = function(item)
    local catalog = sb.world.catalog
    if not catalog then return nil end
    local id = tonumber(item) or catalog:item_id(item)
    local it = id and catalog:item(id)
    if not (it and it.name) then return nil end
    local link = "|cffffffff|Hitem:" .. id .. "::::::::1:::::::|h[" .. it.name .. "]|h|r"
    return it.name, link, 1, 1, 0, "", "", 1, "", QUESTION_MARK_ICON, 0
  end
  -- WoWPro_CompatUtil.lua:342-348 (C_Item_GetItemIconByID prefers the GetItemIcon global), called
  -- by RowUpdate.lua:529,553 and Broker.lua:1370,1438 for U/* item buttons. The icon is only a
  -- texture; catalog items get the question-mark icon, unknown ids nil (as an invalid id does).
  local function item_icon(id)
    local catalog = sb.world.catalog
    local it = catalog and tonumber(id) and catalog:item(tonumber(id))
    return it and QUESTION_MARK_ICON or nil
  end
  env.GetItemIcon = item_icon
  env.C_Item.GetItemIconByID = item_icon
  -- WoWPro_Broker.lua:3341 (IsPlayerSpell): spellID comes from a (";"):split of the SPELL tag
  -- (:3332), so it is a string; the client API coerces numeric strings.
  env.IsPlayerSpell = function(id) return player().spells[tonumber(id)] == true end
  env.ERR_NEWTAXIPATH = M.ERR_NEWTAXIPATH
  -- WoW client GetBindLocation: the hearth location text, nil when unbound
  env.GetBindLocation = function() local b = player().bind; return b and b.name or nil end

  -- WoWPro_Localization.lua:8 (GetLocale); AceDB-3.0.lua:263 (GetCurrentRegion/GetCurrentRegionName)
  env.GetLocale = function() return "enUS" end
  env.GetCurrentRegion = function() return 1 end
  env.GetCurrentRegionName = function() return "US" end

  -- WoWPro_Events.lua:234 (InCombatLockdown), :418 (IsInGroup); CallbackHandler-1.0.lua:10 (securecallfunction, load-time upvalue); AceAddon-3.0.lua:623 (IsLoggedIn, read per call)
  env.securecallfunction = function(f, ...) return f(...) end
  env.IsLoggedIn = function() return false end
  env.InCombatLockdown = function() return false end
  env.IsInGroup = function() return false end

  -- WoWPro_ZoneData_Forever.lua:6 (Enum.UIMapType)
  env.Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 } }
  -- WoWPro_Events.lua:415 (RegisterAddonMessagePrefix); WoWPro_Broker.lua:823 (StaticPopupDialogs)
  env.C_ChatInfo = trap(sb, "C_ChatInfo", { RegisterAddonMessagePrefix = function() return true end })
  env.StaticPopupDialogs = {}
  -- WoWPro_Broker.lua:4853 (WOWPRO_MISSING_ARROW when no TomTom), :4872. Records the dialog name in sb.popups.
  sb.popups = sb.popups or {}
  env.StaticPopup_Show = function(which)
    sb.popups[#sb.popups + 1] = which
    return nil
  end

  -- WoWPro_CurrentGuide.lua:251-257 (GetBestMapForUnit, GetPlayerMapPosition, GetRealZoneText); WoWPro_Command.lua:56 and WoWPro_AutoComplete.lua:489-490 (GetSubZoneText)
  env.GetZoneText = function() return player().zone end
  env.GetRealZoneText = function() return player().zone end
  env.GetSubZoneText = function() return player().subzone end
  -- WoWPro_Mapping.lua:624 (CheckHBDData via WoWPro_Events.lua:302). Client map facts for the starting
  -- maps only; any other id returns nil like an unknown map.
  local MAPS = {
    [1426] = { mapID = 1426, name = "Dun Morogh", mapType = 3, parentMapID = 1415 },
    [1415] = { mapID = 1415, name = "Eastern Kingdoms", mapType = 2, parentMapID = 947 },
  }
  env.C_Map = trap(sb, "C_Map", {
    GetMapInfo = function(id)
      local m = MAPS[id]
      if not m then return nil end
      return { mapID = m.mapID, name = m.name, mapType = m.mapType, parentMapID = m.parentMapID }
    end,
    GetBestMapForUnit = function() return player().map_id end,
    -- WoWPro_Broker.lua:2559 (IZ tag with a numeric id). The catalog has no AreaTable, so every id
    -- answers nil as an unknown one does; the uiMapID comparison on the same line still applies.
    -- Valid only while the numeric IZ ids on the played path are uiMapIDs (e.g. 12_20_Eastern_Kingdom
    -- :315 IZ|-1455): an IZ holding an AreaTable id would need real area names here.
    GetAreaInfo = function() return nil end,
    GetPlayerMapPosition = function()
      return { GetXY = function() local p = player(); return p.x, p.y end }
    end,
  })

  -- WoWPro.lua:606-611 (GetBindingKey, then SetBinding when unbound). Fresh client: no bindings.
  local bindings = {}
  env.GetBindingKey = function(command)
    for key, cmd in pairs(bindings) do
      if cmd == command then return key end
    end
    return nil
  end
  env.SetBinding = function(key, command)
    bindings[key] = command
    return true
  end
  -- WoWPro_RowUpdate.lua:1393 (ClearOverrideBindings), :670/:841/:919/:1074 (SetOverrideBindingClick). Per-owner overrides.
  sb.override_bindings = {}
  env.ClearOverrideBindings = function(owner) sb.override_bindings[owner] = nil end
  env.SetOverrideBindingClick = function(owner, _priority, key, button, click)
    sb.override_bindings[owner] = sb.override_bindings[owner] or {}
    sb.override_bindings[owner][key] = { button = button, click = click }
  end

  -- WoWPro_CompatUtil.lua:215 via WoWPro_Mapping.lua:453 (MapPoint). Records the super-tracked quest.
  env.C_SuperTrack = trap(sb, "C_SuperTrack", {
    SetSuperTrackedQuestID = function(id) sb.super_tracked = id end,
    GetSuperTrackedQuestID = function() return sb.super_tracked or 0 end,
  })

  -- WoWPro.lua:1110 (ShouldPvPHide) via WoWPro_Events.lua:280 on PLAYER_ENTERING_WORLD. Open world.
  env.IsInInstance = function() return false, "none" end
  -- WoWPro.lua:1120 (ShouldCombatHide). Out of combat.
  env.UnitAffectingCombat = function() return false end
  -- WoWPro_AutoComplete.lua:474,507, WoWPro_Events.lua:842,853, WoWPro_Mapping.lua:106. The driver
  -- performs an F step as an arrival (actions.lua perform_travel), never a flight in progress.
  env.UnitOnTaxi = function() return false end

  -- The Classic taxi map (WoWPro_AutoComplete.lua:9-30 RecordTaxiLocations and :32-52 TakeTaxiClassic,
  -- both on TAXIMAP_OPENED, WoWPro_Events.lua:814-825; AutoSelect defaults true, WoWPro.lua:490-492).
  -- Nodes are the player's learned flight points in sorted name order, all reachable; the driver
  -- already moves the player on an F step, so TakeTaxiNode only records the chosen node.
  local function taxi_nodes()
    local names = {}
    for name in pairs(player().flight_points) do names[#names + 1] = name end
    table.sort(names)
    return names
  end
  sb.taxi_taken = sb.taxi_taken or {}
  env.NumTaxiNodes = function() return #taxi_nodes() end
  env.TaxiNodeName = function(i) return taxi_nodes()[i] end
  env.TaxiNodeGetType = function(i) return taxi_nodes()[i] and "REACHABLE" or "NONE" end
  env.GetNumRoutes = function(i) return taxi_nodes()[i] and 1 or 0 end
  env.TaxiGetNodeSlot = function(i) return i end
  env.TakeTaxiNode = function(i) sb.taxi_taken[#sb.taxi_taken + 1] = taxi_nodes()[i] end
  env.IsMounted = function() return false end
  env.Dismount = function() end

  -- WoWPro_CompatUtil.lua:273-275: with no GetSpellInfo global, WoWPro.C_Spell_GetSpellInfo calls
  -- C_Spell.GetSpellInfo. The SPELL-tag check (WoWPro_Broker.lua:3332-3340) skips the step with an
  -- error when it returns nil, and otherwise reads only .name, for debug and why text (:3359-3366);
  -- whether the spell is known comes from IsPlayerSpell. The client answers for every real spell id,
  -- so any numeric id gets an info table. There is no spell catalog, so the name is "Spell <id> (stub)".
  env.C_Spell = trap(sb, "C_Spell", {
    GetSpellInfo = function(id)
      id = tonumber(id)
      if not id then return nil end
      return { spellID = id, name = "Spell " .. id .. " (stub)" }
    end,
  })

  -- WoWPro_CompatUtil.lua:231-237 (GetItemCooldown falls back to C_Container.GetItemCooldown), read by
  -- the U-step item button (RowUpdate.lua:555). The world models no cooldowns: start 0, duration 0, enabled true.
  env.C_Container = trap(sb, "C_Container", {
    GetItemCooldown = function() return 0, 0, true end,
  })

  -- WoWPro_Trade.lua:439-476 (UpdateTradeSkills, Forever/Retail path) via WoWPro_Events.lua:282, backed by player.skills.
  -- Parent skill-line ids from the Forever WoWPro.ProfessionSkillLines table (WoWPro_Trade.lua:27-52).
  local SKILL_LINES = require("hwc.world.skill_lines")
  local function skill_names()
    local names = {}
    for name in pairs(player().skills) do names[#names + 1] = name end
    table.sort(names)
    return names
  end
  env.C_TradeSkillUI = trap(sb, "C_TradeSkillUI", {
    -- :439; ids of learned skill lines
    GetAllProfessionTradeSkillLines = function()
      local ids = {}
      for _, name in ipairs(skill_names()) do
        if SKILL_LINES[name] then ids[#ids + 1] = SKILL_LINES[name] end
      end
      return ids
    end,
    -- :442; the table is indexed unguarded, so unknown ids get zero ranks rather than nil
    GetProfessionInfoBySkillLineID = function(id)
      for name, line in pairs(SKILL_LINES) do
        local s = line == id and player().skills[name]
        if s then
          return { professionName = name, skillLevel = s.rank, maxSkillLevel = s.max, skillModifier = 0 }
        end
      end
      return { professionName = "", skillLevel = 0, maxSkillLevel = 0, skillModifier = 0 }
    end,
  })
  -- :458 (GetProfessions returns indices into the learned list; none when fresh)
  env.GetProfessions = function()
    local n = #skill_names()
    if n == 0 then return end
    local idx = {}
    for i = 1, n do idx[i] = i end
    return unpack(idx)
  end
  -- :460 name, icon, rank, maxRank, numAbilities, spellOffset, skillLineID, skillModifier
  env.GetProfessionInfo = function(index)
    local name = skill_names()[index]
    if not name then return nil end
    local s = player().skills[name]
    return name, 0, s.rank, s.max, 0, 0, SKILL_LINES[name], 0
  end

  -- WoWPro_Broker.lua:3883 (CompleteStep plays the check sound before it records completion at :3888,
  -- so a missing global aborts every completion). Client returns willPlay; headless plays nothing.
  env.PlaySoundFile = function() return true end
  -- WoWPro_Events.lua:689, :743, :753, :787 (compared with == to the step name). GetTitleText is the open
  -- NPC quest dialog's title: the catalog name of world.dialog's quest, "" with no dialog open.
  -- Reads sb.world per call, never a captured copy.
  env.GetTitleText = function()
    local w = sb.world
    local d = w and w.dialog
    local q = d and w.catalog and w.catalog:quest(d.qid)
    return q and q.name or ""
  end

  -- FrameXML constant. WoWPro_Widgets.lua:510 (CreateScrollbar border colour)
  env.TOOLTIP_DEFAULT_COLOR = { r = 1, g = 1, b = 1 }
  -- FrameXML table. WoWPro_CurrentGuide.lua:44 (ESC-closable frames)
  env.UISpecialFrames = {}

  require("hwc.stubs.questlog").install(sb)
end

return M
