# Guide filters and an installable `hwc`

Status: draft for review · 2026-11-17 · Changes the CLI surface in
`2026-11-11-headless-client-design.md` (§4.4 run scope, the `--addon` option).

## 1. Intent

Today `hwc` is wired to one place and one route. `--addon` (default
`~/Projects/WoW-Pro-Guides`) names the WoW-Pro folder, the addon loads the
race's start guide (`ForeverStartGuides`), and the run follows `nextGID` to
level 25. You can't say "just play the guide I'm fixing" or "everything except
the dungeon guide" without editing the addon.

The user wants to work the way they already work with guides: stand in a
WoW-Pro folder (their git repo, or the game's `Interface/AddOns` folder), run
`hwc`, and narrow what gets played with `--include` / `--exclude` filters that
behave like the AWS S3 CLI's. To make "stand in the folder and run it" real,
`hwc` must be installable as a command on `$PATH`.

**Success:** from inside a WoW-Pro folder,
`hwc run --class PRIEST --exclude "*" --include "*Dun_Morogh*"` plays only the
Dun Morogh guide, at its place in the chain, and writes the usual findings; and
`hwc run --class PRIEST` with no filters plays the race's whole chain to the
last line of the last guide, and up to level 25 its findings match today's
`bin/hwc run --class PRIEST --addon <that folder>`.

## 2. Goals, non-goals, anti-goals

**Goals**
- The WoW-Pro folder comes from where `hwc` is run, not from a flag.
- Every guide is included by default; `--include` / `--exclude` narrow it with
  S3-CLI semantics.
- Guides always play in the addon's own chain order, whatever the filters.
- `hwc` installs as a command, with README instructions for `$PATH`.

**Non-goals**
- Playing guide files that live outside a WoW-Pro folder, or overriding a
  guide with a copy from elsewhere.
- Making up quest progress for jumped guides (see §5, known limits).
- Horde characters, or lifting any other existing scope limit beyond the stop
  rule below.
- A configurable stop level. `--stop-level` is removed (decided by the user:
  scope creep).
- Packaging (Homebrew formula, LuaRocks rockspec). A symlink install is enough.

**Anti-goals** (a failure even if it works)
- Filters that change the order guides play in. Order is the addon's, always.
- Filters that can unload the addon's engine files. They only select guides.
- An installed `hwc` that quietly depends on one machine's layout (the hidden
  `~/Projects/WoW-Pro-Guides` default, the hard-coded
  `/opt/homebrew/bin/luajit`). LuaRocks packages under `~/.luarocks` are
  the one accepted exception: that is LuaRocks' default install location.
- A no-filter run whose findings up to level 25 differ from today's for the
  same folder.

## 3. The source folder

The **source folder** is the nearest folder at or above the current directory
that contains `WoWPro/WoWPro.toc`. Both a git copy of WoW-Pro and the game's
`Interface/AddOns` folder have that layout (`WoWPro/`, `WoWPro_Leveling/`, …
side by side), so one rule covers both. No such folder: usage error (exit 2),
naming the directory searched from.

- `--addon` is removed from every command (`boot`, `quest`, `run`, `matrix`).
  `quest` never needed it: the catalog does not read the addon, so `quest` just
  drops the flag.
- The `~/Projects/WoW-Pro-Guides` default is removed everywhere it is used as a
  default (`cli.lua`, `config.lua`, `driver/actions.lua`). Specs that read the
  real addon keep their own path constant.
