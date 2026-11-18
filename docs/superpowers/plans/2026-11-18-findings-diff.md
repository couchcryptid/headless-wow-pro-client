# `hwc diff` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `hwc diff OLD.json NEW.json [--json]` tells a WoW-Pro contributor which findings their fix removed or added, warns when the two runs aren't comparable, and exits 1 on regressions.

**Architecture:** A pure module `src/hwc/findings/diff.lua` (compare two decoded findings documents; render the result as text) with its wording in `src/hwc/findings/text.lua`, and a thin `diff` command in `src/hwc/cli.lua` that reads the files, prints, and picks the exit code.

**Tech Stack:** LuaJIT 2.1 (Lua 5.1), dkjson via `hwc.json`, busted 2.3.

**Spec:** `docs/superpowers/specs/2026-11-18-findings-diff-design.md`

## Global Constraints

- LuaJIT 2.1 / Lua 5.1; no new dependencies.
- `findings/diff.lua` is pure: no I/O, no `os.*`, no `io.*`.
- Human-facing wording for diff lives in `findings/text.lua`.
- Only counted findings take part: `report.is_harness(f)` false, `f.expected` not set, `f.severity` present.
- Exit codes: 0 no new or spread findings; 1 at least one new or spread; 2 usage error or not comparable.
- Not comparable: file missing, not valid JSON, `format` ≠ 2, no shared characters.
- `--json` arrays are always arrays, even empty (`setmetatable(t, { __jsontype = "array" })`, as `report.lua` does).
- `diff` runs from any folder (no WoW-Pro folder lookup).
- Run the suite with `~/.luarocks/bin/busted` from the repo root.
- Commit subjects are Conventional Commits (`feat:`, `test:`, `docs:`).

## Review Focus

1. **A non-git addon on either side** (`addon.git == false`, `branch`/`commit` null, `version` set): the header line shows the version instead of crashing on a nil commit. Test in Task 3.
2. **The same file passed as OLD and NEW**: `no changes (N findings in both)`, the same-commit warning, exit 0. Test in Task 3.
3. **`filters` absent on one side and `[]`/absent on the other**: no filters warning (nil and empty are equal). Test in Task 1.
4. **A `.html` path or a path that doesn't exist**: exit 2 with a message naming the path (and "use the .json beside it" for `.html`), not a Lua stack trace. Test in Task 3.
5. **A counted finding with no `combos` field**: treated as present for every character in its file, not dropped. Test in Task 1.

---

### Task 1: `diff.compare`: classify findings and collect warnings

**Files:**
- Create: `src/hwc/findings/diff.lua`
- Modify: `src/hwc/findings/text.lua` (add `text.DIFF_WARNINGS`)
- Test: `spec/findings/diff_spec.lua`

**Interfaces:**
- Consumes: `report.is_harness(f)` from `hwc.findings.report`.
- Produces:
  - `diff.compare(old, new) -> result | nil, err` where `old`/`new` are decoded findings documents (tables) and `err` is a message string for "not comparable".
  - `result = { old = side, new = side, shared = {combo...}, warnings = { {code=string, message=string}... }, counts = { fixed=n, new=n, partly_fixed=n, spread=n, unchanged=n }, fixed = {f...}, new = {f...}, partly_fixed = {f...}, spread = {f...} }`
  - `side = { branch, commit, dirty, git, version }` copied from `header.addon`.
  - Entries in `partly_fixed` are shallow copies of the NEW finding plus `fixed_for` and `still` (sorted combo lists). Entries in `spread` are copies of the NEW finding plus `added_for`. `fixed` holds OLD findings; `new` holds NEW findings. Every finding's `combos` is already cut to `shared`.
  - `diff.exit_code(result) -> 0 | 1`: 1 when `counts.new + counts.spread > 0`.

