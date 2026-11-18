# HTML Findings Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the markdown findings report with one self-contained HTML page
driven by a format-2 findings JSON. Along the way, fix level handling, record
guide entry and exit levels, add a `hidden-use-step` signal, and link root
causes across signals.

**Architecture:**
- **Driver** (`src/hwc/driver/run.lua`): records new facts in the run log —
  levels at each step, guide entry and exit levels, and hidden use steps.
- **Findings** (`group.lua`, `text.lua`, `report.lua`): turns those facts
  into format-2 JSON that carries every derived fact and all wording.
- **Writer** (`html.lua`): a small Lua module that drops that exact JSON into
  a static template, `src/hwc/findings/report.html`.
- **Page:** a small TypeScript and Preact project in `web/report/`, built
  by Vite into that one self-contained template.
  - The template is committed, so running `hwc` never needs Node.
  - Pure logic modules (tested with Vitest) do all the filtering, counting
    and ordering. Components only render.
  - One set of format-2 fixtures, produced by Lua, is tested from both
    sides.

**Tech Stack:**
- **Lua:** Lua 5.1, busted 2.3 (`~/.luarocks/bin/busted`), and dkjson
  behind `hwc.json` (canonical key order).
- **Page (development only):** Node 24, TypeScript, Preact, Vite with
  `vite-plugin-singlefile`, and Vitest.

