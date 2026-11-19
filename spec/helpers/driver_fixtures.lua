-- Shared spec helpers for the driver action specs: a fake engine and a real World
-- on the fixture catalog.
local catalog = require("hwc.catalog")
local World = require("hwc.world")

local FIX = "spec/fixtures/catalog"

local function new_catalog()
  return catalog.load({ catalog = {
    questie_source = dofile(FIX .. "/questie_source.lua"),
    supplement = FIX .. "/actions_supplement.json",
  } })
end

-- Fake engine: fire records { event, args... }, settle reports no limit hit,
-- step/num_steps serve a scripted guide, update_guide counts calls.
local function fake_engine(steps)
  local E = { fired = {}, settles = 0, updates = 0, steps = steps or {} }
  function E:fire(event, ...) self.fired[#self.fired + 1] = { event, ... } end
  function E:settle() self.settles = self.settles + 1; return { ran = 0, now = 0, hit_limit = false } end
  function E:step(i) return self.steps[i] end
  function E:num_steps() return #self.steps end
  function E:update_guide() self.updates = self.updates + 1; return true end
  return E
end

local function step(action, qids, tags, name)
  return { index = 1, action = action, name = name or "x", qids = qids, tags = tags or {} }
end

local function setup(race, steps)
  local w = World.new({ race = race or "Dwarf", class = "WARRIOR", faction = "Alliance", sex = 2 }, new_catalog())
  local E = fake_engine(steps)
  return { engine = E, world = w, cfg = {} }, E, w
end

local function names(E)
  local out = {}
  for i, f in ipairs(E.fired) do out[i] = f[1] end
  return out
end

local function has_event(w, kind)
  for _, e in ipairs(w.events) do
    if e.kind == kind then return e end
  end
  return nil
end

-- Scripted engine for the driver loop specs (spec/driver/run_spec.lua).
-- guides = { [gid] = { startlevel, next_gid, file, steps = { {action, name, qids, tags,
--   sticky, hidden (never in rows), why, outcome = {kind, reason, grind}} } } }.
-- script = { [gid] = { [index] = { complete = {i...}, switch = gid, level = n, done = bool,
--   on_manual = { uncomplete = {i...}, switch = gid } } } }: the settle after the
-- driver acts on (or right-clicks) gid:index applies the entry. With no entry an
-- action completes nothing. Rows are the uncompleted indices, sticky ones first;
-- current is the first uncompleted non-sticky index (as the adapter reads it).
local function scripted_engine(guides, script, start, world)
  local E = { guides = guides, script = script or {}, cur_gid = start, done = {}, comp = {},
    manual = {}, settles = 0, pending = nil, world = world, hit_limit = {} }
  for gid in pairs(guides) do E.comp[gid] = {} end
  local function steps() return E.guides[E.cur_gid].steps end
  function E:gid() return self.cur_gid end
  function E:guide(gid)
    gid = gid or self.cur_gid
    local g = self.guides[gid] or {}
    return { gid = gid, startlevel = g.startlevel, endlevel = g.endlevel, next_gid = g.next_gid,
      file = g.file, done = self.done[gid] }
  end
  function E:step(i)
    local s = steps()[i]
    if not s then return nil end
    return { index = i, gid = self.cur_gid, action = s.action, name = s.name, qids = s.qids or {},
      tags = s.tags or {}, rep = s.rep, line = 100 + i }
  end
  function E:num_steps() return #steps() end
  function E:completed(i, gid) return self.comp[gid or self.cur_gid][i] == true end
  function E:why(i) return steps()[i] and steps()[i].why end
  function E:rows()
    local out = {}
    for pass = 1, 2 do
      for i, s in ipairs(steps()) do
        if not self.comp[self.cur_gid][i] and not s.hidden and ((pass == 1) == (s.sticky == true)) then
          local st = self:step(i)
          st.sticky = s.sticky == true
          out[#out + 1] = st
        end
      end
    end
    return out
  end
  function E:current()
    for i, s in ipairs(steps()) do
      if not self.comp[self.cur_gid][i] and not s.sticky and not s.hidden then return self:step(i) end
    end
    return nil
  end
  function E:fire() end
  function E:rank() return 2 end
  E.skip_dungeons = function() return true end
  -- The guide-list click: loads gid and records it in E.loaded.
  E.loaded = {}
  function E:load_guide(gid)
    self.loaded[#self.loaded + 1] = gid
    self.cur_gid = gid
    self:settle()
    return true
  end
  function E:update_guide() return true end
  function E:complete_manual(i)
    self.manual[#self.manual + 1] = self.cur_gid .. ":" .. i
    self.comp[self.cur_gid][i] = true
    local s = steps()[i]
    if s.action == "D" then self.done[self.cur_gid] = true end
    self.pending = { gid = self.cur_gid, index = i, manual = true }
    return true
  end
  function E:settle()
    self.settles = self.settles + 1
    local p = self.pending
    self.pending = nil
    local hit = false
    if p then
      local entry = self.script[p.gid] and self.script[p.gid][p.index]
      if entry and p.manual then entry = entry.on_manual end
      if entry then
        for _, i in ipairs(entry.complete or {}) do self.comp[p.gid][i] = true end
        for _, i in ipairs(entry.uncomplete or {}) do self.comp[p.gid][i] = nil end
        if entry.level and self.world then self.world.player.level = entry.level end
        if entry.done then self.done[p.gid] = true end
        if entry.switch then self.cur_gid = entry.switch end
        hit = entry.hit_limit == true
      end
    end
    return { ran = 0, now = 0, hit_limit = hit }
  end
  -- perform stand-in: records the acted index, returns the step's scripted outcome.
  function E.perform(ctx, step)
    local s = E.guides[E.cur_gid].steps[step.index]
    E.acted = E.acted or {}
    E.acted[#E.acted + 1] = E.cur_gid .. ":" .. step.index
    E.pending = { gid = E.cur_gid, index = step.index }
    local o = s.outcome or { kind = "acted" }
    local out = { kind = o.kind, reason = o.reason, qid = (step.qids or {})[1], events = {}, levels = 0,
      grind = o.grind, level_grind = o.level_grind, elite = false, abstracted_turnin = o.abstracted_turnin, missing = o.missing,
      missing_any = o.missing_any, arrivals = o.arrivals }
    -- o.records: world events this step's action leaves behind (quest_accept / quest_turn_in).
    for _, rec in ipairs(o.records or {}) do ctx.world.events[#ctx.world.events + 1] = rec end
    out.settle = E:settle()
    return out
  end
  return E
end

-- Minimal world for the driver loop: player, a quest log of qids and a catalog table.
local function fake_world(quests, log_qids)
  -- The real Player:add_xp, so a level raise is recorded as XP (w.xp_records).
  local w = { xp_records = {}, events = {} }
  w.player = setmetatable({ level = 1, xp = 0, race_token = "Dwarf", class_token = "WARRIOR", skills = {},
    _record = function(kind, f) if kind == "xp" then w.xp_records[#w.xp_records + 1] = f end end },
    require("hwc.world.player"))
  function w.player.knows_skill(self, name) return self.skills[name] ~= nil end
  local order = log_qids or {}
  w.log = {
    entries = function() local out = {} for i, q in ipairs(order) do out[i] = { id = q, quest = (quests or {})[q] } end return out end,
    get = function(_, q) for _, x in ipairs(order) do if x == q then return { id = q } end end return nil end,
    history = {},
  }
  w.catalog = { quest = function(_, q) return (quests or {})[q] end,
    -- A quest table's `chain = { part, total }` stands in for the catalog's chain_part.
    chain_part = function(_, q)
      local x = (quests or {})[q]
      if x and x.chain then return x.chain[1], x.chain[2] end
    end }
  return w
end

return { scripted_engine = scripted_engine, fake_world = fake_world, new_catalog = new_catalog, fake_engine = fake_engine, step = step, setup = setup, names = names, has_event = has_event }
