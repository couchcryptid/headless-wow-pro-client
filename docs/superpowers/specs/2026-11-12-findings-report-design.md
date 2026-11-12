# Findings report redesign

Status: draft for review · 2026-11-12 · Supersedes the file layout in
`2026-11-11-headless-client-design.md` §7.2 and the input format in §8.

## 1. Intent

The findings markdown is the first thing a contributor reads after running the
simulator. Today the layout serves a parser that doesn't exist yet (`/triage`,
still listed as **Next** in the README) and a provenance audit. The person who
ran the simulator gets the worst of it: hash-named headings, 15 fixed fields
where half say "none", engine debug strings instead of sentences, root causes
mixed in with their effects, and about 20 lines of SHA-256 values before the
first finding.

**Reader:** whoever ran `bin/hwc run` or `bin/hwc matrix`. That's the user today
and any contributor later. They know WoW and WoW-Pro guides, but they may not
know this client's internal vocabulary (signal names, rulings, `why` formats).

**What they come for:** to find out what's wrong and decide what to look at
first.

**Success:** within about 30 seconds of opening the file, the reader knows how
many real problems there are, which few explain most of the findings, and where
they are. Each finding then reads as a sentence they could paste into a bug
report.

## 2. Goals, non-goals, anti-goals

**Goals**
- Split the output into two formats: a canonical JSON file for machines and a
  human-first markdown file.
- Lead the report with a conclusion: which root causes to start with, and how
  many findings each one explains.
- Give every finding a plain-English title and one explanatory sentence, both
  generated from its signal.
- Show each root cause once, with its effects linked to it by name.
- Group findings by guide file in line order, so one file can be worked through
  top to bottom.
- Keep the engine detail available without putting it in the reading path.
- Keep output byte-identical for identical inputs (design spec §9).

**Non-goals**
- Changing what gets detected, severities, grouping keys or finding ids. The
  `group.lua` logic stays as it is, apart from the additions in §6.
- Building `/triage`.
- HTML, a web view, or any new dependency.

**Anti-goals** (a failure even if it works)
- Throwing information away. Every field the current markdown carries must
  still exist in the JSON.
- Sentences that overclaim. A sentence states only what the signal and its
  fields prove. When the cause is unknown, it says so.
- Losing the grep handle. Every finding's `F-xxxxxxxx` id still appears in the
  markdown.
- Absolute paths in anything written under the output directory: the markdown,
  the findings JSON or the run logs. Paths are written relative to a base
  directory (§4.10).

## 3. Outputs

`play()` in `src/hwc/cli.lua` writes three things per invocation:

| Path | Audience | Content |
|---|---|---|
| `findings/<date>-<scope>.md` | people | the report in §4 |
| `findings/<date>-<scope>.json` | `/triage` and other tools | §5 |
| `findings/<date>-<scope>/*.json` | debugging | per-character run logs (unchanged apart from the path rewrite in §4.10) |

The CLI's "wrote" line names both the `.md` and the `.json` file.

## 4. The markdown report

### 4.1 Page order

1. **Title and run line**
2. **Warnings** (only when there is something to warn about)
3. **Start here**: the top root causes
4. **At a glance**: counts
5. **Findings by file**: guide files, then addon code
6. **Harness notices** (folded)
7. **Expected manual clicks** (folded)
8. **About this run**: provenance and modelling gaps

### 4.2 Title and run line

```markdown
# Dwarf Warrior: 113 findings from 9 root causes

2026-11-12 · WoW-Pro `fix/forever-prereq-gates` @ `64fe6b3` · 1 character · `Dwarf-WARRIOR-baseline`
```

- **Character label.** One combo gives "Dwarf Warrior". The baseline variant is
  implied; any other variant is added in parentheses, e.g. "Dwarf Hunter
  (alch-herb)". Several combos give "<N> characters: Dwarf, Gnome", with races
  in sorted, distinct order. Class tokens are title-cased for display
  (`WARRIOR` → "Warrior").
- **Counts.** The title counts findings with a severity, not expected manual
  clicks or harness notices. A root cause is a finding with no `caused_by`.
- **Scope slug.** The scope slug stays visible in code formatting so the file
  can be matched to its name.
- **Commit hashes.** Shortened to 7 characters here; the full hash is in §4.9
  and the JSON.

### 4.3 Warnings

This is a blockquote, emitted only when at least one condition holds. It has one
bullet per condition:

