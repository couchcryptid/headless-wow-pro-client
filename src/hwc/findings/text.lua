-- Every human-facing word in the findings report (design spec §4.7, §4.8).
-- Pure: no I/O. The findings JSON carries every title, sentence and label from
-- here, so the wording lives in one place and the HTML page holds none.
local RACES = require("hwc.world.player").RACES
local reputation = require("hwc.world.reputation")
local gap = require("hwc.findings.gap")

local text = {}

text.SEVERITY = {
  ["high"] = { marker = "🔴", word = "High", rank = 1 },
  ["medium-high"] = { marker = "🟠", word = "Medium-high", rank = 2 },
  ["medium"] = { marker = "🟡", word = "Medium", rank = 3 },
  ["low"] = { marker = "⚪", word = "Low", rank = 4 },
}

-- Action letter -> verb. Every letter is an entry in WoWPro.actionlabels in
-- WoWPro/WoWPro_Parser.lua (the addon checkout), at the line noted. The wording
-- is the spec's (§4.8), not the addon's tooltip text, except where noted.
text.VERBS = {
  A = "Accept",           -- WoWPro_Parser.lua:64  (label "Accept")
  a = "Accept repeatable", -- WoWPro_Parser.lua:66  ("Accept (repeatable)")
  T = "Turn in",          -- WoWPro_Parser.lua:68  ("Turn in")
  t = "Turn in when complete", -- WoWPro_Parser.lua:69  ("Turn in when complete")
  C = "Complete",         -- WoWPro_Parser.lua:67  ("Complete")
  K = "Kill",             -- WoWPro_Parser.lua:70  ("Kill")
  R = "Run to",           -- WoWPro_Parser.lua:71  ("Run to")
  H = "Hearth to",        -- WoWPro_Parser.lua:72  ("Hearth to")
  h = "Set hearth at",    -- WoWPro_Parser.lua:73  ("Set hearth to")
  F = "Fly to",           -- WoWPro_Parser.lua:74  ("Fly to")
  f = "Get flight path at", -- WoWPro_Parser.lua:75  ("Get flight path for")
  M = "Make",             -- WoWPro_Parser.lua:76  ("Make")
  N = "Note:",            -- WoWPro_Parser.lua:77  ("Note")
  U = "Use",              -- WoWPro_Parser.lua:80  ("Use")
  B = "Buy",              -- WoWPro_Parser.lua:78  ("Buy")
  b = "Take boat to",     -- WoWPro_Parser.lua:79  ("Take Boat or Zeppelin")
  l = "Loot",             -- WoWPro_Parser.lua:82  ("Loot")
  -- The addon labels r "Repair/Restock" (WoWPro_Parser.lua:83); it never says
  -- "sell", so the spec's "Sell and repair at" would claim more than the step
  -- shows. Worded to what the parser confirms.
  r = "Repair or restock at",
  L = "Reach level",       -- WoWPro_Parser.lua:81  ("Level")
  D = "Guide done:",       -- WoWPro_Parser.lua:84  ("Done")
  P = "Take portal to",    -- WoWPro_Parser.lua:86  ("Take portal"); P step names are destinations
  ["*"] = "Trash",         -- WoWPro_Parser.lua:96  ("Trash")
}

-- A short plain label per signal slug: filter chips and legends.
text.SIGNALS = {
  ["never-shown-accept"] = "Never offered",
  ["hidden-use-step"] = "Use step never shown",
  ["accept-refused"] = "Can't be taken",
  ["log-full"] = "Quest log full",
  ["orphan-turnin"] = "Turn-in without the quest",
  ["wrong-race-class"] = "Wrong race or class",
  ["below-level"] = "Offered below level",
  ["level-check"] = "Level check reached short",
  ["did-not-advance"] = "Doesn't advance",
  ["manual-completion"] = "Manual click",
  ["stuck"] = "Stuck",
  ["leftover-quests"] = "Left in log",
  ["lua-error"] = "Lua error",
  ["missing-global"] = "Missing global",
  ["rep-faction-unmet"] = "REP faction never met",
  ["arrival-data-gap"] = "Arrival data missing",
}

