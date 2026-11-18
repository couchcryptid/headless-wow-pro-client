# Contributing

Thanks for helping. This client is only useful if its findings can be trusted,
so most of the rules below protect one property: when a finding says a guide is
broken, the guide is broken. A finding must never come from a gap in the
simulation.

## Setup

See [Requirements](README.md#requirements) and [Quick start](README.md#quick-start).

Specs run with busted under LuaJIT:

```sh
~/.luarocks/bin/busted                 # default suite (seconds)
~/.luarocks/bin/busted --tags=slow     # full guide runs, determinism, Red/Green anchors
```

The report page has its own suite (Node 24, see
[Working on the report page](README.md#working-on-the-report-page)):

```sh
cd web/report && npm ci && npm run typecheck && npm test
```

Lint the Lua with luacheck (config in `.luacheckrc`):

```sh
~/.luarocks/bin/luacheck .
```

Run lint and both suites before committing; a change to the page also needs `npm run build`.

The integration specs need two things, and are pending without them:
- a WoW-Pro-Guides checkout;
- QuestieDB: `hwc init`.

The anchors also need the pinned addon worktrees; see
[Addon worktrees and Red/Green anchors](README.md#addon-worktrees-and-redgreen-anchors).

## Ground rules

1. **The addon is read-only input.** Never modify, vendor or patch WoW-Pro code,
   and never write its engine state. That includes `WoWPro.*` decisions,
   `ActiveStep`, `completion` and `currentguide`.
   - The harness changes the simulated world, fires the events the game client
     fires, and settles the clock.
   - The driver makes only two engine calls, both of which a player could make:
     `WoWPro.CompleteStep(i, "Right-Click")` and `WoWPro:UpdateGuide("sim:level")`.
2. **Reproduce the addon, bugs included.** If the real engine doesn't advance
   where a player would, find the root cause first:
   - **A harness gap** (a missing stub, a wrong event order, a missing world
     fact): fix the harness, citing the addon file and line it serves.
   - **An engine or guide problem:** that's a finding. Report it; don't work
     around it.
3. **World facts come from the catalog, never from guide lines.**
   - The catalog covers QuestieDB and the hand-checked supplement.
   - Guide tags may say only where the player goes (`Z`, `M`, `TZ`) and what
     they buy or loot (`L`, `B`).
   - A quest missing from every source gets a placeholder flagged "unverified
     quest data". Its level, rewards and objectives are never taken from the
     guide.
4. **No third-party data in the repository.** QuestieDB and supplement
   data stay in the git-ignored `local/` directory or at paths in config.
   - Commit only loaders, scripts, structure-only examples and invented test
     fixtures.
   - Supplement entries must name their source, e.g. an in-game check and the
     date it was made.
5. **Determinism.** The same addon commit, catalog, config, seed and `--date`
   give byte-identical findings.
   - No wall-clock time inside the sandbox.
   - Sort anything built from `pairs` before it reaches output.
6. **Cite what you rely on.** Each engine behaviour a change depends on gets an
   addon `file:line` reference in a comment, and each external fact gets its
   source.

## Workflow

- **Branch from `main`.** Use a pinned addon worktree
  (`tools/addon-worktree.sh <ref>`) for Red/Green work instead of switching
  your WoW-Pro checkout's branch, because the game's AddOns folder may point at
  it.
- **Write the failing spec first,** then the change. Keep the default suite
  fast; tag anything that plays whole guides `#slow`.
- **If you change what the driver does,** re-run `bin/hwc run` for a few characters (the loop in the
  README's "Running characters and findings") on a pinned worktree. Report the before and after signal counts in the pull request.
- **Commits:** an imperative subject line (e.g. "Give quest reward items on
  turn-in"), and a body saying why when it isn't obvious.
- **Pull requests** go into `main`, with a
  [Conventional Commit](https://www.conventionalcommits.org/) title and a
  capitalised, imperative subject: `fix: Give quest reward items on turn-in`.
  The `PR title` check enforces it. semantic-release reads the subject lines of
  the commits that land on `main`, not PR titles, so each PR must land at least
  one Conventional Commit subject. Either:
  - make one of the PR's own commits a Conventional Commit, and merge with a
    merge commit or rebase; or
  - when squash-merging, edit the squash commit's subject to the Conventional
    Commit, e.g. the PR title. GitHub may fill in "Merge pull request #N"
    instead, and then nothing releases.
- **Releases are automatic.** Each merge into `main` runs CI again, then
  [semantic-release](https://semantic-release.gitbook.io/) reads the subject
  line of each new commit on `main` and decides the next version:

  | Title type | Release |
  |---|---|
  | `fix:` | patch (`v1.2.3` → `v1.2.4`) |
  | `feat:` | minor (`v1.2.3` → `v1.3.0`) |
  | `feat!:`, `fix!:`, or a `BREAKING CHANGE:` footer | major (`v1.2.3` → `v2.0.0`) |
  | `perf:`, `docs:`, `test:`, `refactor:`, `chore:`, `ci:`, `build:`, `style:` | none |

  Only `fix` and `feat` release. Title anything a user of `hwc` should get
  as `fix:` or `feat:`. Two exceptions follow from how semantic-release
  reads commits:
  - A breaking change on **any** type (`refactor!:`, or a
    `BREAKING CHANGE:` footer in the squash body) releases a major.
  - A plain `git revert` commit (`Revert "..."` plus "This reverts commit
    <sha>.") releases a patch. A squash-merged GitHub revert PR doesn't match
    that pattern and releases nothing; retitle it `fix:` if it should ship.

  A release is a `v`-prefixed git tag plus a GitHub release with generated
  notes. Config: `.releaserc.json`. Tooling is pinned in `.github/release/`.
- **CI on pull requests** (`.github/workflows/ci.yml`) runs luacheck, the
  default busted suite on LuaJIT 2.1, and the report page's typecheck, tests
  and build. It fails if `src/hwc/findings/report.html` doesn't match a fresh
  build. Integration specs report pending in CI because there's no WoW-Pro
  checkout or QuestieDB there; run them locally.
- **Design decisions** and the reasons for them are recorded under
  `docs/superpowers/`. Read the design spec before larger changes.

## Reporting a guide bug found by the client

Findings files list the guide file and line, the engine's own reason (`why`),
the affected race/class combinations, and a data-confidence flag.

Before opening an issue on
[WoW-Pro-Guides](https://github.com/Ludovicus-Maior/WoW-Pro-Guides/issues),
check that the finding isn't one of these:
- marked "unverified quest data";
- caused by a gap listed in the findings file's header.

## Licence

By contributing you agree that your contributions are licensed under the
[MIT License](LICENSE).
