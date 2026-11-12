-- The driver loop (design spec §4.4): read the step the real engine shows,
-- perform it in the simulated world (actions.perform, §5.2), right-click it off
-- when the engine did not advance, follow the engine's own next-guide autoload,
-- and record a run log of snapshots and signals (§7.1) for the findings step.
--
-- Fidelity: the driver never chooses a step, never writes engine state and makes
-- only the player-equivalent engine calls (E:complete_manual, via actions
-- E:update_guide). Everything it reads goes through the Engine adapter.
--
-- Determinism: the run log holds only ordered data (arrays in loop order, indices
-- walked 1..n); nothing in it is built from pairs.
local actions = require("hwc.driver.actions")

local run = {}

run.DEFAULTS = {
  max_iterations = 20000, -- loop passes before the iterations watchdog
  stuck_limit = 5,        -- same (gid, index) acted on more than this many times in a row
  max_addon_errors = 200, -- addon (non-harness) lua errors before the errors watchdog
  stop_level = 25,        -- design spec §4.4 stop condition
  max_guides = nil,       -- Ruling C: stop with max-guides once this many guides loaded (nil = unlimited)
}

-- A guide whose startlevel is at or past this is outside the 1-25 chain (spec §4.4).
run.CHAIN_MAX_START = 25

-- Stop reasons. max-guides is Ruling C's opts.max_guides cap (integration specs).
run.STOP = {
  level = true, ["chain-range"] = true, ["no-next-guide"] = true, stuck = true,
  iterations = true, errors = true, ["no-step"] = true, ["max-guides"] = true,
}

