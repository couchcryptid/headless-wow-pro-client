# CLI UX: one character per run, help, progress and log levels

Status: draft for review · 2026-11-18 · Projects B and C from the CLI UX review
(A was `hwc diff`, `2026-11-18-findings-diff-design.md`). Changes the CLI
surface in `2026-11-11-headless-client-design.md` §4.4 and
`2026-11-17-guide-filters-design.md`.

## 1. Intent

The person using `hwc` for the first time is a WoW-Pro contributor checking a
guide fix. Trying the CLI as that person turned up:

- **Help:** no `--version` or `help`, and no per-command help. Every usage error
  prints the full 40-line usage, so the one line that says what went wrong
  scrolls away.
- **Progress:** a run is silent until its last line, and `init`/`update`
  download silently.
- **Messages:** two kinds of output only (result or fatal error). What matters
  (runs that stopped early, skipped races, Lua errors) is only in the HTML.
- **Inconsistencies:** `boot` defaults to Human and `run` to Dwarf; `--class`
  is upper-cased but `--race` is case-sensitive; `matrix` has both `--race` and
  `--races`.
- **Unclear terms:** "variant" means "which professions the character knows",
  and the name doesn't say so.

Looking again at what each command is for, the user decided:

- **A run is one character:** one race, one class, one set of professions.
  `matrix` goes away. Every combination can still be played, as separate runs.
  Fewer combinations per report keeps the report simple.
- **`boot` goes away.** It was the first plan's milestone, not a contributor use case.
- **Variant becomes `--professions`,** naming the professions themselves, so
  any pair can be played (herbalism,skinning; herbalism,mining;
  tailoring,enchanting), not just the five fixed pairs. Cooking, First Aid and
  Fishing are always known.

**Success:**
- A contributor who has never used `hwc` can find out, from the tool alone:
  - which command to run
  - which races, classes and professions exist
  - what an error means
- During a run they see which guide it's on. Afterwards they see how many
  findings it had and how bad, without opening the report.

## 2. Goals, non-goals, anti-goals

**Goals**
- One declaration per command drives its parsing, its help and the top-level usage.
- `hwc --version` / `hwc version`, `hwc help [command]`, `hwc <command> --help`.
- One-line usage errors naming the command's help.
- `--key=value`; case-insensitive race, class and profession names.
- `hwc run` plays one character, with `--race`, `--class` (both required) and
  `--professions`.
- `hwc list` for races, classes per race and professions, usable from a shell loop.
- `hwc update` replaces `sync questie`.
- `doctor` checks that the addon loads, replacing `boot`.
- Progress and warnings on stderr; results on stdout; `--quiet` / `--verbose`.
- An end-of-run summary on stdout.
- Download progress, and curl's own error text.
- The deferred `diff` error-wording items (§8).

**Non-goals**
- Stripping the report's and `diff`'s cross-character machinery. It's now
  unused, since every file holds one character. A separate follow-up.
- Colour output.
- Profession presets (e.g. "every Camping 101 quest"). The README gives a
  copyable list instead.
- Shell completion.

**Anti-goals**
- A second copy of the parsing rules or help text that can drift from the
  parser. Help is generated, never hand-written per command.
- Anything but results on stdout. `hwc diff --json > x.json`,
  `hwc quest 179 | jq` and `hwc run … > log` must stay clean.
- A run playing a character the game can't make: more than two primary
  professions, or a class the race can't play in Forever.
- Silent fallbacks: an unknown profession, race or class is a usage error that
  lists the valid values, never a default.

## 3. Approaches

1. **One declaration per command, shared parser and help** (picked).
   - Each command is a module under `src/hwc/cli/` that declares its options and a handler.
   - `src/hwc/cli/args.lua` parses them for every command.
   - `src/hwc/cli/help.lua` renders help and usage from them.
   - `src/hwc/ui.lua` owns the output channels, log levels and progress.
   - Every agreed rule lives in one place. Costs the most churn:
     `cli.lua` (~770 lines, five hand parsers) becomes about ten files.
