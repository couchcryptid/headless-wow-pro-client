# Plan 1: Boot the real WoW-Pro addon headless

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Load the unmodified WoW-Pro addon (core + Leveling + Forever guides) from an external checkout under LuaJIT, boot it through its real AceAddon lifecycle, and reach a state where the real engine shows the first steps of the race's start guide. A command prints those steps for a given race and class.

**Architecture:**
- **Isolation:** each simulated character is one sandbox environment table. Addon chunks run with `setfenv(chunk, env)`, and `env._G == env`, so many runs can share one LuaJIT process without leaking globals.
- **Contents of the sandbox:**
  - the Lua 5.1 builtins;
  - WoW Lua extensions (`strsplit` etc.);
  - WoW API stubs backed by a small `player` table;
  - a virtual clock (`GetTime`, `C_Timer.After`);
  - a stateful frame mock with an event bus;
  - a trap that logs reads of undefined globals.
- **Loader:** a TOC/XML loader runs the addon's own files in TOC order, with `[Game]` set to `Forever` and a reviewed skip list of UI-only files.

**Tech Stack:** LuaJIT 2.1 (Lua 5.1) at `/opt/homebrew/bin/luajit`; busted 2.3.0 at `~/.luarocks/bin/busted` (luajit/5.1 rock tree, with penlight, luafilesystem and dkjson available). No other dependencies.

**Spec:** `docs/superpowers/specs/2026-11-11-headless-client-design.md` (approved 2026-11-11). This is plan 1 of 4; see "Follow-on plans" at the end.

## Global Constraints

- **Runtime:** LuaJIT/Lua 5.1 only. Homebrew `lua` (5.5) must never be used to run specs or the client.
- **The addon is read-only input:** the client reads it from a configured path (default `~/Projects/WoW-Pro-Guides`) and never writes, patches or vendors anything there.
- **Fidelity:** addon behaviour, bugs included, is reproduced, never corrected. Stubs model the WoW client, not what the addon "should" see.
- **Licensing and data:**
  - No committing QuestieDB, Wowhead or other third-party data.
  - No copying code from GPL projects (e.g. Mechanic). The licence for this repo is undecided, so add no LICENSE file.
- **Python:** offline tooling only, stdlib, run with `python3 -I` (not used in this plan).
- **Determinism:** identical inputs (addon commit, config, seed) give identical output.
- **Commits:** subject in the imperative mood. Body ends with the `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` trailer.

## Review Focus

1. **A UTF-8 BOM at the start of an addon file** (e.g. `WoWPro/WoWPro_ZoneData_Patches.lua`). The client accepts it; LuaJIT `loadstring` does not. The loader must strip it and the file must load (test in Task 6).
2. **A timer scheduled from inside a timer callback, at the same virtual time**, plus an `OnUpdate` script that never stops. `settle()` must run the new timer in order and still terminate at its virtual-time limit (test in Task 3).
3. **`strsplit` with adjacent or trailing delimiters and a piece limit.** Empty pieces are returned and counted, and the limit leaves the remainder unsplit (test in Task 2).
4. **An addon error during load or inside an Ace `safecall`.** It is recorded with its stack, and the boot reports it, rather than vanishing or killing the process (test in Task 5).
5. **The addon path is missing, or points at a checkout on another branch.** A clear error, or the branch and commit recorded in the boot result, so a Red run is never mistaken for a Green one (test in Task 1).

---

## File structure

