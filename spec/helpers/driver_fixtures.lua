-- Shared spec helpers for the driver action specs: a fake engine and a real World
-- on the fixture catalog.
local catalog = require("hwc.catalog")
local World = require("hwc.world")

local FIX = "spec/fixtures/catalog"

local function new_catalog()
  return catalog.load({ catalog = {
    questie_dir = FIX .. "/questie",
    wh_json = FIX .. "/wh.json",
    objs_json = FIX .. "/objs.json",
    rate_overrides = FIX .. "/rate_overrides.json",
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

return { new_catalog = new_catalog, fake_engine = fake_engine, step = step, setup = setup, names = names, has_event = has_event }
