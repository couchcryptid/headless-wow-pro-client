local args = require("hwc.cli.args")

local function decl()
  return {
    name = "run",
    positionals = { min = 0, max = 0 },
    options = {
      {
        name = "race",
        metavar = "RACE",
        required = true,
        choices = function()
          return { "Dwarf", "Gnome" }
        end,
      },
      { name = "class", metavar = "CLASS", required = true },
      { name = "json", flag = true },
      { name = "include", metavar = "PATTERN", filter = true },
      { name = "exclude", metavar = "PATTERN", filter = true },
      {
        name = "date",
        metavar = "D",
        validate = function(v)
          if v == "bad" then
            return nil, "--date bad is not a date"
          end
          return v:upper()
        end,
      },
      { name = "n", metavar = "N" },
    },
  }
end

describe("args.parse", function()
  it("accepts --race Dwarf and --race=dwarf, canonicalising", function()
    local a = args.parse(decl(), { "--race", "Dwarf", "--class", "X" })
    assert.equal("Dwarf", a.race)
    local b = args.parse(decl(), { "--race=dwarf", "--class=X" })
    assert.equal("Dwarf", b.race)
    assert.equal("X", b.class)
  end)

  it("rejects a value that looks like an option", function()
    local o, msg = args.parse(decl(), { "--race", "--class", "WARRIOR" })
    assert.is_nil(o)
    assert.equal("--race needs a value", msg)
  end)

  it("rejects a trailing option with no value", function()
    local o, msg = args.parse(decl(), { "--class" })
    assert.is_nil(o)
    assert.equal("--class needs a value", msg)
  end)

  it("accepts a single-dash value", function()
    local o = args.parse(decl(), { "--race", "Dwarf", "--class", "X", "--n", "-5" })
    assert.equal("-5", o.n)
  end)

  it("names the command for an unknown option", function()
    local o, msg = args.parse(decl(), { "--colour", "x" })
    assert.is_nil(o)
    assert.equal("unknown option --colour for hwc run", msg)
  end)

  it("rejects an unknown single-dash option", function()
    local o, msg = args.parse(decl(), { "--race", "Dwarf", "--class", "X", "-c" })
    assert.is_nil(o)
    assert.equal("unknown option -c for hwc run", msg)
    o, msg = args.parse(decl(), { "-5" })
    assert.is_nil(o)
    assert.equal("unknown option -5 for hwc run", msg)
  end)

  it("keeps a lone - and words after -- as positionals", function()
    local d = { name = "q", options = {}, positionals = { min = 2, max = 2, noun = "words" } }
    local o = args.parse(d, { "-", "--", "-c" })
    assert.same({ "-", "-c" }, o.positionals)
  end)

  it("rejects an empty inline value", function()
    for _, a in ipairs({ "--race=", "--class=", "--n=" }) do
      local o, msg = args.parse(decl(), { a })
      assert.is_nil(o)
      assert.equal(a:sub(1, -2) .. " needs a value", msg)
    end
  end)

  it("names the replacement for a renamed option", function()
    local d = decl()
    d.renamed = { variant = "--professions" }
    local o, msg = args.parse(d, { "--variant", "x" })
    assert.is_nil(o)
    assert.equal("unknown option --variant for hwc run; use --professions", msg)
    o, msg = args.parse(d, { "--variant=x" })
    assert.is_nil(o)
    assert.equal("unknown option --variant for hwc run; use --professions", msg)
  end)

  it("reports a missing required option", function()
    local o, msg = args.parse(decl(), { "--race", "Dwarf" })
    assert.is_nil(o)
    assert.equal("missing --class", msg)
  end)

  it("reports a bad choice with the list", function()
    local o, msg = args.parse(decl(), { "--race", "Dwarff", "--class", "X" })
    assert.is_nil(o)
    assert.equal("--race Dwarff is not a race; races: Dwarf, Gnome", msg)
  end)

  it("rejects a value on a flag", function()
    local o, msg = args.parse(decl(), { "--json=yes" })
    assert.is_nil(o)
    assert.equal("--json takes no value", msg)
  end)

  it("sets flags", function()
    local o = args.parse(decl(), { "--race", "Dwarf", "--class", "X", "--json" })
    assert.is_true(o.json)
  end)

  it("keeps filters in order", function()
    local o = args.parse(decl(), {
      "--race", "Dwarf", "--class", "X",
      "--include", "a", "--exclude", "b", "--include", "c",
    })
    assert.same({
      { kind = "include", raw = "a" },
      { kind = "exclude", raw = "b" },
      { kind = "include", raw = "c" },
    }, o.filters)
  end)

  it("last single value wins", function()
    local o = args.parse(decl(), { "--race", "Dwarf", "--class", "A", "--class", "B" })
    assert.equal("B", o.class)
  end)

  it("enforces positional counts", function()
    local d = decl()
    d.options = {}
    d.name = "diff"
    d.positionals = { min = 2, max = 2, noun = "files" }
    local o, msg = args.parse(d, { "a", "b", "c" })
    assert.is_nil(o)
    assert.equal("diff needs 2 files, got 3", msg)
    o, msg = args.parse(d, { "a" })
    assert.is_nil(o)
    assert.equal("diff needs 2 files, got 1", msg)
    o = args.parse(d, { "a", "b" })
    assert.same({ "a", "b" }, o.positionals)
  end)

  it("words a range of positionals", function()
    local d = { name = "list", options = {}, positionals = { min = 0, max = 2, noun = "arguments" } }
    local _, msg = args.parse(d, { "a", "b", "c" })
    assert.equal("list needs 0-2 arguments, got 3", msg)
  end)

  it("treats words after -- as positional", function()
    local d = { name = "q", options = { { name = "json", flag = true } }, positionals = { min = 1, max = 1, noun = "words" } }
    local o = args.parse(d, { "--", "--json" })
    assert.same({ "--json" }, o.positionals)
    assert.is_nil(o.json)
  end)

  it("passes a validator message through", function()
    local o, msg = args.parse(decl(), { "--race", "Dwarf", "--class", "X", "--date", "bad" })
    assert.is_nil(o)
    assert.equal("--date bad is not a date", msg)
    o = args.parse(decl(), { "--race", "Dwarf", "--class", "X", "--date", "ok" })
    assert.equal("OK", o.date)
  end)

  it("runs check last", function()
    local d = decl()
    d.check = function(o)
      return "check saw " .. o.race
    end
    local _, msg = args.parse(d, { "--race", "Dwarf", "--class", "X" })
    assert.equal("check saw Dwarf", msg)
    _, msg = args.parse(d, { "--race", "Dwarf" })
    assert.equal("missing --class", msg)
  end)
end)

