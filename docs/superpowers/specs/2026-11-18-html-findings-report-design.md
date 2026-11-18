# HTML findings report

Status: draft for review · 2026-11-18 · Supersedes the markdown report in
`2026-11-12-findings-report-design.md` §3–§4. That spec's §5 (the JSON) still
holds, apart from the changes in §5 below.

## 1. Intent

Each run writes the same findings twice: `<run>.json` (built by
`src/hwc/findings/report.lua`) and `<run>.md` (laid out by
`src/hwc/findings/render.lua`). The markdown has three problems:

- It's hard to scan and you can't filter it.
- Its anchor links work or fail depending on the viewer.
- It repeats what the JSON already says.

This work replaces the markdown with one HTML page that the JSON drives. The
JSON stays the only source of truth, and the page is a view onto it.

Two engine changes are part of the same work, plus a level-handling fix
(§7a) that the level flags depend on. Both came out of reviewing the
report against a real run, and the report is where their absence shows:

- **Root-cause linking** misses causes across signals. For example, a refused
  turn-in of quest N is the cause of a "never offered" for a quest whose
  prerequisite is N.
- **A new signal for hidden use steps.** WoWPro hides a `U` step whose `L`
  items aren't in bags yet. Nothing reports this, so the run's findings land
  on the turn-in and accept steps further down instead of on the step at fault.

**Reader:** whoever ran `bin/hwc run` or `bin/hwc matrix`, on their own
machine. They open the file locally. To share it they zip the findings folder
or take a screenshot. Nothing is hosted.

**Success:**
- Opening the page answers three questions at a glance: how many findings,
  where they cluster in the guides, and what to fix first.
- Any finding can be reached by searching its title, quest id or `file:line`.
- A screenshot of the page is enough to explain a finding to someone else.

## 2. Goals, non-goals, anti-goals

**Goals**
- One self-contained `<date>-<scope>.html` per run that works offline when
  opened from disk by double-click.
- Priority order by default (most important first), with a switch to guide
  order.
- A guide map showing where findings sit in each guide file.
- A filter sidebar plus search, with counts that tell the truth about what's
  hidden.
- Follow-on findings nested inside the finding that causes them.
- Better root-cause linking (§6) and a hidden-use-step signal (§7).

**Non-goals**
- Triage of any kind in this report. `/triage` will write its own separate
  report keyed by finding id and signal. Its format and the skill itself are
  later work.
- Hosting, sharing links, or editing verdicts in the page.
- Changing severities, finding ids or grouping keys for existing signals.

**Anti-goals** (a failure even if it works)
- **The page and the JSON disagree.** The page shows only what the JSON says.
  It doesn't re-derive any fact the engine owns, such as severity, causes or
  sentences.
- **A filter hides something without saying so.** Every count reflects the
  active filters as "N of M". A follow-on that matches a filter is never
  hidden because its cause doesn't match.
- **Losing the grep handle.** Every finding's `F-xxxxxxxx` id and signal slug
  are visible on its card. Triage will reference both.
- **Network dependencies.** No CDN scripts, web fonts or remote images. The
  page must render from a zip on a plane.
- **Absolute paths** anywhere under the output directory. This rule is
  unchanged from the 2026-11-12 spec §4.10.
- **Non-deterministic output.** Identical inputs give byte-identical `.html`
  and `.json` files (headless-client design §9).

## 3. Outputs

`play()` in `src/hwc/cli.lua` writes:

| Path | Audience | Change |
|---|---|---|
| `findings/<date>-<scope>.html` | people | **new**, replaces `.md` |
| `findings/<date>-<scope>.json` | tools, `/triage` | format bumped (§5) |
| `findings/<date>-<scope>/*.json` | debugging | per-character run logs, unchanged |

The `.md` output, `render.markdown`, and the markdown-only helpers in
`text.lua` (`md_text`, `anchor`, `links` and the markdown forms) are removed
along with their specs. The CLI's "wrote" line names the `.html` and `.json`
files.

**How the page gets its data (decided):**
- A browser blocks a page opened from `file://` from fetching a JSON file
  next to it. So the page carries its data inside itself.
