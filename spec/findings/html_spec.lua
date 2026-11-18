local html = require("hwc.findings.html")
local dkjson = require("dkjson")

local TEMPLATE = "<html><script type=\"application/json\" id=\"report\">" .. html.PLACEHOLDER .. "</script></html>"

local function embedded(out)
  return out:match('id="report">(.-)</script>')
end

describe("html.render", function()
  it("embeds the JSON in place of the placeholder", function()
    local out = html.render('{"a":1}', TEMPLATE)
    assert.equal('{"a":1}', embedded(out))
    assert.is_nil(out:find(html.PLACEHOLDER, 1, true))
  end)

  it("escapes < so a name can't close the script", function()
    local data = '{"name":"</script><!--x"}'
    local out = html.render(data, TEMPLATE)
    assert.is_nil(out:find("</script><!--", 1, true))
    assert.equal("</script><!--x", dkjson.decode(embedded(out)).name)
  end)

  it("keeps % in the data literal", function()
    local out = html.render('{"p":"100%s %1 %%"}', TEMPLATE)
    assert.equal("100%s %1 %%", dkjson.decode(embedded(out)).p)
  end)

  it("errors when the placeholder is missing or repeated", function()
    assert.has_error(function() html.render("{}", "<html></html>") end)
    assert.has_error(function() html.render("{}", html.PLACEHOLDER .. html.PLACEHOLDER) end)
  end)

  it("is byte-identical across two renders", function()
    assert.equal(html.render('{"a":"<"}', TEMPLATE), html.render('{"a":"<"}', TEMPLATE))
  end)
end)

describe("html.template", function()
  it("the committed template has the placeholder once and no network references", function()
    local t = html.template()
    local _, n = t:gsub(html.PLACEHOLDER, "")
    assert.equal(1, n)
    assert.is_nil(t:find("<script[^>]-%ssrc="))
    assert.is_nil(t:find("<link", 1, true))
    assert.is_nil(t:find("src%s*=%s*[\"']?http"))
    assert.is_nil(t:find("href%s*=%s*[\"']?http"))
    assert.is_nil(t:find("url%(%s*[\"']?http"))
    assert.is_nil(t:find("@import", 1, true))
  end)
end)
