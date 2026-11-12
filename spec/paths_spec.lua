local paths = require("hwc.paths")

describe("hwc.paths", function()
  it("normalizes slashes, dots and trailing separators", function()
    assert.equal("/a/b/d", paths.normalize("/a//b/./c/../d/"))
    assert.equal("/", paths.normalize("/"))
  end)

  it("resolves relative paths against cwd", function()
    assert.equal("/p/x/a", paths.resolve("a", "/p/x"))
    assert.equal("/z", paths.resolve("/z/", "/p/x"))
  end)

  it("computes relative paths", function()
    assert.equal(".", paths.relative("/p/x", "/p/x"))
    assert.equal("local/q", paths.relative("/p/x/local/q", "/p/x"))
    assert.equal("../WoW-Pro-Guides", paths.relative("/p/WoW-Pro-Guides", "/p/x"))
    assert.equal("../../q/r", paths.relative("/q/r", "/p/x"))
  end)

  describe("rewrite", function()
    it("replaces the longest root first", function()
      assert.equal("@local/addon/A.lua:3",
        paths.rewrite("@/p/x/local/addon/A.lua:3", { "/p/x", "/p/x/local/addon" }, "/p/x", "/p/x"))
    end)

    it("resolves a relative root against cwd first", function()
      assert.equal("local/addon/main/W.lua",
        paths.rewrite("/p/x/local/addon/main/W.lua", { "local/addon/main" }, "/p/x", "/p/x"))
    end)

    it("does not touch a sibling that shares a prefix", function()
      assert.equal("/p/WoW-Pro-Guides-old/x",
        paths.rewrite("/p/WoW-Pro-Guides-old/x", { "/p/WoW-Pro-Guides" }, "/p/x", "/p/x"))
    end)

    it("rewrites nested tables without mutating the input", function()
      local input = { a = { "/p/x/f.lua", "WoWPro_Leveling/F/a.lua" }, n = 5, ok = true }
      local out = paths.rewrite(input, { "/p/x" }, "/p/x", "/p/x")
      assert.equal("f.lua", out.a[1])
      assert.equal("WoWPro_Leveling/F/a.lua", out.a[2])
      assert.equal(5, out.n)
      assert.equal(true, out.ok)
      assert.equal("/p/x/f.lua", input.a[1])
    end)

    it("handles roots followed by quotes, parens and whitespace, and ignores empty roots", function()
      assert.equal("'.' (../w) ok",
        paths.rewrite("'/p/x' (/p/w) ok", { "/p/x", "/p/w", "", false }, "/p/x", "/p/x"))
    end)

    it("turns a bare base root into a dot", function()
      assert.equal("cwd is .", paths.rewrite("cwd is /p/x", { "/p/x" }, "/p/x", "/p/x"))
    end)

    it("does not rewrite keys and survives cycles", function()
      local t = { ["/p/x"] = "/p/x/a" }
      t.self = t
      local out = paths.rewrite(t, { "/p/x" }, "/p/x", "/p/x")
      assert.equal("a", out["/p/x"])
      assert.equal(out, out.self)
    end)
  end)
end)