**Spec:** `docs/superpowers/specs/2026-11-18-html-findings-report-design.md`
(read it with this plan; section numbers below are the spec's).

## Global Constraints

- **Same input, same bytes:** identical inputs give byte-identical `.html`
  and `.json` (headless-client design §9).
- **No network:**
  - no `http://` or `https://` URLs in `report.html`;
  - no CDN scripts, web fonts or remote images.
- **No absolute paths** in anything written under the output directory
  (2026-11-12 spec §4.10). `paths.rewrite` already covers the header and
  logs; anything new added to the header goes through it.
- **The page invents nothing:** the page may sort, filter, count and lay
  out. Every fact and every piece of wording comes from the JSON (spec §5).
- **Node is for development only** (spec §3.1).
  - `hwc` reads the committed `src/hwc/findings/report.html`.
  - Dependencies are pinned to exact versions with a committed lockfile.
  - No dependency beyond the stack goes in without a written reason.
- **The bundle stays current:** after any change under `web/report/src`,
  run `npm run build`, and commit the rebuilt `report.html` with that
  change.
- **Ids are stable:** finding ids, grouping keys and severities of existing
  signals don't change.
- **Format:** the findings JSON says `format: 2`. The page reads format 2
  only.
- **Visible handles:** every card shows `F-xxxxxxxx · <signal>`, selectable.
- **Harness and expected findings:** left out of every count and filter,
  shown only in their folds (`report.is_harness`, `expected`).
- **No triage** anywhere in the page.

## Review Focus

1. **A quest or step name containing `</script>`, `<!--` or `<script`.** The
   page must still load and show the name literally. The test is in Task 6.
2. **A matrix run where a guide is played by only some characters**, or the
   characters enter it at different levels. `header.guides` must merge
   without losing a character's levels, and flags must name the right
   characters. The test is in Task 5.
3. **A run that stops early, or has zero findings.** The page shows the
   header, warnings, "No findings" and the stop reason, and the map is
   absent. Stop data is tested in Task 5, and the `empty` fixture in
   Task 6. The page is checked in Task 9.
4. **A finding with no `file` or `line`,** such as a `lua-error` or `stuck`
   with no step. It can't be pinned on the map. It must still appear: in
   its severity section under Priority, and in an "Addon code" section after
   the guide files under Guide order. Tested in Task 8 (`prioritySections`
   and `guideSections` with the `single` fixture's lua-error).
5. **A guide with no `startlevel` or `endlevel` in its registration.** It
   gets no level flags and no error, and its label shows only the levels
   entered and left. The test is in Task 5.

---

## File map

| File | Change |
|---|---|
| `src/hwc/driver/run.lua` | Task 1: jump levels only at run start. Task 2: per-step pass levels and `log.guide_levels`. Task 3: hidden use steps. |
| `src/hwc/findings/group.lua` | Task 3: severity for `hidden-use-step`. Task 4: linking rules. |
| `src/hwc/findings/text.lua` | Task 3: hidden-use-step wording. Task 5: plain sentences, `SIGNALS` and `STOPS` label tables, markdown helpers removed. |
| `src/hwc/findings/report.lua` | Task 5: format 2 (`step`, `explains`, `labels`, `header.gaps`, `header.warnings`, `header.stop`, `header.guides`, summary counts). |
| `src/hwc/findings/render.lua` | Task 5: deleted, with `spec/findings/render_spec.lua`. |
| `src/hwc/findings/html.lua` | Task 6: new, the template writer. |
| `src/hwc/findings/report.html` | Task 6: placeholder. Task 7 on: the committed build output of `web/report`. |
| `src/hwc/cli.lua` | Task 5: no `.md`, header facts. Task 6: write `.html`, wrote line. |
| `tools/report-fixtures.lua`, `spec/fixtures/findings/*.json` | Task 6: the shared format-2 fixtures and the script that makes them. |
| `web/report/` | Task 7: project, build and bundle check. Task 8: `src/logic`. Tasks 9–10: `src/components`. |
| `README.md`, `CONTRIBUTING.md`, `.gitignore` | Task 1: jump wording. Task 6: outputs list. Task 7: page development and both suites. |
| `spec/driver/run_spec.lua`, `spec/findings/{group,text,report,html,fixtures}_spec.lua`, `spec/cli_spec.lua` | Lua tests per task. |

---

### Task 1: Set the level only at the start of a run

**Files:**
- Modify: `src/hwc/driver/run.lua:181-211` (`Driver:jump` and the comment
  above it)
- Modify: `README.md` (the guide-filter paragraph that says the level is
  raised "as a player skipping them would")
- Test: `spec/driver/run_spec.lua` (`describe("guide filters")`, around
  lines 618–700)

**Interfaces:**
- Produces: `jump.level_after == jump.level_before` for any jump made after a
  guide has been played. Run-log shape unchanged.

- [ ] **Step 1: Update the tests.** In `describe("guide filters")`:
  - `"an excluded guide is jumped to the next included one on the chain"`:
    change `assert.equal(10, j.level_after)` to `assert.equal(1, j.level_after)`.
  - Rename `"raises the level with the XP table, recording it as XP"` to
    `"raises the level with the XP table when the start guide is excluded"`.
    Drive it with `{ included = set("G2", "G3") }` and assert
    `world.player.level` is `5` after the jump into G2. Keep its XP-total
    assertion, recomputed for levels 1→5.
  - Add `"a mid-chain jump keeps the level earned so far"`:
    `included = set("G1", "G3")`, `world.player.level = 3` before driving.
    Assert `log.jumps[1].level_before == 3` and `log.jumps[1].level_after == 3`.
- [ ] **Step 2: Run them and confirm they fail.**
  Run: `~/.luarocks/bin/busted spec/driver/run_spec.lua`
  Expected: the three cases above fail. `level_after` is 10 where the tests
  now expect 1 and 3.
- [ ] **Step 3: Implement.** In `Driver:jump`, raise the level only when
  `#self.log.guides == 0`. Rewrite the comment above `Driver:jump` to state
  the rule from spec §7a. Update the README paragraph to match: the level is
  set only when no guide has been played yet, and a mid-chain jump keeps the
  level earned so far.
- [ ] **Step 4: Run the full driver suite.**
  Run: `~/.luarocks/bin/busted spec/driver`
  Expected: all pass.
- [ ] **Step 5: Commit.**
  `git commit -am "Set the level only when a run starts, not on mid-chain jumps"`

---

### Task 2: Levels at the step, and guide entry and exit levels, in the run log

**Files:**
- Modify: `src/hwc/driver/run.lua`:
  - `Driver:iterate` around line 468, where `info.seen` is set;
  - `Driver:open`;
  - `Driver:close` (around lines 217–245);
  - the initial `log` table (around line 600).
- Test: `spec/driver/run_spec.lua`

**Interfaces:**
- Produces:
  - `log.guide_levels`: an array, in `log.guides` order, of
    `{ gid, file, start_level, end_level, enter, leave, finished, last_line }`.
    - `start_level` and `end_level` come from `E:guide(gid)`.
    - `enter` is the player's level when the first step of that guide is
      acted on (recorded before acting).
    - `leave` is the player's level when `close` runs.
    - `finished` is true when `close` was called with `full`.
    - `last_line` is the highest `line` among the captured steps.
    - A guide opened but never acted on is left out.
  - `Driver:level_passing(info, i) -> number`: the level recorded at the
    first acted step whose index is greater than `i`. Falls back to
    `self.W.player.level`.
  - The `level` field of `never-shown-accept` (and, in Task 3, of
    `hidden-use-step`) is `self:level_passing(info, i)`.

- [ ] **Step 1: Write the failing tests.**
  - `"records the level the run passed a hidden accept at, not the level at close"`:
    a one-guide chain `R a` / `A Hidden (hidden, why "PRE not met")` /
    `R b` / `R c` / `D`. The script's entry for step 1 is
    `{ complete = {1}, level = 4 }`, for step 3 `{ complete = {3} }`, and
    for step 4 `{ complete = {4}, level = 7 }`.
    - Assert `signals(log,"never-shown-accept")[1].level == 4`. Step 3, the
      first acted on after the hidden index 2, is acted on at level 4.
    - Assert `log.guide_levels[1].enter == 1` and
      `log.guide_levels[1].leave == 7`.
  - `"records each guide's entry and exit levels"`: the `chain()` fixture
    with no filters, where G1's script entry adds `level = 5`.
    - Assert `log.guide_levels[1]` equals
      `{ gid="G1", file="g1.lua", start_level=1, enter=1, leave=5, finished=true, last_line=101 }`
      (`end_level` is nil in the fixture).
    - Assert `log.guide_levels[2].gid == "G2"` and
      `log.guide_levels[2].enter == 5`.
  - `"marks a guide cut short as not finished"`: a guide that stops on
    `max_iterations`. Assert `finished == false`.
- [ ] **Step 2: Run them and confirm they fail.**
  Run: `~/.luarocks/bin/busted spec/driver/run_spec.lua`
  Expected: FAIL. `guide_levels` is nil, and `level` is the level at close.
- [ ] **Step 3: Implement.**
  - In `iterate`, just before a step is acted on, append
    `{ index = cur.index, level = self.W.player.level }` to `info.passes`.
    Set `info.passes = {}` in `open`.
  - Add `Driver:level_passing`.
  - In `close`:
    - use `level_passing` for `never-shown-accept`;
    - append the `guide_levels` entry: `enter = info.passes[1].level`,
      `leave = self.W.player.level`, `finished = full == true`.
  - Initialise `log.guide_levels = {}`.
- [ ] **Step 4: Run the tests.**
  Run: `~/.luarocks/bin/busted spec/driver`
  Expected: all pass.
- [ ] **Step 5: Commit.**
  `git commit -am "Record guide entry and exit levels and the level a hidden accept was passed at"`

---

### Task 3: The `hidden-use-step` signal

**Files:**
- Modify: `src/hwc/driver/run.lua`:
  - `Driver:open` (step capture, around line 170);
  - `Driver:refresh_why`;
  - `Driver:close`.
- Modify: `src/hwc/findings/group.lua:33` (`SEVERITY`)
- Modify: `src/hwc/findings/text.lua` (`text.title`, `clauses`)
- Test: `spec/driver/run_spec.lua`, `spec/findings/text_spec.lua`

**Interfaces:**
- Produces: a signal `hidden-use-step` with the fields of `never-shown-accept`
  plus `use` (the U tag, a string id) and `loot` (`{ [item id] = qty }`, the
  L tag as captured). Its severity is `"high"`.
- Produces: `run.HIDDEN_USE_WHY = "You don't have the required items for this step."`

- [ ] **Step 1: Write the failing driver tests.**
  - `"records hidden-use-step for a U step hidden until its L items are in bags"`:
    the steps are
    `A Q (qids {1016})`,
    `l Q (qids {1016})`,
    `U Scroll (qids {1016}, tags { use = "5456", lootitem = { [5455] = 1 } }, hidden = true, why = "You don't have the required items for this step.")`,
    `T Q (qids {1016})`,
    `D`. Assert exactly one `hidden-use-step` with:
    - `line == 103`;
    - `use == "5456"`;
    - `loot` equal to `{ [5455] = 1 }`;
    - `qid == 1016`;
    - `before.action == "l"` and `after.action == "T"`.
  - `"records no hidden-use-step without an L tag, for an optional step, or for another why"`:
    three hidden U steps, each failing one condition. Assert none are
    recorded.
  - `"keeps a hidden A step with a use item as never-shown-accept"`: assert
    one `never-shown-accept` and no `hidden-use-step`.
- [ ] **Step 2: Write the failing text tests** in `spec/findings/text_spec.lua`:
  - `text.title({ signal = "hidden-use-step", name = "Divined Scroll" }) == '"Divined Scroll" is never shown'`.
  - `text.sentence` for `{ signal="hidden-use-step", use="5456", loot={[5455]=1} }` equals:
    `"WoWPro hides this use step until item 5455 is in bags, and it wasn't while the run passed here, so the client never used item 5456."`.
    With several loot ids, list them ascending, joined by `", "`, and use
    "items … are" in place of "item … is".
- [ ] **Step 3: Run them and confirm they fail.**
  Run: `~/.luarocks/bin/busted spec/driver/run_spec.lua spec/findings/text_spec.lua`
  Expected: FAIL.
- [ ] **Step 4: Implement.**
  - In `open`, capture `use`, `loot` (the `lootitem` tag) and `optional`
    onto `info.steps[i]`. Collect `info.uses`: the indices of `U` steps that
    have both a `use` and a `lootitem` tag.
  - `refresh_why` refreshes `info.uses` the same way it refreshes
    `info.accepts`.
  - In `close`, walk `info.uses` with the same `seen`, `limit` and
    `already_done` conditions as accepts. Add two more conditions:
    `not s.optional`, and `why` contains `run.HIDDEN_USE_WHY` (plain find).
  - Add a comment citing `WoWPro_Broker.lua` around line 2182 as the source
    of the text.
  - Add `["hidden-use-step"] = "high"` to `group.lua` `SEVERITY`.
  - Add the title and sentence branches to `text.lua`.
- [ ] **Step 5: Run the findings and driver suites.**
  Run: `~/.luarocks/bin/busted spec/driver spec/findings`
  Expected: all pass.
- [ ] **Step 6: Commit.**
  `git commit -am "Report U steps WoWPro hides until their L items are in bags"`

---

### Task 4: Root-cause linking across signals

**Files:**
- Modify: `src/hwc/findings/group.lua` (`link_roots`, lines 116–145)
- Test: `spec/findings/group_spec.lua`

**Interfaces:**
- Consumes: the `hidden-use-step` findings from Task 3 (`signal`, `qid`, `gid`).
- Produces: `caused_by` and `causes` set by the new rules. There's no API
  change.

- [ ] **Step 1: Write the failing tests** in `describe("group.findings")`.
  Build each from run logs, the way the existing group tests do.
  - `"links a never-shown-accept to the incomplete turn-in of its prerequisite"`:
    - a `did-not-advance` with `action="T"`, `qid=95213`,
      `reason="incomplete"`;
    - a `never-shown-accept` with `qid=95214` and
      `why="NextStep:PRE&(95213): A mandatory prereq was not met: 95213"`.

    Assert the accept's `caused_by` is the turn-in's id.
  - `"links a never-shown-accept to a hidden-use-step of its prerequisite"`:
    the same shape with a `hidden-use-step` for `qid=1016` and an accept
    whose prerequisite is 1016.
  - `"links an incomplete turn-in to a hidden-use-step for the same quest in the same guide"`:
    assert the `did-not-advance`'s `caused_by` is the hidden-use-step.
    Also assert that it does not link when the `gid` differs.
  - `"prefers refusal, then hidden-use-step, then incomplete turn-in, then hidden accept"`:
    one accept whose prerequisite N has one candidate of each kind. Assert
    it links to the refusal. Remove the refusal and assert it links to the
    hidden-use-step, and so on down the list.
- [ ] **Step 2: Run them and confirm they fail.**
  Run: `~/.luarocks/bin/busted spec/findings/group_spec.lua`
  Expected: FAIL, with `caused_by` nil.
- [ ] **Step 3: Implement** in `link_roots`:
  - Index two more maps: `hidden_use[qid]` and `incomplete_turnin[qid]`
    (`did-not-advance` with `action == "T"` and `reasons` containing
    `"incomplete"`).
  - For a `did-not-advance` turn-in with reason incomplete, try
    `pick(hidden_use[f.qid])` filtered to the same `gid` before the
    existing refusal lookup.
  - For a `never-shown-accept`, take
    `pick(refusals[n]) or pick(hidden_use[n]) or pick(incomplete_turnin[n]) or pick(hidden[n])`.
  - Update the comment.
- [ ] **Step 4: Run the findings suite.**
  Run: `~/.luarocks/bin/busted spec/findings`
  Expected: all pass, including the existing group tests.
- [ ] **Step 5: Commit.**
  `git commit -am "Link hidden accepts to incomplete turn-ins and hidden use steps of their prerequisite"`

---

### Task 5: Findings JSON format 2, and remove the markdown report

**Files:**
- Modify: `src/hwc/findings/report.lua`, `src/hwc/findings/text.lua`,
  `src/hwc/cli.lua` (`play`, lines 249–364)
- Delete: `src/hwc/findings/render.lua`, `spec/findings/render_spec.lua`
- Test: `spec/findings/report_spec.lua`, `spec/findings/text_spec.lua`,
  `spec/cli_spec.lua`

**Interfaces:**
- Consumes: `log.guide_levels` (Task 2).
- Produces, in `report.lua`:
  - `report.FORMAT = 2`
  - `report.GAPS`: moved verbatim from `render.GAPS`, with its comments.
  - `report.warnings(header, findings) -> { string... }`: the rules from
    `render.lua` `warning_lines`, as plain strings. Backticks are dropped
    (`Catalog source supplement was missing.`). Then one line per level-flag
    rule that fires, e.g. `"2 guides entered under-levelled"`,
    `"1 guide left under-levelled"`, `"1 guide entered over-levelled"`.
  - `report.guides(entries) -> list`. `entries` is
    `{ { combo = "<label>", guide_levels = log.guide_levels }, ... }`.
    - The result is `header.guides`: an array of
      `{ file, gid, last_line, start_level, end_level, levels = { [combo] = { enter, leave, finished } }, flags = { { combo, rule } ... } }`.
    - Merge order: the first appearance of each gid, walking the entries in
      order. `last_line` is the maximum across entries.
    - Flag rules: `enter-under` when `enter < start_level`; `leave-under`
      when `finished` and `leave < end_level`; `enter-over` when
      `enter > end_level`.
    - A missing level skips its rule.
    - Sort flags by `combo`, then `rule`.
  - `report.build(findings, header)`, extended:
    - each finding gains:
      - `step = { action = f.action, name = f.name }`;
      - `sentence`, now plain text;
      - on primary findings only, `explains`: counted descendants, the
        `render.lua` `descendants` and `counted` logic moved here.
    - the document gains `labels = { signals = text.SIGNALS, actions = text.VERBS, combos = { [label] = text.character(label) }, stops = text.STOPS }`;
    - `header.gaps = report.GAPS`;
    - `header.warnings = report.warnings(header, findings)`;
    - `summary.by_file[file][severity] = { primary = n, follow = n }`;
    - `summary.by_combo[combo][severity] = { primary = n, follow = n }`, for
      counted findings only.
- Produces, in `text.lua`:
  - `text.SIGNALS`, exactly:
    `never-shown-accept="Never offered"`,
    `hidden-use-step="Use step never shown"`,
    `accept-refused="Can't be taken"`,
    `log-full="Quest log full"`,
    `orphan-turnin="Turn-in without the quest"`,
    `wrong-race-class="Wrong race or class"`,
    `below-level="Offered below level"`,
    `did-not-advance="Doesn't advance"`,
    `manual-completion="Manual click"`,
    `stuck="Stuck"`,
    `leftover-quests="Left in log"`,
    `lua-error="Lua error"`,
    `missing-global="Missing global"`.
  - `text.STOPS`, exactly:
    `iterations="Hit its step limit"`,
    `errors="Too many addon errors"`,
    `no-step="No step to show"`,
    `max-guides="Reached --max-guides"`.
    `no-next-guide` (a normal end) has no entry.
  - `text.sentence(f, ctx)`: plain text, with no "Follows from" prefix and
    no links. The prerequisite reads "quest N".
  - Removed: `text.anchor`, `text.md_text`, `text.links`, `prereq_of`, and
    the markdown-link paths in `clauses`.
- Produces, in `cli.lua`:
  - `header.guides = report.guides(...)`, built from `logs` and `labels`
    before `paths.rewrite`;
  - `header.stop = { { combo, reason } ... }` for each log whose
    `stop.reason ~= "no-next-guide"`, or nil when there are none;
  - no `.md` write. `render` is no longer required.

- [ ] **Step 1: Write the failing report tests** in `spec/findings/report_spec.lua`:
  - `"writes format 2"`: `report.build({}, {}).format == 2`.
  - `"gives each finding its own step and a plain sentence"`: a follow-on's
    sentence has no `[`, no `](#` and no `"Follows from"`.
  - `"counts explains as counted descendants"`: a root with one counted
    child and one harness child gets `explains == 1`. Children have no
    `explains`.
  - `"carries labels for signals, actions, combos and stops"`:
    `labels.combos["NightElf WARRIOR baseline"] == "Night Elf Warrior"`.
  - `"carries gaps and warnings in the header"`: a dirty client gives the
    line `"The client checkout had uncommitted changes; this run may not be reproducible from its commit."`.
  - `report.guides` cases:
    - a guide played by one of two combos;
    - two combos entering at different levels;
    - each flag rule firing and not firing;
    - `leave-under` suppressed when `finished == false`;
    - a guide with nil `start_level` and `end_level` (no flags, no error);
    - the merged order when combo 2 plays a guide combo 1 didn't.
  - `"adds a level-flag warning line"`: one `enter-under` gives
    `"1 guide entered under-levelled"`.
- [ ] **Step 2: Update the text and CLI tests.**
  - Delete the markdown-only cases in `text_spec.lua` (anchor, md_text,
    links, and linked sentences). Add the `SIGNALS` and `STOPS` cases.
  - In `cli_spec.lua`, assert no `.md` file is written, and that the JSON
    has `format == 2` and a `header.guides` array.
  - Delete `spec/findings/render_spec.lua`.
- [ ] **Step 3: Run them and confirm they fail.**
  Run: `~/.luarocks/bin/busted spec/findings spec/cli_spec.lua`
  Expected: FAIL on the new cases.
- [ ] **Step 4: Implement** the interfaces above. Delete `render.lua`.
- [ ] **Step 5: Run the full suite.**
  Run: `~/.luarocks/bin/busted`
  Expected: all pass, with no reference to `hwc.findings.render` left
  (`grep -rn "findings.render" src spec` prints nothing).
- [ ] **Step 6: Commit.**
  `git commit -am "Findings JSON format 2: plain sentences, labels, guide levels and flags; drop the markdown report"`

---

### Task 6: The HTML writer and the shared fixtures

**Files:**
- Create: `src/hwc/findings/html.lua`
- Create: `src/hwc/findings/report.html`. For now, a placeholder page:
  `<!doctype html>`, a `<title>`, and
  `<script type="application/json" id="report">__HWC_REPORT_JSON__</script>`.
  Task 7 replaces it with the built bundle.
- Create: `tools/report-fixtures.lua`, and its output
  `spec/fixtures/findings/{single,matrix,empty}.json`
- Modify: `src/hwc/cli.lua` (`play`, `M.wrote_line`), `README.md` (the
  outputs list around line 149)
- Test: create `spec/findings/html_spec.lua` and
  `spec/findings/fixtures_spec.lua`, and modify `spec/cli_spec.lua`

**Interfaces:**
- Produces, in `html.lua`:
  - `html.PLACEHOLDER = "__HWC_REPORT_JSON__"`
  - `html.template() -> string`: reads
    `require("hwc.config").repo_root() .. "/src/hwc/findings/report.html"`.
    Errors naming the path when the file is missing.
  - `html.render(json_text, template) -> string`:
    - Replaces the placeholder with `json_text`, after replacing every `<`
      in `json_text` with `<`. That's valid JSON, and stricter than the
      spec's `<\/` because it also defuses `<!--`.
    - Use a function replacement so `%` in the data stays literal.
    - Errors unless the placeholder occurs exactly once.
- Produces: `cli.wrote_line(stem, n)`, which returns
  `"hwc: wrote <stem>.html and <stem>.json (N character[s])\n"`.
- Produces, in `tools/report-fixtures.lua`:
  - `fixtures.build() -> { [name] = json_text }`, a pure function. It runs
    synthetic run logs through `group.findings`, `report.guides` and
    `report.build`.
    - It uses a fixed header (date `2026-01-01`, a git addon with a fixed
      commit) and `paths_relative_to = "headless-wow-pro-client"`.
    - It has no I/O, so the busted test can call it.
  - Run as a script (`luajit tools/report-fixtures.lua`), it writes each
    document to `spec/fixtures/findings/<name>.json`.
  - The three fixtures:
    - `single`: one combo, about 25 findings. It includes:
      - a follow-on in a different severity from its cause;
      - a two-level chain;
      - quest ids 93 and 96393;
      - a `lua-error` with no file;
      - one harness `missing-global`;
      - one expected `manual-completion`;
      - a `hidden-use-step`;
      - three guides, one of them with pins closer than 1% of its length;
      - one `enter-under` flag.
    - `matrix`: three combos (two races). It includes a guide played by
      only two of them, combos entering one guide at different levels, and
      an `enter-over` flag.
    - `empty`: zero findings, with `header.stop` set to
      `{ { combo = "Dwarf WARRIOR baseline", reason = "iterations" } }`.

- [ ] **Step 1: Write the failing tests.**
  - `html_spec.lua`:
    - `"embeds the JSON in place of the placeholder"`.
    - `"escapes < so a name can't close the script"`: the data
      `{"name":"</script><!--x"}` gives output containing no
      `</script><!--`. Decoding the embedded JSON returns the original
      string.
    - `"keeps % in the data literal"`.
    - `"errors when the placeholder is missing or repeated"`.
    - `"is byte-identical across two renders"`.
    - `"the committed template has the placeholder once and no http(s) URL"`.
  - `fixtures_spec.lua`:
    `"committed fixtures match what report.build produces now"`. For each
    name, compare `fixtures.build()[name]` with the file's bytes. On
    failure, the message says to run `luajit tools/report-fixtures.lua`.
  - `cli_spec.lua`:
    - update the `wrote_line` case;
    - the run cases assert `<stem>.html` exists and its embedded JSON
      decodes equal to `<stem>.json`.
- [ ] **Step 2: Run them and confirm they fail.**
  Run: `~/.luarocks/bin/busted spec/findings spec/cli_spec.lua`
  Expected: FAIL, with `hwc.findings.html` and the fixtures not found.
- [ ] **Step 3: Implement** `html.lua`, the placeholder template and the
  fixture script, then write the fixtures.
  - In `play`, encode the JSON once:
    `local doc = json.encode(report_json(report.build(findings, header)), { indent = true }) .. "\n"`.
    Write `doc` to `.json` and `html.render(doc, html.template())` to
    `.html`.
  - Update the README outputs list.
- [ ] **Step 4: Run the full suite.**
  Run: `~/.luarocks/bin/busted`
  Expected: all pass.
- [ ] **Step 5: Commit.**
  `git add src/hwc/findings/html.lua src/hwc/findings/report.html tools/report-fixtures.lua spec/fixtures/findings spec/findings/html_spec.lua spec/findings/fixtures_spec.lua && git commit -am "Write the findings report as HTML; shared format-2 fixtures"`

---

### Task 7: The `web/report` project, build and bundle check

**Files:**
- Create in `web/report/`:
  - `package.json`, `package-lock.json`, `.nvmrc` (`24`), `tsconfig.json`,
    `vite.config.ts`, `index.html`;
  - `scripts/install-template.mjs`;
  - `src/main.tsx`, `src/types.ts`, `src/App.tsx`;
  - `test/fixtures.test.ts`, `test/bundle.test.ts`.
- Modify: `src/hwc/findings/report.html` (now the build output),
  `.gitignore` (`web/report/node_modules/`, `web/report/dist/`),
  `README.md` (a "Working on the report page" section), `CONTRIBUTING.md`
  (the setup section runs both suites).

**Interfaces:**
- **Dependencies:** `preact`; and as dev dependencies `vite`,
  `@preact/preset-vite`, `vite-plugin-singlefile`, `typescript`, `vitest`.
  - Use exact versions (no `^` or `~`), the current ones at install time,
    recorded in the lockfile.
  - Nothing else without a reason written in the commit message.
- **Scripts:**
  - `build`: `vite build && node scripts/install-template.mjs`. The second
    step copies `dist/index.html` to `../../src/hwc/findings/report.html`.
  - `dev`: `vite`.
  - `test`: `vitest run`.
  - `typecheck`: `tsc --noEmit`.
- **`index.html`:** contains
  `<script type="application/json" id="report">__HWC_REPORT_JSON__</script>`
  exactly once.
- **`vite.config.ts`:** a small inline plugin that applies only in `serve`
  mode. It replaces the placeholder with
  `spec/fixtures/findings/<name>.json`, where `name` comes from
  `?fixture=` and defaults to `single`.
- **`src/types.ts`:** `ReportDoc`, the format-2 document: `format: 2`,
  `header`, `summary`, `labels` and `findings: Finding[]`, with every field
  from spec §5 and plan Task 5. Optional fields are optional in the type.
  Other modules import it, and nothing else defines the shape.
- **`src/main.tsx`:**
  - reads `document.getElementById("report")!.textContent`;
  - `JSON.parse`s it as a `ReportDoc`;
  - renders `<App doc>`.

  For now `App` renders only the title and finding count. Task 9 builds it
  out.

- [ ] **Step 1: Write the failing tests.**
  - `test/fixtures.test.ts`, `"every shared fixture parses as a format-2 ReportDoc"`:
    - load each `spec/fixtures/findings/*.json`;
    - assert `format === 2`;
    - assert every finding has `id`, `signal` and `title`;
    - assert every `caused_by` names an id in the document.

    `npm run typecheck` covers the static shape.
  - `test/bundle.test.ts`, `"the committed report.html matches a fresh build"`:
    - run Vite's `build()` API with the project config and `outDir` set to
      a temporary directory;
    - compare the output's bytes with `../../src/hwc/findings/report.html`;
    - on failure, the message says to run `npm run build`.
  - `test/bundle.test.ts`, `"the bundle is self-contained"`: no `https?://`,
    no `<script src`, no `<link rel="stylesheet"`, and the placeholder
    occurs exactly once.
- [ ] **Step 2: Run them and confirm they fail.**
  Run: `cd web/report && npm ci && npm test`
  Expected: the bundle tests FAIL, because the committed `report.html` is
  still the Task 6 placeholder.
- [ ] **Step 3: Implement** the scaffold and `App`. Then run
  `npm run build`.
- [ ] **Step 4: Run every suite.**
  Run:
  - `cd web/report && npm run typecheck && npm test` (expected: all pass);
  - `cd ../.. && ~/.luarocks/bin/busted spec/findings/html_spec.lua`
    (expected: PASS against the built template);
  - building twice in a row leaves `git status` clean.
- [ ] **Step 5: Commit.**
  `git add web/report src/hwc/findings/report.html .gitignore README.md CONTRIBUTING.md && git commit -m "Build the report page from web/report with Vite and Preact"`

---

### Task 8: The page logic

**Files:**
- Create in `web/report/src/logic/`: `state.ts`, `filter.ts`, `order.ts`,
  `hash.ts`
- Test: create the matching `web/report/test/logic/*.test.ts`, run against
  the shared fixtures

**Interfaces (all pure, with no DOM):**
- `state.ts`:
  - `type FilterState = { q: string; sev: Set<string>; file: Set<string>; kind: Set<string>; combo: Set<string>; order: "prio" | "guide" }`
  - `defaultState(doc: ReportDoc): FilterState`: every option on, `q`
    empty, order `"prio"`.
  - `counted(f: Finding): boolean`: true when `f.severity` is set,
    `!f.expected`, and the finding isn't harness (`missing-global`, or
    `lua-error` with `harness`).
- `filter.ts`:
  - `matches(f: Finding, s: FilterState): boolean`:
    - Text search is case-insensitive over `title`, `qname`, `` `${file}:${line}` ``
      and `id`.
    - A query of digits only matches `f.qid === Number(q)`, or a whole
      digit token in `title`, `file:line` or `id`.
    - A combo matches when `f.combos` intersects `s.combo`.
  - `visible(doc, s): { roots: Finding[]; lifted: Finding[] }`:
    - `roots`: counted primary findings that match;
    - `lifted`: counted follow-ons that match while some ancestor doesn't
      (spec §4.5).
  - `childrenShown(f, doc, s): Finding[]`: the causes to nest under `f`.
    That's those that match, or have a matching descendant.
  - `counts(doc, s): { shown: number; total: number; options: Record<"sev"|"file"|"kind"|"combo", Record<string, number>> }`:
    - `shown` and `total` count counted findings once each, by their own
      fields.
    - The count for each option is computed under all the other active
      filters, with that group's own filter ignored.
- `order.ts`:
  - `prioritySections(doc, s): { severity: string; primary: number; follow: number; cards: Finding[] }[]`.
    - `cards` are roots and lifted findings of that severity, sorted by:
      1. `explains` descending (0 when absent);
      2. `confidence === "verified"` first;
      3. the index of `file` in `header.guides`, with no file or an
         unknown file last;
      4. `line`;
      5. `id`.
    - `primary` and `follow` count the counted findings of that severity
      that match.
  - `guideSections(doc, s): { file: string | null; cards: Finding[] }[]`:
    files in `header.guides` order, each in `line` order, then one
    `file: null` section ("Addon code") for findings with no file or an
    unknown file.
- `hash.ts`:
  - `toHash(s): string` and `fromHash(h, doc): FilterState`.
  - The format is `q=…&sev=a,b&file=…&kind=…&char=…&order=guide`, with
    values URI-encoded.
  - Only parts that differ from `defaultState` are written. An empty hash
    gives `defaultState`.

- [ ] **Step 1: Write the failing tests** (Vitest, against
  `single.json` and `matrix.json`):
  - `matches`:
    - `"93"` matches quest 93 and not 96393;
    - case-insensitive title match;
    - `file:line` match;
    - id match.
  - `visible`:
    - a search that matches only a follow-on whose cause doesn't match
      puts it in `lifted`;
    - a matching cause keeps its matching follow-on nested, not lifted;
    - harness and expected findings never appear.
  - `counts`:
    - with only `High` on, `shown` equals the number of High counted
      findings, and `total` is unchanged;
    - the `sev` option counts ignore the severity filter but respect the
      text query;
    - a follow-on nested under a cause of another severity is counted
      under its own severity.
  - `prioritySections`:
    - follow-ons don't appear as top-level cards unless lifted;
    - the order follows the four keys (assert the exact id order for one
      fixture section);
    - the `lua-error` with no file sorts last in its severity.
  - `guideSections`: the file order matches `header.guides`, and the last
    section is `file: null` holding the `lua-error`.
  - `hash`: `fromHash(toHash(s))` deep-equals `s` for a state with every
    field set, and `fromHash("")` equals `defaultState`.
  - Matrix: filtering to one combo hides findings only other combos hit.
- [ ] **Step 2: Run them and confirm they fail.**
  Run: `cd web/report && npm test`
  Expected: FAIL, with the modules missing.
- [ ] **Step 3: Implement** the four modules.
- [ ] **Step 4: Run the tests and the type check.**
  Run: `npm run typecheck && npm test`
  Expected: all pass. The bundle test still passes, because the logic isn't
  imported by `App` yet.
- [ ] **Step 5: Commit.**
  `git add web/report/src/logic web/report/test/logic && git commit -m "Report page logic: matching, lifting, counts, ordering, URL state"`

---

### Task 9: The page: header, sidebar, cards, order and folds

**Before writing components, invoke the `frontend-design:frontend-design`
skill.** The mockups in `.superpowers/brainstorm/mockups/layout.tpl.html`
(tab D) are the structure the user approved. They are not the finished
visual design. Keep the bundle lean: no component library, no icon font,
no CSS framework.

**Files:**
- Create in `web/report/src/components/`: `Header.tsx`, `Sidebar.tsx`,
  `Sections.tsx`, `Card.tsx`, `Folds.tsx`, `StepKey.tsx`
- Create: `web/report/src/styles.css`
- Modify: `web/report/src/App.tsx`, `src/hwc/findings/report.html` (rebuilt)

**Interfaces:**
- Consumes: the Task 8 functions only. Components never filter, count or
  sort on their own.
- `App` holds `FilterState`. It initialises from `fromHash(location.hash, doc)`
  and writes `toHash` with `history.replaceState` whenever the state
  changes.

**What to build (spec §4.2, 4.3, 4.5–4.9):**
- **Header:**
  - title from `labels.combos` and counts, reading "N of M findings" while
    a filter is on;
  - the run line;
  - `header.warnings`.
- **Sidebar:**
  - search, plus checkbox groups using `counts().options`;
  - the Character group is hidden when there's one combo;
  - Kind labels come from `labels.signals`;
  - "Also in this run" links set the fold open and then scroll to it;
  - sticky, and a collapsible panel below 900px.
- **Order switch:** Priority (`prioritySections`) or Guide order
  (`guideSections`), where each file heading stays at the top of the screen
  while you scroll that file's cards.
- **Card (spec §4.6):**
  - follow-ons nested through `childrenShown`;
  - a lifted card shows "Follows from <title> (hidden by filters)", a
    button that resets to `defaultState`, then scrolls to the cause;
  - the step trio, with verbs from `labels.actions` and a `StepKey`
    popover;
  - the footer is `F-… · signal` as a `<button>` that toggles the `why`
    and `reasons`.
- **Folds:**
  - harness notices;
  - expected manual clicks;
  - About this run: provenance, catalog, rank, dungeons, carried,
    `paths_relative_to` and `gaps`.
- **Empty and stopped runs:** "No findings", plus each `header.stop` entry
  named through `labels.combos` and `labels.stops`.
- **Look and behaviour:**
  - light and dark via `prefers-color-scheme`;
  - every control is a `<button>`, `<input>` or `<a>`.

- [ ] **Step 1: Build the components.** Then run `npm run build`.
- [ ] **Step 2: Run every suite.**
  Run: `cd web/report && npm run typecheck && npm test && cd ../.. && ~/.luarocks/bin/busted`
  Expected: all pass.
- [ ] **Step 3: Check it by hand.** Open each fixture with `npm run dev`
  (`?fixture=single|matrix|empty`). Then open a page written by `bin/hwc`
  from disk, to confirm `file://` works. Use Chrome with the
  `claude-in-chrome` tools and `read_console_messages` with pattern `.`,
  expecting no errors. Confirm:
  - (a) the sidebar and the file headings in Guide order stay in place
    while scrolling;
  - (b) the sidebar links open their folds;
  - (c) Tab reaches every control, and Enter or Space works each one;
  - (d) a reload keeps the filters and order;
  - (e) `empty` shows "No findings" and "Dwarf Warrior: Hit its step
    limit";
  - (f) the look holds in both light and dark;
  - (g) the narrow-window panel works at 800px wide.

  Save a screenshot of each fixture (`save_to_disk`).
- [ ] **Step 4: Commit.**
  `git add web/report src/hwc/findings/report.html && git commit -m "Report page: header, sidebar, cards, both orders, folds"`

---

### Task 10: The guide map and level flags

**Files:**
- Create: `web/report/src/logic/map.ts`,
  `web/report/test/logic/map.test.ts`,
  `web/report/src/components/GuideMap.tsx`
- Modify: `web/report/src/App.tsx`, `web/report/src/styles.css`,
  `src/hwc/findings/report.html` (rebuilt)

**Interfaces:**
- `map.ts`:
  - `tracks(doc, s): Track[]`
  - `type Track = { file; label; levelText; flags: { rule; combos: string[] }[]; perCombo: { combo; enter; leave }[]; groups: PinGroup[] }`
  - `type PinGroup = { at: number /* 0..1 */; findings: Finding[] }`
  - Pins are the findings that match `matches(f, s)` and have this `file`,
    at `line / last_line`.
  - Group, in line order, any pin closer than `minGap` (default `0.012`)
    to the previous pin in the current group.
  - `levelText` for one combo is `"19–25 · entered 19, left 23"`. When the
    declared range is missing, it's only `"entered 19, left 23"`. For
    several combos it's the min–max of `enter` and of `leave`, with the
    exact form `"19–25 · entered 18–19, left 23–24"`.
  - `flags` are grouped by rule, with the combos named through
    `labels.combos`.

- [ ] **Step 1: Write the failing tests** in `map.test.ts`:
  - the close pins in `single.json` form one group with the right count,
    and the others stay alone;
  - `minGap = 0` gives one pin per group;
  - a filter that excludes a finding removes its pin;
  - `levelText` for single, for matrix, and for a guide with no declared
    range;
  - `flags` for `matrix.json` group the `enter-over` combos under one rule;
  - the track order follows `header.guides`.
- [ ] **Step 2: Run them and confirm they fail.**
  Run: `cd web/report && npm test`
  Expected: FAIL.
- [ ] **Step 3: Implement** `map.ts`, then `GuideMap`:
  - each track has a line scale;
  - a pin or group is a `<button>`, with follow-ons drawn smaller;
  - hover or focus shows a custom tooltip right away (no `title`);
  - clicking a single pin scrolls to its card and highlights it;
  - clicking a group expands it in place;
  - the track name switches to Guide order and jumps to that file;
  - flags sit on the label in the severity colour, with a tooltip naming
    the rule and the combos;
  - a compact copy of the map stays pinned to the top of the main column
    once the full map scrolls away;
  - there's no map when there are no findings.

  Then run `npm run build`.
- [ ] **Step 4: Run every suite and check by hand.**
  Run: `npm run typecheck && npm test && cd ../.. && ~/.luarocks/bin/busted`
  (expected: all pass).
  In Chrome, confirm:
  - (a) the tooltip appears with no delay;
  - (b) the group in `single` expands;
  - (c) a pin click highlights its card, and the pinned map is reachable;
  - (d) the map follows the filters;
  - (e) `matrix` shows the levels per combo and the flag tooltip;
  - (f) Tab reaches the pins.

  Save screenshots.
- [ ] **Step 5: Commit.**
  `git add web/report src/hwc/findings/report.html && git commit -m "Report page: guide map with pin grouping and level flags"`

---

### Task 11: Check against a real run

**Files:** none changed, unless a defect turns up. Fix a defect in the task
that owns it, with a regression test in that task's suite.

- [ ] **Step 1: Run the client for real.**
  Run: `bin/hwc run --class WARRIOR --race Dwarf --out findings`, against
  the current WoW-Pro checkout (`main`).
  Expected: `hwc: wrote findings/<today>-Dwarf-WARRIOR-baseline.html and …json (1 character)`.
- [ ] **Step 2: Check the engine changes in the JSON.**
  `jq '.findings[] | select(.signal=="hidden-use-step") | {line,file,use,loot}'`
  shows `19_25_Alliance.lua` line 449, `use "5456"` and loot `5455`.
  - The "Elemental Bracers" `did-not-advance` has `caused_by` pointing at
    it.
  - The "Mage Summoner" `never-shown-accept` is linked through that chain.
  - `.header.guides` lists the played guides with `levels`.
- [ ] **Step 3: Open the `.html` from disk** and walk the Task 9 and
  Task 10 hand checks against it. Save screenshots.
- [ ] **Step 4: Run every suite.**
  Run: `~/.luarocks/bin/busted && (cd web/report && npm run typecheck && npm test)`
  Expected: all pass. Then `git status` shows only the untracked
  `findings/` output, which stays uncommitted.