- The addon checkout had uncommitted changes: "The WoW-Pro checkout had
  uncommitted changes; this run may not be reproducible from its commit."
- The client checkout had uncommitted changes, with the same wording for the
  client.
- A catalog source has `present=false`: "Catalog source `<name>` was missing."
  For `supplement` it adds: "Camping 101 quests aren't recognised, so
  profession variants match their baselines."
- More than half the findings rest on unverified quest data: "<n> of <m>
  findings rest on quest data not checked against a second source." This
  replaces the per-finding `Confidence:` wall; see §4.6.

### 4.4 Start here

```markdown
## Start here

These root causes explain the most findings. Fixing one should clear the findings listed under it.

1. 🔴 [EnableDungeons auto-completes dungeon accepts](#f-1aa80a4c): explains 12 more · `WoWPro/WoWPro_Broker.lua:2588`
2. 🔴 ["Stolen Blasting Powder" is never offered](#f-7f8b32ee): explains 1 more · `01_12_Dun_Morogh.lua:275`
…
```

- **Candidates.** Root causes with a severity, excluding harness items.
- **Ranking.** By severity, then by the number of findings that trace back to
  the root (descendants, counted through the whole chain) with most first, then
  file, line and id.
- **Length.** At most 5 entries. Show "explains N more" only when N > 0.
- If no findings exist, the section reads "Nothing found." and §4.5 and §4.6
  are omitted.

### 4.5 At a glance

There are two small tables.

**By severity**, in severity order:

| | Root causes | Follow-on | Total |
|---|---|---|---|
| 🔴 High | 9 | 17 | 26 |

**By file**, in the same order as §4.6. Each file name links to its section:

| File | 🔴 | 🟠 | 🟡 | ⚪ |
|---|---|---|---|---|

Zero counts are written as blanks, not as `0`, so the eye goes to the counts
that exist.

### 4.6 Findings by file

```markdown
## Guide files

### 01_12_Dun_Morogh.lua
`WoWPro_Leveling/Forever/Alliance/01_12_Dun_Morogh.lua`

#### 🔴 "Stolen Blasting Powder" is never offered <a id="f-7f8b32ee"></a>
High · line 275 · quest 95214 · level 12 · unverified quest data

The guide tells you to accept this quest, but WoWPro hides the step because its prerequisite, quest 95213, is never completed.

- **Between steps:** Turn in "Stolen Blasting Powder" → *this step* → Accept "Those Blasted Troggs!"
- **Also blocks:** ["Old Ironforge Incursion" is never offered](#f-ff215041)

<details><summary>Engine detail · F-7f8b32ee</summary>

- Signal: `never-shown-accept`
- Engine said: `NextStep:PRE&(95213): A mandatory prereq was not met: 95213`
- Quest log: 95213
</details>

Triage: _pending_
```

**Sections**
- "Guide files" lists files under `WoWPro_Leveling/`.
- "Addon code" lists every other file, plus addon `lua-error` findings that have
  no file.
- Within each section, files are sorted by path and findings by line. File-less
  findings come last. Ties are broken by signal, then id.
- Severity no longer drives the order here. Prioritising is the job of §4.4.

**File heading.** The basename, followed by the full repo-relative path on its
own line.

**Finding heading**
- The format is `#### <marker> <title> <a id="f-<hex>"></a>`.
- Markers: 🔴 high, 🟠 medium-high, 🟡 medium, ⚪ low.
- The anchor is the lower-cased id. The `F-` id appears in the summary of the
  folded engine detail, so grepping for `F-7f8b32ee` still lands on the
  finding.

**Meta line**
- The fields, in order and joined with ` · `: severity word, `line N`,
  `quest Q`, `level L`, and `unverified quest data`.
- Each field is omitted when it doesn't apply. The unverified marker appears
  only when `confidence == "unverified"`.

**Sentence.** One paragraph, generated from the templates in §4.7.

**Bullets.** Only the ones that apply, in this order:
- `Between steps:` the steps before and after, each written with its verb (§4.8)
  when the action is known, otherwise as the quoted name.
- `Caused by:` a link to the parent, using the parent's title as the link text.
- `Also blocks:` links to the direct children, by title. The root of the
  dungeon chain lists all of them.
- `Affects:` the combo summary (§4.8). Omitted when the matrix has one combo.
- `Ground:` for below-level findings: "<kills> kills to reach level <to>".