| Path | Responsibility |
|---|---|
| `bin/hwc` | shell entry point: execs luajit with the repo's `package.path`, runs `src/hwc/cli.lua` |
| `.busted` | busted config: `lua = "luajit"`, `ROOT = {"spec"}`, `lpath = "src/?.lua;src/?/init.lua"` |
| `.gitignore` | `local/`, `out/`, `findings/*.json`, `evidence/` |
| `README.md` | what it is, how to run, and the external-data policy |
| `src/hwc/config.lua` | load and validate the run config (addon path, flavor, character) |
| `src/hwc/addon_info.lua` | branch, commit and dirty flag of the addon checkout |
| `src/hwc/polyfills.lua` | WoW Lua extensions (`strsplit`, `strtrim`, `wipe`, aliases) |
| `src/hwc/clock.lua` | virtual clock, timer queue and `settle()` |
| `src/hwc/frames.lua` | `CreateFrame` mock, frame registry and event bus |
| `src/hwc/sandbox.lua` | builds the env table, the missing-global trap and the error policy |
| `src/hwc/stubs/core.lua` | load-time WoW API stubs (from the spec's §4.1 list), backed by `player` |
| `src/hwc/stubs/questlog.lua` | quest-log API backed by an empty log (filled properly in Plan 2) |
| `src/hwc/stubs/standins.lua` | no-op stand-ins for functions that skipped UI files define, each logging its call |
| `src/hwc/stubs/hbd.lua` | HereBeDragons-2.0 and HereBeDragons-Migrate stub libraries registered with LibStub |
| `src/hwc/toc.lua` | TOC and XML parsing, `[Game]` substitution, skip list, file list |
| `src/hwc/skiplist.lua` | the reviewed UI-only skip list, one entry per file with its reason |
| `src/hwc/boot.lua` | `boot(cfg)`: runs the whole sequence and returns a `BootResult` |
| `src/hwc/cli.lua` | `hwc boot --race R --class C [--addon PATH]`: prints the boot result |
| `spec/*_spec.lua` | one spec file per module; `spec/integration/boot_spec.lua` needs the addon path |

## Tasks

### Task 1: Repository, config and addon checkout info

**Files:**
- Create: `bin/hwc`, `.busted`, `.gitignore`, `README.md`, `src/hwc/config.lua`, `src/hwc/addon_info.lua`, `src/hwc/cli.lua` (only `--help` for now)
- Test: `spec/config_spec.lua`, `spec/addon_info_spec.lua`

**Interfaces:**
- Produces:
  - `config.load(tbl) -> Config`, raising `error("hwc: addon path not found: <path>")` when `<path>/WoWPro/WoWPro.toc` is missing.
  - `Config` fields: `addon_path: string`, `flavor: "Forever"`, `toc_version: 16001`, `race: string`, `class: string` (token, e.g. `"WARRIOR"`), `faction: "Alliance"`, `sex: 2|3` (default 2), `seed: number` (default 1), `quest_log_size: 40`.
  - `addon_info.read(path) -> {branch: string, commit: string, dirty: boolean}`, using `git -C path rev-parse --abbrev-ref HEAD`, `git -C path rev-parse HEAD` and `git -C path status --porcelain` through `io.popen`.

- [ ] **Step 1:** `git init` in `~/Projects/headless-wow-pro-client`. Commit the already-written spec and this plan (`docs/superpowers/…`) as the first commit: "Add headless client design and plan 1".
- [ ] **Step 2: Write failing specs.**
  - `config_spec`: "defaults apply" asserts `toc_version == 16001`, `quest_log_size == 40`, `faction == "Alliance"`.
  - `config_spec`: "missing addon path errors" asserts `config.load{addon_path="/nonexistent"}` errors matching `"addon path not found"`.
  - `addon_info_spec`: in a temp git repo made with `git init` plus one commit, `read()` returns that commit's 40-hex sha, `branch == "main"` or `"master"`, and `dirty == false`. Writing an untracked file makes `dirty == true`.
- [ ] **Step 3:** Run `~/.luarocks/bin/busted`. Expect failures: module not found.
- [ ] **Step 4:** Implement `config.lua` and `addon_info.lua`. Create `bin/hwc`, which sets `package.path` to `"$REPO/src/?.lua;$REPO/src/?/init.lua;" .. package.path` and execs `/opt/homebrew/bin/luajit $REPO/src/hwc/cli.lua "$@"`.
- [ ] **Step 5:** Run `busted`. Expect PASS. `bin/hwc --help` prints usage.
- [ ] **Step 6:** Commit: "Add config and addon checkout info".

### Task 2: WoW Lua polyfills

**Files:** Create `src/hwc/polyfills.lua`. Test: `spec/polyfills_spec.lua`.

**Interfaces:**
- Produces:
  - `polyfills.install(env)`, which sets `env.strsplit`, `env.strtrim`, `env.strjoin`, `env.wipe`, `env.tinsert`, `env.tremove`, `env.sort`, `env.floor`, `env.ceil`, `env.abs`, `env.max`, `env.min`, `env.sqrt`, `env.format`, `env.strupper`, `env.strlower`, `env.strsub`, `env.strlen`, `env.strfind`, `env.strmatch`, `env.gsub`, `env.date = os.date`, `env.time = os.time`, `env.debugstack`, `env.debuglocals`.
  - It also sets `string.split = strsplit` and `string.trim = strtrim` on the shared `string` table, so `("^&"):split(s)` works. That is a process-wide change: idempotent, and documented.

- [ ] **Step 1: Write failing specs** (`polyfills_spec`):
  - `strsplit("^&", "1&2^3")` returns `"1","2","3"`. The delimiter is a set of characters.
  - `select("#", strsplit("&", "a&&b&"))` is `4`, with pieces `"a","","b",""` (empties kept, including a trailing one). [Review Focus 3]
  - `strsplit(" ", "a b c", 2)` returns `"a","b c"` (piece limit). [Review Focus 3]
  - `strsplit("|", "abc")` returns exactly `"abc"`.
  - Delimiter characters that are Lua pattern magic (`"."`, `"%"`, `"^"`) are taken literally.
  - `strtrim("  x \t\n")` is `"x"`; `strtrim("xxaxx", "x")` is `"a"`.
  - `("a;b"):split(";")` behaves like `strsplit(";", "a;b")`. Note the WoW argument order for the method form: `(delims):split(str)`.
  - `wipe(t)` empties the table and returns the same table.
- [ ] **Step 2:** Run `busted spec/polyfills_spec.lua`. Expect FAIL.
- [ ] **Step 3:** Implement. `strsplit(delims, str, pieces)` scans byte by byte against a set built from `delims`, without patterns. `string.split` is `strsplit` itself, so the `(delims):split(str)` method form passes `delims` as self.
- [ ] **Step 4:** Run. Expect PASS.
- [ ] **Step 5:** Commit: "Add WoW Lua polyfills with faithful strsplit".

### Task 3: Virtual clock and timers

**Files:** Create `src/hwc/clock.lua`. Test: `spec/clock_spec.lua`.

**Interfaces:**
- Produces:
  - `clock.new() -> Clock`.
  - `Clock:now() -> number`. Starts at 1000.0.
  - `Clock:after(delay, fn)`, the `C_Timer.After` contract. A delay below 0 is treated as 0.
  - `Clock:add_ticker(fn)` registers a per-tick callback (used for `OnUpdate`). It returns a handle with `:cancel()`.
  - `Clock:settle(opts) -> {ran: integer, now: number, hit_limit: boolean}`. `opts.max_virtual` defaults to 30 s, and `opts.tick` (the `OnUpdate` step) defaults to `1/30` s.
- **Settle algorithm** (the order matters):
  - Repeat: take the earliest timer (ties broken by insertion order). Advance `now` towards it in steps of `tick`, calling every ticker with `elapsed = tick` at each step. When `now` reaches the timer's time, run the timer.
  - Stop when the timer queue is empty, or when `now - start >= max_virtual`, in which case `hit_limit = true`.
  - Tickers alone never keep `settle` running.

- [ ] **Step 1: Write failing specs:**
  - Timers at 0.25 and 0.1 run in time order, and `now()` advances to the last one.
  - A timer that schedules another `after(0, …)` from inside its callback runs it within the same `settle`, after itself. [Review Focus 2]
  - With a ticker that never stops and no timers, `settle()` returns at once (`ran == 0`). With a ticker plus a timer at 1.0, the ticker is called about 30 times. [Review Focus 2]
  - A timer that keeps rescheduling itself every 0.1 s makes `settle{max_virtual=5}` return `hit_limit == true`. [Review Focus 2]
- [ ] **Step 2:** Run. Expect FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expect PASS.
- [ ] **Step 5:** Commit: "Add virtual clock with settle".

### Task 4: Frame mock and event bus

**Files:** Create `src/hwc/frames.lua`. Test: `spec/frames_spec.lua`.

**Interfaces:**
- Consumes: `Clock:add_ticker` (Task 3).
- Produces:
  - `frames.new(clock) -> Frames`.
  - `Frames:create(ftype, name, parent, template) -> Frame`. This is `CreateFrame`. A named frame is also returned by `Frames:get(name)`.
  - `Frames:fire(event, ...)` delivers `OnEvent(frame, event, ...)` to every frame registered for `event` (or via `RegisterAllEvents`), in registration order.
  - `Frames:shown(frame) -> boolean`.
- **Frame contract:**
  - Real behaviour for: `RegisterEvent`, `UnregisterEvent`, `UnregisterAllEvents`, `IsEventRegistered`, `SetScript`, `GetScript`, `HookScript`, `Show`, `Hide`, `IsShown`, `IsVisible` (true only if this frame and every parent are shown), `SetParent`, `GetParent`, `GetName`.
  - `SetScript("OnUpdate", fn)` registers a clock ticker that calls `fn(frame, elapsed)` while the frame is shown.
  - **Every other method** (e.g. `SetPoint`, `SetText`, `CreateFontString`, `CreateTexture`) exists and returns the frame itself, or a new child mock frame for `Create*` methods.
  - `SetText`/`GetText` store and return text. `SetChecked`/`GetChecked` store a boolean.
  - Mock frames are shown by default (WoW's default).

- [ ] **Step 1: Write failing specs:**
  - Event delivery happens only to registered frames, with arguments, in registration order.
  - `IsVisible` is false when the parent is hidden.
  - `OnUpdate` runs during `clock:settle()` only while the frame is shown.
  - Unknown methods are chainable: `f:SetPoint("TOP"):SetSize(1, 1)` does not error.
  - `f:CreateFontString():SetText("x")` then `GetText()` returns `"x"`.
- [ ] **Step 2:** Run. Expect FAIL.
- [ ] **Step 3:** Implement. Unknown methods go through an `__index` that returns a chainable function.
- [ ] **Step 4:** Run. Expect PASS.
- [ ] **Step 5:** Commit: "Add stateful frame mock and event bus".

### Task 5: Sandbox, missing-global trap and error policy

**Files:** Create `src/hwc/sandbox.lua`. Test: `spec/sandbox_spec.lua`.

**Interfaces:**
- Consumes: `polyfills.install` (Task 2), `clock.new` (Task 3), `frames.new` (Task 4).
- Produces:
  - `sandbox.new(cfg) -> Sandbox`.
  - `Sandbox` fields: `env` (the table addon chunks run in), `clock`, `frames`, `errors` (an array of `{msg, stack, where}`), `missing` (a set of names, plus `missing_order`, an array in first-seen order).
  - `Sandbox:run_file(path, ...) -> ok:boolean`. Reads the file, strips a leading UTF-8 BOM (`\239\187\191`), runs `loadstring(src, "@"..path)` with `setfenv(chunk, env)`, then `pcall(chunk, ...)`. On failure it appends to `errors` and returns false.
  - `Sandbox:call(fn, ...)` is a protected call that records into `errors` the same way.
- **Environment rules:**
  - `env._G = env`.
  - Reads fall through an `__index` that first checks Lua builtins (`string`, `table`, `math`, `pairs`, `ipairs`, `select`, `type`, `tostring`, `tonumber`, `pcall`, `xpcall`, `error`, `assert`, `setmetatable`, `getmetatable`, `rawget`, `rawset`, `rawequal`, `next`, `unpack`, `loadstring`, `setfenv`, `getfenv`, `coroutine`, `bit`, `os` (only `date`, `time`, `clock`), `print`).
  - Any other name not set in `env` returns nil and is recorded once in `missing`.
  - Writes go to `env` without restriction.
- **Error policy:**
  - `env.geterrorhandler()` returns a handler that appends `{msg, debug.traceback()}` to `errors` and returns.
  - `env.seterrorhandler(fn)` stores `fn` but **also** keeps recording.
  - So errors swallowed by AceAddon's `safecall` still appear in `errors`.

- [ ] **Step 1: Write failing specs:**
  - A chunk that sets global `X = 1` leaves `env.X == 1` and the real `_G.X == nil` (isolation).
  - Reading `TomTom` returns nil and `missing.TomTom == true`; `string` resolves without being recorded.
  - A file that starts with a BOM loads. [Review Focus 1]
  - A chunk that calls `error("boom")` makes `run_file` return false, with `errors[1].msg` matching `"boom"`. [Review Focus 4]
  - `xpcall(function() error("x") end, geterrorhandler())` records `"x"`. [Review Focus 4]
  - Two sandboxes don't see each other's globals.
- [ ] **Step 2:** Run. Expect FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expect PASS.
- [ ] **Step 5:** Commit: "Add isolated sandbox with missing-global trap and error recording".

### Task 6: TOC and XML loader

**Files:** Create `src/hwc/toc.lua` and `src/hwc/skiplist.lua`. Test: `spec/toc_spec.lua`, with fixtures under `spec/fixtures/addon/`.

**Interfaces:**
- Produces:
  - `toc.files(addon_root, toc_relpath, game) -> {entries}`.
  - Each entry is `{path=absolute, rel=relative, source="toc"|"xml", skipped=false|reason}`, in client load order.
  - `skiplist.reason(rel) -> string|nil`.
- **Rules:**
  - Ignore lines starting with `##` or `#`, and blank lines.
  - Convert `\` to `/`. Replace `[Game]` with `game` (`"Forever"`), matching on-disk case.
  - `.xml` entries are parsed for `<Script file="…"/>` and `<Include file="…"/>`, recursively, relative to the XML file's directory, in document order. Everything else in the XML is ignored.
  - Missing files are kept as entries with `skipped = "missing on disk"`; the game also loads past them.
- **Skip list** (reason strings are required, from the spec's §4.2):
  - **Libraries:** `Libraries/LibSharedMedia-3.0/*`, `Libraries/AceGUI-3.0-SharedMediaWidgets/*`, `Libraries/LibDataBroker-1.1/*`, `Libraries/LibDBIcon-1.0/*`, `Libraries/HereBeDragons/*` (replaced by the stub in Task 7), `Libraries/LibPetJournal-2.0/*`.
  - **Ace UI parts:** the AceGUI, AceConfig and AceDBOptions entries reached through `Ace.xml`.
  - **Core UI files:** `WoWPro_Templates.xml`, `WoWPro_Widgets.lua`, `WoWPro_GuideList.lua`, `WoWPro_CurrentGuide.lua`, `WoWPro_Tutorial.lua`, `WoWPro_Config.lua`, `WoWPro_Command.lua`, `WoWPro_Pets.lua`.
  - **Leveling UI files:** `WoWPro_Leveling_Config.lua`, `WoWPro_Leveling_Frames.lua`.
  - **Not skipped:** `WoWPro_Frames.lua` and `WoWPro_RowUpdate.lua`.

- [ ] **Step 1: Write failing specs:**
  - With a fixture addon (a TOC containing `##` headers, a `Libs\X.xml` that includes a `Script` and a nested `Include`, a `Data_[Game].lua`, and a missing file), the result is the expected ordered list. `[Game]` resolves to `Data_Forever.lua`, and the missing file has a skipped reason.
  - **Integration** (`pending` if the configured addon path is absent): for the real `WoWPro/WoWPro.toc`, the list
    - starts with `Libraries/Ace/LibStub/LibStub.lua`;
    - contains `WoWPro/WoWPro_ZoneData_Forever.lua` before `WoWPro/WoWPro_ZoneData_Patches.lua` (the TOC order, which is faithful even though Patches' own header comment says it should load first; record that in the README as a noted upstream quirk);
    - marks `WoWPro_Config.lua` as skipped;
    - includes `WoWPro_RowUpdate.lua`.
  - The real `WoWPro_Leveling.toc` expands to `Forever/Alliance/Guides.xml` guide files, including `01_12_Dun_Morogh.lua`.
- [ ] **Step 2:** Run. Expect FAIL.
- [ ] **Step 3:** Implement with Lua patterns over the XML text (`<Script%s+file="([^"]+)"`, `<Include%s+file="([^"]+)"`), in document order.
- [ ] **Step 4:** Run. Expect PASS.
- [ ] **Step 5:** Commit: "Add TOC/XML loader with Forever game token and reviewed skip list".

### Task 7: Load-time WoW API stubs, quest-log stub, stand-ins and HBD stub

**Files:** Create `src/hwc/stubs/core.lua`, `src/hwc/stubs/questlog.lua`, `src/hwc/stubs/standins.lua` and `src/hwc/stubs/hbd.lua`. Test: `spec/stubs_spec.lua`.

**Interfaces:**
- Consumes: `Sandbox` (Task 5), `Config` (Task 1).
- Produces:
  - `stubs.install(sb, cfg, player)`. `player` is `{name="Hwc", realm="HwcRealm", race, race_token, class, class_token, faction, sex, level=1, xp=0, xp_max=400, zone="Dun Morogh", subzone="", map_id=1426, x=0.3, y=0.7}`.
  - `stubs.standins.install(sb)`. Runs after the WoWPro global exists, before `ADDON_LOADED`.
  - `stubs.hbd.register(sb)`. Runs right after LibStub loads.
- **`core.lua` values** (from spec §4.1 and the discovery tables; each stub's comment cites the addon line that needs it):
  - `GetBuildInfo` returns `"1.16.1", "0", "Nov 1 2026", 16001`.
  - `GetAddOnMetadata(name, "Version")` and `C_AddOns.GetAddOnMetadata` return the `## Version:` value read from that addon's TOC (`2026.11.08.A` today).
  - Player identity:
    - `UnitName("player") = player.name`, `GetRealmName() = player.realm`;
    - `UnitClass` returns `(class, class_token)`, `UnitRace` returns `(race, race_token)`;
    - `UnitFactionGroup` returns `(faction, faction)`, `UnitSex` returns `sex`;
    - `UnitLevel`, `UnitXP` and `UnitXPMax` come from `player`.
  - Region and locale: `GetLocale() = "enUS"`, `GetCurrentRegion() = 1`, `GetCurrentRegionName() = "US"`.
  - Clock: `GetTime = clock:now`, `C_Timer = {After = function(d, f) clock:after(d, f) end, NewTicker = …, NewTimer = …}`. These must be installed before any library loads.
  - Frames: `CreateFrame = frames:create`, `UIParent`, `DEFAULT_CHAT_FRAME`/`ChatFrame1` as mock frames whose `AddMessage` appends to `sb.chat`.
  - Misc: `securecallfunction(f, ...) = f(...)`, `IsLoggedIn` (false until boot flips it), `InCombatLockdown() = false`, `IsInGroup() = false`.
  - `Enum.UIMapType = {Cosmic=0, World=1, Continent=2, Zone=3, Dungeon=4, Micro=5, Orphan=6}`.
  - `C_ChatInfo.RegisterAddonMessagePrefix() = true`, `StaticPopupDialogs = {}`.
  - Zone and map:
    - `GetZoneText`, `GetRealZoneText`, `GetSubZoneText`, `GetMinimapZoneText` always return strings;
    - `C_Map.GetBestMapForUnit() = player.map_id`;
    - `C_Map.GetPlayerMapPosition()` returns an object with `GetXY() = player.x, player.y`.
- **`questlog.lua`:** the quest-log functions the compat layer selects for Forever.
  - For an empty log, `GetNumQuestLogEntries` returns `0, 0`, and the info and title calls return nil for any index, which ends `PopulateQuestLog`'s loop.
  - `IsQuestFlaggedCompleted` returns false; the OnAccount and ForAccount variants return false.
  - Before writing this file, read `WoWPro/WoWPro_CompatUtil.lua:121–208` and stub exactly the functions that dispatch reaches under Forever.
- **`standins.lua`:**
  - `WoWPro.RefreshConfig`, `WoWPro.SetDefaults`, `WoWPro.InitializeTutorial`, `WoWPro.QueueTutorial`, `WoWPro.CreateConfig`, `WoWPro.CreateMiniMapButton` (plus anything else Task 8 finds), each a function that appends its name to `sb.standin_calls` and returns nil.
  - `standins.install` must not overwrite a function the addon has already defined.
- **`hbd.lua`:**
  - `LibStub:NewLibrary("HereBeDragons-2.0", 999)` with `GetZoneSize(mapID) -> 1000, 1000` and `GetZoneDistance(...) -> 0, 0, 0`. Values are placeholders (no time model this pass), noted in the file.
  - `"HereBeDragons-Migrate"` with `GetUIMapIDFromMapAreaId(id) -> id`.

- [ ] **Step 1: Write failing specs:**
  - After `install`: `select(4, env.GetBuildInfo()) == 16001`, and `env.UnitRace("player")` returns `"Dwarf","Dwarf"` for a Dwarf player.
  - `env.C_Timer.After(0.1, f)` then `clock:settle()` calls `f`.
  - `env.GetSubZoneText()` is a string.
  - `env.LibStub("HereBeDragons-2.0"):GetZoneSize(1426)` returns two numbers.
  - `standins.install` keeps an existing `WoWPro.RefreshConfig`.
- [ ] **Step 2:** Run. Expect FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expect PASS.
- [ ] **Step 5:** Commit: "Add load-time WoW API stubs, empty quest log, stand-ins and HBD stub".

### Task 8: Boot sequence to the first shown steps

**Files:** Create `src/hwc/boot.lua`. Modify `src/hwc/cli.lua` (add a `boot` subcommand). Test: `spec/integration/boot_spec.lua` (marked `pending` when the addon path is absent).

**Interfaces:**
- Consumes: everything above.
- Produces:
  - `boot.run(cfg) -> BootResult`. Fields:
    - `addon = {path, branch, commit, dirty}` [Review Focus 5]
    - `files_loaded: integer`, `files_failed: {rel}`, `skipped: {rel=reason}`
    - `errors`, `missing_order`, `standin_calls`
    - `guide = {gid: string|nil, loaded: boolean, active_step: integer|nil}`
    - `steps`: the first up-to-15 visible rows from `WoWPro.rows[i]` where `IsVisible()`. Each is `{index, action=WoWPro.action[i], step=WoWPro.step[i], qid=WoWPro.QID[i], why=WoWPro.why[i]}`.
    - `sb`: the sandbox, for later plans.
  - `hwc boot --race Dwarf --class WARRIOR [--addon PATH] [--json]`. Prints the addon branch and commit, the loaded guide GID, the first visible steps, counts of errors and missing globals, and the stand-ins called.
- **Sequence** (spec §4.3):
  1. `sandbox.new`, then `stubs.install`.
  2. Seed `math.random`: set `env.math` to a copy of `math` whose `random` and `randomseed` use a per-sandbox generator seeded from `cfg.seed`.
  3. `env.WoWProCharDB = {QID2Guide = {}, DebugLevel = 0}`.
  4. Run `toc.files` for `WoWPro/WoWPro.toc`, then `WoWPro_Leveling/WoWPro_Leveling.toc`, with the addon varargs `("WoWPro", {})` and `("WoWPro_Leveling", {})`. Call `stubs.hbd.register` right after `LibStub.lua` runs, and `stubs.standins.install` right after `WoWPro/WoWPro.lua` runs.
  5. Fire `ADDON_LOADED("WoWPro")` and `ADDON_LOADED("WoWPro_Leveling")`, set `IsLoggedIn` to true, and fire `PLAYER_LOGIN`. Fire `PLAYER_ENTERING_WORLD(true, false)`.
  6. `clock:settle{max_virtual = 60}`.
  7. Collect the result.
- **Iteration rule** (expected for this task, in place of guessing stubs up front):
  - Run the integration spec. For each error or missing global that blocks boot, add the minimal faithful stub to `core.lua` or `standins.lua`, with a comment citing the addon `file:line` that needs it.
  - Never edit the addon, and never stub in a way that changes engine decisions (e.g. never set `WoWPro.GuideLoaded` directly).
  - If the real `OnEnable` can't complete headless, replace only the failing UI call with a stand-in, and record it in `standin_calls`.
  - A blocking problem that needs a decision (an engine path that can't run headless without changing behaviour) stops the task and is reported to the user.

- [ ] **Step 1: Write the failing integration spec** `boot_spec` "Dwarf Warrior boots into Dun Morogh":
  - `result.addon.commit` is 40 hex characters.
  - `result.guide.gid == "ClassicDunMorogh0112"` and `result.guide.loaded == true`.
  - `result.steps[1]` exists with `action` in `{"A","C","T","K","R","N","L"}`. Among the first steps there is `A Dwarven Outfitters` with `qid == "179"`, the first quest line of `01_12_Dun_Morogh.lua`.
  - The count of `result.errors` whose stack runs through `src/hwc` (harness bugs) is 0. Errors from the addon are allowed but printed.
  - A second spec: "Gnome Mage boots into Dun Morogh" asserts the same GID.
- [ ] **Step 2:** Run `busted spec/integration/boot_spec.lua`. Expect FAIL.
- [ ] **Step 3:** Implement `boot.run`, then iterate stubs and stand-ins per the iteration rule until the spec passes.
- [ ] **Step 4:** Run the full suite (`busted`). Expect all PASS. Run `bin/hwc boot --race Dwarf --class WARRIOR` and paste its output into the commit body.
- [ ] **Step 5:** Commit: "Boot real WoW-Pro headless to the first Dun Morogh steps".
- [ ] **Step 6:** Update `README.md` with:
  - how to run `hwc boot`;
  - the skip list;
  - the TOC-order quirk for ZoneData_Patches;
  - the missing-globals list from the Dwarf boot.

  Commit: "Document boot and harness limits".

---

## Follow-on plans (written after Plan 1 lands, each from the same spec)

- **Plan 2: World and catalog.**
  - Player state (§5.1), with the quest log (40 slots) behind the real quest-log API (§5.4).
  - Classic XP rules and the XP table up to 26 (§5.5).
  - The catalog exporter and loader with per-field precedence, the pinned QuestieDB `d57637f49` plus `QuestXP`, and the provenance trace for `db2.pickle` (§6).
  - Profession variants and the Camping 101 skill gate.
- **Plan 3: Driver and findings.**
  - The loop (§4.4) and the step-action table (§5.2), including the refusal policy, grind-to-level, the immediate Camping 101 turn-in and the forced update on level-up.
  - Signals with severity and root-cause links (§7.1).
  - The findings markdown (§7.2).
  - The anchors from §10: #3535 Red/Green, #3554 U-step, Rhapsody Malt.
  - The Dwarf/Gnome 1–25 matrix run.
- **Plan 4: `/triage` skill** (§8).
- **Later:** the remaining Alliance races, and CI.
