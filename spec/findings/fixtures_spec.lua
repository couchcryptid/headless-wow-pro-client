-- The fixtures are the format contract between Lua and the TypeScript page.
local fixtures = dofile(require("hwc.config").repo_root() .. "/tools/report-fixtures.lua")

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

describe("report fixtures", function()
  for _, name in ipairs({ "single", "matrix", "empty" }) do
    it("committed fixture " .. name .. " matches what report.build produces now", function()
      local path = require("hwc.config").repo_root() .. "/spec/fixtures/findings/" .. name .. ".json"
      assert.equal(fixtures.build()[name], read(path),
        name .. ".json is stale: run `luajit tools/report-fixtures.lua` and commit the result")
    end)
  end
end)
