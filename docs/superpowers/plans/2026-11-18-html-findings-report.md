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
- **Page:** all layout is plain JS inside the template. No build step, no
  network.

**Tech Stack:** Lua 5.1, busted 2.3 (`~/.luarocks/bin/busted`), dkjson behind
`hwc.json` (canonical key order). Vanilla HTML, CSS and JS in one file.

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
- **The page invents nothing:** the template JS may sort, filter, count and
  lay out. Every fact and every piece of wording comes from the JSON (spec
  §5).
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
   absent. Stop data is tested in Task 5; the page is checked in Tasks 7
   and 9.
4. **A finding with no `file` or `line`,** such as a `lua-error` or `stuck`
   with no step. It can't be pinned on the map. It must still appear: in
   its severity section under Priority, and in an "Addon code" section after
   the guide files under Guide order. Checked in Task 7 against a fixture
   JSON with a lua-error.
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
| `src/hwc/findings/report.html` | Task 6: placeholder template. Tasks 7–8: the page. |
| `src/hwc/cli.lua` | Task 5: no `.md`, header facts. Task 6: write `.html`, wrote line. |
| `README.md` | Task 1: jump wording. Task 6: outputs list. |
| `spec/driver/run_spec.lua`, `spec/findings/{group,text,report,html}_spec.lua`, `spec/cli_spec.lua` | Tests per task. |
| `spec/fixtures/findings/` | Task 7: format-2 fixture JSON files for checking the page by hand. |

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

### Task 6: The HTML writer

**Files:**
- Create: `src/hwc/findings/html.lua`
- Create: `src/hwc/findings/report.html`. For now, a minimal valid page:
  `<!doctype html>`, a `<title>`, and
  `<script type="application/json" id="report">__HWC_REPORT_JSON__</script>`.
  Tasks 7–8 fill it in.
- Modify: `src/hwc/cli.lua` (`play` and `M.wrote_line`), `README.md` (the
  outputs list around line 149)
- Test: create `spec/findings/html_spec.lua`, modify `spec/cli_spec.lua`

**Interfaces:**
- Produces:
  - `html.PLACEHOLDER = "__HWC_REPORT_JSON__"`
  - `html.template() -> string`: reads
    `require("hwc.config").repo_root() .. "/src/hwc/findings/report.html"`.
    Errors naming the path when the file is missing.
  - `html.render(json_text, template) -> string`:
    - Replaces `html.PLACEHOLDER` with `json_text`, after replacing every
      `<` in `json_text` with `<`. That's valid JSON, and stricter
      than the spec's `<\/`, because it also defuses `<!--`.
    - Use a function replacement in `gsub` so `%` in the data is literal.
    - Errors unless the placeholder occurs exactly once.
  - `cli.wrote_line(stem, n)`, which returns
    `"hwc: wrote <stem>.html and <stem>.json (N character[s])\n"`.

- [ ] **Step 1: Write the failing tests** in `spec/findings/html_spec.lua`:
  - `"embeds the JSON in place of the placeholder"`.
  - `"escapes < so a name can't close the script"`: the data
    `{"name":"</script><!--x"}` gives output containing no `</script><!--`.
    Decoding the embedded JSON returns the original string.
  - `"keeps % in the data literal"`.
  - `"errors when the placeholder is missing or repeated"`.
  - `"is byte-identical across two renders"`.
  - `"the shipped template has the placeholder once and no http(s) URL"`.
    Read the real file through `html.template()`. Assert the placeholder
    occurs once, and that `not tpl:find("https?://")`.

  In `cli_spec.lua`:
  - update the `wrote_line` case;
  - the run cases assert `<stem>.html` exists, and that its embedded JSON
    decodes equal to `<stem>.json`.
- [ ] **Step 2: Run them and confirm they fail.**
  Run: `~/.luarocks/bin/busted spec/findings/html_spec.lua spec/cli_spec.lua`
  Expected: FAIL, with `hwc.findings.html` not found.
- [ ] **Step 3: Implement** `html.lua` and the placeholder template. In
  `play`, encode the JSON once:
  `local doc = json.encode(report_json(report.build(findings, header)), { indent = true }) .. "\n"`.
  Write `doc` to `.json` and `html.render(doc, html.template())` to
  `.html`. Update the README outputs list: the `.html` report, the `.json`
  findings, and the per-character logs.
- [ ] **Step 4: Run the full suite.**
  Run: `~/.luarocks/bin/busted`
  Expected: all pass.
