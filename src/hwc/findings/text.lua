-- Every human-facing word in the findings report (design spec §4.7, §4.8).
-- Pure: no I/O. render, JSON and markdown all take their titles, sentences and
-- labels from here so the wording lives in one place.
local RACES = require("hwc.world.player").RACES

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

function text.anchor(id)
  local hex = tostring(id):gsub("^[Ff]%-", "")
  return "f-" .. hex:lower()
end

-- Escapes text placed in a markdown heading or link text, so a title such as
-- "Lua error: '<eof>' expected near ']'" can't open a link, emphasis or HTML
-- tag. JSON titles stay plain; only the markdown forms go through this.
function text.md_text(s)
  s = tostring(s):gsub("[\\%[%]%*_]", "\\%0")
  return (s:gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function link(title, id) return "[" .. text.md_text(title) .. "](#" .. text.anchor(id) .. ")" end

-- Markdown links to several findings shown together (one list or sentence).
-- Links whose titles collide get " (quest N, line L)" so they can be told
-- apart; a missing part is left out. Returns the links in input order.
function text.links(findings)
  local seen = {}
  for _, f in ipairs(findings) do
    local t = text.title(f)
    seen[t] = (seen[t] or 0) + 1
  end
  local out = {}
  for i, f in ipairs(findings) do
    local t = text.title(f)
    if seen[t] > 1 then
      local parts = {}
      if f.qid then parts[#parts + 1] = "quest " .. tostring(f.qid) end
      if f.line then parts[#parts + 1] = "line " .. tostring(f.line) end
      if #parts > 0 then t = t .. " (" .. table.concat(parts, ", ") .. ")" end
    end
    out[i] = link(t, f.id)
  end
  return out
end

local function lower_first(s) return (s:gsub("^%u", string.lower)) end

local function titlecase(s) return (s:sub(1, 1):upper() .. s:sub(2):lower()) end

local function quoted(name) return '"' .. name .. '"' end

-- "step" is the verb form of a step: Get flight path at "Thelsamar".
function text.step(action, name)
  if name == nil or name == "" then return nil end
  if action == nil or action == "" then return quoted(name) end
  return (text.VERBS[action] or action) .. " " .. quoted(name)
end

-- Split "Night Elf HUNTER lw-skin" into race (may hold spaces), class, variant.
local function split_combo(combo)
  local rest, variant = combo:match("^(.*) (%S+)$")
  local race, class = (rest or ""):match("^(.*) (%S+)$")
  return race or combo, class or "", variant or "baseline"
end

-- A race token as the game shows it: "NightElf" -> "Night Elf". Unknown
-- tokens (and labels that already hold the display name) pass through.
local function race_name(token)
  local r = RACES[token]
  return r and r.name or token
end

function text.character(combo)
  local race, class, variant = split_combo(combo)
  local out = race_name(race) .. " " .. titlecase(class)
  if variant ~= "baseline" then out = out .. " (" .. variant .. ")" end
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

  -- Detail is dropped only when a group reads "(all N variants)": "all N
  -- characters", "all except ..." and named-variant groups lose nothing.
  local summary, dropped = nil, false
  if #unaffected == 0 then
    summary = "all " .. #matrix .. " characters"
  elseif #unaffected <= 3 then
    local list = {}
    for i, c in ipairs(unaffected) do list[i] = text.character(c) end
    table.sort(list)
    summary = "all except " .. table.concat(list, ", ")
  else
    -- Group by race and class, remembering how many matrix variants each has.
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
      local _, _, variant = split_combo(c)
      g.hit[#g.hit + 1] = variant
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
            label = name .. " (all " .. g.total .. " variants)"
            dropped = true
          else
            -- baseline first, then the rest alphabetically.
            table.sort(g.hit, function(a, b)
              if (a == "baseline") ~= (b == "baseline") then return a == "baseline" end
              return a < b
            end)
            label = name .. " (" .. table.concat(g.hit, ", ") .. ")"
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

local function name_of(f)
  if f.name and f.name ~= "" then return quoted(f.name) end
  if f.qid then return "quest " .. f.qid end
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

local function article(word)
  return word:match("^[AEIOUaeiou]") and "an " or "a "
end

local function has_reason(f, reason)
  for _, r in ipairs(f.reasons or {}) do if r == reason then return true end end
  return false
end

local STUCK = {
  ["settle-limit"] = { 'Stuck after %s', "WoWPro kept scheduling work after this step and never settled." },
  ["same-step"] = { 'Stuck on %s', "WoWPro stayed on this step past the watchdog limit." },
  ["max-iterations"] = { "Run hit its step limit", "The run stopped at its step limit before this guide ended." },
  ["no-current-step"] = { "No step to show", "WoWPro had no current step to show, so the run couldn't continue." },
  ["no-guide-loaded"] = { "No guide loaded", "WoWPro loaded no guide, so nothing ran." },
}

function text.title(f)
  local s = f.signal
  local nm = name_of(f)
  if s == "never-shown-accept" then
    if has_reason(f, "engine-dungeon-skip") then return "Dungeon quest " .. nm .. " is skipped" end
    return nm .. " is never offered"
  elseif s == "accept-refused" then
    local kind = kind_of(f)
    if kind then
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
    return nm .. " is offered below its level"
  elseif s == "did-not-advance" then
    return nm .. " doesn't advance"
  elseif s == "manual-completion" then
    return nm .. " needed a manual click"
  elseif s == "stuck" then
    local t = STUCK[(f.reasons or {})[1]]
    if t then return (t[1]:gsub("%%s", function() return nm end)) end
  elseif s == "leftover-quests" then
    if f.qname and f.qname ~= "" then return "Quest " .. quoted(f.qname) .. " (" .. tostring(f.qid) .. ") is left in the log" end
    return "Quest " .. tostring(f.qid) .. " is left in the log"
  elseif s == "lua-error" then
    local first = tostring(f.message or f.name or ""):match("^[^\n]*")
    if #first > 80 then first = first:sub(1, 80) .. "…" end
    return "Lua error: " .. first
  elseif s == "engine-dungeon-skip" then
    return "EnableDungeons auto-completes dungeon accepts"
  end
  return tostring(s) .. ": " .. (text.step(f.action, f.name) or f.name or "")
end

-- Returns the sentence as (first sentence, remainder or nil).
-- prereq_of: the finding the never-shown sentence links as its prerequisite.
-- A follow-on already links its parent in "Follows from"; don't link it twice.
local function prereq_of(f, ctx)
  if f.signal ~= "never-shown-accept" or has_reason(f, "engine-dungeon-skip") then return nil end
  local pre = f.why and f.why:match("not met: (%d+)")
  local hit = pre and ctx and ctx.by_qid and ctx.by_qid[tonumber(pre)]
  if hit and hit.id ~= f.caused_by then return hit end
  return nil
end

-- linked: id -> markdown link for findings this sentence links (text.links).
local function clauses(f, ctx, linked)
  local s, q = f.signal, tostring(f.qid)
  ctx = ctx or {}
  linked = linked or {}
  if s == "never-shown-accept" then
    if has_reason(f, "engine-dungeon-skip") then
      return "WoWPro marks this dungeon quest done without showing it, because dungeon quests are switched off."
    end
    local pre = f.why and f.why:match("not met: (%d+)")
    if pre then
      local ref = "quest " .. pre
      local hit = prereq_of(f, ctx)
      if hit then ref = "quest " .. (linked[hit.id] or link(text.title(hit), hit.id)) end
      return "The guide tells you to accept this quest, but WoWPro hides the step because its prerequisite, "
        .. ref .. ", is never completed."
    elseif f.why and f.why ~= "" then
      return "The guide tells you to accept this quest, but WoWPro never shows the step.",
        "The engine's reason is in the detail below."
    end
    return "The guide tells you to accept this quest, but WoWPro never shows the step and gave no reason."
  elseif s == "accept-refused" then
    local kind = kind_of(f)
    if kind then
      local label = label_for(f, ctx, kind)
      return "The guide shows this accept, but the quest data says " .. article(label) .. label .. " can't take quest " .. q .. "."
    end
    return "The guide shows this accept, but the quest data says a prerequisite of quest " .. q .. " isn't done yet."
  elseif s == "log-full" then
    return "The guide shows this accept while the quest log is already full."
  elseif s == "orphan-turnin" then
    local verb = text.VERBS[f.action] or f.action or "handle"
    return "The guide asks you to " .. lower_first(verb) .. " quest " .. q .. ", but this character never had it."
  elseif s == "wrong-race-class" then
    local kind = kind_of(f)
    if not (ctx.single) and #(f.combos or {}) > 1 then
      return "WoWPro shows this step to characters that quest " .. q .. " excludes."
    end
    local label = label_for(f, ctx, kind or "race")
    return "WoWPro shows this step to " .. article(label) .. label .. ", but quest " .. q .. " is for other "
      .. (kind == "class" and "classes" or kind == "race" and "races" or "characters") .. "."
  elseif s == "below-level" then
    -- The signal fires after the grind, so f.level is the level the client
    -- ground up to, not the level the guide reached the accept at.
    local g = f.grind
    if g and g.to and g.kills then
      return "The guide reaches this accept below level " .. tostring(g.to) .. ", the level the quest requires; "
        .. "the client ground " .. tostring(g.kills) .. " kills to get there."
    end
    return "The guide reaches this accept below the level the quest requires."
  elseif s == "did-not-advance" then
    return "The simulated action didn't move WoWPro to the next step, so the client clicked it off."
  elseif s == "manual-completion" then
    return "No game event completed this step, so the client clicked it off."
  elseif s == "stuck" then
    local t = STUCK[(f.reasons or {})[1]]
    if t then return t[2] end
  elseif s == "leftover-quests" then
    local which = q
    if f.qname and f.qname ~= "" then which = quoted(f.qname) .. " (" .. q .. ")" end
    return "Quest " .. which .. " was still in the log when this guide ended; the run never turned it in."
  elseif s == "lua-error" then
    return "WoWPro raised an error during the run.", "The message and stack are in the detail below."
  elseif s == "engine-dungeon-skip" then
    return "WoWPro's EnableDungeons setting marks dungeon-quest accepts done without showing them; "
      .. "every finding it explains is a dungeon quest the guide never offers."
  end
  return ""
end

function text.sentence(f, ctx)
  local parent = f.caused_by and ctx and ctx.by_id and ctx.by_id[f.caused_by]
  local related = {}
  if parent then related[#related + 1] = parent end
  local pre = prereq_of(f, ctx)
  if pre then related[#related + 1] = pre end
  local linked = {}
  for i, l in ipairs(text.links(related)) do linked[related[i].id] = l end
  local first, rest = clauses(f, ctx, linked)
  if parent then
    return "Follows from " .. linked[parent.id] .. ". " .. first
  end
  if rest then return first .. " " .. rest end
  return first
end

return text
