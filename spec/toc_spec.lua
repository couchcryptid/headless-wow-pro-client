local toc = require("hwc.toc")
local skiplist = require("hwc.skiplist")
local config = require("hwc.config")

local function rels(entries)
  local t = {}
  for i, e in ipairs(entries) do t[i] = e.rel end
  return t
end

local function find(entries, rel)
  for i, e in ipairs(entries) do
    if e.rel == rel then return e, i end
  end
end

describe("toc.files (fixture addon)", function()
  local root = "spec/fixtures/addon"

  it("returns the client load order with XML expanded and [Game] resolved", function()
    local entries = toc.files(root, "Fix/Fix.toc", "Forever")
    assert.same({
      "Fix/Libs/A.lua",
      "Fix/Libs/Sub/C.lua",
      "Fix/Libs/B.lua",
      "Fix/Data_Forever.lua",
      "Fix/Main.lua",
      "Fix/Gone.lua",
      "Fix/forever/G1.lua",
    }, rels(entries))
    assert.equal("toc", entries[4].source)
    assert.equal("xml", entries[1].source)
    assert.is_false(entries[1].skipped)
    assert.is_nil(find(entries, "Fix/Libs/Hidden.lua"))
    assert.equal("missing on disk", find(entries, "Fix/Gone.lua").skipped)
    assert.truthy(entries[1].path:match("^/"))
  end)

  it("matches [Game] directories case-insensitively using the on-disk spelling", function()
    local entries = toc.files(root, "Fix/Case.toc", "Forever")
    assert.equal("Fix/forever/G1.lua", entries[#entries].rel)
    assert.is_false(entries[#entries].skipped)
  end)
end)

describe("skiplist.reason", function()
  it("skips reviewed libraries, UI files and Ace UI parts with a reason", function()
    assert.is_string(skiplist.reason("WoWPro/Libraries/LibSharedMedia-3.0/lib.xml"))
    assert.is_string(skiplist.reason("WoWPro/Libraries/HereBeDragons/HereBeDragons-2.0.lua"))
    assert.is_string(skiplist.reason("WoWPro/Libraries/Ace/AceGUI-3.0/AceGUI-3.0.xml"))
    assert.is_string(skiplist.reason("WoWPro/WoWPro_Config.lua"))
    assert.is_string(skiplist.reason("WoWPro_Leveling/WoWPro_Leveling_Frames.lua"))
  end)

  it("does not skip engine files", function()
    assert.is_nil(skiplist.reason("WoWPro/WoWPro_Frames.lua"))
    assert.is_nil(skiplist.reason("WoWPro/WoWPro_RowUpdate.lua"))
    assert.is_nil(skiplist.reason("WoWPro/Libraries/Ace/LibStub/LibStub.lua"))
  end)
end)

describe("toc.files (real addon)", function()
  local ok, cfg = pcall(config.load, {})
  local root = ok and cfg.addon_path

  it("expands WoWPro.toc in client order", function()
    if not ok then return pending("addon checkout not found") end
    local entries = toc.files(root, "WoWPro/WoWPro.toc", "Forever")
    assert.equal("WoWPro/Libraries/Ace/LibStub/LibStub.lua", entries[1].rel)
    local _, forever = find(entries, "WoWPro/WoWPro_ZoneData_Forever.lua")
    local _, patches = find(entries, "WoWPro/WoWPro_ZoneData_Patches.lua")
    assert.truthy(forever)
    assert.truthy(patches)
    assert.is_true(forever < patches)
    assert.is_truthy(find(entries, "WoWPro/WoWPro_Config.lua").skipped)
    assert.is_truthy(find(entries, "WoWPro/Libraries/Ace/AceGUI-3.0/AceGUI-3.0.xml").skipped)
    local row = find(entries, "WoWPro/WoWPro_RowUpdate.lua")
    assert.is_false(row.skipped)
  end)

  it("expands WoWPro_Leveling.toc to the Forever guide files", function()
    if not ok then return pending("addon checkout not found") end
    local entries = toc.files(root, "WoWPro_Leveling/WoWPro_Leveling.toc", "Forever")
    local e = find(entries, "WoWPro_Leveling/Forever/Alliance/01_12_Dun_Morogh.lua")
    assert.truthy(e)
    assert.is_false(e.skipped)
    assert.truthy(find(entries, "WoWPro_Leveling/Forever/Alliance/14_24_Dungeon_Deadmines.lua"))
    assert.is_nil(find(entries, "WoWPro_Leveling/Forever/Alliance/15_24_Dungeon_Wailing_Caverns.lua"))
  end)
end)
