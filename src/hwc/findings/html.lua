-- Embeds the findings JSON in the committed HTML page (design spec §5). Pure
-- apart from template(), which reads the committed file.
local html = {}

html.PLACEHOLDER = "__HWC_REPORT_JSON__"

function html.template()
  local path = require("hwc.config").repo_root() .. "/src/hwc/findings/report.html"
  local f, err = io.open(path, "rb")
  if not f then error("findings: cannot read the report template " .. path .. ": " .. tostring(err), 0) end
  local s = f:read("*a")
  f:close()
  return s
end

-- Every "<" becomes the JSON escape <: the same string once decoded, and
-- stricter than escaping only "</" because it also defuses "<!--" inside the script.
function html.render(json_text, template)
  local safe = json_text:gsub("<", "\\u003c")
  local first, last = template:find(html.PLACEHOLDER, 1, true)
  if not first then error("findings: the report template has no " .. html.PLACEHOLDER .. " placeholder", 0) end
  if template:find(html.PLACEHOLDER, last + 1, true) then
    error("findings: the report template has more than one " .. html.PLACEHOLDER .. " placeholder", 0)
  end
  return template:sub(1, first - 1) .. safe .. template:sub(last + 1)
end

return html