- [ ] **Step 1: Write the failing tests** in `spec/findings/diff_spec.lua`. Build documents with a local helper `doc(opts)` returning `{ format = 2, header = { addon = { git = true, branch = opts.branch or "main", commit = opts.commit or "aaaaaaa", dirty = false }, catalog = { questie = { tag = "v1.1.2", build = "e1652ce" }, supplement = { present = false } }, client = { commit = "c1" }, matrix = { combos = opts.combos or { "Dwarf WARRIOR baseline", "Gnome MAGE baseline" } }, filters = opts.filters, paths_relative_to = "WoW-Pro-Guides" }, findings = opts.findings or {} }` and a finding helper `f(id, combos, extra)` with `severity = "high"`, `signal = "never-shown-accept"`, `title`, `file = "WoWPro_Leveling/Forever/Alliance/01_12_Dun_Morogh.lua"`, `line = 10`. Tests:
  - `it("puts ids only in OLD under fixed and only in NEW under new")`: `counts.fixed == 1`, `counts.new == 1`, `result.fixed[1].id == "F-1"`, `result.new[1].id == "F-2"`.
  - `it("counts a finding in both with the same combos as unchanged")`: `counts.unchanged == 1`, lists empty.
  - `it("marks fewer characters in NEW as partly fixed")`: OLD combos both, NEW only Dwarf → `partly_fixed[1].fixed_for == { "Gnome MAGE baseline" }`, `still == { "Dwarf WARRIOR baseline" }`.
  - `it("marks more characters in NEW as spread")`: → `spread[1].added_for == { "Gnome MAGE baseline" }`, `diff.exit_code(r) == 1`.
  - `it("ignores harness, expected and severity-less findings")`: a `missing-global`, an `expected = true`, and a finding with `severity = nil` only in NEW → `counts.new == 0`, `diff.exit_code(r) == 0`.
  - `it("compares only shared characters and warns about the rest")`: OLD combos `{Dwarf, Gnome}`, NEW `{Dwarf}`, a finding only on Gnome in OLD → not in `fixed`; a warning with `code == "combos"` whose message names `Gnome Mage`.
  - `it("treats a finding without combos as on every character")` (Review Focus 5).
  - `it("returns nil and a message when no characters are shared")`, `it("rejects a format other than 2")`: `assert.is_nil(r)`, `assert.matches("no shared characters", err)` / `assert.matches("format", err)`.
  - `it("warns for each header mismatch")`: one test per code: `questie` (tag differs), `supplement` (presence differs), `filters` (one side has a filter), `relative-to`, `client`, `same-commit` (equal commits, neither dirty), `dirty-old`, `dirty-new`.
  - `it("does not warn when filters are nil on one side and empty on the other")` (Review Focus 3).

- [ ] **Step 2: Run to verify they fail.** Run: `~/.luarocks/bin/busted spec/findings/diff_spec.lua`. Expected: FAIL, `module 'hwc.findings.diff' not found`.

- [ ] **Step 3: Add `text.DIFF_WARNINGS`** in `text.lua`: a table code → function(args) → message, with this wording:
  - `questie`: `"different QuestieDB: %s (%s) → %s (%s); changes may come from the data, not the guide"` (tag, build short 7 each side)
  - `supplement`: `"different supplement; changes may come from the data, not the guide"`
  - `filters`: `"different guide filters"`
  - `combos`: `"characters only in %s: %s; left out"` (`"OLD"`/`"NEW"`, `text.character` names joined `", "`), one warning per side that has extras
  - `relative-to`: `"runs started from different folders (%s, %s); Lua errors may show as fixed and new"`
  - `client`: `"different hwc versions (%s, %s)"`
  - `same-commit`: `"both runs are the same addon commit (%s)"`
  - `dirty-old` / `dirty-new`: `"uncommitted changes in the OLD run"` / `"... NEW run"`

- [ ] **Step 4: Implement `diff.compare` and `diff.exit_code`.** Compare filters by `hwc.json.encode` of each side's `filters or {}`. Compare supplement by `present` and `sha256`. Order of warnings: the table order in Step 3. Sort every result list by `text.SEVERITY[sev].rank`, then `file`, then `line`, then `id`.

- [ ] **Step 5: Run to verify they pass.** Run: `~/.luarocks/bin/busted spec/findings/diff_spec.lua`. Expected: all pass. Then `~/.luarocks/bin/busted`: no other spec breaks.

- [ ] **Step 6: Commit.** `git add src/hwc/findings/diff.lua src/hwc/findings/text.lua spec/findings/diff_spec.lua && git commit -m "feat: Compare two findings documents by finding id"`

---

### Task 2: `diff.render`: the terminal text

**Files:**
- Modify: `src/hwc/findings/diff.lua`
- Test: `spec/findings/diff_spec.lua`

**Interfaces:**
- Consumes: `diff.compare` result (Task 1), `text.SEVERITY`, `text.character`.
- Produces: `diff.render(result) -> string` (ends in `"\n"`), and `diff.side_label(side) -> string`.

- [ ] **Step 1: Write the failing tests** (new `describe("diff.render")`):
  - `it("names both sides")`: first line `"hwc diff: main@aaaaaaa → fix/x@bbbbbbb (dirty)\n"` (commit cut to 7; ` (dirty)` only on a dirty side).
  - `it("labels a non-git side by its version")`: `side_label({ git = false, version = "2026.11.12.A" }) == "2026.11.12.A (not a git folder)"`.
  - `it("prints warnings, then counts")`: lines `"warning: different guide filters"` and `"fixed 1 · new 1 · partly fixed 0 · unchanged 3"` appear in that order.
  - `it("lists a finding with marker, title, basename and line")`: output contains `"🔴 \"Secure the Mountain\" is never offered"` and `"01_12_Dun_Morogh.lua:162"`.
  - `it("folds follow-ons under their root in the same list")`: root `F-1`, `F-2` with `caused_by = "F-1"`, `F-3` with `caused_by = "F-2"`, all fixed → one line for F-1 ending `"(+2 follow-on)"`; no line for F-2 or F-3.
  - `it("shows who a partly fixed finding was fixed for")`: contains `"fixed: Gnome Mage · still: Dwarf Warrior"`; spread shows `"now also: Gnome Mage"`.
  - `it("leaves out empty sections")`: no `"New"` heading when `new` is empty.
  - `it("says no changes when nothing moved")`: `"no changes (4 findings in both)"`.

