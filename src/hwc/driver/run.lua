-- The driver loop (design spec §4.4): read the step the real engine shows,
-- perform it in the simulated world (actions.perform, §5.2), right-click it off
-- when the engine did not advance, follow the engine's own next-guide autoload,
-- and record a run log of snapshots and signals (§7.1) for the findings step.
--
-- Fidelity: the driver never chooses a step, never writes engine state and makes
-- only the player-equivalent engine calls (E:complete_manual, E:load_guide for the
-- guide-list click over an excluded guide, via actions E:update_guide). Everything
-- it reads goes through the Engine adapter.
--
-- Determinism: the run log holds only ordered data (arrays in loop order, indices
-- walked 1..n); nothing in it is built from pairs.
local actions = require("hwc.driver.actions")
local xp = require("hwc.world.xp")
local findings_text = require("hwc.findings.text")

local run = {}

-- WoWPro hides a non-optional U step that has an L tag until every L item is in
-- bags, and records this why (WoWPro_Broker.lua:2182).
run.HIDDEN_USE_WHY = "You don't have the required items for this step."

run.DEFAULTS = {
  max_iterations = 20000, -- loop passes before the iterations watchdog
  stuck_limit = 5,        -- same (gid, index) acted on more than this many times in a row
  max_addon_errors = 200, -- addon (non-harness) lua errors before the errors watchdog
  max_guides = nil,       -- Ruling C: stop with max-guides once this many guides loaded (nil = unlimited)
  included = nil,         -- { [gid] = true } the guide filters selected; nil = every guide
}