- `cli.main` takes the starting directory as a parameter (defaulting to the
  process's current directory) so specs can point it at fixtures without
  changing the process directory.

**A folder without git** (`Interface/AddOns`): `addon_info.read` today returns
an empty commit and `boot.run` refuses to run. New behaviour (decided by
Claude, not the user): when the source folder is not in a git repository, read
`## Version:` from `WoWPro/WoWPro.toc`, record it as the addon identity, and
mark the report header "not a git folder" instead of refusing. A git folder
with no commit is still an error. In `boot --json` and the report JSON,
`branch` and `commit` are `null` and a `version` field carries the TOC version
(decided by Claude).

**Symlinks** (decided by Claude): `Interface/AddOns` is often a symlink into a
git checkout. The source-folder search walks up the logical current directory
(`$PWD`, as the shell shows it), and `./`, `../` and absolute patterns resolve
lexically against it, so a tab-completed path never lands outside the source
folder because of a link.

## 4. Filters

`--include PATTERN` and `--exclude PATTERN`, each repeatable, on `run` and
`matrix`.

**Semantics, following the AWS S3 CLI** (decided by the user):
- Every guide starts included.
- Filters are applied in the order given on the command line; for each guide
  file, the **last** filter whose pattern matches decides. No filter matches:
  included.
- Patterns are globs matched against the guide file's path relative to the
  source folder, with `/` separators. `*` matches any run of characters
  including `/`; `?` matches one character; `[abc]` and `[!abc]` are character
  classes. Matching is case-sensitive.
- Example: `--exclude "*" --include "*Dun_Morogh*"` plays only Dun Morogh;
  `--exclude "*/19_25_*"` plays everything but the 19-25 guide.

**Additions to S3** (decided by Claude):
- A pattern starting with `./` or `../`, or an absolute path, is resolved from
  the current directory and then made relative to the source folder, so
  tab-completed paths work: `cd WoWPro_Leveling/Forever/Alliance && hwc run
  --class PRIEST --exclude "*" --include ./01_12_Dun_Morogh.lua`. A pattern
  that resolves outside the source folder is a usage error.
- A pattern naming a folder (resolves to an existing directory) matches every
  file under it, as if `/*` were appended.

**What a filter applies to:** only **guide files**: the files the Forever TOC
load order (`toc.files`) loads whose source registers a guide
(`RegisterGuide`). Every file still loads exactly as today; filters decide only
which registered guides are *played*. `--exclude "*"` therefore cannot unload
`WoWPro.lua`.

**Errors (exit 2):**
- Filters leave no guide included.
- An `--include` pattern matches no guide file (most likely a typo). An
  `--exclude` that matches nothing is allowed, as in S3.

## 5. Play order and jumping

Order is the addon's chain, decided by the addon exactly as today: the race's
start guide (the addon picks it at boot), then each guide's next guide as
`WoWPro:NextGuide` resolves it.

When the run reaches a guide (at boot, or when the engine autoloads the next
guide) and that guide is **excluded**:
1. Walk the chain forward from it with the engine's own next-guide resolution
   until reaching an included guide. If the chain ends first, the run stops
   (`no-next-guide`).
2. If the character's level is below that guide's `startlevel`, raise it
   through the simulated world's XP path (so the addon sees the level-ups as
   it would in game).
3. Load the guide with `WoWPro:LoadGuide(gid)`, the call a player's click in
   the guide list makes. This keeps the driver's fidelity rule: only
   player-equivalent engine calls.

The run log records each jump: the guides passed over, the guide loaded, and
the level before and after.

**Included guides the run never reaches** (not on this race's chain, e.g. a
Human guide in a Dwarf run, or a side guide no `nextGID` points to) are listed
in the run log and the report header, not silently dropped. Only guides an
`--include` pattern matched count (decided by Claude): with no filters, or only
excludes, nothing is listed, since every Horde, dungeon and 25+ guide would
otherwise be "never reached" in every run.

**`matrix` with a race that reaches no included guide** (decided by Claude):
that race's combos are skipped and named in the report header; the matrix
exits 2 only if no race reaches any included guide.

**Stops** (decided by the user): a run ends when it reaches the last line of
the last included guide on the chain (`no-next-guide`), or on a watchdog
(`stuck`, `iterations`, `errors`, `no-step`). The level stop (25) and the
`chain-range` stop (`CHAIN_MAX_START`) are removed, together with
`--stop-level`. Consequences the builder must handle:
- A no-filter run now plays past 25 for as long as the chain goes. The world,
  catalog and XP tables have only been exercised to 25, so harness gaps past
  25 will show up as findings or watchdog stops; that is expected, not a
  reason to keep a level cap. The XP cap (`xp.CAP_LEVEL`) still caps level.
- `run.DEFAULTS.stop_level`, `run.CHAIN_MAX_START` and the `level` /
  `chain-range` stop reasons go; specs that relied on them (including
  `max_guides` users, which stay) are updated.
- Output scope names lose the `-1-25` suffix
  (`forever-alliance-dwarf-gnome`).
- Slow specs that run the full chain get slower; their timeouts may need
  raising.

**Known limit:** quests from jumped guides were never done. Prerequisite
gates, `orphan-turnin`, and `leftover-quests` (`not-turned-in`) findings next
to a jump can be noise from the jump rather than guide bugs. The report header
says how many guides were jumped so the reader knows to weigh those findings.

## 6. Commands after the change

```
hwc boot   [--race RACE] [--class CLASS] [--json]
hwc quest  <id>
hwc run    --class CLASS [--race RACE] [--variant V]
           [--include PATTERN]... [--exclude PATTERN]...
           [--date D] [--out DIR] [--relative-to DIR]
hwc matrix [--race RACE]... [--races LIST]
           [--include PATTERN]... [--exclude PATTERN]...
           [--date D] [--out DIR] [--relative-to DIR]
```

