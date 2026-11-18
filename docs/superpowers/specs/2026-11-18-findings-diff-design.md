# `hwc diff`: compare two findings files

Status: draft for review · 2026-11-18 · First of three CLI UX projects
(A: diff, B: summary/progress/log levels, C: help and error cleanup).

## 1. Intent

The person using `hwc` for the first time is a WoW-Pro contributor checking a
guide fix. Their loop: run on `main`, switch to the fix branch, run again, and
ask "did my finding go away, and did I add any?" Today the answer means
diffing two findings JSON files by hand.

`hwc diff OLD.json NEW.json` answers it in the terminal.

**Success:** after running the same `hwc run`/`hwc matrix` on `main` and on a fix
branch, `hwc diff` lists what was fixed and what is new, warns
when the two runs aren't comparable, and exits 1 only if the fix branch adds
findings.

## 2. Goals, non-goals, anti-goals

**Goals**
- Match findings by id (`group.lua`: the id excludes line numbers, so a fix
  that moves lines keeps the ids of everything below it).
- Report fixed, new, partly fixed (same id, fewer characters) and still-present counts.
- Name every reason two files may not be comparable.
- Exit codes a script or CI job can use.
- A second run on another branch doesn't overwrite the first run's files (§4.6).

**Non-goals**
- An HTML compare page (possible follow-up).
- `hwc compare BASE HEAD` (worktrees + two runs + diff); it would build on this.
- `--baseline` on `run`/`matrix`; a later thin wrapper over this module.

**Anti-goals**
- A clean diff from runs that differ in catalog, characters or filters with no
  warning. That would let a QuestieDB update pass as a guide fix.
- Harness notices (missing globals, harness Lua errors) or expected manual
  clicks turning the exit code red: they are not guide findings.

## 3. Approaches

1. **Terminal summary + `--json`** (picked). Pure `findings/diff.lua`, thin CLI
   command. Smallest change that answers the contributor's question.
2. Terminal + HTML compare page in the Preact report. Better for pasting into a
   PR, about twice the work, needs a `report.html` rebuild. Deferred.
3. `--baseline OLD.json` on `run`/`matrix`. Couples comparing to running, so two
   old files can't be re-diffed. Deferred as a wrapper over approach 1.

## 4. Behaviour

### 4.1 Command

```
hwc diff OLD.json NEW.json [--json]
```

Runs from any folder (needs no WoW-Pro folder, like `doctor`). OLD is the
baseline (usually `main`), NEW the change.

### 4.2 What is compared

- Only **counted** findings: `report.is_harness(f)` false, `f.expected` not
  set, a severity present (the same rule `report.lua` uses for counts).
- Only characters present in **both** files (`header.matrix.combos`). A
  finding's `combos` is cut to the shared characters before comparing; one
  left with none on a side is absent on that side.
- With the shared characters, for each id:
  - **fixed**: in OLD, not in NEW.
  - **new**: in NEW, not in OLD.
  - **partly fixed**: in both, NEW's combos a strict subset of OLD's. Shows
    which characters it was fixed for and which still have it.
  - **spread**: in both, NEW has combos OLD lacked. Counted as new for the exit
    code (it is a regression for those characters).
  - **unchanged**: everything else; counted, not listed.

### 4.3 Comparability warnings

Each mismatch is a warning, printed before the results and listed in `--json`
under `warnings`. The diff still runs.

| Check | Warning |
|---|---|
| `header.catalog.questie.tag`/`build` differ | different QuestieDB; changes may come from the data, not the guide |
| supplement presence or sha differs | different supplement |
| `header.filters` differ | different guide filters |
| combos differ | characters only in OLD / only in NEW, named; they are left out |
| `header.paths_relative_to` differs | Lua-error ids depend on the start folder; Lua errors may show as fixed+new |
| `header.client.commit` differs | different hwc version |
| same `header.addon.commit` and neither dirty | both runs are the same addon commit |
| either side `dirty` | uncommitted changes on that side |