-- Stop reasons. max-guides is Ruling C's opts.max_guides cap (integration specs).
-- The run plays the chain to its last line: no level or guide-range stop.
run.STOP = {
  ["no-next-guide"] = true, stuck = true,
  iterations = true, errors = true, ["no-step"] = true, ["max-guides"] = true,
  -- The engine switched back to a guide that came back on the very step that sent
  -- the run away (Forever 30_41 -> Dungeon_Uld pops back to 30_41's final D step).
  ["guide-cycle"] = true,
}

-- Accept refusals that are signals of their own (spec §7.1). Other refusal reasons
-- (incomplete, requires-skill, already-in-log, ...) only become the reason of the
-- did-not-advance that follows when the engine does not move.
local REFUSAL_SIGNALS = {
  ["log-full"] = "log-full",
  race = "accept-refused", class = "accept-refused", prerequisite = "accept-refused",
  reputation = "accept-refused",
}

local function contains(list, v)
  for _, x in ipairs(list) do
    if x == v then return true end
  end
  return false
end

local function copy_array(t)
  local out = {}
  for i, v in ipairs(t or {}) do out[i] = v end
  return out
end

local function first_stack_line(stack)
  for line in (stack or ""):gmatch("[^\n]+") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and line ~= "stack traceback:" then return line end
  end
  return nil
end

local Driver = {}
Driver.__index = Driver

function Driver:log_qids()
  local out = {}
  for i, e in ipairs(self.W.log:entries()) do out[i] = e.id end
  return out
end

-- "unverified" for a placeholder quest (no catalog entry) or one the catalog marks
-- unverified; "verified" otherwise; nil without a qid.
function Driver:confidence(qid)
  if qid == nil then return nil end
  local W = self.W
  local entry = W.log:get(qid)
  local quest = entry and entry.quest or (W.catalog and W.catalog:quest(qid))
  if not quest or quest.confidence == "unverified" then return "unverified" end
  return "verified"
end

-- The catalog's name for a quest id; nil without a qid or a catalog entry.
-- The catalog's name for qid, else the guide's own: an A step that lists qid (a T step
-- if no A does), in the order the run opened the guides. WoWPro writes a quest step's
-- name as the quest's name, and custom quests such as Forever's 95213 have no catalog
-- entry, so without this a leftover-quests finding (which has no step) shows only an id.
function Driver:quest_name(qid)
  if qid == nil then return nil end
  local catalog = self.W.catalog
  local quest = catalog and catalog:quest(qid)
  if quest and quest.name then return quest.name end
  for _, action in ipairs({ "A", "T" }) do
    for _, gid in ipairs(self.log.guides) do
      -- In step order (steps may have holes, so not ipairs/pairs) for a deterministic pick.
      local steps = self.info[gid] and self.info[gid].steps or {}
      for i = 1, table.maxn(steps) do
        local s = steps[i]
        if s and s.action == action and s.name and contains(s.qids, qid) then return s.name end
      end
    end
  end
  return nil
end

-- { part, total } for a quest in a same-name chain, else nil.
function Driver:chain_of(qid)
  local catalog = self.W.catalog
  if qid == nil or not (catalog and catalog.chain_part) then return nil end
  local part, total = catalog:chain_part(qid)
  if part then return { part = part, total = total } end
  return nil
end

-- Names the quest a hidden accept's unmet prerequisite refers to ("not met: N").
function Driver:prerequisite_ref(sig)
  local pre = sig.why and sig.why:match(findings_text.PRE_NOT_MET)
  if not pre then return end
  pre = tonumber(pre)
  sig.pre_qname, sig.pre_chain = self:quest_name(pre), self:chain_of(pre)
end

-- Appends a Signal. step (an Engine:step record) supplies the location fields;
-- fields may override any of them. Step signals wait for `after` (the name of
-- the next step acted on).
function Driver:signal(kind, step, fields)
  fields = fields or {}
  local s = { signal = kind, level = self.W.player.level, log = self:log_qids() }
  if self.before_name then s.before = { name = self.before_name, action = self.before_action } end
  if step then
    local info = self.info[step.gid or self.gid]
    s.gid, s.line, s.action, s.name = step.gid or self.gid, step.line, step.action, step.name
    s.ordinal = step.ordinal
    s.file = info and info.file
    s.qid = step.qids and step.qids[1]
    -- After a guide switch inside the action's settle, E:why reads the new guide:
    -- use the why captured before the action (or the closing guide's last read).
    local acting = self.acting
    if self.E:gid() == s.gid then
      s.why = self.E:why(step.index)
    elseif acting and acting.gid == s.gid and acting.index == step.index then
      s.why = acting.why
    else
      s.why = info and info.why[step.index]
    end
  end
  for k, v in pairs(fields) do s[k] = v end
  s.qname = self:quest_name(s.qid)
  s.chain = self:chain_of(s.qid)
  s.confidence = self:confidence(s.qid)
  self.log.signals[#self.log.signals + 1] = s
  if step and fields.after == nil then self.awaiting[#self.awaiting + 1] = s end
  return s
end

-- Reports a progress event to opts.on_progress (optional; the driver never prints).
function Driver:emit(event)
  local cb = self.opts.on_progress
  if cb then cb(event) end
end

-- Emits a level event when the player's level differs from the last one seen.
-- The first value seen is the starting level and is not emitted.
function Driver:check_level()
  local level = self.W.player.level
  if self.last_level ~= nil and level ~= self.last_level then
    self:emit({ kind = "level", level = level })
  end
  self.last_level = level
end

function Driver:stop(reason)
  self.stopped = reason
end

function Driver:check_settle(settle, step)
  if settle and settle.hit_limit then self:signal("stuck", step, { reason = "settle-limit" }) end
end

-- The unshown A indices' engine reasons, kept current while the guide is loaded
-- (WoWPro.why is rebuilt when the next guide loads).
function Driver:refresh_why()
  local info = self.info[self.gid]
  for _, i in ipairs(info.accepts) do
    if not info.seen[i] then info.why[i] = self.E:why(i) end
  end
  -- A U step performed off-guide keeps the why that hid it: the turn-in that follows
  -- turns its why into "QID is complete", which would hide its hidden-use-step.
  for _, i in ipairs(info.uses) do
    if not info.seen[i] and not info.offguide[i] then info.why[i] = self.E:why(i) end
  end
end

-- A guide the engine loaded: capture its steps while its arrays are live, then
-- apply the max-guides stop. A guide the filters excluded is jumped instead,
-- before it becomes self.gid, so it is never played, captured or closed.
function Driver:open(gid)
  local E = self.E
  local included = self.opts.included
  if included and not included[gid] then return self:jump(gid) end
  self.gid = gid
  local g = E:guide(gid)
  local info = { file = g.file, steps = {}, accepts = {}, uses = {}, seen = {}, why = {}, sticky_done = {}, retried = {}, offguide = {},
    max_acted = 0, passes = {} }
  self.info[gid] = info
  for i = 1, E:num_steps() do
    local s = E:step(i)
    if s then
      info.steps[i] = { action = s.action, name = s.name, qids = copy_array(s.qids), line = s.line,
        ordinal = s.ordinal, dungeon = s.tags and s.tags.dungeon ~= nil, prof = s.tags and s.tags.prof,
        use = s.tags and s.tags.use, loot = s.tags and s.tags.lootitem, optional = s.tags and s.tags.optional,
        rep = s.rep }
      if s.action == "A" then info.accepts[#info.accepts + 1] = i end
      if s.action == "U" and s.tags and s.tags.use and s.tags.lootitem then info.uses[#info.uses + 1] = i end
    end
  end
  self.log.guides[#self.log.guides + 1] = gid
  self:emit({ kind = "guide", gid = gid, file = g.file, index = #self.log.guides })
  if self.opts.max_guides and #self.log.guides >= self.opts.max_guides then return self:stop("max-guides") end
  self:refresh_why()
end

-- Jumps over the excluded guide `from` (and any excluded guides after it) to the
-- next included guide on the chain and click it in the guide list
-- (E:load_guide). The level is set only at the start of a run: when no guide
-- has been played yet (#log.guides == 0) it is raised to the target guide's
-- startlevel (never lowering it, at most xp.CAP_LEVEL). A mid-chain jump keeps
-- the level earned so far. A chain that ends, or cycles back, before an
-- included guide is the end of the run (no-next-guide).
function Driver:jump(from)
  local E, p, included = self.E, self.W.player, self.opts.included
  local passed, seen, to = {}, {}, nil
  local g = from
  while g ~= nil and not seen[g] do
    seen[g] = true
    passed[#passed + 1] = g
    local nxt = E:guide(g).next_gid
    if nxt ~= nil and included[nxt] then to = nxt; break end
    g = nxt
  end
  local jump = { from = from, passed = passed, to = to, level_before = p.level }
  self.log.jumps[#self.log.jumps + 1] = jump
  if to == nil then
    jump.level_after = p.level
    self:emit({ kind = "jump", from = from, to = nil, passed = copy_array(passed) })
    return self:stop("no-next-guide")
  end
  local start = #self.log.guides == 0 and E:guide(to).startlevel or 0
  while p.level < start and p.level < xp.CAP_LEVEL do p:add_xp(xp.to_next(p.level)) end
  jump.level_after = p.level
  self:emit({ kind = "jump", from = from, to = to, passed = copy_array(passed) })
  self:check_level()
  local _, err = E:load_guide(to)
  if E:gid() ~= to then
    self:signal("stuck", nil, { gid = to, reason = "load-guide-failed", message = err })
    return self:stop("no-step")
  end
  return self:open(to)
end

-- The level the run was at when it first acted on a step after index i in this
-- guide (the level it passed index i at); the current level when none was.
function Driver:level_passing(info, i)
  for _, p in ipairs(info.passes) do
    if p.index > i then return p.level end
  end
  return self.W.player.level
end

-- Appends the signal for step i of a guide the engine never showed, with the
-- fields every such signal carries; `extra` adds the signal's own fields. Returns the signal.
function Driver:record_hidden_step(gid, info, i, signal, extra)
  local s = info.steps[i]
  local prev, nxt = info.steps[i - 1], info.steps[i + 1]
  local sig = {
    signal = signal, gid = gid, file = info.file, line = s.line, ordinal = s.ordinal,
    action = s.action, name = s.name, qid = s.qids[1], why = info.why[i], level = self:level_passing(info, i),
    log = self:log_qids(),
    before = prev and { name = prev.name, action = prev.action } or nil,
    after = nxt and { name = nxt.name, action = nxt.action } or nil,
  }
  for k, v in pairs(extra or {}) do sig[k] = v end
  sig.qname = self:quest_name(sig.qid)
  sig.chain = self:chain_of(sig.qid)
  if signal == "never-shown-accept" then self:prerequisite_ref(sig) end
  sig.confidence = self:confidence(sig.qid)
  self.log.signals[#self.log.signals + 1] = sig
  return sig
end

-- Closes a guide: unshown accepts and the quests left in the log. A guide the
-- run left part-way (end of run, not done) only reports accepts below the
-- furthest index acted on: the unreached rest was never due to be shown.
function Driver:close(gid, full)
  local info = self.info[gid]
  if not info or info.closed then return end
  info.closed = true
  if info.max_acted == 0 then return end -- loaded, never played (stopped on load)
  local g = self.E:guide(gid)
  local last_line
  for _, s in pairs(info.steps) do
    if s.line and (not last_line or s.line > last_line) then last_line = s.line end
  end
  if info.passes[1] then
    self.log.guide_levels[#self.log.guide_levels + 1] = {
      gid = gid, file = info.file, start_level = g.startlevel, end_level = g.endlevel,
      enter = info.passes[1].level, leave = self.W.player.level, finished = full == true, last_line = last_line,
    }
  end
  local limit = full and math.huge or info.max_acted
  local function unshown(i)
    return not info.seen[i] and i < limit and not run.already_done(info.why[i])
  end
  for _, i in ipairs(info.accepts) do
    local s = info.steps[i]
    if unshown(i) and not self:taken(s.qids) and not self:lacks_profession(s) then
      if s.dungeon and self.E:completed(i, gid) then
        -- Skip Dungeon Quests completed it unshown: run info, not a signal.
        local d = self.log.dungeon_skips
        d[#d + 1] = { gid = gid, file = info.file, line = s.line, qid = s.qids[1], name = s.name }
      else
        self:record_hidden_step(gid, info, i, "never-shown-accept")
      end
    end
  end
  -- A non-optional U step with an L tag is hidden until the L items are in bags
  -- (WoWPro_Broker.lua:2182); the same unshown conditions as an accept apply.
  for _, i in ipairs(info.uses) do
    local s = info.steps[i]
    if unshown(i) and not s.optional and info.why[i] and info.why[i]:find(run.HIDDEN_USE_WHY, 1, true) then
      self:record_hidden_step(gid, info, i, "hidden-use-step", { use = s.use, loot = s.loot })
    end
  end
  self:unmet_factions(gid, info, limit)
end

-- REP steps whose faction the character never met (design 2026-11-18-reputation §4.5),
-- in step order, one per step. Detected from the C_Reputation stub: it records every
-- faction id it returned nil for because the character hadn't met it
-- (ReputationState.unmet_lookups), after which WoWPro logs "Bad Faction number" and skips
-- the step (WoWPro_Broker.lua:2882-2885; :2807 splits the tag on ";", :2816 tonumbers the
-- second field). Recorded at lookup time, so a faction met later in the guide still counts.
-- Only steps below `limit` (Driver:close's bound for reached steps) are considered.
-- Unverified: kill and encounter reputation isn't modelled, so a real player may have met it.
function Driver:unmet_factions(gid, info, limit)
  local rep = self.W.reputation
  if not rep or not rep.unmet_lookups then return end
  for i = 1, math.min(table.maxn(info.steps), limit - 1) do
    local s = info.steps[i]
    if s and type(s.rep) == "string" then
      local tag_name, id_field = s.rep:match("^([^;]*);([^;]*)")
      local id = id_field and tonumber(id_field)
      if id and rep.unmet_lookups[id] then
        tag_name = tag_name:match("^%s*(.-)%s*$")
        local sig = self:record_hidden_step(gid, info, i, "rep-faction-unmet", {
          faction = id, faction_name = rep:name(id), tag_faction = tag_name ~= "" and tag_name or nil,
        })
        sig.confidence = "unverified"
      end
    end
  end
end

-- The first `action` step for qid the run reached, in guide then step order, as
-- (gid, info, step); nil when no guide played has one at or before where the run got to.
function Driver:reached_step(action, qid)
  for _, gid in ipairs(self.log.guides) do
    local info = self.info[gid]
    local steps = info and info.steps or {}
    for i = 1, math.min(table.maxn(steps), info and info.max_acted or 0) do
      local s = steps[i]
      if s and s.action == action and contains(s.qids, qid) then return gid, info, s end
    end
  end
  return nil
end

-- Quests still in the log when the run ends. A quest carried into the next guide and
-- turned in there is normal, so nothing is checked at guide ends. At the end:
--   * the run passed a turn-in step for it: a leftover-quests finding at that step;
--   * it was accepted in an earlier guide than the one the run stopped in, and no guide
--     played turns it in: a leftover-quests finding at the accept, reason
--     "not-turned-in" (not turned in within the run's scope);
--   * otherwise it was taken in the guide the run stopped in, which may still turn it
--     in past the run's end: listed in RunLog.carried, not a finding.
function Driver:leftovers()
  for _, q in ipairs(self:log_qids()) do
    local gid, info, s = self:reached_step("T", q)
    local reason
    if not s then
      gid, info, s = self:reached_step("A", q)
      if s and gid ~= self.gid then reason = "not-turned-in" else s = nil end
    end
    if s then
      local sig = {
        signal = "leftover-quests", gid = gid, file = info.file, line = s.line, ordinal = s.ordinal,
        action = s.action, name = s.name, qid = q, reason = reason, level = self.W.player.level,
        log = self:log_qids(),
      }
      sig.qname = self:quest_name(q)
      sig.chain = self:chain_of(q)
      sig.confidence = self:confidence(q)
      self.log.signals[#self.log.signals + 1] = sig
    else
      self.log.carried[#self.log.carried + 1] = { qid = q, qname = self:quest_name(q), chain = self:chain_of(q) }
    end
  end
end

-- Ruling X: the engine skips a step whose quest is already completed with this why
-- (WoWPro_Broker.lua:2042, "NextStep(): QID is complete: " .. tostring(QID)). Such an
-- accept is hidden because the quest is done, not by a defect, so it is no signal.
-- An accept whose quest entered the log or the turned-in history anyway (through
-- another step, an engine auto-complete, an abstracted turn-in) hid nothing.
function Driver:taken(qids)
  local log = self.W.log
  for _, q in ipairs(qids or {}) do
    if log.history[q] or log:get(q) then return true end
  end
  return false
end

-- Spec §3: an accept gated by a P| profession tag the character doesn't know is hidden
-- by design; only a gated accept withheld from a character WITH the skill is a finding.
-- The engine stores the tag as "<Profession>;<skill line>[;...]" (DefineTag("P","prof"),
-- WoWPro_Parser.lua) and skips the step when the profession is unknown.
-- Only an accept the engine permanently skips counts: a P tag whose skill level
-- resolves to 0 is shown to a character without the profession
-- (WoWPro_Broker.lua:2783-2787), so it stays reportable. The level is parsed as the
-- engine does at :2738-2747: "name;id;[exp+]lvl;flip;max", "*" means 101, default 1.
function Driver:lacks_profession(step)
  local prof = step.prof
  if type(prof) ~= "string" then return false end
  local fields = {}
  for f in (prof .. ";"):gmatch("([^;]*);") do fields[#fields + 1] = f end
  local name = fields[1] and fields[1]:match("^%s*(.-)%s*$")
  if not name or name == "" or #fields < 2 then return false end
  local main = (fields[3] ~= nil and fields[3] ~= "") and fields[3] or "*+1"
  local exp, lvl = main:match("^([^+]*)%+?(.*)$")
  if lvl == "" then lvl = nil end
  local proflvl = (lvl == "*") and 101 or (tonumber(lvl or exp) or 1)
  if proflvl == 0 then return false end
  return not self.W.player:knows_skill(name)
end

function run.already_done(why)
  return type(why) == "string" and why:find("NextStep(): QID is complete:", 1, true) == 1
end

function Driver:addon_error_count()
  local errs = self.ctx.errors or {}
  for i = self.err_cursor + 1, #errs do
    if not self.is_harness_error(errs[i], self.ctx.missing) then self.addon_errors = self.addon_errors + 1 end
  end
  self.err_cursor = #errs
  return self.addon_errors
end

-- Ruling P: only when every listed QID excludes the character (a multi-QID step
-- lists race/class variants; one admitting id is enough). A QID the catalog does
-- not know admits. One signal per (gid, index), with the first id's reason. Only
-- quest steps (A/C/K/T) are checked: a non-quest step such as `f Thelsamar|QID|94466`
-- borrows a quest id for its skip-when-complete check, not to gate it by race or class.
function Driver:wrong_race_class(cur)
  local W = self.W
  local p = W.player
  local key = cur.gid .. ":" .. cur.index
  local qids = cur.qids or {}
  if #qids == 0 or not actions.is_quest_step(cur) or self.race_class_seen[key] then return end
  local first_qid, first_reason
  for _, q in ipairs(qids) do
    local quest = W.catalog and W.catalog:quest(q)
    local reason
    if quest then
      if quest.races and not contains(quest.races, p.race_key) then reason = "race"
      elseif quest.classes and not contains(quest.classes, p.class_token) then reason = "class" end
    end
    if not reason then return end
    if not first_reason then first_qid, first_reason = q, reason end
  end
  self.race_class_seen[key] = true
  self:signal("wrong-race-class", cur, { qid = first_qid, reason = first_reason })
end

-- A reputation refusal is unverified whatever the quest data's confidence: kill,
-- item turn-in and encounter reputation isn't modelled, so a real player may have the
-- standing (design 2026-11-18-reputation §4.5, user decision). sig.rep names the
-- failing gate { faction, name, bound, value, points } when the world can tell.
function Driver:reputation_refusal(sig)
  sig.confidence = "unverified"
  local W = self.W
  local rep = W.reputation
  local quest = sig.qid and W.catalog and W.catalog:quest(sig.qid)
  local gate = rep and quest and rep:gate(quest)
  if gate then
    gate.name = rep:name(gate.faction)
    sig.rep = gate
  end
end

-- Sets out.explained when it records a signal that says why the step was refused:
-- the driver then clicks the step off without a did-not-advance as well.
-- A prerequisite refusal names the prerequisites that aren't done (QuestLog:refusal)
-- and their names, keyed by the id as a string, so the finding can say which quest is
-- missing and the linker can attach it under that quest's own failure. any_of: the list
-- is a pre_single one (any one of them would do).
function Driver:missing_prerequisites(sig, missing, any_of)
  local ids, names, chains = {}, {}, {}
  for i, id in ipairs(missing) do
    ids[i] = id
    names[tostring(id)] = self:quest_name(id)
    local chain = self:chain_of(id)
    if chain then chains[tostring(id)] = chain end
  end
  sig.missing, sig.missing_names = ids, names
  if next(chains) then sig.missing_chain = chains end
  sig.missing_any = any_of and true or nil
end

function Driver:refusals(cur, out)
  if out.kind == "refused" then
    local r = out.reason
    if REFUSAL_SIGNALS[r] then
      local sig = self:signal(REFUSAL_SIGNALS[r], cur, { qid = out.qid, reason = r, outcome = out.kind })
      if r == "prerequisite" and out.missing then
        self:missing_prerequisites(sig, out.missing, out.missing_any)
        -- Where in the world's event stream the refusal happened, so finish can tell a quest
        -- done later from one done earlier. Kept off the signal: it isn't part of the log.
        self.refusal_marks = self.refusal_marks or {}
        self.refusal_marks[#self.refusal_marks + 1] = { sig = sig, at = #(self.W.events or {}) }
      end
      if r == "reputation" then self:reputation_refusal(sig) end
      out.explained = true
    elseif r == "not-in-log" and (cur.action == "T" or cur.action == "C") then
      -- Every listed id the character never had (Review Focus 5).
      local history = self.W.log.history or {}
      for _, q in ipairs(cur.qids or {}) do
        if not self.W.log:get(q) and not history[q] then
          self:signal("orphan-turnin", cur, { qid = q, reason = r, outcome = out.kind })
          out.explained = true
        end
      end
    end
  elseif out.kind == "acted" then
    if out.grind and cur.action == "A" then
      self:signal("below-level", cur, { qid = out.qid, reason = "below-level", outcome = out.kind,
        grind = { kills = out.grind.kills, to = out.grind.to }, levels_short = out.grind.short })
    end
    local lg = out.level_grind
    if lg then
      -- A level check (L step, or a plain LVL tag on any other step) the character arrived below.
      self:signal("level-check", cur, { reason = "level-check", outcome = out.kind, gap = lg.short,
        grind = { kills = lg.kills, to = lg.to, point = lg.point, offset = lg.offset } })
    end
  end
end

-- Travel steps (arrival emulation spec section 10): with no Forever tables installed a
-- stalled one is never judged.
local ARRIVAL_ACTIONS = { F = true, f = true, b = true, P = true, H = true, h = true, R = true }
local NO_TABLES = { reason = "tables-missing", key = "no-tables" }

-- The harness notice for an arrival step that didn't advance, or nil when the step is
-- the guide's to answer for (arrival emulation spec section 10). The first rule that
-- applies decides: the action's own data gap; no Forever tables at all (nothing can be
-- judged, so even an R step with no gap is tables-missing); a landing subzone no
-- capture knows (key "<gid>:<line>").
function Driver:arrival_gap(step, out)
  if out.data_gap then return out.data_gap end
  if not ARRIVAL_ACTIONS[step.action] then return nil end
  local catalog = self.W.catalog
  if not (catalog and catalog.forever) then return NO_TABLES end
  if out.classify == "subzone-unknown" then
    return { reason = "subzone-unknown",
      key = string.format("%s:%s", tostring(step.gid or self.gid), tostring(step.line or step.index)) }
  end
  return nil
end

-- A did-not-advance's reason for a step with no gap: the action's own (a guide reason
-- such as no-taxi-node, or a refusal), else what the arrival classification says.
local function stall_reason(out)
  if out.reason then return out.reason end
  if out.classify == "name-not-an-area" then return "name-not-an-area" end
  if out.arrived then return "arrival-mismatch" end
  return nil
end

-- Once per run, before the first step: what hwc's arrival data itself is missing or gets
-- wrong. start-node-unknown only with the tables present (without them every arrival is
-- tables-missing anyway); each catalog:arrival_problems() row as arrival-data-mismatch.
function Driver:arrival_notices()
  local W = self.W
  local catalog = W.catalog
  if catalog and catalog.forever and W.start_node_unknown then
    self:signal("arrival-data-gap", nil, { reason = "start-node-unknown", key = W.player.race_key })
  end
  if not (catalog and catalog.arrival_problems) then return end
  for _, row in ipairs(catalog:arrival_problems(W.arrivals)) do
    self:signal("arrival-data-gap", nil, { reason = "arrival-data-mismatch", key = row.key, detail = row.detail })
  end
end

function Driver:snapshot(cur, why, rows, out)
  local p = self.W.player
  local row_idx = {}
  for i, r in ipairs(rows) do row_idx[i] = r.index end
  local snap = {
    n = #self.log.steps + 1, gid = cur.gid, index = cur.index, action = cur.action, name = cur.name,
    qids = copy_array(cur.qids), line = cur.line, why = why, rows = row_idx,
    outcome = {
      kind = out.kind, reason = out.reason, qid = out.qid, events = copy_array(out.events),
      levels = out.levels, grind = (out.grind or out.level_grind) and { kills = (out.grind or out.level_grind).kills,
        to = (out.grind or out.level_grind).to } or nil,
      elite = out.elite,
      -- spec §5.2: the Camping 101 abstraction is "logged as an abstracted-turnin event".
      abstracted_turnin = out.abstracted_turnin,
    },
    level = p.level, xp = p.xp, log = self:log_qids(),
  }
  self.log.steps[#self.log.steps + 1] = snap
  return snap
end

-- The first shown sticky C/K row for a quest not yet performed in this guide.
function Driver:sticky_row(rows, info)
  for _, r in ipairs(rows) do
    if r.sticky and (r.action == "C" or r.action == "K") and r.qids and #r.qids > 0
      and not info.sticky_done[r.index] and not self.E:completed(r.index) then
      return r
    end
  end
  return nil
end

-- The ids of qid's item objectives the bags are short of, as a set; empty when
-- the quest isn't in the log.
function Driver:short_items(qid)
  local log = self.W.log
  local entry = qid and log:get(qid)
  local short = {}
  if not entry or not entry.quest then return short end
  for i, obj in ipairs(entry.quest.objectives or {}) do
    if obj.kind == "item" and type(obj.ids) == "table" and log:have(qid, i) < obj.count then
      for _, id in ipairs(obj.ids) do short[id] = true end
    end
  end
  return short
end

-- Design 2026-11-18-hidden-use-turnin: a T refused "incomplete" while an item objective
-- of its quest is short, in a guide with a U step for that quest that the engine never
-- showed (info.seen), holds back for missing items (why has run.HIDDEN_USE_WHY,
-- WoWPro_Broker.lua:2182) and whose L tag names a short item. In game the player
-- combines the item themselves and turns in. The player can only use an item they
-- hold: the U step's use item (U|<id>|, its first id) must be in the bags, and the
-- harness never supplies it (perform_use adds a missing use item, so without this
-- check the off-guide use would invent its reagent). A U step already performed
-- off-guide is not performed again (a second T for the quest after a failed retry).
-- Returns the lowest such U index, or nil.
function Driver:hidden_use_for(step, out, info)
  if step.action ~= "T" or out.kind ~= "refused" or out.reason ~= "incomplete" then return nil end
  if info.retried[step.index] then return nil end -- one retry per T step
  local qid = out.qid
  local short = self:short_items(qid)
  if next(short) == nil then return nil end
  for _, i in ipairs(info.uses) do
    local s = info.steps[i]
    local why = info.why[i]
    local use_id = tonumber(tostring(s.use):match("%d+"))
    if not info.seen[i] and not info.offguide[i] and contains(s.qids, qid) and type(why) == "string"
      and why:find(run.HIDDEN_USE_WHY, 1, true)
      and use_id and self.W.player:item_count(use_id) > 0 then
      for _, it in ipairs(actions.parse_loot(s.loot)) do
        if short[it.id] then return i end
      end
    end
  end
  return nil
end

-- Performs hidden U step i off-guide (the same actions.perform a shown U step gets, so
-- its events, levels and settle apply) and logs it in log.offguide. It stays unseen, so
-- the guide still closes with its hidden-use-step. Returns false when the action's
-- settle left the guide (the T step is no longer loaded to retry).
function Driver:perform_offguide(step, i, info)
  info.offguide[i] = true
  local ustep = self.E:step(i)
  ustep.gid = ustep.gid or self.gid
  local uout = self.perform(self.ctx, ustep)
  self:check_settle(uout.settle, ustep)
  local o = self.log.offguide
  o[#o + 1] = { gid = self.gid, file = info.file, line = info.steps[i].line, qid = (ustep.qids or {})[1],
    action = "U", for_line = step.line, events = copy_array(uout.events), levels = uout.levels }
  return self.E:gid() == self.gid
end

-- An R step's arrival credits (actions credit_arrival's out.arrivals): one
-- log.arrivals record per objective credited.
function Driver:record_arrivals(step, out, info)
  local a = self.log.arrivals
  for _, index in ipairs(out.arrivals or {}) do
    a[#a + 1] = { gid = step.gid or self.gid, file = info.file, line = step.line, qid = out.qid, objective = index }
  end
end

-- Performs one shown step: before/after bookkeeping, wrong-race-class, the action,
-- its snapshot, settle-limit and refusal signals. Returns the outcome and snapshot.
-- A turn-in refused for an item a hidden U step makes gets that U step performed
-- off-guide and one more turn-in (Driver:hidden_use_for); the retry's outcome is the
-- step's outcome.
function Driver:act(step, rows, info)
  for _, s in ipairs(self.awaiting) do s.after = { name = step.name, action = step.action } end
  self.awaiting = {}
  self.before_name, self.last_name = self.last_name, step.name
  self.before_action, self.last_action = self.last_action, step.action
  self:wrong_race_class(step)
  local why = self.E:why(step.index)
  self.acting = { gid = step.gid, index = step.index, why = why }
  local out = self.perform(self.ctx, step)
  local use = self:hidden_use_for(step, out, info)
  local checked = false -- whether out.settle was already checked
  if use then
    info.retried[step.index] = true
    self:check_settle(out.settle, step)
    checked = true
    if self:perform_offguide(step, use, info) then
      out = self.perform(self.ctx, step)
      checked = false
    end
  end
  if step.index > info.max_acted then info.max_acted = step.index end
  self:record_arrivals(step, out, info)
  local snap = self:snapshot(step, why, rows, out)
  -- The first turn-in's settle is checked before the off-guide use; it is checked here
  -- only when no retry replaced it.
  if not checked then self:check_settle(out.settle, step) end
  self:refusals(step, out)
  return out, snap
end

-- A harness-level engine read failure: never act on it (engine adapter contract).
function Driver:read_failed(err, step)
  self:signal("stuck", step, { reason = tostring(err) })
  self:stop("no-step")
end

-- One pass of the loop. Returns nothing; sets self.stopped to end the run.
function Driver:iterate()
  local E, opts = self.E, self.opts
  self.iter = self.iter + 1
  if self.iter > opts.max_iterations then
    self:signal("stuck", nil, { gid = self.gid, reason = "max-iterations" })
    return self:stop("iterations")
  end
  if self:addon_error_count() > opts.max_addon_errors then return self:stop("errors") end

  local cur, err = E:current()
  if err then return self:read_failed(err) end
  if not cur then
    if E:guide(self.gid).done then return self:stop("no-next-guide") end
    self:signal("stuck", nil, { gid = self.gid, reason = "no-current-step" })
    return self:stop("no-step")
  end
  local rows, rerr = E:rows()
  if rerr then return self:read_failed(rerr, cur) end
  cur.gid = cur.gid or self.gid
  local info = self.info[self.gid]
  info.seen[cur.index] = true
  for _, r in ipairs(rows) do info.seen[r.index] = true end

  -- Sticky objective rows (S tag, WoWPro_Parser.lua:572) sit above the current
  -- step until their objectives are done (the engine's partial-completion path,
  -- AutoComplete.lua:382-399, or an unsticky US step, WoWPro_Parser.lua:571). A player does them while
  -- following the guide, so the driver performs each shown sticky C/K row once,
  -- with no advance check and no right-click; then the loop re-reads the engine.
  local sticky = self:sticky_row(rows, info)
  if sticky then
    info.sticky_done[sticky.index] = true
    sticky.gid = sticky.gid or self.gid
    local _, snap = self:act(sticky, rows, info)
    snap.sticky = true
    return self:after_settle(sticky)
  end

  -- Stuck watchdog: the same (gid, index) acted on more than stuck_limit times in a row.
  local key = self.gid .. ":" .. cur.index
  self.repeats = (key == self.last_key) and self.repeats + 1 or 1
  self.last_key = key
  if self.repeats > opts.stuck_limit then
    self:signal("stuck", cur, { reason = "same-step" })
    return self:stop("stuck")
  end

  info.passes[#info.passes + 1] = { index = cur.index, level = self.W.player.level }
  local out = self:act(cur, rows, info)

  -- Advanced (Review Focus 2): the acted-on index is complete, the guide changed,
  -- or the acted-on index is no longer current; not "some index completed".
  local advanced
  if E:gid() ~= self.gid then
    advanced = true
  elseif E:completed(cur.index) then
    advanced = true
  else
    local now, cerr = E:current()
    if cerr then return self:read_failed(cerr, cur) end
    advanced = now == nil or now.index ~= cur.index
  end

  if not advanced then
    -- One right-click, one signal. An unexpected click is a did-not-advance; only an
    -- expected one (N, D, notes, ...) is a manual-completion. Recording both for the
    -- same click made every did-not-advance show up twice in the report. A step that
    -- comes back even after the click is the stuck watchdog's job, not a separate signal.
    -- A refused step whose refusal is already a signal (accept-refused, log-full,
    -- orphan-turnin) gets no second one for the same click. An arrival step whose stall
    -- is hwc's own missing data is an arrival-data-gap notice instead (spec section 10).
    local expected = actions.expects_manual(cur)
    local gap = not expected and not out.explained and self:arrival_gap(cur, out)
    local sig
    if expected then
      sig = self:signal("manual-completion", cur,
        { qid = out.qid, reason = out.reason, outcome = out.kind, expected = true })
    elseif gap then
      self:signal("arrival-data-gap", cur, { qid = out.qid, reason = gap.reason, key = gap.key, outcome = out.kind,
        named = out.named, arrived = out.arrived, resolved_by = out.resolved_by })
      out.explained = true
    elseif not out.explained then
      sig = self:signal("did-not-advance", cur, { qid = out.qid, reason = stall_reason(out), outcome = out.kind,
        named = out.named, arrived = out.arrived, resolved_by = out.resolved_by })
    end
    -- An addon error inside the right-click is in sb.errors (a lua-error at the end)
    -- and becomes this signal's reason.
    local ok, merr = E:complete_manual(cur.index)
    if not ok and sig then sig.reason = merr end
    self:check_settle(E:settle(), cur)
  end

  return self:after_settle(cur)
end

-- Follow the engine's own guide switch (Review Focus 1): read the gid after every settle.
-- `acted` is the step whose action led here. A switch records it as the step the old
-- guide was left on; a guide that later comes back on that same step would only send
-- the run away again (the same-step watchdog resets on every switch, so it never trips),
-- and a player stops there: stuck guide-cycle. Coming back further along is a normal
-- return from a side guide.
function Driver:after_settle(acted)
  local E = self.E
  local new = E:gid()
  if new ~= nil and new ~= self.gid then
    self:close(self.gid, true)
    self.repeats, self.last_key = 0, nil
    self.left_at = self.left_at or {}
    if acted then self.left_at[self.gid] = acted.index end
    local back = self.left_at[new]
    if back ~= nil then
      local now = E:current()
      if now and now.index == back then
        now.gid = now.gid or new
        self:signal("stuck", now, { gid = new, reason = "guide-cycle", from = self.gid })
        return self:stop("guide-cycle")
      end
    end
    return self:open(new)
  end
  if E:guide(self.gid).done then return self:stop("no-next-guide") end
  self:refresh_why()
end

-- What became of each missing prerequisite of a prerequisite refusal, from the run's own
-- quest events: never-accepted, never-completed (accepted, any number of times, never
-- turned in) or completed-later. A quest turned in before the refusal can't be missing,
-- so it is left out rather than claimed.
function Driver:missing_outcomes()
  local events = self.W.events or {}
  for _, mark in ipairs(self.refusal_marks or {}) do
    local outcome = {}
    for _, id in ipairs(mark.sig.missing) do
      local accepted, before, later = false, false, false
      for i, e in ipairs(events) do
        if e.id == id then
          if e.kind == "quest_accept" then accepted = true
          elseif e.kind == "quest_turn_in" or e.kind == "abstracted-turnin" then
            if i > mark.at then later = true else before = true end
          end
        end
      end
      if later then outcome[tostring(id)] = "completed-later"
      elseif not before then
        outcome[tostring(id)] = accepted and "never-completed" or "never-accepted"
      end
    end
    if next(outcome) then mark.sig.missing_outcome = outcome end
  end
  self.refusal_marks = nil
end

function Driver:finish()
  local log, W = self.log, self.W
  self:missing_outcomes()
  self:close(self.gid, self.stopped == "no-next-guide")
  self:leftovers()
  for _, e in ipairs(self.ctx.errors or {}) do
    local sig = { signal = "lua-error", message = e.msg, stack = first_stack_line(e.stack), level = W.player.level }
    if self.is_harness_error(e, self.ctx.missing) then sig.reason = "harness" end
    log.signals[#log.signals + 1] = sig
  end
  local seen = {}
  for _, name in ipairs(self.ctx.missing_order or {}) do
    if not seen[name] then
      seen[name] = true
      log.signals[#log.signals + 1] = { signal = "missing-global", global = name }
    end
  end
  log.stop = { reason = self.stopped, level = W.player.level, gid = self.gid }
  -- Changes are in turn-in order and assumptions are sorted (ReputationState), so the
  -- encoded log is the same on every run.
  local rep = W.reputation
  if rep then log.reputation = { changes = rep.changes, assumptions = rep:assumptions() } end
end

-- ctx = { engine, world, cfg, errors = sb.errors, missing_order = sb.missing_order, missing = sb.missing,
-- addon = {path, git, branch, commit, dirty, version} } (boot.run's addon identity;
-- git = false marks a folder with no git, named by its TOC version). opts as run.DEFAULTS, plus opts.perform
-- (default actions.perform; the fake-engine specs pass a scripted one) and
-- opts.is_harness_error (default boot.is_harness_error).
function run.drive(ctx, opts)
  local o = {}
  for k, v in pairs(run.DEFAULTS) do o[k] = v end
  for k, v in pairs(opts or {}) do o[k] = v end
  local cfg = ctx.cfg or {}
  local W = ctx.world
  local profs = {}
  for i, p in ipairs(cfg.professions or {}) do profs[i] = p.name end
  local addon = ctx.addon or {}
  local log = {
    character = { race = cfg.race, class = cfg.class, professions = profs },
    addon = { path = addon.path, git = addon.git, branch = addon.branch, commit = addon.commit,
      dirty = addon.dirty, version = addon.version },
    catalog = { sources = W.catalog and W.catalog.sources },
    rank = ctx.engine:rank(),
    -- Expected for this client (no dungeon runs): the setting and what it skipped are
    -- run info, not signals. A hidden DUNGEON accept the engine didn't complete is
    -- still a never-shown-accept.
    skip_dungeons = ctx.engine:skip_dungeons(),
    dungeon_skips = {},
    carried = {},
    -- Actions the player takes off-guide: { gid, file, line, qid, action = "U",
    -- for_line = <the T step's line>, events, levels } (Driver:perform_offguide).
    offguide = {},
    -- Objectives an R step's arrival credited: { gid, file, line, qid, objective = index }
    -- (Driver:record_arrivals).
    arrivals = {},
    steps = {}, signals = {}, guides = {}, guide_levels = {},
    jumps = {}, -- { from, passed = {gid...}, to (nil: end of chain), level_before, level_after }
  }
  local d = setmetatable({
    ctx = { engine = ctx.engine, world = W, cfg = cfg, errors = ctx.errors, missing_order = ctx.missing_order,
      missing = ctx.missing },
    E = ctx.engine, W = W, opts = o, log = log, info = {}, awaiting = {}, race_class_seen = {},
    iter = 0, repeats = 0, err_cursor = 0, addon_errors = 0,
    perform = o.perform or actions.perform,
    is_harness_error = o.is_harness_error or require("hwc.boot").is_harness_error,
  }, Driver)

  d.last_level = W.player.level -- the starting level: recorded, not emitted
  d:arrival_notices()
  local gid = d.E:gid()
  if gid == nil then
    d:signal("stuck", nil, { reason = "no-guide-loaded" })
    d:stop("no-step")
  else
    d:open(gid)
  end
  while not d.stopped do
    d:iterate()
    d:check_level()
  end
  d:finish()
  return log
end

-- Boots one character (boot.run) and drives it; the Engine is built once per run
-- (its guide-source index is cached per instance).
function run.character(cfg, opts)
  local boot = require("hwc.boot")
  local Engine = require("hwc.driver.engine")
  local result = boot.run(cfg)
  return run.drive({
    engine = Engine.new(result), world = result.world, cfg = cfg,
    errors = result.sb.errors, missing_order = result.sb.missing_order, missing = result.sb.missing,
    addon = result.addon,
  }, opts)
end

return run