- `--out` defaults to `$HOME/.hwc/findings` (decided by the user), created
  if missing, so runs never write into the WoW-Pro folder. `--relative-to`
  keeps its default, the current directory.
- `--stop-level` is removed from `run` (see §5, Stops).
- `boot` keeps no filters: it shows what the addon loads at login, which is
  the start guide.
- `matrix --race` is repeatable; `--races Dwarf,Gnome` stays as an alias, and
  both may be combined (union, first-seen order). Default stays Dwarf, Gnome.
- `matrix` takes each race's classes from its start guide file as today, even
  if a filter excludes that guide (it reads which classes exist, not what is
  played).
- With any filter given, the scope in output file names gains `-filtered`
  (e.g. `2026-11-17-Dwarf-PRIEST-baseline-filtered.md`). The report header
  lists the filters in order, the guides played, the guides jumped, and the
  included guides never reached.
- The value parser for `run`/`matrix` today keeps one value per option name;
  `--include`, `--exclude` and `--race` must keep every occurrence in order.
- Help text lists the filter semantics in two lines and points at the README.

## 7. Installing `hwc`

- `bin/hwc` resolves its own path through symlinks (a `readlink` loop that
  works on macOS's BSD `readlink`, which lacks `-f`) to find the repo, so a
  symlink on `$PATH` works.
- It runs the first `luajit` on `$PATH`, falling back to
  `/opt/homebrew/bin/luajit`, then `/usr/local/bin/luajit`; none found: a
  one-line error naming what it looked for.
- A `Makefile` with `install` and `uninstall`: `install` symlinks `bin/hwc`
  into `$(PREFIX)/bin`, `PREFIX` defaulting to `~/.local`; `uninstall` removes
  that symlink only if it points at this repo.
- README: an Install section with `make install`, the line to add
  `~/.local/bin` to `$PATH` for zsh (`~/.zshrc`) and bash (`~/.bashrc` /
  `~/.bash_profile`), and `hwc --help` as the check. Every usage example in
  the README changes from `bin/hwc … --addon PATH` to `cd` into the WoW-Pro
  folder and `hwc …`.

## 8. Bundled quest data (deferred: separate plan)

Decided by the user: every catalog source the client reads (quest XP, item
rewards, levels, …) is to be bundled with the client, and how that data is
sourced and updated gets its own plan. **Nothing in this section is built by
this design's plan;** catalog paths and `tools/fetch-questie.sh` stay as they
are. Notes carried forward for that plan:


Every catalog source the client reads ships in this repo (decided by the
user), so a fresh clone plus LuaRocks packages is a complete install:

- The pinned QuestieDB Forever files (quest, NPC, item, object DBs and the
  quest-XP tables, about 6.4 MB) move from git-ignored `local/questie/<pin>/`
  to a tracked `data/questie/<pin>/`, with their `SHA256SUMS`.
  `tools/fetch-questie.sh` writes there, so updating the pin is still one
  command plus a commit.
- The hand-checked `local/catalog/supplement.json` moves to
  `data/supplement.json`; `catalog/supplement.example.json` is removed, since
  the real file is now tracked.
- `config.lua` defaults point at these repo paths (resolved from the repo
  root, as today). Catalog sources stay optional in code; a missing one is
  still recorded rather than fatal, but in a normal install none is missing.
- A spec checks that every default catalog path exists in the repo and that
  the Questie files match their `SHA256SUMS`.
- README gains a short Data section: what each source is, where it came from,
  and its licence. Licences must be checked before the first commit of the
  data: QuestieDB is (to Claude's knowledge, unverified here) GPL-3.0 while
  this repo is MIT, so the bundled files keep their own licence and notice in
  `data/`. Finding a licence that forbids redistribution stops this section
  and goes back to the user.

## 9. Left to the builder

- Module boundaries (e.g. a `hwc.filters` module for glob matching and
  selection, a `hwc.source` module for finding the source folder) and the
  exact run-log field names for jumps and unreached guides.
- How the chain walk in §5 reuses `Engine:guide` / `next_gid`, provided it uses
  the engine's own next-guide resolution and never pops the engine's guide
  stack for a guide that isn't loaded (see the comment in `Engine:guide`).
- Test fixtures: tiny fake WoW-Pro folders like the ones `matrix_spec` already
  builds.
- Updating `2026-11-11-headless-client-design.md` where it describes
  `--addon`, the run's start and the §4.4 stop conditions, and the README's
  "levels 1 to 25" scope line.
