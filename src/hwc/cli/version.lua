-- hwc version (and --version): the client's release tag and commit (design §4.7).
local version = {}

-- info = { git, describe, commit, dirty } -> the one line printed. Pure.
function version.text(info)
  if not info.git then return "hwc unknown version\n" end
  local short = tostring(info.commit):sub(1, 7)
  if not info.describe then return "hwc unreleased (" .. short .. ")\n" end
  return "hwc " .. info.describe .. " (" .. short .. ")" .. (info.dirty and " (dirty)" or "") .. "\n"
end

-- `git describe --tags --abbrev=0` in root, or nil when there is no tag.
local function describe(root)
  local p = io.popen("git -C '" .. root .. "' describe --tags --abbrev=0 2>/dev/null", "r")
  if not p then return nil end
  local out = p:read("*a"):gsub("%s+$", "")
  p:close()
  return out ~= "" and out or nil
end

version.name = "version"
version.summary = "Print the version"
version.description = "Print hwc's release tag and commit."

function version.run(ctx)
  local root = require("hwc.config").repo_root()
  local a = require("hwc.addon_info").read(root, { tracked_only = true })
  local info = { git = a.git, commit = a.commit, dirty = a.dirty }
  if a.git then info.describe = describe(root) end
  ctx.ui:result(version.text(info))
  return 0
end

return version