- The HTML is a static template committed to the repo. At write time Lua
  drops the exact JSON document it writes to `<run>.json` into a
  `<script type="application/json" id="report">` element.
- `</` in the embedded JSON is escaped (`<\/`) so a title can't close the
  script element.
- Lua does no layout. All layout lives in the template's JS, working from that
  JSON.

### 3.1 How the page is built (the user's call: Node only for development)

The page source is a small TypeScript project. Its build output, the
template, is committed. Running `hwc` needs only Lua. Node is needed only to
work on the page or run its tests.

- **Stack:** TypeScript, Preact, Vite with a single-file plugin (all JS and
  CSS inlined, no network references), and Vitest.
  - Exact versions are pinned with a committed lockfile.
  - The Node version is pinned in `.nvmrc`.
  - Lightweight is a requirement: a dependency or feature beyond this spec
    has to justify itself.
- **Layout:**
  - `web/report/`: `package.json`, `package-lock.json`, `.nvmrc`,
    `tsconfig.json`, `vite.config.ts`, `index.html`, `src/`, `test/`.
  - `npm run build` writes the bundle to `src/hwc/findings/report.html`.
    The JSON placeholder lives in `index.html` and comes through the build
    unchanged.
- **Split:**
  - The page logic lives in plain TS modules with no DOM: matching,
    lifting follow-ons out when their cause is hidden, counting, ordering,
    map pin grouping, and URL state.
  - Preact components only render.
  - The format-2 document has one TS type that both the logic and the
    components use.
- **One set of fixtures:** format-2 fixtures in `spec/fixtures/findings/`,
  produced by a Lua script from synthetic run logs.
  - A busted test fails when the committed fixtures differ from what
    `report.build` produces now.
  - Vitest loads the same files.
  - So format drift breaks one side or the other.
- **The bundle stays current:** a Vitest test builds into a temporary
  directory and fails when the result differs byte for byte from the
  committed `report.html`. There's no CI, so the README's development
  section tells contributors to run both suites.
- **Dev loop:** `npm run dev` serves the page with a fixture filled in
  (`?fixture=<name>`). Nothing else.

## 4. The page

The layout was chosen from mockups (`.superpowers/brainstorm/mockups/`,
option D): A's sidebar, C's map and B's cards.

### 4.1 Structure

```
┌──────────────┬───────────────────────────────────────────────┐
│ Search       │ Title: <characters>: N findings, M follow on  │
│              │ run line: date · WoW-Pro branch @ commit      │
│ Severity  ☑  │ warnings (only when any apply)                │
│ Character ☑  │ ┌ Guide map ───────────────────────────────┐  │
│ Guide file ☑ │ │ 01_12_Dun_Morogh   ●  ●     ●   ◉•        │  │
│ Kind      ☑  │ │ 12_20_Eastern_...     •●   ◉     ●●  ●    │  │
│              │ └──────────────────────────────────────────┘  │
│ Also in run  │ Order: [Priority] [Guide order]               │
│  Harness  38 │ ── High · 9 primary · 2 follow-on ──          │
│  Expected 11 │ ┌ card ───────────────────────────────────┐   │
│  About       │ │ ● title       explains 1 more           │   │
│              │ │ file:line · quest · level · kind        │   │
│              │ │ sentence                                │   │
│              │ │ prev step → THIS STEP → next step       │   │
│              │ │ ▸ F-40ccf1a8 · never-shown-accept       │   │
│              │ │   └ nested follow-on cards              │   │
│              │ └─────────────────────────────────────────┘   │
│              │ ▸ Harness notices · ▸ Expected clicks · ▸ About│
└──────────────┴───────────────────────────────────────────────┘
```

### 4.2 Header
- **Title:** characters, finding count and follow-on count, worded as in the
  current markdown title.
- **Run line:** date, WoW-Pro branch and short commit (or version when it's
  not a git folder), and the character count.
- **Warnings:** the same rules as today (uncommitted changes, unverified quest
  data), shown only when one applies.

### 4.3 Sidebar

**Filters:**
- **Search** matches title, quest name, `file:line` and finding id as text.
  Quest ids match whole numbers only, so `93` matches quest 93 and not 96393.