-- Why a character's run stopped early: every stop reason driver/run.lua passes
-- to Driver:stop except the normal end, no-next-guide, which has no entry.
-- spec/findings/text_spec.lua scans run.lua so a new reason can't go unlabelled.
text.STOPS = {
  iterations = "Hit its step limit",
  errors = "Too many addon errors",
  ["no-step"] = "No step to show",
  ["max-guides"] = "Reached --max-guides",
  stuck = "Stuck on a step",
  ["guide-cycle"] = "Guide loops back on itself",
}

local function lower_first(s) return (s:gsub("^%u", string.lower)) end

local function titlecase(s) return (s:sub(1, 1):upper() .. s:sub(2):lower()) end

-- WoWPro's unmet-prerequisite why ("...: A mandatory prereq was not met: N"): captures N.
text.PRE_NOT_MET = "not met:%s*(%d+)"

local function quoted(name) return '"' .. name .. '"' end

-- "step" is the verb form of a step: Get flight path at "Thelsamar".
function text.step(action, name)
  if name == nil or name == "" then return nil end
  if action == nil or action == "" then return quoted(name) end
  return (text.VERBS[action] or action) .. " " .. quoted(name)
end

-- Split "Night Elf HUNTER herbalism,skinning" into race (may hold spaces), class, and the
-- profession token ("none" for no professions).
local function split_combo(combo)
  local rest, token = combo:match("^(.*) (%S+)$")
  local race, class = (rest or ""):match("^(.*) (%S+)$")
  return race or combo, class or "", token or "none"
end