- [ ] **Step 5: Commit.**
  `git add -A src/hwc/findings spec/findings/html_spec.lua && git commit -am "Write the findings report as a self-contained HTML page"`

---

### Task 7: The page: header, sidebar, cards, order and folds

**Before writing markup, invoke the `frontend-design:frontend-design`
skill.** The mockups in `.superpowers/brainstorm/mockups/layout.tpl.html`
(tab D) are the structure the user approved. They are not the finished
visual design.

**Files:**
- Modify: `src/hwc/findings/report.html`
- Create: the format-2 fixtures in `spec/fixtures/findings/`, made by
  running the Task 6 CLI against the existing driver fixtures, or written by
  hand to the format-2 shape. They are only for opening by hand:
  - `single.json` and `single.html`: one character, about 25 findings,
    including follow-ons across severities and one lua-error with no file.
  - `matrix.json` and `matrix.html`: three combos, plus a guide only some
    combos played.
  - `empty.json` and `empty.html`: zero findings, `header.stop` set.

**Interfaces (inside the template):**
- Data: `JSON.parse(document.getElementById("report").textContent)`.
- State: `{ q, sev:Set, file:Set, kind:Set, combo:Set, order:"prio"|"guide" }`,
  serialised to and from `location.hash` as
  `q=…&sev=a,b&file=…&kind=…&char=…&order=guide`. Values are
  URI-encoded. An empty hash means every option on and order `prio`.
- `matches(f, state) -> bool`:
  - text search is case-insensitive over `title`, `qname`, `file:line` and
    `id`;
  - a query of digits only matches `f.qid === Number(q)`, or a digit-only
    token inside `title`, `file:line` or `id`. A substring of a longer
    number is not a match.
- `visible(findings, state) -> { roots, lifted }`. `roots` are primary
  findings that match. `lifted` are follow-ons that match while some
  ancestor doesn't (spec §4.5).
- Counting (spec §4.5): every finding is counted once, by its own fields.
  The sidebar option counts are computed under all the *other* active
  filters.

**What to build (spec §4.2, 4.3, 4.5, 4.6, 4.7, 4.8, 4.9):**
- Header: title, run line, warnings from `header.warnings`, and "N of M"
  while a filter is on.
