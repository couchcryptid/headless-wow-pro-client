local questie = require("hwc.catalog.questie")

local FIX = "spec/fixtures/catalog/questie"
local PIN = "d57637f490c9dfcdbbc967dab47a8b0d8fe1b3cc"
local REAL = "local/questie/" .. PIN

local function write(path, text)
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end

local function copy_fixture()
  local dir = os.tmpname()
  os.remove(dir)
  os.execute("mkdir -p '" .. dir .. "' && cp " .. FIX .. "/* '" .. dir .. "/'")
  return dir
end

describe("questie.load", function()
  local data = questie.load(FIX)

  it("decodes quest rows into named fields using the file's own key table", function()
    local q = data.quests[1001]
    assert.are.equal("Fixture Wolves", q.name)
    assert.are.equal(3, q.requiredLevel)
    assert.are.equal(18, q.questLevel)
    assert.are.same({ { 2001 } }, q.startedBy)
    assert.are.same({ 1000 }, q.preQuestSingle)
    assert.are.same({ nil, nil, { { 5001, "Fixture Pelt" } } }, q.objectives)
    assert.are.equal(10, data.keys.quest.preQuestSingle)
    assert.is_nil(data.quests[424242])
  end)

  it("decodes npcs, items and objects", function()
    assert.are.equal("Fixture Boss", data.npcs[2003].name)
    assert.are.equal(1, data.npcs[2003].rank)
    assert.are.equal(11, data.npcs[2003].minLevel)
    assert.are.same({ { 10.5, 20.5 }, { 11, 21 } }, data.npcs[2001].spawns[12])
    assert.are.equal("Fixture Pelt", data.items[5001].name)
    assert.are.same({ 2003 }, data.items[5001].npcDrops)
    assert.are.equal("Fixture Chest", data.objects[3001].name)
  end)

  it("loads QuestXP with the traces file winning over the classic file", function()
    assert.are.same({ 18, 700 }, data.xp[1001])
    assert.are.same({ 13, 450 }, data.xp[1006])
  end)

  it("reads sha256 from SHA256SUMS", function()
    assert.matches("^%x+$", data.sha256["foreverQuestDB.lua"])
    assert.are.equal(64, #data.sha256["foreverQuestDB.lua"])
  end)

  it("fails with an error naming the file when a file calls io.open", function()
    local dir = copy_fixture()
    write(dir .. "/foreverNpcDB.lua", "local f = io.open('/etc/passwd')\n")
    local ok, err = pcall(questie.load, dir)
    os.execute("rm -rf '" .. dir .. "'")
    assert.is_false(ok)
    assert.matches("foreverNpcDB.lua", err, 1, true)
    assert.matches("io", err, 1, true)
  end)

  it("fails with an error naming the file when a file calls os.execute", function()
    local dir = copy_fixture()
    write(dir .. "/foreverItemDB.lua", "os.execute('true')\n")
    local ok, err = pcall(questie.load, dir)
    os.execute("rm -rf '" .. dir .. "'")
    assert.is_false(ok)
    assert.matches("foreverItemDB.lua", err, 1, true)
  end)

  it("fails with an error naming the file when a file reads an undefined global", function()
    local dir = copy_fixture()
    write(dir .. "/xpDB-classic.lua", "local x = SomethingUndefined\n")
    local ok, err = pcall(questie.load, dir)
    os.execute("rm -rf '" .. dir .. "'")
    assert.is_false(ok)
    assert.matches("xpDB-classic.lua", err, 1, true)
    assert.matches("SomethingUndefined", err, 1, true)
  end)

  it("fails with an error naming the file when a data string reaches for io", function()
    local dir = copy_fixture()
    write(dir .. "/foreverObjectDB.lua",
      "local QuestieDB = QuestieLoader:ImportModule('QuestieDB')\nQuestieDB.objectKeys = {name = 1}\n" ..
      "QuestieDB.objectData = [[return { [1] = {io.open('/etc/passwd')} }]]\n")
    local ok, err = pcall(questie.load, dir)
    os.execute("rm -rf '" .. dir .. "'")
    assert.is_false(ok)
    assert.matches("foreverObjectDB.lua", err, 1, true)
  end)

  it("records a missing file instead of failing", function()
    local dir = copy_fixture()
    os.remove(dir .. "/foreverQuestDB.lua")
    local d = questie.load(dir)
    os.execute("rm -rf '" .. dir .. "'")
    assert.are.same({ "foreverQuestDB.lua" }, d.missing)
    assert.is_nil(d.quests[1001])
    assert.are.same({}, questie.load(FIX).missing)
  end)
end)

local lfs = require("lfs")
local real_present = lfs.attributes(REAL, "mode") == "directory"

describe("questie.load (pinned data)", function()
  if not real_present then
    pending("pinned QuestieDB absent: run tools/fetch-questie.sh " .. PIN)
    return
  end

  local data = questie.load(REAL)

  it("has preQuestSingle at field 13 (read from the file, not hard-coded)", function()
    assert.are.equal(13, data.keys.quest.preQuestSingle)
  end)

  it("decodes known rows", function()
    assert.are.same({ 218 }, data.quests[282].preQuestSingle)
    assert.are.same({ { 786 } }, data.quests[282].startedBy)
    assert.are.same({ { 1965 } }, data.quests[282].finishedBy)
    assert.are.equal("Vagash", data.npcs[1388].name)
    assert.are.equal(1, data.npcs[1388].rank)
    assert.are.equal("Tough Wolf Meat", data.items[750].name)
  end)

  it("carries sha256 values for every pinned file", function()
    assert.are.equal(64, #data.sha256["foreverQuestDB.lua"])
    assert.are.equal(64, #data.sha256["xpDB-traces.lua"])
  end)
end)