**Follow-on findings** (those with `caused_by`) are compact:
- the heading,
- the meta line,
- `Caused by: [parent title](#anchor)`, written as the sentence itself (for
  example, "Follows from [parent title](#anchor).") instead of a separate
  bullet, followed by the template's first clause,
- the engine fold and the triage line.

They keep their place in file order so the file can be worked through top to
bottom, but each one takes about 6 lines instead of about 20.

**Engine detail fold**
- It carries the raw signal name, the raw `why`, the `reason` (or `reasons`), the
  quest log ids, the full combo list when it was summarised, and the `stack` for
  Lua errors.
- `why` and messages are written as inline code, single line (`one_line`), with
  backticks inside them replaced by `'`.
- Only fields that have a value are listed.

**Triage line.** Exactly one line, `Triage: _pending_`, is the slot `/triage`
fills in place.

### 4.7 Titles and sentences

Below, `<name>` is the step name, `<step>` is the verb form from §4.8, and `Q`
is the quest id. A link to a related finding is used whenever that finding
exists. Each sentence states what the signal shows; the template states its
limits.

| Signal / case | Title | Sentence |
|---|---|---|
| `never-shown-accept`, why matches `not met: N` | "<name>" is never offered | The guide tells you to accept this quest, but WoWPro hides the step because its prerequisite, quest N, is never completed. (N links to N's finding when there is one.) |
| `never-shown-accept`, reason `engine-dungeon-skip` | Dungeon quest "<name>" is skipped | WoWPro marks this dungeon quest done without showing it, because dungeon quests are switched off. |
| `never-shown-accept`, any other why | "<name>" is never offered | The guide tells you to accept this quest, but WoWPro never shows the step. The engine's reason is in the detail below. |
| `never-shown-accept`, no why | "<name>" is never offered | The guide tells you to accept this quest, but WoWPro never shows the step and gave no reason. |
| `accept-refused`, reason race/class | "<name>" can't be taken by a <Race/Class> | The guide shows this accept, but the quest data says a <Race/Class> can't take quest Q. |
| `accept-refused`, reason prerequisite | "<name>" can't be taken yet | The guide shows this accept, but the quest data says a prerequisite of quest Q isn't done yet. |
| `log-full` | "<name>" can't be taken: quest log full | The guide shows this accept while the quest log is already full. |
| `orphan-turnin` | <step> for a quest the character never had | The guide asks you to <verb lower> quest Q, but this character never had it. |
| `wrong-race-class` | "<name>" is shown to the wrong <race/class> | WoWPro shows this step to a <Race/Class>, but quest Q is for other <races/classes>. (In multi-combo runs: "…to characters that quest Q excludes.") |
| `below-level` | "<name>" is offered below its level | The guide reaches this accept at level L, below the level the quest requires. |
| `did-not-advance` | "<name>" doesn't advance | The simulated action didn't move WoWPro to the next step, so the client clicked it off. |
| `manual-completion` (not expected) | "<name>" needed a manual click | No game event completed this step, so the client clicked it off. |
| `stuck`, settle-limit | Stuck after "<name>" | WoWPro kept scheduling work after this step and never settled. |
| `stuck`, same-step | Stuck on "<name>" | WoWPro stayed on this step past the watchdog limit. |
| `stuck`, max-iterations | Run hit its step limit | The run stopped at its step limit before this guide ended. |
| `stuck`, no-current-step | No step to show | WoWPro had no current step to show, so the run couldn't continue. |
| `stuck`, no-guide-loaded | No guide loaded | WoWPro loaded no guide, so nothing ran. |
| `leftover-quests` | Quest "<qname>" (Q) is left in the log | Quest Q was still in the log when this guide ended; nothing in it turns the quest in. (`<qname>` falls back to "Q" alone.) |
| `lua-error` (addon) | Lua error: <message, first 80 chars> | WoWPro raised an error during the run. The message and stack are in the detail below. |
| `engine-dungeon-skip` (root) | EnableDungeons auto-completes dungeon accepts | WoWPro's EnableDungeons setting marks dungeon-quest accepts done without showing them; every finding it explains is a dungeon quest the guide never offers. |
| unknown signal | <raw signal>: <step or name> | (none) |

An unknown signal raises, as `group.lua` already does; the last row is there
only as a defensive fallback in `render`. It must not be reachable.

### 4.8 Display helpers

**Step verbs.** These map WoW-Pro action codes to words: A "Accept", T "Turn in",
C "Complete", K "Kill", R "Run to", H "Hearth to", h "Set hearth at", F "Fly
to", f "Get flight path at", N "Note:", U "Use", B "Buy", b "Take boat to",
l "Loot", r "Sell and repair at", L "Reach level", D "Guide done:".

The builder confirms each against WoW-Pro's parser (`WoWPro_Parser.lua`). An
unconfirmed or unknown code renders as the raw letter plus the name, which is
what happens today.

**Combo summary**
- If every matrix combo is affected: "all N characters".
- Else, if at most 3 combos are not affected: "all except <list>".
- Else, group by race and class:
  - "Dwarf Hunter (all 7 variants)" when every matrix variant of that race and
    class is affected;
  - otherwise "Dwarf Hunter (baseline, lw-skin)".
- Groups are joined with ", " and sorted.
- When the summary drops detail, the raw sorted list goes into the engine fold.

**Paths.** See §4.10. The markdown, the findings JSON and the run logs all go
through the same rewrite.

### 4.9 Folded sections and About this run

**Harness notices.** These are `missing-global` findings and `lua-error`
findings with `harness`. They are about the client, not guides.

```markdown
## Harness notices

<details><summary>38 missing globals and 0 harness errors: gaps in this client's WoW API stubs, not guide bugs</summary>

- `FACTION_HORDE` · F-0f143634
- `TomTom` · F-0c198787
</details>
```

They have no triage line. Harness Lua errors get a one-line message plus
`F-` id each.

**Expected manual clicks**

```markdown
## Expected manual clicks

<details><summary>11 steps the client clicked off by design (notes, sell-and-repair, guide ends)</summary>

- `01_12_Dun_Morogh.lua:23` Sell and repair at "Sell Junk" · F-9a686790
</details>
```

When the line is unknown, the location is just the file name.

**About this run**
- "WoW-Pro": the relative path (e.g. `../WoW-Pro-Guides`), branch, full commit,
  clean or uncommitted changes.
- "Client": full commit, clean or uncommitted changes.
- "Characters": the sorted, de-duplicated combo list.
- "Guide rank": `2` (WoWPro's setting for which optional steps are shown).
- "Catalog": one bullet per source with:
  - name,
  - present or missing,
  - commit when there is one,
  - the first 12 hex characters of each hash,
  - the path.
  The per-file Questie hashes are a nested list, one file per line.
- "What the simulation doesn't model": the gap list (`render.GAPS`).
- "Paths relative to": the base directory's name only (its last path segment,
  e.g. `headless-wow-pro-client`), never its absolute path.

### 4.10 Relative paths

The user's decision: output paths are anonymised by writing them relative to a
base directory. The base defaults to the current working directory.

- **CLI.** `run` and `matrix` accept `--relative-to DIR`. When it's absent, the
  base is the current working directory (`lfs.currentdir()`). A relative `DIR`
  is resolved against the current working directory.
- **Roots.** These are the absolute directory and file paths the run knows
  about: the addon path, each catalog source's `path`, and the base itself.
  Any root given as a relative path (e.g. `local/addon/main`) is first
  resolved against the current working directory.
- **Rewrite.** Every string value in the run logs, the findings and the header
  is rewritten before anything is written. That covers `path` fields, Lua error
  `message` and `stack`, and `why`. For each root, longest first, every literal
  occurrence is replaced by that root's path relative to the base:
  - a root equal to the base becomes `.`;
  - a root inside the base becomes `sub/dir`;
  - a root outside the base becomes `../x/y`.
- **Mechanism.** A walk over all strings, not field-by-field handling. A future
  field holding a path is then covered automatically.
- **Normalisation.** Plain string arithmetic on normalised paths: collapse `//`
  and `/./`, resolve `..` segments, drop a trailing `/`. There is no `realpath`,
  so a symlinked path is shown as given.
- **Already-relative strings** stay as they are (`WoWPro_Leveling/…` guide file
  paths, for example).
- **Determinism.** Output is byte-identical for identical inputs *and the same
  base*. Running from a different directory with no `--relative-to` changes the
  paths, and that's expected.
- **Leftovers.** An absolute path under no known root (rare: a stub reading an
  unexpected file) is left unchanged. The test in §8 asserts that the known
  roots never leak.

## 5. The JSON contract

```json
{
  "format": 1,
  "header": { "...": "everything render.markdown receives today, unabridged" },
  "summary": { "findings": 113, "roots": 9, "by_severity": {}, "by_signal": {} },
  "findings": [ { "...": "one object per finding" } ]
}
```

- **`format`.** An integer that is bumped on any breaking change.
- **Findings array.**
  - It holds every finding `group.findings` returns, including expected and
    harness ones, in `group`'s order.
  - Each finding object carries all fields `group` sets (`id`, `severity`,
    `signal`, `file`, `line`, `gid`, `action`, `name`, `qid`, `qname`, `why`,
    `reasons`, `combos`, `before`, `after`, `level`, `log`, `confidence`,
    `caused_by`, `causes`, `expected`, `harness`, `message`, `stack`, `grind`).
  - It also carries the rendered `title` and `sentence`, so `/triage` and the
    markdown agree on wording.
  - Absent values are absent, not `"none"`.
  - Paths are relative, as in §4.10. `header.paths_relative_to` holds the base's
    last segment only.
- **Encoding.** `hwc.json.encode` with indentation (keys are already sorted, so
  the file is deterministic).
- **Contract change.** `/triage` (§8 of the design spec) reads this file for
  data. It still writes its verdict into the markdown's `Triage:` line.

## 6. Changes to grouping data

These are small additions so the report can say what it needs to. None of them
changes ids, keys, severities or sort order.

- `new_finding` copies `grind` (`kills`, `to`) from a below-level signal.
- `Driver:signal` records `qname` when the catalog knows the quest's name. It is
  used by leftover-quests and copied by `new_finding`.
- `before` and `after` record the neighbouring step's `action` as well as its
  `name`, where the driver has it.
- Descendant counts and the root list for §4.4 are computed in `render` from
  `caused_by` and `causes`. `group` is unchanged for this.

## 7. Constraints

- **Language.** Lua 5.1 / LuaJIT, with no new dependencies; `render.lua` stays
  pure.
- **Determinism.** Every list rendered is sorted by a total order. The existing
  determinism spec is extended to compare the `.json` too.
- **Output text.** Lines end in `\n`, the output ends with exactly one newline,
  and there are no `\r` characters.
- **Emoji.** The severity markers are the only emoji, and they always sit next
  to the severity word, in the meta line or the table header, so the meaning
  doesn't rest on colour alone.

## 8. Tests

`spec/findings/render_spec.lua` is rewritten against the new layout. It keeps:

- the determinism (shuffle/reverse) test,
- the trailing-newline and no-`\r` tests,
- one `Triage: _pending_` per non-expected, non-harness finding.

It adds:

- **Templates.** One title-and-sentence assertion per row of §4.7, including the
  prereq-link case.
- **Start here.** Ranking by descendant count and the 5-entry cap.
- **Follow-on findings.** Compact rendering and correct parent links.
- **Empty fields.** No "none" or "n/a" anywhere in the markdown.
- **Relative paths** (new `spec/paths_spec.lua`):
  - relative-path arithmetic for a root equal to, inside and outside the base;
  - normalisation of `//`, `/./`, `..` and a trailing `/`;
  - longest root first, so a nested root wins over its parent;
  - the walk rewrites nested tables and leaves already-relative strings alone.
- **Combo summary.** The all, all-except and grouped cases.
- **Harness and expected sections.** Folded, with ids present.
- **JSON round trip.** Decode the `.json` and check that its findings equal the
  `group.findings` output, plus the title and sentence.

`spec/cli_spec.lua` checks that both files are written and that `--relative-to`
is parsed. The slow determinism spec also asserts that no file under the output
directory contains the absolute addon path or the absolute working directory. The `group_spec` cases
cover `grind` and `qname` passing through.

## 9. Left to the builder

- Splitting `render.lua` into `render/markdown.lua`, `render/json.lua` and
  `render/text.lua` (templates and helpers), or keeping one file.
- Exact wording polish, within the rule that sentences don't overclaim.
- How deep the step-verb confirmation against the WoW-Pro parser goes.
- Re-rendering a report from an existing `.json` (`hwc render <file>`). It is
  useful, but optional for this change.

## 10. My calls (not discussed)

- Triage verdicts stay in the markdown's `Triage:` line. They are not written
  back to the JSON.
- Harness notices and expected manual clicks get no triage slot.
- Findings are sorted by file and line, not by severity. Prioritising happens in
  "Start here" and "At a glance".
- Unverified quest data is shown as a short meta-line marker plus one header
  warning, not a field on every finding.
- Emoji severity markers, always paired with the severity word.
- The design spec's §7.2 and §8 get a pointer to this document rather than
  being rewritten.
