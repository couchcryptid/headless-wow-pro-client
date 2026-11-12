# Findings Report Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the parser-first findings markdown with a human-first report,
add a canonical findings JSON, and write every output path relative to a base
directory.

**Architecture:** `group.lua` keeps producing findings, with three extra fields
passed through. Four modules sit downstream of it:
- `hwc.paths` rewrites absolute paths;
- `hwc.findings.text` owns every human-facing word (titles, sentences, labels);
- `hwc.findings.report` builds the JSON document;
- `hwc.findings.render` lays out the markdown from findings plus `text`.

`cli.play` applies the path rewrite to run logs, findings and header, then
writes all three files.

**Tech Stack:** LuaJIT 2.x (Lua 5.1), busted 2.3.0 (`~/.luarocks/bin/busted`), dkjson via `hwc.json`, lfs.

**Spec:** `docs/superpowers/specs/2026-11-12-findings-report-design.md`. The
section numbers below (§4.7 and so on) refer to it.

## Global Constraints

- Lua 5.1 / LuaJIT only. No new dependencies. `render`, `text`, `report` and
  `paths` are pure: no I/O, no `os.date`, no `lfs` (except `paths.cwd()`, which
  is called only by the CLI).
- **Determinism.** Every rendered list is sorted by a total order. The same
  inputs and the same base give byte-identical `.md` and `.json`.
- **Markdown text.** Lines end in `\n`, the file ends with exactly one `\n`, and
  there's no `\r`. The words "none" and "n/a" never appear as field values.
- **Severity display.**

  | severity | marker | word |
  |---|---|---|
  | `high` | 🔴 | High |
  | `medium-high` | 🟠 | Medium-high |
  | `medium` | 🟡 | Medium |
  | `low` | ⚪ | Low |

  A marker always appears next to its word or under a column header naming it.
- Finding ids, grouping keys, severities and `group.findings` sort order are
  unchanged.
- No absolute path of a known root (addon, catalog sources, base) appears in
  any file under `--out`.
- Run the tests with `~/.luarocks/bin/busted` from the repo root. The `.busted`
  file sets `lpath`.
- Work on a branch `findings-report`, cut from `main` before Task 1.

## Review Focus

1. **A finding whose step name is nil or empty** (stuck/no-current-step,
   leftover without a qname). The title must still read as a sentence with no
   `""` or `nil` in it. Tested in Task 3:
   `text.title handles a stuck finding with no name`.
2. **An addon path given relative on the CLI** (`--addon local/addon/main`). It
   must still be rewritten and must not produce `../../` noise. Tested in
   Task 1: `rewrite resolves a relative root against cwd first`.
3. **Root path equal to a prefix of a sibling** (`/p/WoW-Pro-Guides` and
   `/p/WoW-Pro-Guides-old`). Only whole-segment matches may be rewritten.
   Tested in Task 1: `rewrite does not touch a sibling that shares a prefix`.
4. **Backticks or pipes in a `why` or Lua message.** They must not break the
   inline code span or a table. Tested in Task 5:
   `engine fold neutralises backticks`.
5. **A run with zero findings.** It must produce "Nothing found." and a valid
   JSON document with `findings: []`. Tested in Task 5 and Task 4.

---

### Task 1: Relative paths module

**Files:**
- Create: `src/hwc/paths.lua`
- Test: `spec/paths_spec.lua`

**Interfaces:**
- Produces:
  - `paths.normalize(p: string) -> string`: absolute in, absolute out. It
    collapses `//`, drops `/./`, resolves `..` and strips a trailing `/`
    (except for `/` itself).
  - `paths.resolve(p: string, cwd: string) -> string`: if `p` starts with `/`,
    returns `normalize(p)`; otherwise returns `normalize(cwd .. "/" .. p)`.
  - `paths.relative(p: string, base: string) -> string`: both are absolute.
    Returns `"."` when they are equal, `"a/b"` when `p` is inside `base`, and
    `"../x"` otherwise.
  - `paths.rewrite(value: any, roots: {string}, base: string, cwd: string) -> any`:
    returns a deep copy. Every string has each root (resolved, longest first)
    replaced by `relative(root, base)`. A match counts only when the next
    character after the root is end-of-string, `/`, `:`, a quote, whitespace or
    `)`. Keys are not rewritten, and cycles are guarded.
  - `paths.cwd() -> string`: `lfs.currentdir()`.