2. Patch each hand parser in `cli.lua` and hand-write per-command help. Smaller
   diff, but a sixth copy of the parsing rules, and help that can drift (it
   already says "default WARRIOR" for a required `--class`).
3. The `argparse` LuaRock. A new dependency (README, `doctor`, CI), and its
   error and help format isn't the agreed one-line style.

## 4. Command surface

| Command | Job | Needs a WoW-Pro folder |
|---|---|---|
| `hwc init` | Download QuestieDB (latest Forever release), then run `doctor` | no |
| `hwc doctor [--json]` | Health check (§4.6) | no |
| `hwc update [--tag TAG]` | Install the newest QuestieDB Forever release (or TAG) and make it active | no |
| `hwc run --race R --class C [--professions P] …` | Play one character; write findings and its run log | yes |
| `hwc diff OLD.json NEW.json [--json]` | Unchanged from project A | no |
| `hwc quest <id>` | Print a quest from the catalog, with its sources, as JSON | no |
| `hwc list [races\|classes RACE\|professions]` | §4.5 | no |
| `hwc version` | `hwc v1.1.0 (45c3198)` | no |
| `hwc help [command]` | Top-level usage, or one command's help | no |

**Global flags,** accepted by every command and before or after it:
- `-h`/`--help`: help for the command, or the top-level usage when there's none.
- `--version`: same as `hwc version`.
- `-q`/`--quiet` and `-v`/`--verbose`: §5.3.

**Removed:** `boot`, `matrix` and `sync`. For one release each stays as a stub
that writes one line to stderr and exits 2:
- `hwc boot`: "hwc boot was removed; hwc doctor checks that the addon loads"
- `hwc matrix`: "hwc matrix was removed; hwc run plays one character — see hwc help run"
- `hwc sync questie`: "hwc sync questie is now hwc update"

The stubs are declared like any command but hidden from help and from "did you
mean". A stub takes any arguments without parsing them, so it always prints its
one line. A later release deletes them.

This is a breaking change: the subject of the PR's squash commit is `feat!: …`,
so semantic-release cuts a major version.

### 4.1 Parsing rules (`src/hwc/cli/args.lua`)

- **Option forms:** `--name value` and `--name=value`. `-h`, `-q` and `-v` are
  the only short forms.
- **Flags** (no value): `--json`, `--quiet`, `--verbose`, `--help`. A flag given
  a value (`--json=yes`) is a usage error.
- **Repeatable options** keep every value in order. Only `--include`/`--exclude`
  are repeatable; they share one ordered list, because their relative order
  decides the result (last match wins, unchanged).
- **Single-value options** given twice: the last one wins (unchanged).
- **Positional arguments** are declared per command, with a count:
  - `diff`: exactly 2
  - `quest`: exactly 1
  - `list`: 0-2
  - `help`: 0-1
- **`--`** ends option parsing.
- **Errors** (exit 2):
  - Distinct messages:
    - `unknown option --colour for hwc run`
    - `--race needs a value`
    - `missing --class`
    - `hwc diff needs 2 files, got 3`
    - `unknown command: hwc rnu (did you mean run?)`
  - The "did you mean" suggestion is offered only for an edit distance of 2 or
    less, and only among visible commands; the hidden stubs never appear in it.
  - Output: one line `hwc: <message>`, then `see hwc <command> --help`
    (`see hwc --help` when there is no command).
- **Choices:**
  - A declared option can list allowed values, matched case-insensitively and
    stored in their canonical spelling (`dwarf` → `Dwarf`, `warrior` →
    `WARRIOR`).
  - A value not in the list is `--race Dwarff is not a race; races: Dwarf, Gnome, …`.
  - Races accept `NightElf` and `nightelf`. Skyborne keeps its two tokens.
- **Validators:** an option can declare a validator that returns a canonical
  value, or nil and a message (used by `--professions`, `--date`, `--out`).
- **Cross-option checks** run after parsing: e.g. the class must be one the race
  can play, `Gnome can't be a PALADIN in Forever; Gnome classes: MAGE, …`.

