-- Lint config for `luacheck .` (run in CI on every pull request).
std = "luajit"
-- Long lines carry addon file:line citations and fixture data; length is not policed.
max_line_length = false
-- Handlers share one signature per dispatch table (driver actions, frame
-- metamethods, stubs), so an unused argument is the norm, not a smell.
unused_args = false

include_files = { "src/**/*.lua", "spec/**/*.lua", "tools/**/*.lua", "bin/hwc.lua", ".busted", ".luacheckrc" }
-- Third-party code is kept byte-identical to upstream.
exclude_files = { "src/hwc/vendor/**" }

-- polyfills.lua adds string.split/string.trim the way the game client does.
files["src/hwc/polyfills.lua"] = { globals = { "string" } }

files["spec/**"] = {
  std = "+busted",
  -- Specs stub io/os functions and restore them after each case.
  globals = { "io", "os" },
  -- Unpacked-but-unused fixture returns (`local w, E = ...`) and shadowed locals in nested cases.
  ignore = { "211", "431" },
}
-- Fixture guides are addon files: they register on the WoWPro global the sandbox provides.
files["spec/fixtures/**"] = { globals = { "WoWPro" } }