- [ ] **Step 1: Write the failing tests.** Cover:
  - `normalize("/a//b/./c/../d/") == "/a/b/d"`;
  - `relative("/p/x", "/p/x") == "."`;
  - `relative("/p/x/local/q", "/p/x") == "local/q"`;
  - `relative("/p/WoW-Pro-Guides", "/p/x") == "../WoW-Pro-Guides"`;
  - `relative("/q/r", "/p/x") == "../../q/r"`;
  - longest root first:
    `rewrite("@/p/x/local/addon/A.lua:3", {"/p/x", "/p/x/local/addon"}, "/p/x", "/p/x")`
    returns `"@local/addon/A.lua:3"`;
  - `rewrite resolves a relative root against cwd first`: root
    `"local/addon/main"` with cwd and base `/p/x` rewrites
    `/p/x/local/addon/main/W.lua` to `local/addon/main/W.lua`;
  - `rewrite does not touch a sibling that shares a prefix`: root
    `/p/WoW-Pro-Guides` leaves `/p/WoW-Pro-Guides-old/x` unchanged;
  - nested tables are rewritten, the input is not mutated, and the
    already-relative `"WoWPro_Leveling/F/a.lua"` is unchanged.
- [ ] **Step 2: Run them and confirm they fail.** Run
  `~/.luarocks/bin/busted spec/paths_spec.lua`. Expected: FAIL, module
  `hwc.paths` not found.
- [ ] **Step 3: Implement the functions above in `src/hwc/paths.lua`.**
  - Use `plain` `string.find` in a loop for the replacements, not gsub
    patterns, because paths contain `-` and `(`.
  - Sort the roots by length in descending order, ties by string.
- [ ] **Step 4: Run the tests.** Same command. Expected: all pass.
- [ ] **Step 5: Commit.**
  `git add src/hwc/paths.lua spec/paths_spec.lua && git commit -m "Add relative path rewriting for findings output"`

### Task 2: Carry grind, quest name and neighbour actions into findings

**Files:**
- Modify: `src/hwc/driver/run.lua`:
  - `Driver:signal` (around line 85): add `s.qname`; give `before` an action.
  - line ~169: give `before` and `after` an `action` in `close()`.
  - lines ~305–310: give `after` an action, and track `before_action`.
- Modify: `src/hwc/findings/group.lua`: `new_finding` copies `grind` and `qname`.
- Test: `spec/findings/group_spec.lua`, `spec/driver/run_spec.lua`

**Interfaces:**
- Produces, as signal and finding fields:
  - `qname: string?`: the catalog quest name for `qid`;
  - `grind: {kills: number, to: number}?`: on `below-level` findings;
  - `before` / `after`: `{name: string, action: string?}`.

- [ ] **Step 1: Write the failing tests.**
  - In `group_spec`, add `it("passes grind, qname and neighbour actions through to the finding")`.
    Feed a below-level signal with `grind = {kills = 4, to = 6}`,
    `qname = "Pre"` and `before = {name = "b", action = "T"}`, then assert the
    same values on the finding.
  - In `run_spec`, add an assertion on an existing fixture run: some signal with
    a `qid` that the fixture catalog names has a `qname`, and some signal's
    `before.action` is a one-letter string. The implementer picks the signal
    from the fixture's existing assertions.
- [ ] **Step 2: Run them and confirm they fail.** Run
  `~/.luarocks/bin/busted spec/findings/group_spec.lua spec/driver/run_spec.lua`.
  Expected: the new assertions fail.
- [ ] **Step 3: Implement.**
  - `qname = W.catalog and W.catalog:quest(qid) and W.catalog:quest(qid).name`,
    set in `Driver:signal` after the fields merge, so it covers a
    leftover-quests `qid` too.
  - Also set it in the `close()` never-shown literal.
  - Track `self.before_action` beside `self.before_name`, taken from
    `step.action`.
