-- Launcher for bin/hwc: the CLI module returns a status, this performs the exit.
-- A real terminal on stderr gets the redrawing progress line.
os.exit(require("hwc.cli").main(arg, nil, nil, { tty = require("hwc.ui").isatty(2) }))
