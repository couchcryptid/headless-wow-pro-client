-- Removed commands, kept one release as stubs (design §4): hidden from help and
-- from "did you mean", their arguments unparsed, each prints one line and exits 2.
local function stub(name, line)
  return {
    name = name,
    hidden = true,
    passthrough = true,
    summary = line,
    run = function(ctx)
      ctx.ui.err:write(line, "\n")
      return 2
    end,
  }
end

return {
  boot = stub("boot", "hwc boot was removed; hwc doctor checks that the addon loads"),
  matrix = stub("matrix", "hwc matrix was removed; hwc run plays one character \226\128\148 see hwc help run"),
  sync = stub("sync", "hwc sync questie is now hwc update"),
}