- [ ] **Step 2: Run to verify they fail.** Run: `~/.luarocks/bin/busted spec/findings/diff_spec.lua`. Expected: FAIL, `attempt to call field 'render' (a nil value)`.

- [ ] **Step 3: Implement `diff.render`.** Section order and headings: `Fixed`, `New`, `Partly fixed`, `Spread`. Each entry is indented two spaces: `<marker> <title>  <basename>:<line>[  (+N follow-on)][  <extra>]`. N counts all descendants in the same list through `caused_by` (a root is an entry whose `caused_by` is not an id in that list). Titles aren't padded or truncated (left to the builder per spec §6). Counts line: `fixed N · new N · partly fixed N · unchanged N`, always shown; `· spread N` is inserted before `unchanged` only when N > 0 (spec §4.4's example has no spread).

- [ ] **Step 4: Run to verify they pass.** Run: `~/.luarocks/bin/busted spec/findings/diff_spec.lua`. Expected: all pass.

- [ ] **Step 5: Commit.** `git commit -am "feat: Render a findings diff for the terminal"`

---

### Task 3: `hwc diff` command, usage and README

**Files:**
- Modify: `src/hwc/cli.lua` (USAGE text, `M.main` dispatch, a `run_diff(args, out, err)` local)
- Modify: `README.md` (new "Comparing runs" section after "Running characters and findings")
- Test: `spec/cli_spec.lua`

**Interfaces:**
- Consumes: `diff.compare`, `diff.render`, `diff.exit_code` (Tasks 1-2), `hwc.json.encode`, `dkjson.decode`.
- Produces: the `hwc diff OLD NEW [--json]` command.

- [ ] **Step 1: Write the failing tests** in `spec/cli_spec.lua` (new `describe("hwc diff")`), writing documents to a `tmpdir()` with the existing `write` helper and calling `cli.main({ "diff", a, b }, out, err, env_at(tmpdir()))` with string-buffer `out`/`err`:
  - `it("exits 0 and prints the summary when nothing is new")`.
  - `it("exits 1 when NEW has a new finding")`.
  - `it("prints the result as JSON with --json")`: decoded output has `counts`, `warnings`, `fixed`, `new`, `partly_fixed`, `spread`; empty lists encode as `[]` (`assert.matches('"new": %[%]', text)`).
  - `it("accepts --json before or after the paths")`.
  - `it("exits 2 naming a missing file")`: err matches `"hwc: cannot read .*/nope.json"`.
  - `it("exits 2 for a .html path with a hint")`: err matches `"use the %.json beside it"`.
  - `it("exits 2 for invalid JSON and for no shared characters")`.
  - `it("exits 2 with fewer or more than two paths")`.
  - `it("needs no WoW-Pro folder")`: `env_at` a temp dir with no `WoWPro/WoWPro.toc` → exit 0.
  - `it("handles a non-git side and the same file twice")` (Review Focus 1, 2): same path twice → exit 0, output contains `"no changes"` and `"same addon commit"`.

- [ ] **Step 2: Run to verify they fail.** Run: `~/.luarocks/bin/busted spec/cli_spec.lua`. Expected: the new tests FAIL (usage printed, exit 2).

- [ ] **Step 3: Implement `run_diff`** and dispatch `args[1] == "diff"` in `M.main` before the WoW-Pro lookup. Usage errors and not-comparable errors write `"hwc: <message>\n"` to err and return 2. Do **not** append the full USAGE to these errors; write `"see hwc --help\n"` instead (project C will apply this everywhere). With `--json`, write `json.encode(result, { indent = true }) .. "\n"`; otherwise `diff.render(result)`. Return `diff.exit_code(result)`.

- [ ] **Step 4: Update USAGE**: add the line `       hwc diff   OLD.json NEW.json [--json]` after `hwc matrix ...`; under Commands add `  diff          Compare two findings files: fixed, new, partly fixed (exit 1 if anything is new)`; under Options extend `--json` to `Print the boot result or the diff as JSON`.

- [ ] **Step 5: Run to verify they pass.** Run: `~/.luarocks/bin/busted`. Expected: all pass.

- [ ] **Step 6: README "Comparing runs"**: the contributor loop (run on `main`, switch branch, run again with the same flags and from the same folder, `hwc diff`), an example with two real stem names, the five categories, the warning list (one line each), and the exit-code table with the note that 1 means "new findings" here, as in `diff(1)`.

- [ ] **Step 7: Manual check.** From `~/Projects/WoW-Pro-Guides`, run `hwc run --race Dwarf --class WARRIOR --out "$TMPDIR/hwc-diff"`, then `hwc diff` on the resulting `$TMPDIR/hwc-diff/<date>-Dwarf-WARRIOR-baseline.json` against itself. Expected: `no changes (N findings in both)`, the same-commit or dirty warning, `echo $?` → 0.

- [ ] **Step 8: Commit.** `git add src/hwc/cli.lua spec/cli_spec.lua README.md && git commit -m "feat: Add hwc diff to compare two findings files"`
