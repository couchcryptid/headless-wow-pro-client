local convert = require("hwc.forever.convert")

local function fixture(name)
  local f = assert(io.open("spec/fixtures/forever/" .. name .. ".csv", "rb"))
  local text = f:read("*a")
  f:close()
  return text
end

local function col(t, name)
  for i, c in ipairs(t.columns) do
    if c == name then return i end
  end
end

describe("forever.convert", function()
  it("lists the five tables in order", function()
    local names = {}
    for _, t in ipairs(convert.TABLES) do names[#names + 1] = t.name end
    assert.same({ "TaxiNodes", "UiMap", "UiMapAssignment", "AreaTable", "WMOAreaTable" }, names)
  end)

  it("keeps only the kept TaxiNodes columns, numeric except the name", function()
    local t = convert.table("TaxiNodes", fixture("TaxiNodes"))
    assert.same({ "ID", "Name_lang", "ContinentID", "Flags", "Pos_0", "Pos_1" }, t.columns)
    local stormwind
    for _, row in ipairs(t.rows) do
      if row[col(t, "Name_lang")] == "Stormwind, Elwynn" then stormwind = row end
    end
    assert.is_table(stormwind)
    assert.same(6, #stormwind)
    for _, c in ipairs({ "ID", "ContinentID", "Flags", "Pos_0", "Pos_1" }) do
      assert.is_number(stormwind[col(t, c)], c)
    end
    assert.same(2, stormwind[col(t, "ID")])
    assert.is_true(stormwind[col(t, "Pos_0")] < -8800)
  end)

  it("converts every table with its kept columns", function()
    for _, spec in ipairs(convert.TABLES) do
      local t = convert.table(spec.name, fixture(spec.name))
      assert.same(spec.keep, t.columns)
      assert.is_true(#t.rows > 0, spec.name)
      for _, row in ipairs(t.rows) do assert.same(#spec.keep, #row) end
    end
  end)

  it("errors on a CSV missing Pos_1", function()
    local text = fixture("TaxiNodes"):gsub("Pos_1", "Pos_9", 1)
    local ok, err = pcall(convert.table, "TaxiNodes", text)
    assert.is_false(ok)
    assert.same("hwc: forever: TaxiNodes: missing column Pos_1", err)
  end)

  it("errors on an unknown table", function()
    local ok, err = pcall(convert.table, "Nope", "a\n1\n")
    assert.is_false(ok)
    assert.same("hwc: forever: unknown table Nope", err)
  end)
end)