- [ ] **Step 4: Run the full fast suite.** Run `~/.luarocks/bin/busted`.
  Expected: all pass. Ids are unchanged, because the key doesn't include these
  fields.
- [ ] **Step 5: Commit.** Message: "Record quest names, grind counts and neighbour step actions on findings".

### Task 3: Human-facing text

**Files:**
- Create: `src/hwc/findings/text.lua`
- Test: `spec/findings/text_spec.lua`

**Interfaces:**
- Consumes: finding fields from `group.findings`, plus Task 2's fields.
- Produces:
  - `text.SEVERITY`: `{ [sev] = {marker=, word=, rank=} }`, with the values
    from Global Constraints.
  - `text.VERBS`: a map from action letter to verb, per §4.8. An unknown letter
    returns nil.
  - `text.step(action: string?, name: string?) -> string?`:
    - `step("f", "Thelsamar") == 'Get flight path at "Thelsamar"'`;
    - an unknown action gives `'X "name"'`;
    - with no action, the quoted name;
    - nil when the name is nil or empty.
  - `text.character(combo: string) -> string`:
    - `"Dwarf WARRIOR baseline"` gives `"Dwarf Warrior"`;
    - `"Dwarf HUNTER lw-skin"` gives `"Dwarf Hunter (lw-skin)"`.
  - `text.combos(affected: {string}, matrix: {string}) -> string summary, boolean dropped_detail`
    implements the §4.8 rules.
  - `text.title(f) -> string` and
    `text.sentence(f, ctx) -> string` implement §4.7.
    - `ctx = { by_qid = {[qid] = finding}, by_id = {[id] = finding}, single = character-label-or-nil }`.
    - Links are written as `[title](#f-<hex>)`.
    - For a follow-on finding (`caused_by` set), `sentence` returns
      `"Follows from [parent title](#f-x). "` followed by the template's first
      clause.
  - `text.anchor(id) -> "f-" .. hex` (lower case).

- [ ] **Step 1: Write the failing tests.**
  - One `it` per §4.7 row, asserting the exact title and the exact sentence.
    Use the spec wording verbatim; `<Race/Class>` comes from `ctx.single` or the
    distinct races or classes among `f.combos`, joined with `/`. Include:
    - the prereq case, where `why = "NextStep:PRE&(95213): A mandatory prereq was not met: 95213"`
      and `ctx.by_qid[95213]` exists, so the sentence contains `[`…`](#f-`;
    - the same case with no finding for 95213, where it contains plain
      "quest 95213";
    - `text.title handles a stuck finding with no name`: `stuck` with reason
      `no-current-step` and `name = nil` gives exactly `"No step to show"`;
    - leftover with no qname: `"Quest 412 is left in the log"`;
    - a lua-error message longer than 80 characters, truncated to 80 plus `…`.
  - Combos, with a matrix of 13 entries (7 Dwarf HUNTER variants and so on):
    - all of them give `"all 13 characters"`;
    - all but 2 give `"all except Dwarf PRIEST baseline, Gnome MAGE baseline"`,
      run through `text.character`, so it reads `Dwarf Priest, Gnome Mage`;
    - 7 Hunter variants plus 1 Warrior give
      `"Dwarf Hunter (all 7 variants), Dwarf Warrior"`, with
      `dropped_detail == true`.
  - Step verbs: `step("h", "Stoutlager Inn")` and `step("A", "")`, which gives
    nil.
- [ ] **Step 2: Run them and confirm they fail.** Run
  `~/.luarocks/bin/busted spec/findings/text_spec.lua`. Expected: FAIL, module
  missing.
- [ ] **Step 3: Implement `src/hwc/findings/text.lua`.**
  - Before finalising `VERBS`, confirm each letter against
    `../WoW-Pro-Guides/WoWPro/WoWPro_Parser.lua` (or the configured addon
    path).
  - Drop any letter you can't confirm, so it falls back to the raw letter.
  - Note in a comment which file and line confirmed each one.
