# headless-wow-pro-client

Runs the real [WoW-Pro](https://github.com/Ludovicus-Maior/WoW-Pro-Guides) guide
addon outside World of Warcraft. A simulated character plays every step the
addon shows, and the client writes down everywhere a guide breaks: accepts the
character never sees, turn-ins for quests it never had, steps that don't
advance, quests it can't take, and Lua errors.

The point is to check guide fixes without levelling an alt in the game.
- **Bug finding:** play the Forever Alliance and Horde guides, the race's chain to its last
  guide, for each race, class and profession combination, then read the findings.
- **Red/Green:** run the same characters against `main` and against a fix
  branch, and compare the findings.

The addon's code is loaded unmodified from a WoW-Pro-Guides checkout and is
never patched. The client fakes the WoW API underneath it: a player, a 40-slot
quest log, Classic XP rules, a virtual clock, frames and events. Quest facts
come from a catalog built from QuestieDB, never from the guide lines.

**Status:**
- **Scope:** Forever Alliance and Horde, the race's chain to its last guide.
- **XP:** the character levels with Classic's XP rules (`src/hwc/world/xp.lua`).
  One row is verified in Forever: level 29 (`UnitXPMax` 44300, in game,
  2026-11-18). The rest is unverified for Forever (Classic): the other rows of
  the XP table, the mob-XP formula, the gray-level and zero-difference bands,
  and the level cap of 60.
- **Start:** each race starts from its guide in the addon's `ForeverStartGuides`
  table:

  | Race (`--race`) | Faction | Start |
  |---|---|---|
  | `Dwarf`, `Gnome` | Alliance | Dun Morogh |
  | `Human` | Alliance | Elwynn Forest |
  | `NightElf` | Alliance | Teldrassil |
  | `SkyborneAlliance` | Alliance | Zephras Isle |
  | `Orc`, `Troll` | Horde | Durotar |
  | `Tauren` | Horde | Mulgore |
  | `Undead` | Horde | Tirisfal Glades |
  | `SkyborneHorde` | Horde | Zephras Isle |

  Skyborne is two races in the client, picked at character creation, with
  different classes: High Order Skyborne (Alliance, race 95) and Windshaper
  Skyborne (Horde, race 96). Both have the client token `Skyborne`.
- **Next:** the `/triage` skill.
- **Data gaps:** listed in every findings file's header.
- **Design:** the design spec, the plans and the per-plan rulings are in
  `docs/superpowers/`.

## Requirements

- **LuaJIT 2.1** (Lua 5.1), e.g. `brew install luajit`. A Lua 5.4+ `lua` won't
  work.
- **busted 2.3** for Lua 5.1, plus `luafilesystem` and `dkjson`:
  ```sh
  luarocks --lua-version 5.1 install busted
  luarocks --lua-version 5.1 install luafilesystem
  luarocks --lua-version 5.1 install dkjson
  ```
- **A WoW-Pro folder:** a git checkout of WoW-Pro-Guides, or the game's
  `Interface/AddOns` folder. `hwc` must be run from inside it (see
  [Choosing guides](#choosing-guides)).
- **`curl`, `unzip`, and `shasum` or `sha256sum`**, which `hwc init` and
  `hwc update` use to download and verify QuestieDB and the Forever client tables.
- **Optional:** `python3`.

## Install

```sh
make install                                                  # links bin/hwc into ~/.local/bin
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc       # zsh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc      # bash (~/.bash_profile on macOS)
hwc --help                                                    # check
hwc version                                                   # release tag and commit (also hwc --version)
```

`PREFIX` sets another location (`make install PREFIX=/usr/local`);
`make uninstall` removes the link only if it points at this repo. `hwc` finds
LuaJIT on `$PATH`, then `/opt/homebrew/bin`, then `/usr/local/bin`, and reads
LuaRocks modules from `~/.luarocks`.

## Quick start

Run `hwc` from inside a WoW-Pro folder (a git checkout or `Interface/AddOns`):

```sh
hwc init                                                       # download QuestieDB and the Forever client tables into ~/.hwc, check the setup (any folder)
cd ~/Projects/WoW-Pro-Guides
hwc run --race Dwarf --class WARRIOR                           # play one character along the chain
hwc diff OLD.json NEW.json                                     # compare two runs (see "Comparing runs")
```

`hwc boot`, `hwc matrix` and `hwc sync questie` remain for one release as
stubs that print what replaced them (`hwc doctor`, `hwc run`, `hwc update`).

`hwc help` lists the commands and `hwc help <command>` shows one command's
options. `hwc list` shows the races, their classes and the professions that
`hwc run` accepts.

Findings go to `~/.hwc/findings` unless `--out DIR` says otherwise. Specs, from
this repo: `~/.luarocks/bin/busted` (slow ones: `--tags=slow`).

- Run: `hwc --help`.
- Test: `~/.luarocks/bin/busted`.
  - The integration specs are pending when the addon checkout or the local
    catalog is absent.
  - Specs tagged `#slow` (full guide runs, cross-process determinism, the
    anchors) are skipped by default. Run them with
    `~/.luarocks/bin/busted --tags=slow`.

## Working on the report page

The findings report is a small Preact page in `web/report/`, built by Vite into
one self-contained HTML file. That file, `src/hwc/findings/report.html`, is
committed, so running `hwc` never needs Node. Node 24 (`.nvmrc`) is for working on the page only.

```sh
cd web/report
npm ci
npm run dev              # http://localhost:5173/?fixture=single (or matrix, empty)
npm test                 # fixtures parse; the committed report.html equals a fresh build
npm run typecheck
npm run build            # writes ../../src/hwc/findings/report.html
```

Commit the rebuilt `report.html` with the change to the page; `npm test` fails
when it is stale. The dev server fills the page from `spec/fixtures/findings/<name>.json`.

## Licence and third-party data

- **This repository** is MIT-licensed; see [LICENSE](LICENSE).
- **WoW-Pro Addons and Guides** belong to The WoW-Pro Community, under
  [CC BY-NC-ND 3.0](https://creativecommons.org/licenses/by-nc-nd/3.0/). Nothing
  from the addon is included or redistributed here.
  - The client reads your own checkout at run time.
  - Source comments cite addon file and line numbers so harness behaviour can be
    checked against the engine.
- **QuestieDB** is GPL-3.0. It is downloaded to `~/.hwc` on your machine and
  never committed. See [World and catalog](#world-and-catalog).
- **The Forever client tables** (taxi nodes, maps, areas) are Blizzard game data,
  downloaded from wago.tools to `~/.hwc/forever` on your machine, converted to JSON
  and never committed. See [World and catalog](#world-and-catalog).
- **LibDeflate** is vendored under the zlib licence at `src/hwc/vendor/`.
- **Not affiliated with Blizzard Entertainment.** World of Warcraft is a
  trademark of Blizzard Entertainment, Inc.

Contributions are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md).

## Checking the setup

```sh
cd ~/Projects/WoW-Pro-Guides && hwc doctor          # every check, with the fix beside each failure
cd ~/Projects/WoW-Pro-Guides && hwc doctor --json   # the same, as JSON
```

`hwc doctor` checks LuaJIT, the rocks, the tools, the WoW-Pro folder, QuestieDB
and the objective counts file. Its `addon` check loads the addon for a Dwarf Warrior: the
WoW-Pro and Leveling TOCs for the Forever flavor (TOC 16001), then
`ADDON_LOADED`, `PLAYER_LOGIN` and `PLAYER_ENTERING_WORLD`, then the virtual
clock until the startup lockdown releases and the timers drain.

- **ok:** `N files loaded, active step "<action> <step>"`.
- **warn:** harness Lua errors or missing globals. These are gaps in hwc's WoW
  API stubs; findings still work.
- **fail:** addon Lua errors, or no guide loaded. The hint names the first error.
- **skip:** no WoW-Pro folder found; `cd` into yours.

It exits 1 when a check fails. A git checkout without a commit is refused, so
an unidentified run can't be mistaken for a real one. A folder that isn't in
git (`Interface/AddOns`) is identified by the `## Version:` in
`WoWPro/WoWPro.toc`; the report header says "not a git folder" and `branch` and
`commit` are `null` in the findings JSON. With the addon's defaults
(`autoresize = true`, `numsteps = 1`, WoWPro.lua:348-349) the engine shows one
row.

## Running characters and findings

```sh
cd ~/Projects/WoW-Pro-Guides
hwc run --race Dwarf --class PRIEST --out /tmp/findings                    # one character, no professions
hwc run --race Dwarf --class WARRIOR --professions herbalism,alchemy       # with professions
hwc run --race Dwarf --class WARRIOR --exclude "*" --include "*Dun_Morogh*" --date 2026-11-12
```

`hwc run` plays one character through the guide chain with the real engine
(to the chain's last line, or to the last included guide when filters are
given) and writes its findings. `--race` and `--class` are required and
case-insensitive; `hwc list` shows the valid ones. It exits 0 once the findings
are written, whatever they contain, 1 on a harness failure and 2 on a usage
error (a missing `--race` or `--class`, a race not in the table above, a class
the race can't play in Forever, or a bad `--professions`).

To play every class of a race, loop over `hwc list`:

```sh
for c in $(hwc list classes Dwarf); do hwc run --race Dwarf --class "$c"; done
```

### Professions

`--professions LIST` names what the character knows from the start, each at
skill 1 of 75, with the spell that teaches it
(`src/hwc/world/profession_spells.lua`). The guides' `SPELL|<Profession>; <id>;
Flip` tags test those spells. Leaving the flag out means no professions.

- A comma list, case-insensitive; a hyphen stands for a space (`first-aid`).
  `herbalism,alchemy` and `alchemy,herbalism` are the same character.
- At most two primary professions: `alchemy`, `blacksmithing`, `enchanting`,
  `engineering`, `herbalism`, `leatherworking`, `mining`, `skinning`,
  `tailoring`.
- Any number of secondary ones: `first-aid`, `fishing`.
- `cooking` is rejected: every character learns Cooking from Camping 101:
  Cooking, when the guide's trainer step sends it there. Leave it out.
- A repeated name, an empty item (`herbalism,`) and an unknown name are usage
  errors; an unknown name lists the valid ones.

`hwc list professions` prints them one per line.

#### Covering professions

These six `--professions` values, run for a character, between them reach every
`A Camping 101: <Profession>` quest in the 1-25 guides:

| `--professions` |
|---|
| `alchemy,herbalism` |
| `blacksmithing,mining` |
| `leatherworking,skinning` |
| `enchanting,engineering` |
| `tailoring` |
| `first-aid,fishing` |

Cooking needs no entry; every run learns it in the guide. The Camping 101 rules
key on the quest's name, which QuestieDB supplies for the Forever-added Camping
101 quests (96031-96059, 96626/96629/96634, 97915-97950). A quest no source
names is marked `unverified` and its profession plays like a character without
it; the findings header lists this under Gaps. A Camping accept hidden by a `P|`
profession the character doesn't know is by design (spec §3) and is not
reported.

### Output

stdout holds the results only: a summary of the findings and a
`hwc: wrote ...` line with the paths. stderr holds the progress (on a terminal the
guide, level and elapsed time on one redrawn line; otherwise one line per guide)
and warnings. `-q`/`--quiet` prints results only; `-v`/`--verbose`
adds progress detail.

Files go under `--out DIR` (default `~/.hwc/findings`, created if missing, so
runs never write into the WoW-Pro folder). The stem is
`<date>-<Race>-<CLASS>[-<professions>][-filtered]-<hash>`, e.g.
`2026-11-18-Dwarf-WARRIOR-herbalism-skinning-3f9a2c17`, or
`2026-11-18-Dwarf-WARRIOR-3f9a2c17` with no professions. With any filter given
the stem gains `-filtered`.

- `DIR/<stem>.html`: the findings report, one self-contained page with the
  findings JSON embedded in it (it opens from disk and loads nothing from the
  network).
- `DIR/<stem>.json`: the same findings as a machine-readable document (format
  2, the JSON the page embeds), which `/triage` reads.
- `DIR/<stem>/<Race>-<CLASS>[-<professions>].json`: the run log (git-ignored).

`<hash>` is 8 hex digits of the findings JSON: two runs with different results
never overwrite each other, and identical findings files share a name.

`--relative-to DIR` (default: the current directory) sets the base for every
path in the output: the HTML page, the findings JSON and the run logs write paths
under the addon checkout, the catalog sources and DIR relative to DIR. Any other
absolute path (rare: a stub reading an unexpected file) is left as it is. Lua
error messages are rewritten before findings are grouped, so a Lua-error
finding's id depends on the base: run from the same directory (or pass the same
`--relative-to`) to compare ids between runs.

`--date` (default: the host date) is an input, so with a fixed `--date` the same
addon commit, catalog, config and seed give byte-identical `.html` and `.json`.
The `Client` row under "About this run" is this repo's own HEAD commit.

The class lists are in `Player.RACES` (`src/hwc/world/player.lua`), from
Blizzard's Forever race/class table
(<https://worldofwarcraft.blizzard.com/news/24304075/>). They never come from
guide tags: the guide is what's under test, and a guide edit must not change
which characters are played.

## Level findings

Every point where the harness compares the character's level with what the guide
or a quest expects reports the size of the gap, in levels, on one scale. The gap
is fractional levels from real XP (`level + xp / xp.to_next(level)`), rounded to
one decimal:

| Gap | Severity |
|---|---|
| under 2 levels | low (within what the simulation's missing XP explains: no incidental kills or rested XP) |
| 2 to under 4 | medium |
| 4 or more | high |

Two checks use it:

| Check | Signal | Gap |
|---|---|---|
| The guide's level check (an `L` step, or a plain `LVL\|n` on any other step) when the character arrived below the check point and the client ground | `level-check` | check point minus the level before the grind |
| An accept below the quest's required level (the client grinds to it) | `below-level` | levels short of the required level |

The client grades only whether the character can accept a quest (the required
level) and the guide's own level checks. It doesn't grade quest difficulty or
colour (too hard, too easy): those are routing decisions for the guide, not for
this client.

Level checks (`L` steps) grind to the guide's `level;offset` check point, ending at
`max(check, actual)`: the client grinds only when below the point and never moves the
character back. Offset tags on other steps don't grind, since WoWPro never hides those
steps; it just completes them at the XP point.

## Comparing runs

`hwc diff` compares two findings files by finding id and tells you what a guide
change fixed and what it broke. The loop: run on `main`, switch the addon to
your branch, run again with the same flags from the same folder (Lua-error
finding ids depend on the folder, see `--relative-to` above), then diff. The
file names carry a content hash, so take both paths from each run's
`hwc: wrote ...` line:

```sh
cd ~/Projects/WoW-Pro-Guides
hwc run --race Dwarf --class WARRIOR --out /tmp/findings      # on main
git switch my-guide-fix
hwc run --race Dwarf --class WARRIOR --out /tmp/findings      # on the branch
hwc diff /tmp/findings/2026-11-18-Dwarf-WARRIOR-1a2b3c4d.json \
         /tmp/findings/2026-11-18-Dwarf-WARRIOR-5e6f7a8b.json
```

Pass the `.json` files; a `.html` path is refused. Add `--json` for the result
as JSON (before or after the paths). A diff compares one character's two runs.
Findings land in one of five categories:

- **fixed**: in OLD, gone from NEW.
- **new**: in NEW only.
- **partly fixed**: in both, but NEW hits fewer characters.
- **spread**: in both, but NEW hits more characters.
- **unchanged**: in both on the same characters (counted, not listed).

Partly fixed and spread only arise in files that hold several characters, as
older hwc versions (`matrix`) wrote them; a file from `hwc run` holds one.

Only findings that count toward the report take part (not harness or expected
ones), and only on the characters both runs played. A warning line says when
the comparison may mislead:

- different QuestieDB tag or build
- different objective counts file
- different guide filters
- characters only in one run (left out), e.g. a file from an older hwc that played several characters
- a character's run stopped early in one run but not the other (findings past the stop show as fixed)
- runs started from different folders
- different hwc versions
- both runs are the same addon commit
- uncommitted changes in the OLD or NEW run

| Exit | Meaning |
|---|---|
| 0 | nothing new (fixed, partly fixed and unchanged may be present) |
| 1 | NEW has new or spread findings, or a shared character's NEW run stopped early |
| 2 | usage error, unreadable file, invalid JSON, or the runs share no characters |

When the runs share no character, `hwc diff` says what each side played, e.g.
`not comparable: OLD has Dwarf Warrior, NEW has Gnome Mage`. A file written
before the `--professions` flag names its characters differently (`baseline`,
`alch-herb`, ...), so it never shares one with a newer file; the message then
ends `; OLD was written before --professions, so re-run it with this hwc`.

Exit 1 means "new findings or a cut-short run" here, as in `diff(1)` it means "files differ".

## Choosing guides

By default a run plays the race's whole chain. `--include PATTERN` and
`--exclude PATTERN` (each repeatable, on `run`) pick which guides
are played, following the AWS S3 CLI:

- Every guide starts included.
- Filters apply in the order given; for each guide file the **last** filter whose
  pattern matches decides. If none matches, the guide stays included.
- Patterns are globs matched against the guide file's path relative to the
  WoW-Pro folder, with `/` separators. `*` matches any run of characters
  including `/`, `?` matches one character, `[abc]` and `[!abc]` are character
  classes. Matching is case-sensitive.
- Filters apply only to guide files (files that register a guide). Every file
  still loads; filters decide which guides are played.

```sh
cd ~/Projects/WoW-Pro-Guides
hwc run --race Dwarf --class PRIEST --exclude "*" --include "*Dun_Morogh*"   # only Dun Morogh
hwc run --race Dwarf --class PRIEST --exclude "*/19_25_*"                    # everything but the 19-25 guide
```

Additions to S3:

- A pattern starting with `./` or `../`, or an absolute path, is resolved from the
  current directory and made relative to the WoW-Pro folder, so tab completion
  works:
  `cd WoWPro_Leveling/Forever/Alliance && hwc run --race Dwarf --class PRIEST --exclude "*" --include ./01_12_Dun_Morogh.lua`.
  A pattern that resolves outside the WoW-Pro folder is a usage error.
- A pattern naming a folder matches every file under it.
- The WoW-Pro folder is the nearest folder at or above the current directory that
  holds `WoWPro/WoWPro.toc`, found along the logical path (`$PWD`), so a symlinked
  `Interface/AddOns` works. None found is a usage error (exit 2).

Usage errors (exit 2): filters that leave no guide included, or an `--include`
that matches no guide file. An `--exclude` that matches nothing is allowed.

When the chain reaches an excluded guide, the run walks forward to the next
included guide and loads it the way a click in the guide list does. The level
is set only when no guide has been played yet: then it is raised to that
guide's `startlevel` through the simulated XP path. A mid-chain jump keeps the
level earned so far. The
run log records each jump. The run ends at the last line of the last included
guide on the chain. With filters, the page's "About this run" section lists
the filters and the guides played, and the included guides the run never
reaches (only when an `--include` was given).

A race whose chain reaches no included guide plays nothing: `hwc run` exits 2
and writes nothing.

**Known limit:** quests from jumped guides were never done. Prerequisite
gates, `orphan-turnin` and `leftover-quests` (`not-turned-in`) findings near a
jump can be noise from the jump, not guide bugs. "About this run" says how
many guides were jumped, so weigh those findings accordingly.

## Addon worktrees and Red/Green anchors

The anchor specs run the client against results known from the addon's own
history (design spec §10). They read pinned, detached worktrees under
`local/addon/` (git-ignored), never `~/Projects/WoW-Pro-Guides` itself: that
checkout's branch is what the game's AddOns folder loads.

```sh
tools/addon-worktree.sh main                       # local/addon/main
tools/addon-worktree.sh fix/forever-prereq-gates   # local/addon/fix-forever-prereq-gates
tools/addon-worktree.sh fix/u-step-loot-result     # local/addon/fix-u-step-loot-result
tools/addon-worktree.sh <ref> /other/addon/checkout
```

The script runs `git worktree add --detach` in the addon repo (this writes
worktree metadata into its `.git`), names the directory after the ref with `/`
turned into `-`, refuses an existing path and prints the path and commit. It
never checks out, switches or resets anything in the main checkout. To move a
worktree to a newer commit, remove it first with
`git -C ~/Projects/WoW-Pro-Guides worktree remove <path>`.

`spec/integration/anchors_spec.lua` (`#slow`) plays a full Dwarf Warrior
with no professions to level 25 on each worktree. Each anchor is pending while its
worktree or the pinned catalog is absent.

| Anchor | Red (`main`) | Green |
|---|---|---|
| #3535 Camping 101: Cooking prereq gates | `never-shown-accept` for Tools for Steelgrill (400), Flintfire's Shipment (98321), Farsen's Watch (96392) in `01_12_Dun_Morogh.lua` | absent on `fix/forever-prereq-gates` |
| #3554 U step gated on its `L` result | the `U` step for QID 1016 with `U\|5456` (`19_25_Alliance.lua:447`) is never shown | shown on `fix/u-step-loot-result` |
| Dungeons | `19_25_Alliance.lua` `DUNGEON` accepts are in the RunLog's `dungeon_skips` and none is a finding | n/a |
| Harness completeness | zero harness `lua-error` findings in the full run | n/a |

The spec prints what it doesn't assert: each Red why, the `never-shown-accept`
totals on both #3535 branches, how many of 19_25's 9 `DUNGEON` accepts were
skipped, and the `missing-global` list. "Farsen's Watch why names
96629" stays pending: the engine's why names only the first unmet prereq of
`PRE|314&96408`, which is 96408.

## Arrival facts

`src/hwc/world/arrivals.lua` holds first-party facts about where the player stands after a taxi, boat,
portal or hearth. They come from the game, never from a guide. `hwc arrivals capture-script [taxi|landing|bind]`
prints one `/run` line (at most 255 characters) to paste into the WoW Forever chat box; it needs no WoW-Pro
folder and no network. Values are labelled; a missing map position prints `xy% nil`.

| Mode | When | Captures | Goes in `arrivals.lua` as |
| --- | --- | --- | --- |
| `taxi` | At a flight master with the taxi map open | Each node's slot, name and type, in slot order | The subzone per taxi node, and how `taxi_map` lists nodes |
| `landing` | Right after a flight, boat, portal or hearth arrives | Zone, subzone, map ID and position as a percent | A `crossings` entry (departure and landing), or an inn's hearth landing |
| `bind` | Right after setting the hearthstone | The bind location text | An inn's bind text |

Date every entry in its `checked` field, for example `user, 2026-11-19: ...`. Two candidates are still
to capture: the Skyborne skycutter departures from Valanaar's harbour, Alliance to Dalaran (from 64.9, 80.9)
and Horde to Thunder Bluff (from 58.2, 79.5).

## World and catalog

The stubs answer from a simulated world (`src/hwc/world/`): the player, bags,
XP and a 40-slot quest log. Quest, NPC and item facts come from a catalog
(design spec §6) from QuestieDB, plus an optional file of hand-checked objective
counts. The guide lines are never a source.

**Data policy: no third-party data is committed.** QuestieDB lives in
`~/.hwc`, and so do the Forever client tables (taxi nodes, maps, areas), downloaded
from wago.tools. The repo holds only the loaders and the structure-only `catalog/counts.example.json`.

Setup:

```sh
hwc init      # from any folder
```

This downloads the latest QuestieDB Forever release into `~/.hwc/questie/<tag>/`,
makes it the active one. It also downloads the newest Forever client build of five
tables from wago.tools, converts them to JSON in `~/.hwc/forever/<build>/` and makes
that the active build, then runs the health check. `hwc update` refreshes both
(`--tag TAG` pins QuestieDB, `--build VERSION` pins the client tables). `HWC_HOME` moves the store (`~/.hwc/questie`, `~/.hwc/forever`); findings still default to `~/.hwc/findings` unless `--out` is given.

### Reputation

Reputation is simulated from quest rewards (`src/hwc/world/reputation.lua`,
`reputation_state.lua`, `stubs/reputation.lua`). It lets guide steps that need a
faction standing be played, and it reports a faction the character never met.
What is known about Forever, and how:

| Fact | Evidence |
|---|---|
| The API is `C_Reputation.GetFactionDataByID`; `GetFactionInfoByID` is absent; a faction the character hasn't met returns nil | Verified in Forever |
| Bands: Neutral 0-3000, Friendly 3000-9000, Honored 9000-21000 | Verified in Forever |
| Bands: Hated -42000 to -6000, Hostile -6000 to -3000, Unfriendly -3000 to 0, Revered 21000-42000, Exalted 42000-42999, and their reaction numbers 1-3, 7 and 8 | Unverified for Forever (Classic values) |
| Alliance (469) and Horde (67) are headers (`isHeader` true, `isHeaderWithRep` false) | Verified in Forever |
| Starting tables for Dwarf, Orc, Undead and Tauren (below) | Verified (fresh level-1 characters, 2026-11-18) |
| Starting tables for every other race (below) | Inferred, unverified for Forever; each run names it in its gaps |
| Gelkis (92) and Magram (93) are at 2000 when first listed | Observed in Forever (level-29 Human, no centaur quests) |
| A faction becomes known on its first quest reward | Inferred |
| Every other faction is met at an assumed 0 | Assumption; each run lists them in its gaps |
| Gains come only from quest rewards (QuestieDB `reputationReward`), at full value, with no racial bonus (Diplomacy is gone in Forever) | Reward scaling is unverified for Forever |
| `requiredMinRep` and `requiredMaxRep` gate accepts | Refusals and the `rep-faction-unmet` finding are unverified |

Starting tables (faction id = points; Stormwind 72, Ironforge 47, Gnomeregan
Exiles 54, Darnassus 69, Alliance 469, Orgrimmar 76, Thunder Bluff 81,
Darkspear Trolls 530, Undercity 68, Horde 67):

| Race | Table | Evidence |
|---|---|---|
| `Dwarf` | 47 = 4000, 54/69/72 = 3100, 469 = 3300 | Verified |
| `Orc` | 76 = 4000, 81/530 = 3100, 68 = 500, 67 = 3500 | Verified |
| `Undead` | 68 = 4000, 76/530 = 2000, 81 = 500, 67 = 3500 | Verified |
| `Tauren` | 81 = 4000, 76/530 = 3100, 68 = 500, 67 = 3500 | Verified |
| `Human`, `Gnome`, `NightElf` | The Dwarf table with the race's home (72, 54, 69) at 4000 and Ironforge at 3100 | Inferred, unverified for Forever |
| `Troll` | The Orc table with Darkspear Trolls (530) at 4000 and Orgrimmar at 3100 | Inferred, unverified for Forever |
| `SkyborneAlliance` | 72/47/54/69 = 3100, 469 = 3300 | Inferred, unverified for Forever |
| `SkyborneHorde` | 76/81/530 = 3100, 68 = 500, 67 = 3500 | Inferred, unverified for Forever |

An accept the standing refuses is an `accept-refused` finding. A step that needs
a faction the character has not met is a `rep-faction-unmet` finding, with the
faction name the tag gives and the id it checks.

### Health check

`hwc doctor` checks the setup, including that the addon loads; see
[Checking the setup](#checking-the-setup).

### Updating QuestieDB

```sh
hwc update              # the newest Forever release
hwc update --tag TAG    # one release by tag
```

The old releases stay in `~/.hwc/questie/`. The findings header records the
tag and build of the one in use. Quest XP, levels, races, classes, objectives,
starters and item drop rates all come from the installed release (drop rates
from its `support/Forever/DropTables`).

Default source paths (`src/hwc/config.lua`; override with
`config.load{ catalog = { ... } }`). Relative paths resolve against the repo
root, not the working directory.

| Key | Default |
|---|---|
| `questie_dir` | the active release under `~/.hwc/questie/` |
| `counts` | `local/catalog/counts.json` (format: `catalog/counts.example.json`) |

### Objective counts

QuestieDB lists each quest's objectives (what to kill, loot or use) but not how
many: Questie reads the "0/8" progress from the game. Each count is found, in
this order:

1. **The counts file**, when it has the quest. Entries are hand-checked, e.g.
   in game, and each names how it was checked. An entry is matched by
   objective kind (`npc`, `object` or `item`) and id, as `hwc quest <id>`
   lists them; one that matches nothing is noted on the quest.
2. **The quest's objective text** in QuestieDB: the number just before the
   objective's name, in the same clause ("Sten Stoutarm would like 8 pieces of
   Tough Wolf Meat"). A name the text gives with no number counts 1. That is
   taken as checked when the context makes it one thing: a possessive name
   ("Find Pamela's doll"), a singular word before it ("the Sparkling Stone",
   "his head"), or a named NPC that is elite or has one or two spawns ("kill
   Grik'nir the Cold"). A bare name with none of these ("some Soothing
   Spices") is a guess, so the quest stays unverified.
3. **Otherwise 1**, assumed, and the quest is unverified.

`hwc quest <id>` shows where each count came from (`count_from`) and why in
`notes`. The counts file is optional and not committed.

Every source is optional. A missing source is recorded in `sources` with
`present: false`, never treated as an error; a partial QuestieDB copy is recorded as `present: "partial"` with the missing files listed. The catalog is loaded into
the world when a character plays.

```sh
hwc quest 179      # the merged quest as JSON, with each source's path, presence and sha256
```

The integration spec `spec/integration/world_engine_spec.lua` drives the real
engine through Dwarven Outfitters (179) for a Dwarf Warrior and a Gnome Mage.
It is pending when the addon checkout or an installed QuestieDB is absent.

## Skip list

`src/hwc/skiplist.lua` lists the files the harness doesn't run. Each entry
records why.

| Path | Why |
|---|---|
| `WoWPro/Libraries/LibSharedMedia-3.0/` | UI media library |
| `WoWPro/Libraries/AceGUI-3.0-SharedMediaWidgets/` | AceGUI widgets |
| `WoWPro/Libraries/LibDataBroker-1.1/`, `LibDBIcon-1.0/` | minimap/broker display |
| `WoWPro/Libraries/HereBeDragons/` | replaced by the HereBeDragons stub |
| `WoWPro/Libraries/LibPetJournal-2.0/` | pet journal |
| `WoWPro/Libraries/Ace/AceGUI-3.0/`, `AceConfig-3.0/`, `AceDBOptions-3.0/` | Ace UI parts |
| `WoWPro/WoWPro_Templates.xml` | frame templates |
| `WoWPro/WoWPro_GuideList.lua`, `WoWPro_Tutorial.lua`, `WoWPro_Config.lua`, `WoWPro_Command.lua`, `WoWPro_Pets.lua` | UI windows, options, slash commands, pet journal |
| `WoWPro_Leveling/WoWPro_Leveling_Config.lua`, `WoWPro_Leveling_Frames.lua` | Leveling options and frames |

The design spec (§4.2) listed `WoWPro_Widgets.lua` and `WoWPro_CurrentGuide.lua`
as skipped, but both **load**:

- `WoWPro_Frames.lua:1767` builds every row from the Widgets constructors.
- `WoWPro_Broker.lua:1880` calls `WoWPro.CurrentGuideFrame:IsVisible()` on every
  update. CurrentGuide creates that frame hidden at load.

Functions that the skipped files would define, and that the loaded engine
calls, are replaced by logging stand-ins in `src/hwc/stubs/standins.lua`:

- fills: `RefreshConfig`, `SetDefaults`, `InitializeTutorial`, `QueueTutorial`,
  `CreateConfig`, `CreateGuideList`;
- overrides of addon-defined minimap UI that needs skipped libraries:
  `CreateMiniMapButton`, `MinimapSet`.

## TOC-order quirk: ZoneData_Patches

`WoWPro.toc` lists `WoWPro_ZoneData_[Game].lua`, then
`WoWPro_ZoneDataLegacy.lua`, then `WoWPro_ZoneData_Patches.lua`. The Patches
header says it "should be loaded *before* the client specific map lists". The
client loads files in TOC order, so the harness does the same: Patches loads
**after** `WoWPro_ZoneData_Forever.lua`. That matches the game, bug included.

## Missing globals (Dwarf Warrior load)

The sandbox records every global read that has no value. These are the reads
left after loading the addon for a Dwarf Warrior (the `hwc doctor` addon check), in first-read order. None of them blocks the
load.

| Globals | Status |
|---|---|
| `LibStub`, `WoWProDB`, `WoWProData`, `TourGuide` | addon/library probes before they're defined |
| `GetNumQuestLogEntries`, `GetQuestLogTitle` | probed by `WoWPro_CompatUtil.lua`; Forever uses the `C_QuestLog` path |
| `TomTom`, `Nx` (Carbonite), `Grail` | optional integrations, absent |
| `PlayerGetTimerunningSeasonID`, `C_Seasons`, `C_PetBattles`, `C_Covenants`, `C_QuestLine`, `C_QuestInfoSystem`, `C_Garrison`, `SetSuperTrackedQuestID` | guarded probes for other flavors |
| `LE_EXPANSION_*` (12 constants) | feed `guide.expansion` (`WoWPro_GuideRegistry.lua:309`), read only by the guide-list UI |
| `FACTION_HORDE`, `FACTION_ALLIANCE`, `OKAY`, `CANCEL`, `GameFontNormal`, `GameFontNormalSmall`, `BackdropTemplateMixin` | UI strings, fonts and templates |
| `GetItemCooldown` | probed by `WoWPro_CompatUtil.lua:232`; Forever uses `C_Container.GetItemCooldown` |
| `issecretvalue` | guarded probe (`WoWPro_AutoComplete.lua:118`, `:131`, `:432`) |
| `GetBindLocation` | guarded probe (`WoWPro_Events.lua:249`). The hearth location is player state for a later plan, so `WoWProDB.char.hearth` stays unset. |

A Lua error that indexes or calls one of these nil names counts as a harness
error (a gap in hwc, not an addon bug) only when the name is not the addon's own
(no `WoWPro` prefix) and not in `boot.EXPECTED_ABSENT` (`src/hwc/boot.lua`): the
APIs absent in Forever (`GetFactionInfoByID`, checked in game 2026-11-18; the
retail-only probes above, unverified for Forever), the other addons (`Grail`,
`Nx`, `TourGuide`) and `LibStub`, which the addon ships. `TomTom` is not in that
set: the guides expect it installed, so it stays a harness gap until stubbed.

Frame methods the mock doesn't model show up as `Frame:<Name>`, and
unstubbed namespaced APIs show up as `<Namespace>.<Field>`. The Dwarf Warrior load
has neither.
