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

The integration specs need two things, and are pending without them:
- a WoW-Pro-Guides checkout;
- the local catalog: `tools/fetch-questie.sh <commit>`.

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
   - The catalog covers QuestieDB, the Wowhead extract and the hand-checked
     supplement.
   - Guide tags may say only where the player goes (`Z`, `M`, `TZ`) and what
     they buy or loot (`L`, `B`).
   - A quest missing from every source gets a placeholder flagged "unverified
     quest data". Its level, rewards and objectives are never taken from the
     guide.
4. **No third-party data in the repository.** QuestieDB, Wowhead and supplement
   data stay in the git-ignored `local/` directory or at paths in config.
   - Commit only loaders, scripts, structure-only examples and invented test
     fixtures.
   - Supplement entries must name their source, e.g. a Wowhead page and the
     date it was checked.
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
- **If you change what the driver does,** re-run `bin/hwc matrix` on a pinned
  worktree. Report the before and after signal counts in the pull request.
- **Commits:** an imperative subject line (e.g. "Give quest reward items on
  turn-in"), and a body saying why when it isn't obvious.
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