-- "first-aid,herbalism" -> "First Aid, Herbalism"; nil for "none". Reads the token as
-- written (no validation), so Cooking and any future name label too.
local function token_label(token, sep)
  if token == "none" then return nil end
  local names = {}
  for part in token:gmatch("[^,]+") do
    names[#names + 1] = (part:gsub("%-", " "):gsub("(%a)(%a*)", function(a, b) return a:upper() .. b end))
  end
  return table.concat(names, sep or ", ")
end

-- A race token as the game shows it: "NightElf" -> "Night Elf". Unknown
-- tokens (and labels that already hold the display name) pass through.
local function race_name(token)
  local r = RACES[token]
  return r and r.name or token
end

function text.character(combo)
  local race, class, token = split_combo(combo)
  local out = race_name(race) .. " " .. titlecase(class)
  local label = token_label(token)
  if label then out = out .. " (" .. label .. ")" end
  return out
end

function text.combos(affected, matrix)
  local aff, n_aff = {}, 0
  for _, c in ipairs(affected) do
    if not aff[c] then aff[c] = true; n_aff = n_aff + 1 end
  end
  local unaffected = {}
  for _, c in ipairs(matrix) do if not aff[c] then unaffected[#unaffected + 1] = c end end
  table.sort(unaffected)

  -- Detail is dropped only when a group reads "(all N profession sets)": "all N
  -- characters", "all except ..." and named-set groups lose nothing.
  local summary
  local dropped = false
  if #unaffected == 0 then
    summary = "all " .. #matrix .. " characters"
  elseif #unaffected <= 3 then
    local list = {}
    for i, c in ipairs(unaffected) do list[i] = text.character(c) end
    table.sort(list)
    summary = "all except " .. table.concat(list, ", ")
  else
    -- Group by race and class, remembering how many matrix profession sets each has.
    local groups, order = {}, {}
    local function group_for(combo)
      local race, class = split_combo(combo)
      local key = race .. " " .. class
      if not groups[key] then
        groups[key] = { race = race, class = class, total = 0, hit = {} }
        order[#order + 1] = key
      end
      return groups[key]
    end
    for _, c in ipairs(matrix) do group_for(c).total = group_for(c).total + 1 end
    for c in pairs(aff) do
      local g = group_for(c)
      local _, _, token = split_combo(c)
      g.hit[#g.hit + 1] = token
    end
    local parts = {}
    for _, key in ipairs(order) do
      local g = groups[key]
      if #g.hit > 0 then
        table.sort(g.hit)
        local label
        if g.total <= 1 then
          label = text.character(g.race .. " " .. g.class .. " " .. g.hit[1])
        else
          local name = race_name(g.race) .. " " .. titlecase(g.class)
          if #g.hit >= g.total then
            label = name .. " (all " .. g.total .. " profession sets)"
            dropped = true
          else
            -- "none" first, then the rest alphabetically; a set reads "Alchemy + Herbalism"
            -- so it isn't mistaken for two entries of the list.
            table.sort(g.hit, function(a, b)
              if (a == "none") ~= (b == "none") then return a == "none" end
              return a < b
            end)
            local shown = {}
            for i, t in ipairs(g.hit) do shown[i] = token_label(t, " + ") or "none" end
            label = name .. " (" .. table.concat(shown, ", ") .. ")"
          end
        end
        parts[#parts + 1] = label
      end
    end
    table.sort(parts)
    summary = table.concat(parts, ", ")
  end
  return summary, dropped
end

---------------------------------------------------------------------------
-- Titles and sentences
---------------------------------------------------------------------------

-- ` (p/t)` for a quest in a same-name chain, else "".
local function part_of(chain)
  if type(chain) == "table" and chain.part and chain.total then
    return " (" .. tostring(chain.part) .. "/" .. tostring(chain.total) .. ")"
  end
  return ""
end

-- `"<name>" (p/t)`: a quoted quest name, numbered when it is a part of a chain.
function text.with_part(name, chain) return quoted(name) .. part_of(chain) end

-- A quest reference: `quest <id> "<name>" (p/t)`; plain `quest <id>` without a name.
function text.quest_ref(id, name, chain)
  local out = "quest " .. tostring(id)
  if name and name ~= "" then out = out .. " " .. text.with_part(name, chain) end
  return out
end

local function name_of(f)
  if f.name and f.name ~= "" then return text.with_part(f.name, f.chain) end
  if f.qid then return text.quest_ref(f.qid, f.qname, f.chain) end
  return "this step"
end

local function kind_of(f)
  local r = f.reasons or {}
  if #r == 1 and (r[1] == "race" or r[1] == "class") then return r[1] end
  return nil
end

-- The race or class word(s) a finding concerns: from the single character when
-- the run has one, otherwise the distinct values among f.combos joined by "/".
local function label_for(f, ctx, kind)
  local function word(combo_or_label, from_label)
    local race, class
    if from_label then
      local base = combo_or_label:gsub(" %b()$", "")
      race, class = base:match("^(.*) (%S+)$")
    else
      race, class = split_combo(combo_or_label)
      race, class = race_name(race), titlecase(class)
    end
    return kind == "class" and class or race
  end
  if ctx and ctx.single then return word(ctx.single, true) end
  local seen, list = {}, {}
  for _, c in ipairs(f.combos or {}) do
    local w = word(c, false)
    if w and not seen[w] then seen[w] = true; list[#list + 1] = w end
  end
  table.sort(list)
  return table.concat(list, "/")
end

local function is_reputation(f)
  local r = f.reasons or {}
  return #r == 1 and r[1] == "reputation"
end

-- A reputation value in words: its band's name (hwc.world.reputation BANDS), with the
-- points when the value isn't the band's lower bound ("Neutral (2500)").
local function standing_words(points, always_points)
  local reaction, lower = reputation.standing(points)
  local name = reputation.BANDS[reaction].name
  if always_points or points ~= lower then return name .. " (" .. tostring(points) .. ")" end
  return name
end

-- What became of a missing prerequisite by the end of the run (Driver:missing_outcomes).
local OUTCOME_END = { ["never-accepted"] = "which is never accepted", ["never-completed"] = "which is never completed",
  ["completed-later"] = "which isn't done until later in the run" }
local REP_UNMODELLED = "Reputation from kills, item turn-ins and encounters isn't modelled, so a real player may have it."

local function article(word)
  return word:match("^[AEIOUaeiou]") and "an " or "a "
end

local STUCK = {
  ["settle-limit"] = { 'Stuck after %s', "WoWPro kept scheduling work after this step and never settled." },
  ["same-step"] = { 'Stuck on %s', "WoWPro stayed on this step past the watchdog limit." },
  ["max-iterations"] = { "Run hit its step limit", "The run stopped at its step limit before this guide ended." },
  ["no-current-step"] = { "No step to show", "WoWPro had no current step to show, so the run couldn't continue." },
  ["no-guide-loaded"] = { "No guide loaded", "WoWPro loaded no guide, so nothing ran." },
  -- driver/run.lua after_settle: e.g. Forever 30_41 -> Dungeon_Uld pops back to 30_41's final D step.
  ["guide-cycle"] = { 'Guide loops back to %s',
    "Finishing this step sent the run to another guide, and WoWPro then came back to this same step, "
      .. "which would only send it away again; the run stopped here." },
  ["load-guide-failed"] = { "Next guide didn't load", "WoWPro didn't load the next guide in the chain, so the run stopped." },
}

function text.title(f)
  local s = f.signal
  local nm = name_of(f)
  if s == "never-shown-accept" then
    return nm .. " is never offered"
  elseif s == "hidden-use-step" then
    return nm .. " is never shown"
  elseif s == "accept-refused" then
    local kind = kind_of(f)
    if is_reputation(f) then
      local bound = f.rep and f.rep.bound
      return nm .. " can't be taken: reputation too " .. (bound == "min" and "low" or bound == "max" and "high" or "low/high")
    elseif kind then
      local label = label_for(f, nil, kind)
      return nm .. " can't be taken by " .. article(label) .. label
    end
    return nm .. " can't be taken yet"
  elseif s == "log-full" then
    return nm .. " can't be taken: quest log full"
  elseif s == "orphan-turnin" then
    return (text.step(f.action, f.name) or ("Quest " .. tostring(f.qid))) .. " for a quest the character never had"
  elseif s == "wrong-race-class" then
    return nm .. " is shown to the wrong " .. (kind_of(f) or "race/class")
  elseif s == "below-level" then
    if f.levels_short then return nm .. " is offered " .. gap.text(f.levels_short) .. " levels below the level it requires" end
    return nm .. " is offered below its level"
  elseif s == "level-check" and f.gap then
    return "The guide's level check " .. quoted(f.name or "") .. " is reached " .. gap.text(f.gap) .. " levels short"
  elseif s == "did-not-advance" then
    return nm .. " doesn't advance"
  elseif s == "manual-completion" then
    return nm .. " needed a manual click"
  elseif s == "stuck" then
    local t = STUCK[(f.reasons or {})[1]]
    if t then return (t[1]:gsub("%%s", function() return nm end)) end
  elseif s == "leftover-quests" then
    local which = "Quest " .. tostring(f.qid)
    if f.qname and f.qname ~= "" then which = "Quest " .. text.with_part(f.qname, f.chain) .. " (" .. tostring(f.qid) .. ")" end
    if (f.reasons or {})[1] == "not-turned-in" then return which .. " is not turned in within scope" end
    return which .. " is left in the log"
  elseif s == "rep-faction-unmet" then
    local checks = f.faction_name or ("Faction " .. tostring(f.faction))
    if f.tag_faction and f.tag_faction ~= "" then
      return "REP step names " .. f.tag_faction .. " but checks " .. checks .. ", which this character never met"
    end
    return "REP step checks " .. checks .. ", which this character never met"
  elseif s == "arrival-data-gap" then
    return "No arrival data: " .. tostring(f.name or "")
  elseif s == "lua-error" then
    local first = tostring(f.message or f.name or ""):match("^[^\n]*")
    if #first > 80 then first = first:sub(1, 80) .. "…" end
    return "Lua error: " .. first
  end
  return tostring(s) .. ": " .. (text.step(f.action, f.name) or f.name or "")
end

-- Arrival emulation (spec section 10): what hwc itself lacks, one clause per reason.
-- Each says what hwc's own data lacks, never that the step named something wrong.
local GAP_CLAUSES = {
  ["fp-unknown"] = "no flight point is within reach of the departure in hwc's tables",
  ["start-node-unknown"] = "the character's starting taxi node isn't known",
  ["destination-unresolved"] = "the step's destination couldn't be resolved to a place",
  ["arrival-unknown"] = "no captured crossing leaves from here",
  ["inn-unknown"] = "no captured inn is near here",
  ["waypoint-arrival-not-emulated"] = "arrival by waypoint isn't emulated",
  ["subzone-unknown"] = "the landing subzone isn't captured",
  ["taxi-not-taken"] = "the step names a real flight point but the addon never took the flight "
    .. "(for example, this F step wasn't the active row)",
  ["arrival-data-mismatch"] = "two arrival data tables disagree",
}
-- An F step's arrival-unknown: the departure map is on no continent (hwc.driver.flight).
local F_ARRIVAL_UNKNOWN = "hwc's tables place the departure map on no continent"

local function gap_sentence(f)
  local r = (f.reasons or {})[1] or (f.name and f.name:match("^[^:]+"))
  if r == "tables-missing" then
    return "The Forever client tables aren't installed, so arrival steps aren't judged. Run hwc update."
  end
  local clause = GAP_CLAUSES[r] or tostring(r)
  if r == "arrival-unknown" and f.action == "F" then clause = F_ARRIVAL_UNKNOWN end
  if r == "arrival-data-mismatch" and f.detail then clause = clause .. " (" .. tostring(f.detail) .. ")" end
  return "hwc has no arrival data for this: " .. clause .. "."
end

-- Returns the sentence as (first sentence, remainder or nil). Plain text: the
-- page links a follow-on to its parent from caused_by, not from the sentence.
local function clauses(f, ctx)
  local s = f.signal
  local own = text.quest_ref(f.qid, f.qname, f.chain)
  ctx = ctx or {}
  if s == "never-shown-accept" then
    local pre = f.why and f.why:match(text.PRE_NOT_MET)
    if pre then
      return "The guide tells you to accept this quest, but WoWPro hides the step because its prerequisite, "
        .. text.quest_ref(pre, f.pre_qname, f.pre_chain) .. ", is never completed."
    end
    -- The engine's own whys for a hidden step (WoWPro_Broker.lua), said in words.
    local why = f.why and f.why:gsub("^NextStep%(%):%s*", "")
    if why == "Optional steps default to skipped." then
      return "WoWPro skips this accept because the step is optional, and optional steps are skipped by default."
    elseif why == "Skipping step because player level not high enough." then
      local when = f.level and ("; the character was level " .. tostring(f.level) .. " when the guide passed it") or ""
      return "WoWPro hides this accept until the character's level is high enough" .. when .. "."
    elseif why and why ~= "" then
      return "The guide tells you to accept this quest, but WoWPro never shows the step.",
        "The engine said: " .. quoted(f.why) .. "."
    end
    return "The guide tells you to accept this quest, but WoWPro never shows the step and gave no reason."
  elseif s == "hidden-use-step" then
    local ids = {}
    for id in pairs(f.loot or {}) do ids[#ids + 1] = tonumber(id) end
    table.sort(ids)
    for k, id in ipairs(ids) do ids[k] = tostring(id) end
    local many = #ids > 1
    return "WoWPro hides this use step until " .. (many and "items " or "item ") .. table.concat(ids, ", ")
      .. (many and " are" or " is") .. " in bags, and it wasn't while the run passed here, so the client never used item "
      .. tostring(f.use) .. "."
  elseif s == "accept-refused" then
    local kind = kind_of(f)
    if is_reputation(f) then
      local g = f.rep
      if not (g and g.value and g.points) then
        return "The quest data needs a reputation standing this character doesn't have. " .. REP_UNMODELLED
      end
      local need = (g.bound == "max" and "less than " or "") .. standing_words(g.value)
      return "The quest data needs " .. need .. " with " .. (g.name or ("Faction " .. tostring(g.faction)))
        .. "; this character has " .. standing_words(g.points, true) .. ". " .. REP_UNMODELLED
    elseif kind then
      local label = label_for(f, ctx, kind)
      return "The guide shows this accept, but the quest data says " .. article(label) .. label .. " can't take " .. own .. "."
    end
    if f.missing and f.missing[1] then
      local names, list = f.missing_names or {}, {}
      for i, id in ipairs(f.missing) do
        local nm = names[tostring(id)]
        list[i] = text.quest_ref(id, nm, (f.missing_chain or {})[tostring(id)])
      end
      local oc = f.missing_outcome
      local all = oc ~= nil
      for _, id in ipairs(f.missing) do
        if not (oc and oc[tostring(id)] and OUTCOME_END[oc[tostring(id)]]) then all = false end
      end
      if all then
        -- Every id has an outcome: say what became of each. Any-of sharing one outcome collapses.
        if f.missing_any and #list > 1 then
          local first = oc[tostring(f.missing[1])]
          local same = (first == "never-accepted" or first == "never-completed")
          for _, id in ipairs(f.missing) do
            if oc[tostring(id)] ~= first then same = false end
          end
          if same then
            return "The guide shows this accept, but the quest data says it needs one of " .. table.concat(list, " or ")
              .. ", none of which is ever " .. (first == "never-accepted" and "accepted" or "completed") .. "."
          end
        end
        local parts = {}
        for i, id in ipairs(f.missing) do parts[i] = list[i] .. ", " .. OUTCOME_END[oc[tostring(id)]] end
        return "The guide shows this accept, but the quest data says it needs "
          .. table.concat(parts, f.missing_any and ", or " or ", and ") .. "."
      end
      if #list == 1 then
        return "The guide shows this accept, but the quest data says it needs " .. list[1] .. ", which isn't done yet."
      elseif f.missing_any then
        -- pre_single: any one of them would do.
        return "The guide shows this accept, but the quest data says it needs one of " .. table.concat(list, " or ")
          .. ", none of which is done yet."
      end
      return "The guide shows this accept, but the quest data says it needs " .. table.concat(list, " and ")
        .. ", which aren't done yet."
    end
    return "The guide shows this accept, but the quest data says a prerequisite of " .. own .. " isn't done yet."
  elseif s == "log-full" then
    return "The guide shows this accept while the quest log is already full."
  elseif s == "orphan-turnin" then
    local verb = text.VERBS[f.action] or f.action or "handle"
    return "The guide asks you to " .. lower_first(verb) .. " " .. own .. ", but this character never had it."
  elseif s == "wrong-race-class" then
    local kind = kind_of(f)
    if not (ctx.single) and #(f.combos or {}) > 1 then
      return "WoWPro shows this step to characters that " .. own .. " excludes."
    end
    local label = label_for(f, ctx, kind or "race")
    return "WoWPro shows this step to " .. article(label) .. label .. ", but " .. own .. " is for other "
      .. (kind == "class" and "classes" or kind == "race" and "races" or "characters") .. "."
  elseif s == "below-level" then
    -- The signal fires after the grind, so f.level is the level the client
    -- ground up to, not the level the guide reached the accept at.
    local g = f.grind
    if f.levels_short and g and g.to and g.kills then
      local out = "The guide reaches this accept " .. gap.text(f.levels_short) .. " levels below level "
        .. tostring(g.to) .. ", the level the quest requires (the client ground " .. tostring(g.kills)
        .. " kills to get there)."
      if f.levels_short < gap.MEDIUM then out = out .. " " .. gap.MARGIN_SENTENCE end
      return out
    elseif g and g.to and g.kills then
      return "The guide reaches this accept below level " .. tostring(g.to) .. ", the level the quest requires; "
        .. "the client ground " .. tostring(g.kills) .. " kills to get there."
    end
    return "The guide reaches this accept below the level the quest requires."
  elseif s == "level-check" and f.gap then
    local g = f.grind or {}
    local point = ""
    if (g.offset or 0) < 0 then
      point = ", within " .. tostring(-g.offset) .. " XP of level " .. tostring(g.to + 1)
    elseif (g.offset or 0) > 0 then
      point = ", with at least " .. tostring(g.offset) .. " XP"
    end
    local out = "The client ground " .. tostring(g.kills) .. " kills to reach the point the guide checks (level "
      .. tostring(g.to) .. point .. ")."
    if f.gap < gap.MEDIUM then out = out .. " " .. gap.MARGIN_SENTENCE end
    return out
  elseif s == "did-not-advance" then
    -- The reason is the refusal of the client's action (driver.actions); none means it acted.
    local r = (f.reasons or {})[1]
    local named, arrived = f.named or {}, f.arrived or {}
    if r == "name-not-an-area" then
      return quoted(named.name or "") .. (named.tz and (" and TZ " .. quoted(named.tz)) or "")
        .. " name no area in Forever, so the addon can never complete this step by zone; the client clicked it off."
    elseif r == "arrival-mismatch" then
      local sub = arrived.subzone or ""
      return "The step names " .. quoted(named.name or "") .. (named.tz and (" (TZ " .. quoted(named.tz) .. ")") or "")
        .. ", but the player arrived in " .. tostring(arrived.zone or "") .. (sub ~= "" and (" / " .. sub) or "")
        .. ", so the addon didn't complete it and the client clicked it off."
    elseif r == "flight-point-undiscovered" or r == "no-taxi-node" then
      -- "Another way" only when the player did land somewhere (spec section 9's loose match).
      local tail = (f.resolved_by or f.arrived) and ", so the client travelled there another way."
        or ", so the client clicked the step off."
      if r == "flight-point-undiscovered" then
        return "The guide flies to a flight point the character hasn't discovered" .. tail
      end
      return "No flight point on the taxi map matches " .. quoted(named.name or "") .. tail
    elseif r == "incomplete" and f.action == "T" then
      return "The turn-in was refused because " .. own .. " wasn't complete, so the client clicked the step off."
    elseif r == "incomplete" then
      return "The objectives of " .. own .. " weren't complete after the client did this step, "
        .. "so the client clicked it off."
    elseif r == "not-in-log" then
      return "Q" .. own:sub(2) .. " wasn't in the log when the guide reached this step, so the client clicked it off."
    elseif r == "requires-skill" then
      return "The turn-in needs a profession skill the character doesn't have, so the client clicked the step off."
    elseif r then
      return "The step was refused (" .. r .. "), so the client clicked it off."
    end
    return "The client did what this step asks, but WoWPro didn't mark it done, so the client clicked it off."
  elseif s == "manual-completion" then
    return "No game event completed this step, so the client clicked it off."
  elseif s == "stuck" then
    local t = STUCK[(f.reasons or {})[1]]
    if t then return t[2] end
  elseif s == "leftover-quests" then
    if (f.reasons or {})[1] == "not-turned-in" then
      return "The guide accepts this quest here, but no guide the run played has a turn-in step for it; "
        .. "it was still in the log when the run ended."
    end
    return "The run passed this turn-in step, but " .. own .. " was still in the log when the run ended."
  elseif s == "rep-faction-unmet" then
    return "WoWPro asks for reputation with faction " .. tostring(f.faction)
      .. ", but this character has never met that faction, so the step is skipped.",
      "Reputation from kills and encounters isn't modelled; if the guide meant another faction, the id is wrong."
  elseif s == "arrival-data-gap" then
    return gap_sentence(f)
  elseif s == "lua-error" then
    return "WoWPro raised an error during the run.", "The message and stack are in the detail below."
  end
  return ""
end

-- A follow-on keeps only its first clause: its parent's card carries the rest.
function text.sentence(f, ctx)
  local first, rest = clauses(f, ctx)
  local parent = f.caused_by and ctx and ctx.by_id and ctx.by_id[f.caused_by]
  if rest and not parent then return first .. " " .. rest end
  return first
end

-- `hwc diff` comparability warnings (findings-diff design §4.3): code -> function(args) -> message.
-- The order of the entries is the order diff.compare emits them in.
local function short(s) return tostring(s or "?"):sub(1, 7) end

text.DIFF_WARNINGS = {
  -- Same tag and build but a different archive: name the sha256s, else both sides read alike.
  questie = function(a)
    local o, n = short(a.old_build), short(a.new_build)
    if a.old_tag == a.new_tag and a.old_build == a.new_build then
      o, n = o .. ", sha256 " .. short(a.old_sha256), n .. ", sha256 " .. short(a.new_sha256)
    end
    return string.format("different QuestieDB: %s (%s) → %s (%s); changes may come from the data, not the guide",
      tostring(a.old_tag), o, tostring(a.new_tag), n)
  end,
  counts = function()
    return "different objective counts file; changes may come from the data, not the guide"
  end,
  filters = function() return "different guide filters" end,
  combos = function(a)
    local names = {}
    for i, c in ipairs(a.combos) do names[i] = text.character(c) end
    return string.format("characters only in %s: %s; left out", a.side, table.concat(names, ", "))
  end,
  stop = function(a)
    local function reason(r) return r and (text.STOPS[r] or r) or "ran to the end" end
    return string.format("runs stopped differently for %s (OLD: %s; NEW: %s); findings past the stop show as fixed",
      text.character(a.combo), reason(a.old), reason(a.new))
  end,
  ["relative-to"] = function(a)
    return string.format("runs started from different folders (%s, %s); Lua errors may show as fixed and new",
      tostring(a.old), tostring(a.new))
  end,
  client = function(a)
    return string.format("different hwc versions (%s, %s)", short(a.old), short(a.new))
  end,
  ["same-commit"] = function(a)
    return string.format("both runs are the same addon commit (%s)", short(a.commit))
  end,
  ["dirty-old"] = function() return "uncommitted changes in the OLD run" end,
  ["dirty-new"] = function() return "uncommitted changes in the NEW run" end,
}

return text
