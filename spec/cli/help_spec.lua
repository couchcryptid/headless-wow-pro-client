local help = require("hwc.cli.help")

local function decl()
  return {
    name = "run",
    summary = "Play one character.",
    usage = "--race RACE --class CLASS [options]",
    description = "Play one character along the chain.",
    options = {
      {
        name = "race", metavar = "RACE", required = true, help = "Player race.",
        choices = function() return { "Dwarf", "Gnome" } end,
        see = "hwc list races",
      },
      {
        name = "class", metavar = "CLASS", help = "Player class.",
        choices = function() return { "A", "B", "C", "D", "E", "F" } end,
        see = "hwc list classes RACE",
      },
      { name = "json", flag = true, help = "Machine output." },
    },
    notes = { "Filter rules apply." },
  }
end

describe("help.command", function()
  local text = help.command(decl())
  it("starts with the usage line", function()
    assert.equal("Usage: hwc run --race RACE --class CLASS [options]", text:match("^[^\n]*"))
  end)
  it("marks required options", function()
    assert.truthy(text:find("(required)", 1, true))
  end)
  it("lists short choices inline and long ones via see", function()
    assert.truthy(text:find("Dwarf, Gnome", 1, true))
    assert.falsy(text:find("A, B, C", 1, true))
    assert.truthy(text:find("hwc list classes RACE", 1, true))
  end)
  it("prints notes after Options", function()
    assert.is_true(text:find("Options:", 1, true) < text:find("Filter rules apply.", 1, true))
  end)
  it("shows a flag without a metavar", function()
    assert.truthy(text:find("  --json  ", 1, true))
  end)
end)

describe("help.usage", function()
  it("lists visible commands in order and ends with the hint", function()
    local text = help.usage({
      { name = "run", summary = "Run it." },
      { name = "secret", summary = "Hidden.", hidden = true },
      { name = "diff", summary = "Compare." },
    })
    assert.truthy(text:find("run", 1, true))
    assert.falsy(text:find("secret", 1, true))
    assert.is_true(text:find("run", 1, true) < text:find("diff", 1, true))
    assert.truthy(text:find("--version", 1, true))
    assert.equal("Run hwc help <command> for its options.\n", text:sub(-40))
  end)
end)

describe("hwc arrivals help", function()
  it("is listed in the top-level usage", function()
    local commands = require("hwc.cli.commands")
    assert.truthy(help.usage(commands.list):find("arrivals", 1, true))
  end)
end)