- [ ] **Step 4: Run the tests.** Same command. Expected: pass.
- [ ] **Step 5: Commit.** Message: "Add plain-English titles and sentences for findings".

### Task 4: Findings JSON document

**Files:**
- Create: `src/hwc/findings/report.lua`
- Test: `spec/findings/report_spec.lua`

**Interfaces:**
- Consumes: `text.title` and `text.sentence` (Task 3); `group.findings` output.
- Produces:
  - `report.FORMAT = 1`;
  - `report.build(findings, header) -> table`, shaped
    `{format, header, summary = {findings, roots, by_severity, by_signal}, findings}`.
  - `summary.findings` counts findings with a severity that are not harness
    findings.
  - `summary.roots` counts those with no `caused_by`.
  - Each finding is a shallow copy, plus `title` and `sentence`.

- [ ] **Step 1: Write the failing tests.**
  - Round trip: `hwc.json.encode(report.build(fs, h))`, decoded with dkjson,
    has `format == 1` and `#findings == #fs`. Every finding keeps `id`,
    `signal` and `combos`, and has a non-empty `title`.
  - The zero-findings case gives `findings` as an empty array (encoded `[]`)
    and `summary.findings == 0`.
  - The counts on the `sigs()` fixture copied from `render_spec`.
- [ ] **Step 2: Run them and confirm they fail.** Run
  `~/.luarocks/bin/busted spec/findings/report_spec.lua`.
- [ ] **Step 3: Implement `report.build`.** An empty `findings` must encode as
  `[]`, not `{}`. Use dkjson's array marker: `setmetatable(t, {__jsontype = "array"})`.
- [ ] **Step 4: Run the tests.** Same command. Expected: pass.
- [ ] **Step 5: Commit.** Message: "Add canonical findings JSON document".

### Task 5: Human-first markdown

**Files:**
- Modify (rewrite): `src/hwc/findings/render.lua`. Keep `render.GAPS` and the
  signature `render.markdown(findings, header) -> string`.
- Test (rewrite): `spec/findings/render_spec.lua`

**Interfaces:**
- Consumes:
  - `text.*` (Task 3);
  - `header` fields: `scope`, `date`, `addon{path, branch, commit, dirty}`,
    `catalog{name -> {present, commit, sha256, path}}`,
    `client{commit, dirty}`, `matrix.combos`, `rank`, `gaps`.
  - New field: `paths_relative_to` (string, the last segment of the base). The
    paths in `header` arrive already relative (Task 6 rewrites them).
- Produces: the layout in §4.1–§4.9, exactly as specified there.

- [ ] **Step 1: Rewrite `render_spec`.**
  - Keep these tests as they are:
    - the shuffle/reverse determinism test;
    - the trailing-newline and no-`\r` test;
    - the dungeon-root test, with assertions updated to the new strings.
  - Add:
    - `title line counts findings and roots`: matches
      `^# Dwarf Warrior: %d+ findings from %d+ root causes\n`;
    - `start here ranks by descendant count and caps at 5`: build 7 roots with
      0–6 children and assert the 5 entries in order;
    - `one Triage: _pending_ per non-expected, non-harness finding`;
    - `follow-on findings are compact`: a child has `Follows from [` and no
      `**Between steps:**`;
    - `findings sit under their file heading in line order`;
    - `no none or n/a values`: assert that
      `out:find(": none\n")`, `out:find(": n/a\n")` and `out:find("\n- none")`
      are all nil;
    - `engine fold neutralises backticks`: a why containing `` `x` `` appears as
      `'x'` inside the code span;
    - `harness notices are folded and keep ids`;
    - `expected manual clicks are folded`;
    - `warnings appear only when warranted`: a dirty addon, a missing catalog
      source, unverified data on more than half the findings, and a clean header
      that has no `>` line at all;
    - `About this run names the base by its last segment only`;
    - `zero findings renders Nothing found.`;
    - `About this run shortens hashes to 12 and lists questie files on separate lines`;
    - `every F- id appears`: for each finding, `out:find(f.id, 1, true)`.