### 4.2 Help (`src/hwc/cli/help.lua`)

**Top-level usage** (`hwc`, `hwc help`, `hwc --help`):
- One line per visible command: its name and summary, in the §4 table order.
- The global flags.
- The line `Run hwc help <command> for its options.`

A bare `hwc` prints this to stdout and exits 0. Today it exits 2; a bare
command asking for help isn't an error.

**Command help** (`hwc help run`, `hwc run --help`), generated from the declaration:

```
Usage: hwc run --race RACE --class CLASS [--professions LIST] [options]

Play one character along the guide chain; write findings and its run log.
Run it from a WoW-Pro folder (the one holding WoWPro/WoWPro.toc) or below it.

Options:
  --race RACE           Player race (required). See hwc list races.
  --class CLASS         Player class (required). See hwc list classes RACE.
  --professions LIST    Primary professions, comma-separated, at most two (default: none),
                        e.g. herbalism,skinning. Cooking, First Aid and Fishing are always
                        known. See hwc list professions.
  --include PATTERN     ...
```

- Each option's help text, metavar, default and "(required)" come from the
  declaration. Choices with five or fewer values are listed inline; longer lists
  point at `hwc list`.
- A declaration may carry `notes`: extra paragraphs printed after Options, e.g.
  the filter rules or `diff`'s exit codes.

### 4.3 `hwc run`

| Option | Value | Default |
|---|---|---|
| `--race` | a race (choices: `Player.RACES` keys) | required |
| `--class` | a class (choices: every class token) | required |
| `--professions` | §4.4 | none |
| `--include` / `--exclude` | glob, repeatable | all guides (unchanged) |
| `--date` | `YYYY-MM-DD` | host date (unchanged) |
| `--out` | directory | `~/.hwc/findings` (unchanged) |
| `--relative-to` | directory | current directory (unchanged) |

- **Behaviour:** unchanged from today's single-character `run`, apart from the
  progress (§5.1), the summary (§5.2) and the professions (§4.4).
- **Output names:**
  - Stem: `<date>-<Race>-<CLASS>[-<prof>-<prof>][-filtered]-<hash>`, e.g.
    `2026-11-18-Dwarf-WARRIOR-herbalism-skinning-3f9a2c17`.
  - A character with no professions has no professions part:
    `2026-11-18-Dwarf-WARRIOR-3f9a2c17`.
  - Run log: `<stem>/<Race>-<CLASS>[-<prof>…].json`.

### 4.4 Professions

**Syntax.** `--professions herbalism,alchemy`: a comma list, like `--race` was
for `matrix`. It names the character's **primary** professions:
- Case-insensitive.
- Leaving it out means no primary professions.

**Secondaries are always known.** Every character knows Cooking, First Aid and
Fishing, whatever `--professions` says (user decision). They are never named on
the command line and never appear in labels or file names.

**Names.** `--professions` takes the primary keys of
`src/hwc/world/profession_spells.lua`: Alchemy, Blacksmithing, Enchanting,
Engineering, Herbalism, Leatherworking, Mining, Skinning, Tailoring. The
primary/secondary split moves into that module as data,
`{ spell = 2259, primary = true }` per name. Its one other reader
(`player.lua`) changes with it.

**Validation** (usage errors, exit 2):
- An unknown name lists the valid ones.
- A repeated name is an error, and so is an empty item (`herbalism,`).
- More than two is an error: `--professions alchemy,herbalism,mining names 3
  professions; a character can know 2`.
- A secondary is an error with a hint: `cooking is always known;
  --professions takes primary professions` (my call: an error is clearer than
  silently ignoring it).

**One module owns professions** (my call): `src/hwc/world/professions.lua`, with:
- `parse(text) -> primaries | nil, err`: sorted canonical primary names; `""` is not accepted, a missing flag is `{}`
- `known(primaries) -> list`: the primaries plus Cooking, First Aid, Fishing; what the character is given
- `token(primaries) -> "alchemy,herbalism" | "none"`
- `label(primaries) -> "Alchemy, Herbalism" | nil`
- `stem(primaries) -> "alchemy-herbalism" | nil`