describe("args.globals", function()
  it("pulls globals from any position", function()
    local g = args.globals({ "run", "-q", "--race", "Dwarf", "--verbose" })
    assert.equal("run", g.command)
    assert.equal("verbose", g.level)
    assert.same({ "--race", "Dwarf" }, g.rest)
  end)

  it("defaults and reports help/version", function()
    local g = args.globals({ "--version", "-h" })
    assert.equal("normal", g.level)
    assert.is_true(g.version)
    assert.is_true(g.help)
    assert.is_nil(g.command)
    assert.same({}, g.rest)
  end)

  it("leaves everything after -- uninterpreted", function()
    local g = args.globals({ "run", "--", "--help", "-q" })
    assert.falsy(g.help)
    assert.equal("normal", g.level)
    assert.equal("run", g.command)
    assert.same({ "--", "--help", "-q" }, g.rest)
  end)

  it("does not take a command after --", function()
    local g = args.globals({ "--", "run" })
    assert.is_nil(g.command)
    assert.same({ "--", "run" }, g.rest)
  end)

  it("last of quiet/verbose wins", function()
    assert.equal("quiet", args.globals({ "-v", "-q" }).level)
  end)
end)

describe("args.suggest", function()
  it("finds the nearest", function()
    assert.equal("run", args.suggest("rnu", { "run", "diff" }))
  end)
  it("returns nil when far", function()
    assert.is_nil(args.suggest("zzzzz", { "run" }))
  end)
  it("breaks ties by order", function()
    assert.equal("aab", args.suggest("aac", { "aab", "aad" }))
  end)
end)