- [ ] **Step 2: Run them and confirm they fail.** Run
  `~/.luarocks/bin/busted spec/findings/render_spec.lua`.
- [ ] **Step 3: Implement.**
  - Sections in the §4.1 order.
  - Descendant counts: walk `causes` through an `id -> finding` map, guarding
    against cycles.
  - "Guide files" is any `file` starting with `WoWPro_Leveling/`. Every other
    `file`, and addon lua-errors with no `file`, go in "Addon code".
  - Harness means `missing-global`, or `lua-error` with `harness`.
  - A blank count cell is the empty string between pipes.
- [ ] **Step 4: Run the full fast suite.** Run `~/.luarocks/bin/busted`.
  Expected: all pass. `cli_spec` may assert old header strings; update those to
  the new layout in this task.
- [ ] **Step 5: Commit.** Message: "Render findings as a human-first report".

### Task 6: CLI wiring, determinism and docs

**Files:**
- Modify: `src/hwc/cli.lua`:
  - the usage text: add `--relative-to DIR`;
  - the allowed tables for `run` and `matrix` (~line 302 and ~315);
  - `play()` (~lines 158–200).
- Modify: `spec/cli_spec.lua`, `spec/integration/findings_determinism_spec.lua`
- Modify: `README.md`, in its "Output" section (~line 116).
- Modify: `docs/superpowers/specs/2026-11-11-headless-client-design.md` §7.2
  and §8. Add a line at the top of each pointing to the new spec.

**Interfaces:**
- Consumes: `paths.*` (Task 1), `report.build` (Task 4), `render.markdown`
  (Task 5).

- [ ] **Step 1: Write the failing tests.**
  - In `cli_spec`: `--relative-to` is accepted by `run` and `matrix`, and an
    unknown value combination still exits 2. If `cli_spec` already exercises a
    stubbed `play`, assert that both `.md` and `.json` paths appear in the
    "wrote" line.
  - In the determinism spec:
    - also compare the two `.json` files byte for byte;
    - then add `it("writes no absolute addon path or cwd under --out")`, which
      reads every file under `dir` and asserts that `flow.ADDON` (resolved) and
      `lfs.currentdir()` don't occur.
- [ ] **Step 2: Run them and confirm they fail.** Run
  `~/.luarocks/bin/busted spec/cli_spec.lua` and
  `~/.luarocks/bin/busted --tags=slow spec/integration/findings_determinism_spec.lua`.
  The slow spec stays pending without the addon checkout; say so if it does.
- [ ] **Step 3: Implement in `play()`.**
  1. Compute `cwd = paths.cwd()` and `base = paths.resolve(opts["relative-to"] or cwd, cwd)`.
  2. Collect the roots: `first.addon.path`, each `first.catalog.sources[*].path`
     and `base`.
  3. Rewrite each log with `paths.rewrite(log, roots, base, cwd)` before
     encoding it.
  4. Build `header`.
  5. Compute `findings = group.findings(rewritten_logs)`. The logs are already
     rewritten, so the findings are clean.
  6. Rewrite `header`.
  7. Set `header.paths_relative_to = base:match("([^/]+)$") or "/"`.
  8. Write `<scope>.md` and `<scope>.json` (the latter as
     `json.encode(report.build(findings, header), {indent = true}) .. "\n"`).
  9. Print `hwc: wrote <md> and <json> (<n> characters)`.
- [ ] **Step 4: Run the tests.**
  - The full fast suite: `~/.luarocks/bin/busted`.
  - The slow suite, if the addon is present:
    `~/.luarocks/bin/busted --tags=slow`.
  - Manual check: `bin/hwc run --race Dwarf --class WARRIOR --out "$SCRATCH"`,
    then `grep -rl "$HOME" "$SCRATCH"`. Expected: no output.
  - Open the `.md` and read the first screen as a contributor would.
- [ ] **Step 5: Update the docs.**
  - README "Output": add the `.json` bullet, document `--relative-to`, and
    replace "design spec §7.2" with the new spec's path.
  - Add the design spec pointers.
- [ ] **Step 6: Commit.** Message: "Write findings JSON and relative paths from the CLI".