The CLI, `group.lua` (which builds the combo string from the primaries in
`log.character.professions` via `token`), `text.character` and the output stem
all call it.

**Canonical form.** Names are sorted, so `herbalism,alchemy` and
`alchemy,herbalism` are the same character, with the same file name and the
same combo label. Each profession starts known at rank 1 of max 75, as variants
do today (`matrix.professions`).

**Where it shows:**
- The combo string inside findings stays one whitespace-free last token, which
  `text.lua`'s `split_combo` relies on:
  - `"Dwarf WARRIOR alchemy,herbalism"`
  - `"Dwarf WARRIOR none"` for no primaries
- `text.character` renders it as:
  - `Dwarf Warrior (Alchemy, Herbalism)`
  - `Dwarf Warrior` for none
- The run log's `variant` field goes away. `character.professions` (already in
  the log) lists everything the character knows, secondaries included.

**Consequence:** a character with no professions at all can no longer be
played. Every run now sees the Cooking, First Aid and Fishing steps (their
Camping 101 accepts included), so findings change once after upgrading even for
`none`.

**Unchanged:** `header.matrix.combos` keeps its name and shape (findings JSON
format 2), so the Preact report page needs no rebuild. It already renders
`<Race> <Class> (<extra>)` labels.

**Removed:** `matrix.VARIANTS`, `matrix.combos` and `--variant`.
`matrix.classes_for` moves to `Player` (`Player.classes_for(race)`) for
`hwc list`, and `src/hwc/driver/matrix.lua` is deleted.

**Note:** findings files written before this change carry `baseline`/`alch-herb`
tokens, so `hwc diff` against one warns that the characters differ.
Re-running `main` once after upgrading fixes it.

### 4.5 `hwc list`

| Form | Output (stdout) |
|---|---|
| `hwc list` | A table: each race, its faction and its classes; then the primary professions and a line saying Cooking, First Aid and Fishing are always known |
| `hwc list races` | One race token per line |
| `hwc list classes RACE` | One class token per line |
| `hwc list professions` | One primary profession per line, lowercase |

The one-per-line forms exist for shell loops. The README shows a sweep:

```sh
for c in $(hwc list classes Dwarf); do hwc run --race Dwarf --class "$c"; done
```

`RACE` follows the same choice rules as `--race`.

### 4.6 `hwc doctor`

Same checks as today, plus:
- **`addon`:** when the WoW-Pro folder check is ok, load the addon the way
  `hwc boot` did (`boot.run`, Dwarf Warrior).
  - **ok:** `N files loaded, active step "<action> <step>"`.
  - **warn:** harness Lua errors or missing globals, giving the counts. The fix
    hint reads: these are gaps in hwc's WoW API stubs; findings still work.
  - **fail:** addon Lua errors, or no guide loaded. The fix hint names the first
    error.
  - **skipped:** no WoW-Pro folder, shown as `skip` and not counted as a failure.
- The WoW-Pro folder hint becomes "cd into your WoW-Pro folder for hwc run".

### 4.7 `hwc version`

- **Output:** `hwc <describe> (<short commit>)`, e.g. `hwc v1.1.0 (45c3198)`.
  - `<describe>` is `git describe --tags --abbrev=0` in the repo root.
  - `(dirty)` is appended when the repo has uncommitted tracked changes (as
    `addon_info.read(..., { tracked_only = true })` reports).
- **No tag:** `hwc unreleased (45c3198)`.
- **Not a git checkout:** `hwc unknown version`.
- **Exit code:** always 0.

## 5. Output

### 5.1 Channels and progress (`src/hwc/ui.lua`)

**Channels:**
- **stdout:** command results only: help, `version`, `list`, `quest`, `doctor`,
  `diff` (including its warnings, which are part of its result), and the
  `run` summary and `wrote` line.
- **stderr:** progress, warnings and errors.