- **Checkbox groups:** Severity, Character (hidden when the run has one
  character), Guide file, Kind (signal, under a plain label).
- **Counts:** each option shows its count under the other active filters.
  The title becomes "N of M findings" while any filter is on.

**"Also in this run"** links to the three folded sections at the bottom:
Harness notices, Expected manual clicks, About this run. A link opens its
section as well as scrolling to it.

**Layout:** the sidebar stays in view while the main column scrolls.

### 4.4 Guide map
- **One track per guide file**, in chain order, labelled with the short file
  name, its finding count, and the level the character entered and left the
  guide at (`header.guides[].levels`, §5).
  - Level is an outcome of the run, not an input. The client sets it only
    when a run starts with no earlier guide played: level 1 for a full run,
    the guide's start level for a run that begins later (§7a). The end level
    is never dictated.
  - So "entered 19, left 23" against a guide written for 19–25 is a routing
    signal in its own right, and can expose problems no single finding names.
  - For a matrix run the label shows the range across characters. A hover
    lists each character's entered and left levels.
  - Finding levels don't feed the label.
- **Level flags** (the user's call). A track is flagged when a character:
  - **enters under-levelled:** `enter < start_level`;
  - **leaves under-levelled:** `leave < end_level`, when the guide was
    finished rather than cut short by the run stopping;
  - **enters over-levelled:** `enter > end_level`, so the guide's content is
    grey for the character. Including this direction is my call.

  The flag sits on the track label in the severity colour, and a hover says
  which rule fired for which characters. Flags come from the JSON (§5,
  `header.guides[].flags`). The page only draws them. They're also counted in
  the header's warnings line, e.g. "2 guides left under-levelled". They are
  not findings: they have no `F-` id and don't appear in the finding counts.
  This is the same family as `below-level`, which flags a single quest.
- **Pins:**
  - One pin per finding at its line, coloured by severity.
  - Follow-ons are drawn smaller.
  - The track has a line-number scale.
  - Pins that are close together are grouped so none hides another. How to
    group them is the builder's call.
- **Hovering** a pin shows a tooltip right away with the title, `file:line`
  and severity. It doesn't rely on the browser's slow `title` attribute.
- **Clicking** a pin scrolls to its card and highlights it. A way back to the
  map is always within reach, such as a sticky mini-map or a "back to map"
  control (builder's call).
- **Filters:** the map follows the active filters. Clicking a track's name
  switches to Guide order and jumps to that file.

### 4.5 Order

**Priority (default):**
- The findings are split into sections by severity: High, Medium-high,
  Medium, Low.
- Each section lists only primary findings (no `caused_by`). Follow-ons
  appear nested inside their cause, which can be in a different severity
  section.
- Within a section the order is:
  1. findings that explain the most others;
  2. then findings whose quest data was checked against a second source
     (`confidence: verified`) before unchecked ones;
  3. then guide file in chain order, then line.

  This tie-break order is my call; the user hasn't confirmed it.
- This view replaces the old "Start here" box: the top of the High section is
  the old top five.

**When a filter hides a cause:** a follow-on that matches the filters while
its cause doesn't is lifted out as a top-level card in its own severity
section (or its own file in Guide order). It carries a line
"Follows from <title> (hidden by filters)", and clicking that clears the
filters and jumps to the cause.

**Counting:** every count (sidebar, title, section headings) counts each
finding once, by its own severity, file and kind. That's true wherever its
card is nested. A section heading reads "High · 9 primary · 2 follow-on",
meaning the High findings without `caused_by` and the High findings with it.

**Guide order:**
- Sections by guide file, in line order, with follow-ons nested.
- The current file's heading stays at the top of the screen while you scroll
  through its cards.

### 4.6 Card
- **Top line:** severity dot, title, and an "explains N more" chip when the
  finding has causes. N is the finding's `explains` field (§5).
- **Meta line:** `file:line` (in Priority order) or `line` (in Guide order),
  plus quest id, level and a plain label for the kind.
- **Characters:** the characters that hit the finding, shown only for runs
  with several characters.
- **Sentence:** from the JSON, as plain text.
- **"Follows from" link:** built from `caused_by`, not from markup inside the
  sentence (§5).
- **Where in the guide:** previous step → **this step** → next step. All
  three show their action and name, so "this step" carries its own action
  and name too. A key to the step letters (A, T, C, K, R, h, …) is one hover
  or click away.
- **Grind** (kills to reach a level), when present.
- **Footer:** `F-xxxxxxxx · <signal>` in small monospace text that you can
  select and copy. Clicking it opens the engine detail: the WoWPro `why`
  string and the reasons.
- **Nested follow-on cards:** the same card, indented under a rule.

### 4.7 Folded sections
- **Harness notices:** missing globals, and lua errors flagged as harness.
  They're left out of every count and filter above, as today.
- **Expected manual clicks:** left out of every count and filter, as today.
- **About this run:** provenance, catalog sources and hashes, guide rank,
  dungeon skips, quests carried over, paths relative to, and what the
  simulation doesn't model (`render.GAPS` moves into the JSON header, §5).

### 4.8 Empty and stopped runs

A run with no findings still gets a page. It shows the header, the warnings,
and a plain "No findings" in place of the map and cards. If the run stopped
early, the page says why, from the run's stop reason. The folded sections
stay.

### 4.9 Look and behaviour
- **Style:** visual design follows the frontend-design guidance at build
  time. It has to look good in a screenshot and stay dense enough to scan.
- **Light and dark:** both, following `prefers-color-scheme` (my call).
- **Narrow windows:** below about 900px the sidebar becomes a collapsible
  panel above the content.
- **Keyboard:** every control is a real button, checkbox or link and works
  from the keyboard. That covers pins, chips, the Order switch and folds.
- **Remembering the view:** the current filters and order go in the URL
  hash, so a reload keeps the view. Nothing is stored in `localStorage` (my
  call).

## 5. JSON changes (format 1 → 2)

The page needs facts that today's JSON either lacks or carries as markdown.

| Change | Why |
|---|---|
| `sentence` is plain text. The "Follows from [title](#f-…)." prefix is dropped; the page builds that line from `caused_by`. | No markdown inside the data. |
| Each finding gains `step: { action, name }`, its own step, alongside `before` and `after`. | "this step" can name itself. |
| Every finding keeps `action` and `name`. `step` is the plain display form. | Unchanged meaning. |
| `header.gaps`: the list in `render.GAPS`. | "About this run" without a Lua-side renderer. |
| `header.stop`: why each character's run stopped (per combo), when it stopped early. | Empty and stopped runs (§4.8). |
| `summary` gains `by_file` and `by_combo` counts (primary and follow-on, by severity). | The page shows them without re-deriving any rule. |
| `header.warnings`: the warning lines, as the strings `render.lua` `warning_lines` produces today. | The page shows them and doesn't apply the rules itself. |
| `header.guides`: an ordered list of `{ file, gid, last_line, start_level, end_level, levels = {combo → {enter, leave}} }` for every guide played. `start_level` and `end_level` are the guide's own declared range. `enter` and `leave` are the character's level at the first and last step acted on in that guide, from the run log. A guide the run got only part-way through has a `leave` of the level when the run stopped. Each entry also has `flags = [{ combo, rule }]`, where `rule` is one of `enter-under`, `leave-under`, `enter-over` (§4.4). `start_level` and `end_level` come from `E:guide(gid)` (`driver/engine.lua` exposes `startlevel` and `endlevel`). For a matrix run the per-character chains are merged by order of first appearance, with ties broken by file name. `last_line` is the highest guide line the driver parsed. | Chain order for the map, the Priority tie-break and Guide order. Track length on the map. |
| `labels`: `{ signals = {slug → plain label}, actions = {letter → verb}, combos = {combo → display name} }`, taken from `text.lua` (`VERBS`, `character`, and a new signal-label table). | One wording source (Lua). The JS holds no wording tables. |
| Each primary finding gains `explains`, the count of counted descendants (`render.lua` `descendants`/`counted`). | The "explains N more" chip without re-deriving which findings count. |
| `level` on `never-shown-accept` and `hidden-use-step` becomes the player's level when the run passed the step (the level at the first step acted on after it), not the level at guide close. `leftover-quests` keeps the end-of-run level, and the map's level range leaves it out. | Today `level` reads 25 for steps passed at level 21. |
| `format: 2`. | Consumers can tell the formats apart. |

The page reads only format 2. Format 1 files are not supported.

**Rule for the template JS:** it may sort, filter, count and lay out. Every
fact and every piece of wording comes from the JSON.

Harness and expected findings stay in `findings` with their existing markers
(`report.is_harness`, `expected`). The page sorts them into the folds by the
same rule.

## 6. Root-cause linking (`group.lua` `link_roots`)

Today a `never-shown-accept` whose WoWPro `why` names an unmet prerequisite N
links only to a refusal (`accept-refused`, `log-full`) or a hidden accept of
quest N.

**Added rule:** it also links to a finding showing that quest N never
completed:
- a `did-not-advance` on a turn-in (`action == "T"`) of quest N whose reason
  is `incomplete`; or
- a `hidden-use-step` for quest N (§7).

The order below is the order of preference, and the lowest id wins within
each kind. The order is: refusal, then hidden use step, then incomplete
turn-in, then hidden accept. (Where the two new kinds go in that order is my
call.)

**Cases from the 2026-11-12 Dwarf Warrior run:**
- **Line 287 chain:** `F-7f8b32ee` ("Stolen Blasting Powder" never offered,
  prerequisite 95213) follows from `F-158bdbf7` (the 95213 turn-in was
  refused as incomplete). So the chain hanging off line 287 now roots at a
  Medium finding.
- **"Mage Summoner":** `F-f3a4daf7` ("Mage Summoner" never offered,
  prerequisite 1016) follows from the new hidden-use-step finding on line 447
  (§7). Otherwise it follows from `F-0f25485b` (the 1016 turn-in was refused
  as incomplete).

**Rule for the "doesn't advance" findings:** a `did-not-advance` turn-in of
quest N with reason `incomplete` follows from a `hidden-use-step` for quest N
in the same guide when one exists.

Cycle refusal and `caused_by` uniqueness stay as they are.

## 7. New signal: `hidden-use-step`

**Problem.** In `WoWPro_Broker.lua` around line 2182, a non-optional `U` (or
`A`) step with a use item and an `L` tag is skipped until every `L` item is
already in bags. When that happens, WoWPro's `why` is set to "You don't have
the required items for this step." A guide that writes `L` to mean "the item
you'll have *after* using it" has written a step that never shows.

**Real case:** `19_25_Alliance.lua:447` on the 11-12 run's checkout (now line 449 on `main`),
`U Divined Scroll|QID|1016|U|5456|L|5455|`. The run goes from step 346 (loot
the bracers) straight to step 348 (turn in). The turn-in is refused because
1016 is incomplete, and "Mage Summoner" (prerequisite 1016) is never offered.

**Detection.** When `Driver:close` closes a guide, it already walks unseen
accepts. It also walks unseen `U` steps. A step is reported when all of these
hold:
- it was below the furthest step acted on (or the guide finished);
- it was not already done;
- it was not optional;
- it **has an `L` tag**;
- the WoWPro `why` recorded for it is the "required items" message.

**Why the `L` tag is required:** the engine sets the same `why` when a step
has no `L` tag and its use item simply isn't in bags. The client only partly
models items, so without this requirement every use item the client never
obtained would become a High finding.

**`A` steps:** an `A` step with a use item that's hidden this way stays a
`never-shown-accept`, as today. Its signal and id don't change, and there's
no second finding on the same line.

Matching the `why` text is fragile in the same way the existing `not met:`
match is (`group.lua`). The same kind of comment should record where the
text comes from.

**Fields:** the same shape as `never-shown-accept`: `gid`, `file`, `line`,
`ordinal`, `action`, `name`, `qid`, `why`, `level`, `log`, `before`, `after`,
`qname`, `confidence`. It adds `use` (the `U` item id) and `loot` (the
`L` item ids and quantities) so the sentence can name them.

**Severity:** high. The step is mandatory and invisible.

**Wording:**
- **Title:** `"<name>" is never shown`.
- **Sentence:** says that WoWPro hides this use step until item(s) `<L ids>`
  are in bags, and that they aren't there before the item is used. Exact
  wording goes in `text.lua` with the others.

## 7a. Level set only at the start of a run (`Driver:jump`)

**Rule (the user's call):** the client sets the character's level only when
a run starts with no earlier guide played:
- a full run starts at level 1;
- a run whose first included guide comes later in the chain starts at that
  guide's `startlevel`.

After that, level is only ever earned.

**Today:** `Driver:jump` (`src/hwc/driver/run.lua:186–204`) raises the level
to the next included guide's `startlevel` on *every* jump over excluded
guides, including mid-chain gaps (e.g. 01_12 and 19_25 included, 12_20
excluded).

**Change:** `jump` raises the level only when no guide has been played yet in
this run (`#self.log.guides == 0`). A mid-chain jump keeps the level earned so
far. Until a separate use case comes up, the included guides are treated as a
completable chain. If skipping a guide leaves the character under-levelled,
that is reported (an `enter-under` flag, §4.4), not papered over.

- `jump.level_before` and `jump.level_after` stay in the run log. They're
  equal for a mid-chain jump.
- The README's filter section ("raise the level to that guide's startlevel …
  as a player skipping them would") and the comment above `Driver:jump` are
  updated to match.
- **Tests:** a jump before any guide is played raises the level. A mid-chain
  jump leaves it as it was.

## 8. Testing

**Lua (busted, existing setup):**
- `report_spec`: the format 2 fields, a plain-text sentence, `step`,
  `header.gaps`, the summary counts.
- `group_spec`: each new linking rule, including both §6 run cases as
  fixtures, and the preference order.
- `text_spec`: the hidden-use-step title and sentence. Drop the markdown-only
  cases.
- Driver: a fixture guide with an `A` step, then
  `U item|L|<item not in bags>|`, then `T` gives one `hidden-use-step`, and
  the turn-in's `did-not-advance` links to it.
- HTML writer: the template's placeholder is replaced exactly once. `</script>`
  inside a title is escaped. The output is byte-identical across two writes.
  There are no `http(s)://` references outside the embedded data.

**Fixtures, not old ids:** the finding ids in §6 come from the 2026-11-12 run
on WoW-Pro `fix/forever-prereq-gates`, with uncommitted changes, so they
won't reproduce. The `group_spec` and driver cases are synthetic fixtures
built in the shape of those cases.

**Page:**
- **Data:** a fresh `bin/hwc run` for Dwarf Warrior against the current
  WoW-Pro checkout (`main`). There the bug is at
  `19_25_Alliance.lua:449`, still `U Divined Scroll|…|U|5456|L|5455|`.
- **Check:** open that run's `.html` from disk and walk the UX review list
  from the brainstorm:
- a follow-on that matches a search while its cause doesn't still shows;
- quest-id search matches whole numbers;
- counts show "N of M";
- the map has tooltips and a scale, and close pins are grouped;
- there's a way back to the map;
- the file heading stays put in Guide order;
- "this step" is named;
- the sidebar links open their folds;
- keyboard use works.

**Page logic (Vitest, §3.1).** Against the shared fixtures:
- a follow-on that matches while its cause doesn't is lifted out;
- quest ids match whole numbers only;
- "N of M" and per-option counts under the other filters;
- each finding is counted once, by its own fields;
- priority and guide order, including findings with no file;
- the URL state comes back unchanged after a round trip;
- close pins are grouped;
- the built bundle matches the committed `report.html`.

**Hand checks** (Chrome, opening from disk) cover layout and interaction
only: sticky elements, tooltips, keyboard reach, and the look in light and
dark.

## 9. Left to the builder
- How Lua finds the committed template at runtime (`config.repo_root()`).
- Visual design within §4.9, and how close pins are grouped on the map.
- The module and component structure inside `web/report/src`, within §3.1.
- Whether `text.lua` keeps any shared wording helpers after the markdown
  forms are removed.
