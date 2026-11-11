-- Launcher for bin/hwc: the CLI module returns a status, this performs the exit.
os.exit(require("hwc.cli").main(arg))