-- Accept refusals that are signals of their own (spec §7.1). Other refusal reasons
-- (incomplete, requires-skill, already-in-log, ...) only become the reason of the
-- did-not-advance that follows when the engine does not move.
local REFUSAL_SIGNALS = {
  ["log-full"] = "log-full",
  race = "accept-refused", class = "accept-refused", prerequisite = "accept-refused",
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
function Driver:quest_name(qid)
  local catalog = qid ~= nil and self.W.catalog
  local quest = catalog and catalog:quest(qid)
  return quest and quest.name or nil
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
  s.confidence = self:confidence(s.qid)
  self.log.signals[#self.log.signals + 1] = s
  if step and fields.after == nil then self.awaiting[#self.awaiting + 1] = s end
  return s
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
end

-- A guide the engine loaded: capture its steps while its arrays are live, then
-- apply the chain-range and max-guides stops.
function Driver:open(gid)
  local E = self.E
  self.gid = gid
  local g = E:guide(gid)
  local info = { file = g.file, steps = {}, accepts = {}, seen = {}, why = {}, sticky_done = {}, max_acted = 0 }
  self.info[gid] = info
  for i = 1, E:num_steps() do
    local s = E:step(i)
    if s then
      info.steps[i] = { action = s.action, name = s.name, qids = copy_array(s.qids), line = s.line,
        ordinal = s.ordinal, dungeon = s.tags and s.tags.dungeon ~= nil, prof = s.tags and s.tags.prof }
      if s.action == "A" then info.accepts[#info.accepts + 1] = i end
    end
  end
  self.log.guides[#self.log.guides + 1] = gid
  if (g.startlevel or 0) >= run.CHAIN_MAX_START then return self:stop("chain-range") end
  if self.opts.max_guides and #self.log.guides >= self.opts.max_guides then return self:stop("max-guides") end
  self:refresh_why()
end

-- Closes a guide: unshown accepts and the quests left in the log. A guide the
-- run left part-way (end of run, not done) only reports accepts below the
-- furthest index acted on: the unreached rest was never due to be shown.
function Driver:close(gid, full)
  local info = self.info[gid]
  if not info or info.closed then return end
  info.closed = true
  if info.max_acted == 0 then return end -- loaded, never played (stopped on load)
  local limit = full and math.huge or info.max_acted
  for _, i in ipairs(info.accepts) do
    local s = info.steps[i]
    if not info.seen[i] and i < limit and not run.already_done(info.why[i])
        and not self:taken(s.qids) and not self:lacks_profession(s) then
      local prev, nxt = info.steps[i - 1], info.steps[i + 1]
      local sig = {
        signal = "never-shown-accept", gid = gid, file = info.file, line = s.line, ordinal = s.ordinal, action = s.action,
        name = s.name, qid = s.qids[1], why = info.why[i], level = self.W.player.level, log = self:log_qids(),
        before = prev and { name = prev.name, action = prev.action } or nil,
        after = nxt and { name = nxt.name, action = nxt.action } or nil,
      }
      if s.dungeon and self.E:completed(i, gid) then sig.reason = "engine-dungeon-skip" end
      sig.qname = self:quest_name(sig.qid)
      sig.confidence = self:confidence(sig.qid)
      self.log.signals[#self.log.signals + 1] = sig
    end
  end
  for _, q in ipairs(self:log_qids()) do
    self:signal("leftover-quests", nil, { gid = gid, file = info.file, qid = q })
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
    if not self.is_harness_error(errs[i]) then self.addon_errors = self.addon_errors + 1 end
  end
  self.err_cursor = #errs
  return self.addon_errors
end

-- Ruling P: only when every listed QID excludes the character (a multi-QID step
-- lists race/class variants; one admitting id is enough). A QID the catalog does
-- not know admits. One signal per (gid, index), with the first id's reason.
function Driver:wrong_race_class(cur)
  local W = self.W
  local p = W.player
  local key = cur.gid .. ":" .. cur.index
  local qids = cur.qids or {}
  if #qids == 0 or self.race_class_seen[key] then return end
  local first_qid, first_reason
  for _, q in ipairs(qids) do
    local quest = W.catalog and W.catalog:quest(q)
    local reason
    if quest then
      if quest.races and not contains(quest.races, p.race_token) then reason = "race"
      elseif quest.classes and not contains(quest.classes, p.class_token) then reason = "class" end
    end
    if not reason then return end
    if not first_reason then first_qid, first_reason = q, reason end
  end
  self.race_class_seen[key] = true
  self:signal("wrong-race-class", cur, { qid = first_qid, reason = first_reason })
end

function Driver:refusals(cur, out)
  if out.kind == "refused" then
    local r = out.reason
    if REFUSAL_SIGNALS[r] then
      self:signal(REFUSAL_SIGNALS[r], cur, { qid = out.qid, reason = r, outcome = out.kind })
    elseif r == "not-in-log" and (cur.action == "T" or cur.action == "C") then
      -- Every listed id the character never had (Review Focus 5).
      local history = self.W.log.history or {}
      for _, q in ipairs(cur.qids or {}) do
        if not self.W.log:get(q) and not history[q] then
          self:signal("orphan-turnin", cur, { qid = q, reason = r, outcome = out.kind })
        end
      end
    end
  elseif out.kind == "acted" and out.grind and cur.action == "A" then
    self:signal("below-level", cur, { qid = out.qid, reason = "below-level", outcome = out.kind,
      grind = { kills = out.grind.kills, to = out.grind.to } })
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
      levels = out.levels, grind = out.grind and { kills = out.grind.kills, to = out.grind.to } or nil,
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

-- Performs one shown step: before/after bookkeeping, wrong-race-class, the action,
-- its snapshot, settle-limit and refusal signals. Returns the outcome and snapshot.
function Driver:act(step, rows, info)
  for _, s in ipairs(self.awaiting) do s.after = { name = step.name, action = step.action } end
  self.awaiting = {}
  self.before_name, self.last_name = self.last_name, step.name
  self.before_action, self.last_action = self.last_action, step.action
  self:wrong_race_class(step)
  local why = self.E:why(step.index)
  self.acting = { gid = step.gid, index = step.index, why = why }
  local out = self.perform(self.ctx, step)
  if step.index > info.max_acted then info.max_acted = step.index end
  local snap = self:snapshot(step, why, rows, out)
  self:check_settle(out.settle, step)
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
  local E, W, opts = self.E, self.W, self.opts
  if W.player.level >= opts.stop_level then return self:stop("level") end
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
    return self:after_settle()
  end

  -- Stuck watchdog: the same (gid, index) acted on more than stuck_limit times in a row.
  local key = self.gid .. ":" .. cur.index
  self.repeats = (key == self.last_key) and self.repeats + 1 or 1
  self.last_key = key
  if self.repeats > opts.stuck_limit then
    self:signal("stuck", cur, { reason = "same-step" })
    return self:stop("stuck")
  end

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
    local expected = actions.expects_manual(cur)
    if not expected then
      self:signal("did-not-advance", cur, { qid = out.qid, reason = out.reason, outcome = out.kind })
    end
    local manual = self:signal("manual-completion", cur,
      { qid = out.qid, reason = out.reason, outcome = out.kind, expected = expected })
    -- An addon error inside the right-click is in sb.errors (a lua-error at the end)
    -- and becomes this signal's reason.
    local ok, merr = E:complete_manual(cur.index)
    if not ok then manual.reason = merr end
    self:check_settle(E:settle(), cur)
  end

  return self:after_settle()
end

-- Follow the engine's own guide switch (Review Focus 1): read the gid after every settle.
function Driver:after_settle()
  local E = self.E
  local new = E:gid()
  if new ~= nil and new ~= self.gid then
    self:close(self.gid, true)
    self.repeats, self.last_key = 0, nil
    return self:open(new)
  end
  if E:guide(self.gid).done then return self:stop("no-next-guide") end
  self:refresh_why()
end

function Driver:finish()
  local log, W = self.log, self.W
  self:close(self.gid, self.stopped == "no-next-guide")
  for _, e in ipairs(self.ctx.errors or {}) do
    local sig = { signal = "lua-error", message = e.msg, stack = first_stack_line(e.stack), level = W.player.level }
    if self.is_harness_error(e) then sig.reason = "harness" end
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
end

-- ctx = { engine, world, cfg, errors = sb.errors, missing_order = sb.missing_order,
-- addon = {path, branch, commit, dirty} }. opts as run.DEFAULTS, plus opts.perform
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
    variant = cfg.variant or o.variant,
    addon = { path = addon.path, branch = addon.branch, commit = addon.commit, dirty = addon.dirty },
    catalog = { sources = W.catalog and W.catalog.sources },
    rank = ctx.engine:rank(),
    steps = {}, signals = {}, guides = {},
  }
  local d = setmetatable({
    ctx = { engine = ctx.engine, world = W, cfg = cfg, errors = ctx.errors, missing_order = ctx.missing_order },
    E = ctx.engine, W = W, opts = o, log = log, info = {}, awaiting = {}, race_class_seen = {},
    iter = 0, repeats = 0, err_cursor = 0, addon_errors = 0,
    perform = o.perform or actions.perform,
    is_harness_error = o.is_harness_error or require("hwc.boot").is_harness_error,
  }, Driver)

  local gid = d.E:gid()
  if gid == nil then
    d:signal("stuck", nil, { reason = "no-guide-loaded" })
    d:stop("no-step")
  else
    d:open(gid)
  end
  while not d.stopped do d:iterate() end
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
    errors = result.sb.errors, missing_order = result.sb.missing_order, addon = result.addon,
  }, opts)
end

return run
