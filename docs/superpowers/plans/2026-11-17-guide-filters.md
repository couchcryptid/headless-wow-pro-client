# Guide Filters and Installable hwc Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `hwc` runs from inside a WoW-Pro folder, plays every guide on the race's chain to the last line by default, narrows play with S3-style `--include`/`--exclude` filters, and installs onto `$PATH`.

**Architecture:** Two new pure modules: `hwc.source` finds the WoW-Pro folder and `hwc.filters` does glob matching and guide selection. `guide_source` lists the guide files the Forever TOC loads. The driver loses its level and chain-range stops and gains a jump: when the engine loads an excluded guide, it walks the chain to the next included guide, raises the level, and loads that guide the way a guide-list click does. The CLI wires these together and drops `--addon` and `--stop-level`.

**Tech Stack:** LuaJIT 2.1, busted (`~/.luarocks/bin/busted`), luafilesystem, POSIX sh, make.

**Spec:** `docs/superpowers/specs/2026-11-17-guide-filters-design.md`. §8, bundled quest data, is deferred to a separate plan and out of scope here.

## Global Constraints

- The source folder is the nearest folder at or above the starting directory containing `WoWPro/WoWPro.toc`. The search walks the logical `$PWD`.
- `--addon` is removed from `boot`, `quest`, `run` and `matrix`. `--stop-level` is removed from `run`.
- The `~/Projects/WoW-Pro-Guides` default is removed from `cli.lua` and `config.lua`. Specs keep their own `ADDON` constants.
- Filters follow S3 semantics: everything starts included; filters apply in command-line order; the last matching filter decides. `*` matches any characters including `/`. `?` matches one character. `[abc]` and `[!abc]` are character classes. Matching is case-sensitive. Patterns match against the path relative to the source folder.
- Filters select guides only. Every TOC file still loads.
- Play order is always the addon's chain (start guide, then `nextGID`).
- A run stops at `no-next-guide` (the last line of the last included guide on the chain) or on a watchdog (`stuck`, `iterations`, `errors`, `no-step`). `max-guides` stays as a spec-only option. The `level` and `chain-range` stops are removed.
- `--out` defaults to `$HOME/.hwc/findings`. `--relative-to` defaults to the current directory.
- Usage errors exit 2. Runtime failures exit 1.
- With any filter given, the scope gains `-filtered`. Scope names drop `-1-25`.
- Without git, `branch` and `commit` are `null`, a `version` field carries the TOC `## Version:` value, and the header says "not a git folder".
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. A guide file whose name has spaces or `[`/`]` is matched by a literal `--include` of that path. Expected: the literal path still selects it, because a folder or file pattern that names an existing path is escaped before glob compilation. The test goes in Task 2.
2. `hwc` run from a subfolder (e.g. `WoWPro_Leveling/Forever/Alliance`) still finds the root, and a `./x.lua` include resolves against the subfolder, not the root. The test goes in Task 2.
3. The start guide is excluded. Expected: the run jumps before playing anything and logs no steps for the start guide. The test goes in Task 5.
4. Several guides in a row are excluded, and one of them is the chain's last guide. Expected: `no-next-guide` with the jump logged as passing over all of them and no guide loaded. The test goes in Task 5.
5. `$PWD` is unset or stale (it doesn't name the same directory as `lfs.currentdir()`). Expected: `source.start_dir` falls back to `lfs.currentdir()`. The test goes in Task 1.

---

### Task 1: `hwc.source`, finding the WoW-Pro folder

**Files:**
- Create: `src/hwc/source.lua`
- Test: `spec/source_spec.lua`

**Interfaces:**
- Produces:
  - `source.start_dir(env?) -> string`: the absolute logical starting directory. `env` is a table with `pwd` and `cwd`, used by specs; it defaults to `os.getenv("PWD")` and `lfs.currentdir()`. It returns `pwd` when `pwd` is absolute and `lfs.attributes(pwd).ino`/`.dev` equal `cwd`'s; otherwise `cwd`.
  - `source.find(start) -> root | nil, err`: walks `start` and its lexical parents (`paths.normalize`). It returns the first folder where `WoWPro/WoWPro.toc` exists. When none exists, it returns `nil, "hwc: no WoW-Pro folder at or above <start> (looked for WoWPro/WoWPro.toc)"`.

- [ ] **Step 1: Write failing specs** in `spec/source_spec.lua`. Build a temp tree `<tmp>/AddOns/WoWPro/WoWPro.toc` and `<tmp>/AddOns/WoWPro_Leveling/Forever/Alliance/`. The specs:
  - `find(<tmp>/AddOns) == <tmp>/AddOns`.
  - `find(<tmp>/AddOns/WoWPro_Leveling/Forever/Alliance) == <tmp>/AddOns`.
  - `find(<tmp>)` returns `nil` and an error matching `"no WoW%-Pro folder at or above"`.
  - `start_dir({ pwd = "<symlink to AddOns>", cwd = "<tmp>/AddOns" })` returns the symlink path. Create the link with `os.execute("ln -s ...")`.
  - `start_dir({ pwd = nil, cwd = "/x" }) == "/x"`.
  - `start_dir({ pwd = "/nonexistent", cwd = "<tmp>" }) == "<tmp>"`.
- [ ] **Step 2: Run** `~/.luarocks/bin/busted spec/source_spec.lua`. Expected: FAIL, module not found.
- [ ] **Step 3: Implement `src/hwc/source.lua`** per the Interfaces block.
- [ ] **Step 4: Run** the same command. Expected: PASS.
- [ ] **Step 5: Commit** with the message `Find the WoW-Pro folder from the starting directory`.

### Task 2: `hwc.filters`, globs and guide selection

**Files:**
- Create: `src/hwc/filters.lua`
- Test: `spec/filters_spec.lua`

**Interfaces:**
- Produces:
  - `filters.compile(glob) -> fn(rel) -> boolean`: translates the glob to an anchored Lua pattern. `*` becomes `.*`, `?` becomes `.`, `[abc]` stays `[abc]`, `[!abc]` becomes `[^abc]`, and every Lua magic character is escaped (`^$().%+-`). The translation is anchored `^…$`.
  - `filters.resolve(pattern, root, start) -> rel_pattern | nil, err`. Rules:
    - A pattern starting with `./`, `../` or `/` is resolved lexically from `start` (`paths.resolve`). It must lie at or under `root`, or the call returns `nil, "hwc: pattern <p> is outside the WoW-Pro folder <root>"`. It is made relative to root.
    - If the resolved path is an existing directory, the result is `<escaped rel>/*`. For the root itself, it is `*`.
    - If it is an existing file, the result is the escaped rel.
    - Glob characters in a resolved existing path are escaped by wrapping each in `[ ]`, e.g. `[[]`.
    - Any other pattern is returned unchanged.
  - `filters.select(files, list) -> included_set, unmatched_includes`:
    - `files` is an array of root-relative guide paths.
    - `list` is an array of `{ kind = "include"|"exclude", pattern = rel_pattern, raw = original }`.
    - `included_set` is `{ [rel] = true }`.
    - `unmatched_includes` is an array of the `raw` strings of include filters that matched no file, in order.

- [ ] **Step 1: Write failing specs** in `spec/filters_spec.lua`:
  - `compile("*")` matches `"a/b/c.lua"`.
  - `compile("*Dun_Morogh*")` matches `"WoWPro_Leveling/Forever/Alliance/01_12_Dun_Morogh.lua"`.
  - `compile("a?.lua")` matches `"ab.lua"` and not `"abc.lua"`.
  - `compile("[!x]y")` matches `"ay"`, not `"xy"`.
  - `compile("a-b(c).lua")` matches the literal `"a-b(c).lua"`.
  - `select(files, { exclude "*", include "*Dun_Morogh*" })` keeps only the Dun Morogh file.
  - `select(files, { include "*Dun*", exclude "*" })` keeps none.
  - `select(files, {})` keeps all.
  - `select(files, { include "*nope*" })` returns `{ "*nope*" }` as unmatched.
  - `select(files, { exclude "*nope*" })` returns no unmatched.
  - `resolve("./01_12_Dun_Morogh.lua", root, root .. "/WoWPro_Leveling/Forever/Alliance")` gives the escaped rel of that file. This is Review Focus 2.
  - `resolve("../../..", root, root .. "/WoWPro_Leveling/Forever/Alliance") == "*"`.
  - `resolve("../../../..", root, sub)` returns nil plus an error matching `"outside the WoW%-Pro folder"`.
  - A file named `Guide [Beta] 1.lua` exists in the fixture. `compile(resolve("./Guide [Beta] 1.lua", root, dir))` matches its rel. This is Review Focus 1.
- [ ] **Step 2: Run** `~/.luarocks/bin/busted spec/filters_spec.lua`. Expected: FAIL.
- [ ] **Step 3: Implement `src/hwc/filters.lua`** per the Interfaces block.
- [ ] **Step 4: Run** the same command. Expected: PASS.
- [ ] **Step 5: Commit** with the message `Add S3-style include/exclude guide filters`.

### Task 3: Guide files from the Forever TOC

**Files:**
- Modify: `src/hwc/driver/guide_source.lua`
- Test: `spec/driver/guide_source_spec.lua`

**Interfaces:**
- Consumes: `toc.files(addon_root, toc_relpath, game)`, the existing loader (`src/hwc/toc.lua:18`), with `"WoWPro_Leveling/WoWPro_Leveling.toc"` and `"Forever"`.
- Produces: `guide_source.toc_guides(addon_path) -> array of { gid = string, rel = string }`. The array follows TOC load order, has one entry per `RegisterGuide` call, and covers only files the TOC does not skip. Recognise `RegisterGuide` with the same two patterns as `M.index`. Unlike `M.index`, scan every line of the file.

- [ ] **Step 1: Write a failing spec**: "toc_guides lists RegisterGuide gids in TOC order and ignores files the TOC does not load".
  - The fixture has `WoWPro_Leveling/WoWPro_Leveling.toc` listing `b.lua` then `a.lua`.
  - `b.lua` registers `'GB'`, `a.lua` registers `'GA'`, and an unlisted `c.lua` registers `'GC'`.
  - Expected: `{ {gid="GB", rel="WoWPro_Leveling/b.lua"}, {gid="GA", rel="WoWPro_Leveling/a.lua"} }`.
- [ ] **Step 2: Run** `~/.luarocks/bin/busted spec/driver/guide_source_spec.lua`. Expected: FAIL.
- [ ] **Step 3: Implement `toc_guides`.**
- [ ] **Step 4: Run** the same command. Expected: PASS.
- [ ] **Step 5: Commit** with the message `List the guides the Forever TOC loads`.

### Task 4: Folders without git

**Files:**
- Modify: `src/hwc/addon_info.lua`, `src/hwc/boot.lua:106-110`, `src/hwc/cli.lua` (`print_text`), `src/hwc/findings/render.lua` (header around line 535)
- Test: `spec/addon_info_spec.lua` (create), `spec/findings/render_spec.lua`

**Interfaces:**
- Produces:
  - `addon_info.read(path, opts)` returns `{ git = boolean, branch, commit, dirty, version }`.
  - When `git -C path rev-parse --is-inside-work-tree` is not `true`, it returns `git = false`, `branch = nil`, `commit = nil`, `dirty = false`, and `version` set to the trimmed `## Version:` value of `<path>/WoWPro/WoWPro.toc` (or `nil`).
  - When git is present, `version` is still read.
  - `boot.run` errors only when `git` is true and `commit == ""`.
  - In the JSON outputs, nil fields are encoded as `null` through the existing `json.encode`. Check how it encodes nil; if it drops nil keys, use `json.null` or the module's equivalent.

- [ ] **Step 1: Write failing specs**:
  - `read(<tmp folder with WoWPro/WoWPro.toc containing "## Version: 9.9.9">)` gives `git == false` and `version == "9.9.9"`.
  - `read(<this repo>)` gives `git == true` and a 40-hex commit.
  - render: a header with `addon = { git = false, version = "9.9.9", path = "AddOns" }` prints `"not a git folder"` and `9.9.9` in the addon line, with no `commit` text.
- [ ] **Step 2: Run** `~/.luarocks/bin/busted spec/addon_info_spec.lua spec/findings/render_spec.lua`. Expected: FAIL.
- [ ] **Step 3: Implement** the fallback in `addon_info.read`, the error condition in `boot.run`, and the render branch. In `print_text`, a non-git addon prints `version: <v>  (not a git folder)` in place of the branch/commit line.
- [ ] **Step 4: Run** the same command. Expected: PASS.
- [ ] **Step 5: Commit** with the message `Identify a WoW-Pro folder without git by its TOC version`.

### Task 5: The driver plays the chain to the end and jumps excluded guides

**Files:**
- Modify: `src/hwc/driver/run.lua`, `src/hwc/driver/engine.lua`, `spec/helpers/driver_fixtures.lua`
- Test: `spec/driver/run_spec.lua`, `spec/integration/run_dun_morogh_spec.lua`

**Interfaces:**
- Consumes: `Engine:guide(gid).next_gid` (already resolves via `WoWPro:NextGuide` only when `nextGID` is set) and `Player:add_xp(n)`, `xp.to_next(level)`, `xp.CAP_LEVEL`.
- Produces:
  - `Engine:load_guide(gid) -> ok, err`: calls `W.LoadGuide(W, gid)` through the existing protected `call(self.sb, …)`, then `self:settle()`. This is the guide-list click.
  - `run.drive(ctx, opts)` takes `opts.included`, a `{ [gid] = true }` table or nil. nil means every guide is included.
  - The RunLog gains `jumps`, an array of `{ from = gid, passed = { gid... }, to = gid|nil, level_before = n, level_after = n }`.
  - `run.DEFAULTS.stop_level`, `run.CHAIN_MAX_START`, `run.STOP.level` and `run.STOP["chain-range"]` are removed.
  - The fake engine gains `load_guide(gid)`, which sets `cur_gid` and records it in `E.loaded`.

- [ ] **Step 1: Update the specs.**
  - Delete the `chain-range` and `stop_level` specs (`run_spec.lua:207`, `352-360`, `375-…`). Remove `level` and `chain-range` from the stop-reason list at `:581`.
  - In `run_dun_morogh_spec.lua`, drop `stop_level = 13`; `max_guides = 2` ends the run. Update its comment and assertions.
- [ ] **Step 2: Write failing specs** in `run_spec.lua` with the scripted engine:
  - **"an excluded guide is jumped to the next included one on the chain"**:
    - Chain: G1 (startlevel 1) → G2 (startlevel 5) → G3 (startlevel 10). `included = {G1, G3}`.
    - G1 completes and switches to G2.
    - Expected: `log.guides == {"G1","G3"}`, `E.loaded == {"G3"}`, and `log.jumps[1]` has `from = "G2"`, `passed = {"G2"}`, `to = "G3"`, `level_after = 10`.
    - Expected: no step snapshot with gid G2.
  - **"the start guide excluded jumps before playing"** (Review Focus 3): `included = {G2}`. Expected: `log.guides == {"G2"}`, and the first jump has `from = "G1"`.
  - **"excluded guides to the end of the chain stop with no-next-guide"** (Review Focus 4): `included = {G1}`, and G1 switches to G2. Expected: `stop.reason == "no-next-guide"`, `jumps[1].passed == {"G2","G3"}`, `jumps[1].to == nil`.
  - **"a run past level 25 keeps playing"**: G1 sets level 30 via the script, then completes. Expected: `stop.reason == "no-next-guide"`, not `level`.
  - **"the level is never lowered"**: player level 12, jumping to startlevel 10. Expected: `level_after == 12`.
- [ ] **Step 3: Run** `~/.luarocks/bin/busted spec/driver/run_spec.lua`. Expected: the new specs FAIL.
- [ ] **Step 4: Implement.**
  - In `Driver:open(gid)`: if `opts.included` is set and the gid is not in it, call `self:jump(gid)` instead of capturing the guide and do not append it to `log.guides`.
  - `Driver:jump(from)` does the following:
    - Walk `E:guide(g).next_gid` from `from`, collecting `passed`, until a gid is in `included`. Guard against cycles with a `seen` set, and treat a cycle as the end of the chain.
    - If there is no next gid, record the jump with `to = nil` and stop `no-next-guide`.
    - Otherwise, if `W.player.level < startlevel`, add `xp.to_next` XP level by level until `startlevel` or `xp.CAP_LEVEL`.
    - Call `E:load_guide(to)`, record the jump, then `self:open(E:gid())`.
    - If `E:gid()` is not `to` after loading, signal `stuck` with reason `load-guide-failed` and stop `no-step`.
  - In `Driver:close`, skip gids that were never opened (`self.info[gid] == nil`).
  - Remove the level check in `iterate` and the chain-range check in `open`.
- [ ] **Step 5: Run** `~/.luarocks/bin/busted spec/driver`. Expected: PASS.
- [ ] **Step 6: Run the slow driver spec:** `~/.luarocks/bin/busted --tags=slow spec/integration/run_dun_morogh_spec.lua`. Expected: PASS (it pends if the addon is absent).
- [ ] **Step 7: Commit** with the message `Play the chain to its last line and jump excluded guides`.

### Task 6: The CLI uses the source folder and filters, and drops --addon and --stop-level

**Files:**
- Modify: `src/hwc/cli.lua`, `src/hwc/config.lua:47-51`, `src/hwc/driver/matrix.lua` (no default path), `src/hwc/findings/render.lua` (header lines), `src/hwc/findings/report.lua` (header passthrough)
- Test: `spec/cli_spec.lua`, `spec/config_spec.lua`, `spec/findings/render_spec.lua`

**Interfaces:**
- Consumes: `source.start_dir`, `source.find` (Task 1), `filters.resolve`, `filters.select`, `filters.compile` (Task 2), `guide_source.toc_guides` (Task 3), and `run.drive`'s `opts.included` and `log.jumps` (Task 5).
- Produces:
  - `cli.main(args, out, err, env?)`, where `env` is `{ pwd, cwd, home }` and defaults to the process values. It is passed to `source.start_dir` and used for `$HOME/.hwc/findings`.
  - `config.load` no longer defaults `addon_path`. With `addon_path == nil` it skips the TOC check, which keeps the world specs working, and `boot.run` errors `"hwc: no WoW-Pro folder"` when `cfg.addon_path` is nil.
  - Header fields:
    - `filters`: an array of `{ kind, pattern }` in the order given.
    - `jumped`: distinct passed gids in first-seen order across logs.
    - `unreached`: included gids an `--include` matched that no log played. Nil when there are no include filters.
    - `skipped_races`: matrix races whose combos played no guide.

- [ ] **Step 1: Update and write failing specs** in `cli_spec.lua`.
  - Replace the top-level `ADDON` default use with `env = { pwd = ADDON, cwd = ADDON, home = <tmp> }` for real-addon cases.
  - **"run from a folder with no WoW-Pro folder exits 2"**: env pwd/cwd = tmp. Expected: stderr matches `"no WoW%-Pro folder"`.
  - **"--addon is rejected as unknown"**: `{ "run", "--class", "WARRIOR", "--addon", "/x" }` gives 2 and `"unknown or incomplete option: %-%-addon"`.
  - **"--stop-level is rejected as unknown"**: same check for `--stop-level`.
  - **"an --include matching no guide exits 2"**: on a fixture source folder. Expected: stderr matches `"%-%-include \"%*nope%*\" matches no guide"`.
  - **"filters leaving no guide exit 2"**: `--exclude "*"`. Expected: `"no guide left after filters"`.
  - **"--include and --exclude keep every occurrence in order"**: unit-test the parser through a local exported `cli._parse_values` if needed, or assert via the header written for a stubbed `runner.character`. Stub it the way `matrix.combos` is stubbed at `cli_spec.lua:96`.
  - **"matrix accepts repeated --race and merges --races, first-seen order"**: stub `matrix.combos` to capture `races`. Expected: `{ "Dwarf", "Gnome" }` from `--race Dwarf --races Gnome,Dwarf`.
  - **"--out defaults to $HOME/.hwc/findings"**: env.home = tmp, stubbed runner. Expected: the file exists under `<tmp>/.hwc/findings/`.
  - **"a filtered run's scope ends in -filtered and drops -1-25"**: assert the wrote line.
  - **"quest takes no --addon"**: `{ "quest", "1", "--addon", "x" }` gives 2.
  - In `render_spec.lua`, a header with `filters` and `jumped` prints a `Filters:` line listing them in order, and a `Jumped guides:` line. A header with `unreached` prints `Included but never reached:`.
  - In `config_spec.lua`, `config.load({})` does not error and has `addon_path == nil`.
- [ ] **Step 2: Run** `~/.luarocks/bin/busted spec/cli_spec.lua spec/config_spec.lua spec/findings/render_spec.lua`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - `parse_values` stores repeatable options (`include`, `exclude`, `race` for matrix) as arrays, in order. Filters keep their kind, as `{ kind, raw }`, in one combined ordered list.
  - The source folder comes from `source.find(source.start_dir(env))`. Resolve each filter with `filters.resolve(raw, root, start)`.
  - Build the guide list from `toc_guides(root)` and select. A gid is included when its rel is in the set. Pass `included` only when there is at least one filter.
  - Usage errors use the exact messages from Step 1. Remove the `stop-level` handling (`cli.lua:276-279`, `:192`).
  - Scope names:
    - run: `<Race>-<CLASS>-<variant>`.
    - matrix: `forever-alliance-<races>`.
    - Either one gets `-filtered` appended when filters are given.
  - `--out` defaults to `env.home .. "/.hwc/findings"`. `mkdirs` already creates it.
  - `matrix.combos(addon_path, races)` now requires `addon_path`, so the call no longer falls back at `cli.lua:251`.
  - Combos whose log has an empty `guides` go into `skipped_races`. If every combo is skipped, exit 2 with `"hwc: matrix: no race reaches an included guide"`.
  - `boot` and `quest` lose `--addon`. `quest` no longer calls `config.load` with an addon path.
  - Update `USAGE` to the §6 command block. Add these two lines under Options:
    `--include P / --exclude P  Glob filters on guide paths (repeatable; last match wins; default: all guides)`
    `See README "Choosing guides" for the rules.`
- [ ] **Step 4: Run** `~/.luarocks/bin/busted`. Expected: PASS, apart from the known `matrix_spec.lua:83` live-addon failure that predates this plan. Note it in the commit body if it still fails.
- [ ] **Step 5: Commit** with the message `Run from the WoW-Pro folder with include/exclude filters`.

### Task 7: Install, README and design-spec updates

**Files:**
- Modify: `bin/hwc`, `README.md`, `docs/superpowers/specs/2026-11-11-headless-client-design.md`
- Create: `Makefile`
- Test: `spec/install_spec.lua` (tagged `#slow`, since it shells out)

**Interfaces:**
- Produces:
  - `bin/hwc` resolves `$0` through symlinks. The loop is `while [ -L "$f" ]; do l=$(readlink "$f"); case $l in /*) f=$l;; *) f=$(dirname "$f")/$l;; esac; done`, and REPO is the parent of the resolved `bin/`.
  - It picks the first of `command -v luajit`, `/opt/homebrew/bin/luajit`, `/usr/local/bin/luajit`. If none exists, it prints `hwc: luajit not found (looked on PATH, /opt/homebrew/bin, /usr/local/bin)` to stderr and exits 127.
  - `make install` runs `ln -sf "$(CURDIR)/bin/hwc" "$(PREFIX)/bin/hwc"` after `mkdir -p`. `PREFIX ?= $(HOME)/.local`.
  - `make uninstall` removes `$(PREFIX)/bin/hwc` only if `readlink` of it equals `$(CURDIR)/bin/hwc`.

- [ ] **Step 1: Write a failing spec**: "a symlinked hwc prints help".
  - `make install PREFIX=<tmp>`, then run `<tmp>/bin/hwc --help`. Expected: exit 0 and output matching `Usage: hwc`.
  - `make uninstall PREFIX=<tmp>` then leaves no `<tmp>/bin/hwc`.
- [ ] **Step 2: Run** `~/.luarocks/bin/busted --tags=slow spec/install_spec.lua`. Expected: FAIL.
- [ ] **Step 3: Implement** `bin/hwc` and the `Makefile`.
- [ ] **Step 4: Run** the same command. Expected: PASS.
- [ ] **Step 5: Update the README.**
  - **Install section:** `make install`, plus `echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc` for zsh, the same for bash in `~/.bashrc` (or `~/.bash_profile` on macOS), then `hwc --help`.
  - **"Choosing guides" section:** S3 semantics, the two examples from the design §4, the `./` addition, and the known limit about jumped guides.
  - **All usage examples:** change them to `cd ~/Projects/WoW-Pro-Guides && hwc …`, with no `--addon` or `--stop-level`.
  - **Wording:** the "levels 1 to 25" scope line becomes "the race's chain to its last guide". Mention that findings go to `~/.hwc/findings`.
- [ ] **Step 6: Update `2026-11-11-headless-client-design.md`.** Change the `--addon` mentions and the §4.4 stop conditions to point at the new design.
- [ ] **Step 7: Run** `~/.luarocks/bin/busted`. Expected: PASS, apart from the known `matrix_spec.lua:83` failure.
- [ ] **Step 8: Commit** with the message `Install hwc on PATH; document guide filters`.