- Sidebar:
  - Search.
  - Checkbox groups for Severity, Character (hidden when there's one combo),
    Guide file, and Kind, labelled from `labels.signals`.
  - "Also in this run" links that open and scroll to the folds.
  - The sidebar stays fixed (sticky).
  - Below 900px it becomes a collapsible panel.
- Order switch:
  - Priority: severity sections. Within each section, sort by `explains`
    descending, then `confidence === "verified"` first, then the
    `header.guides` index of `file`, then `line`. Findings without a file go
    last.
  - Guide order: file sections in `header.guides` order. Each file heading
    stays at the top of the screen while you scroll its cards. Then an
    "Addon code" section for findings with no file, or a file not in
    `header.guides`.
- Card (spec §4.6):
  - follow-ons nested inside their cause;
  - lifted cards show "Follows from <title> (hidden by filters)", which
    clears the filters and jumps to the cause;
  - the step trio `before → step → after`, using verbs from
    `labels.actions`, with a key one hover away;
  - the footer is `F-… · signal`, and opens the `why` and `reasons`.
- Folds:
  - Harness notices: `report.is_harness` rule, `signal == "missing-global"`,
    or `lua-error` with `harness`.
  - Expected manual clicks: `expected`.
  - About this run: header provenance, catalog, rank, dungeons, carried,
    `paths_relative_to` and `gaps`.
- Empty and stopped runs: "No findings". Name each `header.stop` entry with
  `labels.combos` and `labels.stops`.
- Light and dark via `prefers-color-scheme`. Every control is a `<button>`,
  `<input>` or `<a>`.

- [ ] **Step 1: Generate the fixtures** and confirm each `.html` opens from
  disk with no console errors. Use Chrome with the `claude-in-chrome`
  tools, opening the `file://` URL, and `read_console_messages` with
  pattern `.`.
- [ ] **Step 2: Build the page** as above.
- [ ] **Step 3: Check it against each fixture** by opening it from disk.
  Confirm:
  - (a) a search matching only a follow-on shows it, lifted, with its
    "hidden by filters" line;
  - (b) searching `93` doesn't match 96393;
  - (c) counts read "N of M", and the sidebar counts change with the other
    filters;
  - (d) the file heading stays put in Guide order;
  - (e) the "this step" chip names its action and name;
  - (f) the sidebar links open their folds;
  - (g) Tab reaches every control, and Enter or Space works each one;
  - (h) a reload keeps the filters and order;
  - (i) `empty.html` shows "No findings" and the stop reason;
  - (j) `single.html` shows the lua-error under "Addon code" in Guide
    order;
  - (k) `matrix.html` shows the Character filter.

  Save one screenshot of each fixture (`save_to_disk`) for the review.
- [ ] **Step 4: Run the writer tests again** (the template still has
  exactly one placeholder and no URLs).
  Run: `~/.luarocks/bin/busted spec/findings/html_spec.lua`
  Expected: PASS.
- [ ] **Step 5: Commit.**
  `git add src/hwc/findings/report.html spec/fixtures/findings && git commit -m "Findings page: header, sidebar filters, cards, priority and guide order, folds"`

---

### Task 8: The guide map and level flags

**Files:**
- Modify: `src/hwc/findings/report.html`

**Interfaces:**
- Consumes: `header.guides` (`file`, `last_line`, `start_level`,
  `end_level`, `levels`, `flags`) and the Task 7 functions `state`,
  `matches` and `visible`.

**What to build (spec §4.4):**
- **Tracks and pins:**
  - One track per `header.guides` entry, in order.
  - Each track has a line scale from 1 to `last_line`.
  - Pins for the findings that match, at `line / last_line`. Follow-ons
    are drawn smaller.
  - Pins closer together than their diameter are grouped into one marker
    showing the count. Hover lists the group, and clicking expands it.
- **Labels and flags:**
  - The label is the short file name, the finding count, and the declared
    range plus levels entered and left.
  - A single combo reads "19–25 · entered 19, left 23". A matrix shows the
    range across combos, and hover lists each combo.
  - Flags appear on the label in the severity colour, with a hover naming
    the rule and the combos.
- **Interaction:**
  - Hover shows an immediate tooltip, not the `title` attribute.
  - A click scrolls to the card and highlights it.
  - A compact copy of the map stays pinned to the top of the main column
    once the full map scrolls away. This is the "way back".
  - Clicking a track name switches to Guide order and jumps to that file.
- The map is hidden when there are no findings (spec §4.8).

- [ ] **Step 1: Build it.**
- [ ] **Step 2: Check it against each fixture.** Confirm:
  - (a) the tooltip appears on hover with no delay;
  - (b) close pins in `single.html` group, and expand on click;
  - (c) clicking a pin highlights its card, and the pinned map is
    reachable from there;
  - (d) the map follows the filters;
  - (e) `matrix.html` shows per-combo levels on hover and at least one
    flag, so make the fixture include one;
  - (f) pins and groups are buttons reachable by Tab.

  Save screenshots.
- [ ] **Step 3: Run the writer tests.**
  Run: `~/.luarocks/bin/busted spec/findings/html_spec.lua`
  Expected: PASS.
- [ ] **Step 4: Commit.**
  `git commit -am "Findings page: guide map with pins, grouping and level flags"`

---

### Task 9: Check against a real run

**Files:** none changed, unless a defect turns up. Fix any defect in the
task that owns it, with a regression test where the code is Lua.

- [ ] **Step 1: Run the client for real.**
  Run: `bin/hwc run --class WARRIOR --race Dwarf --out findings`, against
  the current WoW-Pro checkout (`main`).
  Expected: `hwc: wrote findings/<today>-Dwarf-WARRIOR-baseline.html and …json (1 character)`.
- [ ] **Step 2: Check the engine changes in the JSON.**
  `jq '.findings[] | select(.signal=="hidden-use-step") | {line,file,use,loot}'`
  shows `19_25_Alliance.lua` line 449 with `use "5456"` and loot `5455`.
  - The "Elemental Bracers" `did-not-advance` has `caused_by` pointing at it.
  - The "Mage Summoner" `never-shown-accept` is linked through that chain.
  - `.header.guides` lists the played guides with `levels`.
- [ ] **Step 3: Open the `.html` from disk** and walk the Task 7 and Task 8
  checklists against it. Save screenshots.
- [ ] **Step 4: Run the full suite.**
  Run: `~/.luarocks/bin/busted`
  Expected: all pass. Then `git status` shows no stray files. The run's
  output goes to `findings/`, which is untracked today, so leave it
  uncommitted.