**`ui`'s interface:**
- `ui.new{ out, err, level, tty }`, where `level` is `"quiet" | "normal" | "verbose"`.
- `tty` defaults to `isatty(2)` through LuaJIT FFI
  (`ffi.cdef "int isatty(int);"`), and is injectable so specs need no terminal.
- Methods:
  - `:result(text)` → stdout, always
  - `:info(text)` → stderr, unless quiet
  - `:detail(text)` → stderr, verbose only
  - `:warn(text)` → stderr as `warning: <text>`, unless quiet
  - `:error(text)` → stderr as `hwc: <text>`, always
  - `:progress(text)` / `:done()`

**Progress:**
- **On a terminal:** one line, redrawn with `\r` and cleared (`\r\27[K`)
  before any other stderr write and at `:done()`.
- **Not on a terminal:** each progress text is written as its own line, but
  only when it changes (no redraws), so CI logs stay short.
- **Quiet:** progress is off.

**`run` progress:**
- `run.character(cfg, opts)` gains `opts.on_progress(event)`. The driver calls
  it and never prints. Events:
  - `{ kind = "guide", gid, file, index }` when a guide opens (`Driver:open`)
  - `{ kind = "jump", from, to, passed }` on a jump
  - `{ kind = "level", level }` on a level up. The driver compares
    `player.level` after each step it plays and after each jump, and emits on a
    change (my call: keeps `world/` untouched).
- **The CLI renders** them as:
  `Dwarf Warrior · 12_20_Eastern_Kingdom (guide 2) · level 14 · 0:06`.
  - Elapsed time is wall clock from `os.time` (seconds), in the CLI only. The
    findings never see it, so determinism is untouched.
  - The guide total isn't known up front (the chain is followed as it goes),
    so no total or ETA is shown.
- **`--verbose`** adds a `:detail` line for each jump (`jumped over GID…
  (excluded)`), the catalog source paths at the start, and at the end the run's
  total wall time and per-guide wall times (these are the only "timings").

**`init` / `update` downloads:**
- **On a terminal, not quiet:** curl runs with `-#` and its stderr goes to the
  terminal, giving its own progress bar.
- **Otherwise:** curl stays silent.
- **On failure, off a terminal (or quiet):** curl's stderr is captured and its
  last line is put in the error, e.g. `hwc: download … failed: curl: (6) Could
  not resolve host: github.com`. Today the message is only "curl exit 6".
- **On failure, on a terminal:** curl has already printed its own message, so
  the error reads `hwc: download … failed (curl exit 6; see curl's message
  above)` (my call: no tee to a temp file).
- `http.lua`'s `sh()` gains a stderr mode: `"discard"` (today's behaviour, kept
  for `has_tool`, `sha256`, `unzip`), `"capture"` or `"terminal"`.
  `install.lua` picks the mode from the `ui` it's given.
- The `http.lua` injection points stay, so unit specs never touch the network.

### 5.2 `run` summary (stdout)

Printed before the `wrote` line, unless `--quiet`, built from the report document:

```
Dwarf Warrior (Herbalism, Skinning): 256 findings, 152 root causes
  155 high · 6 medium-high · 87 medium · 8 low
  stopped early: Too many addon errors
  harness: 2 Lua errors, 36 missing globals (gaps in hwc's stubs, not guide bugs)
hwc: wrote …/2026-11-18-Dwarf-WARRIOR-herbalism-skinning-3f9a2c17.html and ….json
```

- **Line 1:** `summary.findings` and `summary.roots`.
- **Line 2:** `summary.by_severity`, in `text.SEVERITY` rank order, leaving out
  zeros. When there are no findings, line 1 reads `no findings` and line 2 is
  left out.
- **`stopped early`:** only when `header.stop` is set, with the reason labelled
  by `text.STOPS`.
- **`harness`:** only when harness findings exist. The counts are taken from
  `doc.findings` with `report.is_harness`, split into `lua-error` and
  `missing-global`, because `summary.*` leaves harness findings out.