**Not comparable (exit 2):** a file that is missing or isn't valid JSON, a `format` other than 2, or no shared characters.

### 4.4 Text output

```
hwc diff: main@fb1d504 → fix/forever-prereq-gates@3a9c2e1 (dirty)
warning: different QuestieDB: v1.1.2 (e1652ce) → v1.1.3 (9b01f2a)

fixed 3 · new 1 · partly fixed 1 · unchanged 252

Fixed
  🔴 "Secure the Mountain" is never offered    01_12_Dun_Morogh.lua:162  (+13 follow-on)
  ...
New
  🟡 "Frostmane Hold" doesn't advance          01_12_Dun_Morogh.lua:288
Partly fixed
  🟠 ...   fixed: Gnome Mage · still: Dwarf Warrior
```

- Lines use the finding's own `title`, the file's basename and its line from the
  side it's present on (NEW for new/partly, OLD for fixed).
- Severity markers and order come from `text.SEVERITY`; then file, line.
- Follow-ons: a finding whose `caused_by` is in the same list is folded under
  its root as `(+N follow-on)` rather than listed (my call: keeps the root cause
  in front; a fix to a root usually clears its follow-ons together).
- Empty sections are left out. Nothing changed: `no changes (257 findings in both)`.

### 4.5 `--json`

One object: `runs.old` and `runs.new` (addon branch/commit/dirty, path given; under `runs` so they cannot clash with the `new` findings list),
`warnings` (array of `{ code, message }`), `counts`, and `fixed`, `new`,
`partly_fixed`, `spread` as arrays of the findings (from the side they're
present on), partly/spread entries adding `fixed_for`/`still`/`added_for`. Arrays
are always arrays, even when empty.

### 4.6 Findings file names carry a content hash

Today `run`/`matrix` write `DIR/<date>-<scope>.json` (and `.html`, and the run
log folder `<date>-<scope>/`). The contributor loop runs the same options on
`main` and then on the fix branch, on the same day, so the second run
overwrites the first and leaves nothing to diff.

The stem becomes `<date>-<scope>-<hash>`, where `<hash>` is the 8 hex digits of
`group.fnv1a32` over the findings JSON text written to `.json`, e.g.
`2026-11-18-Dwarf-WARRIOR-baseline-3f9a2c17.json`. The `.html` and the run log
folder use the same stem.

- Why content, not the addon commit: two runs on the same commit with different
  uncommitted edits (the usual case while fixing) would collide.
- Why not a timestamp: a fixed `--date` with the same inputs must still give the
  same files, names included (README, determinism spec).
- Two runs with the same hash wrote identical findings, so the overwrite loses
  nothing.
- The closing `hwc: wrote …` line already prints the full stem, so the user
  learns the name from the run.

The run logs are written after the findings JSON is built (today they are
written first), so their folder can take the hash.

### 4.7 Exit codes

| Code | When |
|---|---|
| 0 | no new or spread findings (fixes, warnings and unchanged findings allowed) |
| 1 | at least one new or spread finding |
| 2 | usage error, or the files are not comparable (§4.3) |

This follows `diff(1)`, not the other `hwc` commands (where 1 means a harness
failure); the help text says so.

## 5. Constraints

- LuaJIT 2.1 / Lua 5.1; `dkjson` via `hwc.json`; no new dependencies.
- `findings/diff.lua` is pure (no I/O), in the style of `report.lua`; the CLI
  reads the files and writes the output.
- Wording lives in `findings/text.lua` (signal and severity labels are already
  there).
- Busted specs for the module (each category, combos cut, every warning, follow-on
  fold) and for the CLI (exit codes, `--json`, unreadable/format errors), using
  fixtures under `spec/fixtures/findings/`.
- README: a "Comparing runs" section next to "Running characters and findings";
  the usage text gains the `diff` line.

## 6. Left to the builder

- Exact column alignment and truncation of long titles.
- Whether `diff` accepts a `.html` path by reading the `.json` beside it, or
  refuses with a hint. My lean: refuse with "use the .json beside it".
