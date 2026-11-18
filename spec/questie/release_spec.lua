local lfs = require("lfs")
local dkjson = require("dkjson")
local release = require("hwc.questie.release")

local function fixture(name)
  local f = assert(io.open("spec/fixtures/questie/" .. name, "rb"))
  local v = dkjson.decode(f:read("*a"))
  f:close()
  return v
end

-- Serves the canned GitHub API by URL and records every URL asked for.
local function fake_github(manifests)
  local list = fixture("releases.json")
  local served, asked = {}, {}
  served[release.API .. "/releases?per_page=30"] = list
  for _, rel in ipairs(list) do
    served[release.API .. "/releases/tags/" .. rel.tag_name] = rel
  end
  served["https://example.test/v1.1.2/release.json"] = fixture("release-v1.1.2.json")
  served["https://example.test/v1.1.3/release.json"] = fixture("release-v1.1.3.json")
  for url, v in pairs(manifests or {}) do served[url] = v end
  return function(url)
    asked[#asked + 1] = url
    local v = served[url]
    if v == nil then return nil, "hwc: GET " .. url .. " failed (curl exit 22)" end
    return v
  end, asked
end

local function tmpdir()
  local d = os.tmpname()
  os.remove(d)
  assert(lfs.mkdir(d))
  return d
end

describe("release.select", function()
  it("takes the newest non-draft, non-prerelease with a Forever build", function()
    local get, asked = fake_github()
    local sel = assert(release.select(get, {}))
    assert.are.equal("v1.1.2", sel.tag)
    assert.are.same({ "v1.1.3" }, sel.skipped)
    assert.are.equal("QuestieDB-1.1.2-Forever.zip", sel.asset_name)
    assert.are.equal("https://example.test/v1.1.2/QuestieDB-1.1.2-Forever.zip", sel.asset_url)
    assert.are.equal(10, sel.asset_size)
    assert.are.equal("ddddddd", sel.build_commit)
    assert.are.equal(release.API .. "/releases?per_page=30", asked[1])
  end)

  it("selects a given tag", function()
    local get, asked = fake_github()
    local sel = assert(release.select(get, { tag = "v1.1.2" }))
    assert.are.equal("v1.1.2", sel.tag)
    assert.are.equal(release.API .. "/releases/tags/v1.1.2", asked[1])
  end)

  it("rejects a tag whose release.json has no Forever entry", function()
    local get = fake_github()
    assert.are.same({ nil, "hwc: questie: v1.1.3 has no Forever build" },
      { release.select(get, { tag = "v1.1.3" }) })
  end)

  it("rejects a non-version tag without any request", function()
    local get, asked = fake_github()
    assert.are.same({ nil, "hwc: questie: preview is not a version tag (vX.Y.Z)" },
      { release.select(get, { tag = "preview" }) })
    assert.are.equal(0, #asked)
  end)

  it("skips non-version tags in the walk without listing them as skipped", function()
    local get = fake_github()
    local list = fixture("releases.json")
    table.insert(list, 1, {
      tag_name = "v1.2.0-hotfix", draft = false, prerelease = false, target_commitish = "eeeeeee",
      assets = list[4].assets,
    })
    local get_list = function(url)
      if url == release.API .. "/releases?per_page=30" then return list end
      return get(url)
    end
    local sel = assert(release.select(get_list, {}))
    assert.are.equal("v1.1.2", sel.tag)
    assert.are.same({ "v1.1.3" }, sel.skipped)
  end)

  it("passes a get_json failure through", function()
    local err = "hwc: GET x failed (curl exit 22)"
    local get = function() return nil, err end
    assert.are.same({ nil, err }, { release.select(get, {}) })
    assert.are.same({ nil, err }, { release.select(get, { tag = "v1.1.2" }) })
  end)
end)

describe("release contract", function()
  local dir
  before_each(function()
    dir = tmpdir()
    lfs.mkdir(dir .. "/QuestieDB")
    lfs.mkdir(dir .. "/QuestieDB/src")
  end)
  after_each(function() os.execute("rm -rf '" .. dir .. "'") end)

  local function write(rel, text)
    local f = assert(io.open(dir .. "/" .. rel, "wb"))
    f:write(text)
    f:close()
  end

  it("reads min and max from config.lua", function()
    write("QuestieDB/src/config.lua", "config.contractVersion = 5\nconfig.minSupportedContract = 4\n")
    local range = release.contract_range(dir)
    assert.are.same({ min = 4, max = 5 }, range)
    assert.is_true(release.contract_ok(range))
  end)

  it("uses max for min when minSupportedContract is absent", function()
    write("QuestieDB/src/config.lua", "config.contractVersion = 4\n")
    assert.are.same({ min = 4, max = 4 }, release.contract_range(dir))
  end)

  it("falls back to the TOC X-Contract-Version without config.lua", function()
    write("QuestieDB/QuestieDB_Forever.toc", "## X-Contract-Version: 4\nfile.lua\n")
    assert.are.same({ min = 4, max = 4 }, release.contract_range(dir))
  end)

  it("errors when neither source has a contract", function()
    local range, err = release.contract_range(dir)
    assert.is_nil(range)
    assert.is_truthy(err:match("^hwc: questie: cannot determine the contract version"))
  end)

  it("rejects a range that excludes 4 with the exact message", function()
    assert.are.same({ false, "QuestieDB contract 5-6 does not include 4 (hwc is built for 4)" },
      { release.contract_ok({ min = 5, max = 6 }) })
  end)
end)