- **Warnings** that today live only in the report header (`header.warnings`)
  are printed through `ui:warn`.
- **The `wrote` line** drops its "(N characters)" suffix, since there's always
  one: `hwc: wrote <stem>.html and <stem>.json`. `cli.stem_name` keeps its
  signature.
- **The `wrote` line** stays on stdout even with `--quiet`. It's the result:
  the path a contributor hands to `hwc diff`.

### 5.3 Log levels

| Level | stdout | stderr |
|---|---|---|
| `--quiet` | results; for `run`, the `wrote` line only | errors only |
| default | results, `run` summary | progress, warnings, errors |
| `--verbose` | same as default | adds detail (jumps, source paths, timings) |

Given both, the last one wins. Exit codes are unchanged by level.

## 6. Constraints

- **Runtime:** LuaJIT 2.1 / Lua 5.1; no new dependencies. FFI ships with LuaJIT.
- **Determinism:** findings JSON and HTML bytes are unchanged by any of this,
  except the combo/profession labels and the `professions` run-log field (§4.4).
  Progress and timing never enter a findings file.
- **Exit codes:**
  - 0 ok; 1 harness failure; 2 usage error.
  - `diff` keeps 0/1/2 as in project A.
  - `doctor` keeps 1 on a failed check.
- **Purity:** `diff.lua`, `report.lua` and `text.lua` stay pure.
- **Specs:** the suite keeps calling `cli.main(args, out, err, env)`. `env` gains
  `tty` (default false in specs) and `clock`, so progress and elapsed time are
  testable.
- **Wording:** user-facing text lives with its command's declaration (help) or
  in `text.lua` (findings labels).
- **Commits:** Conventional Commits. The PR is a breaking change (`feat!:`).
- **README and CONTRIBUTING:**
  - Every command example is updated.
  - `boot`, `matrix`, `--variant` and `sync questie` sections are rewritten for
    `doctor`, `run` plus a loop, `--professions` and `update`.
  - Add a "Covering professions" list of combinations that together reach every
    Camping 101 quest. The list is today's variants, which between them reach every
    Camping 101 quest: `alchemy,herbalism`, `blacksmithing,mining`,
    `leatherworking,skinning`, `enchanting,engineering`, `tailoring`. The
    secondaries need no entry, since every run knows them.

## 7. Specs affected

- `spec/cli_spec.lua`: run/matrix/boot/sync tests move to per-command spec
  files (`spec/cli/run_spec.lua` …) or are rewritten. The `with_runner` helper
  stays.
- `spec/driver/matrix_spec.lua` is deleted. Its race/class assertions move to a
  `Player.classes_for` spec.
- `spec/integration/boot_spec.lua` keeps testing `boot.run` (the module stays,
  since `run` uses it).
- `spec/findings/*` and `spec/fixtures/findings/*.json`: the combo tokens
  `baseline`/`secondary` → `none`, and `alch-herb` … → comma tokens (`alchemy,herbalism`).
- `web/report` fixtures are those same JSON files. `npm test` must still pass,
  with `report.html` rebuilt only if a fixture change makes its test demand it.
- The slow anchors (`spec/integration/anchors_spec.lua`) and the determinism spec
  run with the new flags.

## 8. Carried from project A (deferred minors)

- `diff`: an unknown `--flag` is reported as unknown, never read as a path
  (falls out of §4.1).
- `diff`: a directory path reports "cannot read", not "not valid JSON".
- `diff`: a `.HTML` path (any case) gets the `.json` hint.
- `diff`: an internal Lua error is worded as
  `hwc: internal error: <first line> (please report it)`, exit 2, separate from
  "not valid findings files".
- `report.counted` is exported and reused by `diff.lua` instead of a copy.
- The `diff` QuestieDB warning also compares `catalog.questie.sha256`.

## 9. Left to the builder

- Module boundaries under `src/hwc/cli/` beyond `args.lua`, `help.lua` and one
  file per command.
- Exact column widths in help and in `hwc list`'s table.
- Whether the "did you mean" suggestion also covers option names.
