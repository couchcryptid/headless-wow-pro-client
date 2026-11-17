# QuestieDB as a managed dependency: `hwc init`, `hwc doctor`, `hwc sync questie`

Status: draft for review · 2026-11-17 · Changes the catalog's QuestieDB source
(`2026-11-11-headless-client-design.md` §6) and the setup steps in the README.

## 1. Intent

Today QuestieDB reaches hwc through `tools/fetch-questie.sh <commit>`, a
repo-side shell script. It downloads six raw files from GitHub into
`local/questie/<commit>/` **inside the hwc checkout**, at a commit hash that is
hardcoded in `src/hwc/config.lua` (`QUESTIE_PIN = d57637f…`) and copied by
hand from the README. Meanwhile `hwc` itself is installed on `$PATH` and run
from a WoW-Pro folder. Someone who installed `hwc` and never opened the repo,
or never installed the Questie addon, has no supported way to get the data.

The user wants QuestieDB to behave like a dependency of hwc, with hwc owning
its whole lifecycle:

- `hwc init` downloads it.
- `hwc doctor` reports its version against upstream, along with the rest of
  hwc's health.
- `hwc sync questie` pulls a fresh copy.

The user also wants hwc to see **what players see**: QuestieDB data **with its
corrections applied**. The raw `data/Forever/*.lua` files hwc reads today are
the data before corrections.

**Success:**
- On a machine with `hwc` installed and nothing else set up, `hwc init` and
  then `hwc run --race Dwarf --class WARRIOR` (from a WoW-Pro folder) plays
  against the latest QuestieDB Forever release, with corrections applied.
- `hwc doctor` prints one report covering the runtime, the WoW-Pro folder and
  QuestieDB, including "v1.1.2, up to date" or "v1.1.2 → v1.1.3 available".
- `hwc sync questie` moves to a newer release without touching the repo.

## 2. What upstream provides (recon, 2026-11-17)

- **Versions:** QuestieDB (`github.com/Questie/QuestieDB`) publishes GitHub
  releases with semver tags. The latest is `v1.1.2` (2026-11-16, commit
  `e1652ce`). The current hwc pin `d57637f` is untagged and 66 commits behind it.
- **Release assets:** each release has one zip per flavor, including
  `QuestieDB-<ver>-Forever.zip` (about 15 MB), plus a `release.json` that
  lists every zip with its flavor and interface metadata
  (`"flavor": "forever"`).
- **The Forever zip is the shipped addon, not raw data.** It holds no
  `foreverQuestDB.lua`. Entity data is "baked" into
  `QuestieDB/QuestieDB_Forever.toc` (about 17 MB, about 131k lines) as
  `## X-<Entity>-<id>-<field>: <base64>` metadata lines. The TOC header names
  itself:
  ```
  ## X-Contract-Version: 4
  ## X-Flavor: Forever
  ## X-Mode: baked
  ## X-BUILD-COMMIT: e1652ce62113c152da682baf2d6fb85f1396bcfb
  ```
  The zip also contains `QuestieDB_Camelot.toc`, which hwc ignores.
- **Corrections come in two kinds.** *Static* corrections are folded into the
  baked data when the TOC is generated, and the packaged correction files have
  those bodies stripped (`src/corrections/register.lua`). *Dynamic*
  corrections run when the addon loads: `src/api.lua` calls
  `ApplyRegisteredCorrections`, and the result is cached for the session. They
  depend on the player. `UnitClassBase("player")` selects class-specific quest
  rows (`src/corrections/Forever/legacy/classicQuestFixes.lua:32`,
  `Forever/foreverQuestFixes.lua:42`), and `UnitFactionGroup("player")`
  selects the Horde or Alliance tables in all five fix files. The corrected data
  is only visible through QuestieDB's own code, so running that code, **as the
  character being played**, is the only way to see what that player sees.
- **Prereleases:** upstream also publishes a moving `preview` tag marked
  `prerelease: true`. hwc ignores drafts and prereleases.
- **The public surface:** `src/api.lua` publishes `QuestDB`, `NpcDB`, `ItemDB`
  and `ObjectDB` globals with `Get(id, key)`, `GetAll(id, keys)`,
  `GetAllIds()`, `Exists(id)` and `IdsByName(name)`. It also exposes
  `LibQuestieDB.RequireContract(n)` and `contractVersion`/`minSupportedContract`.
- **XP tables** (`support/Forever/QuestXP/xpDB-classic.lua`,
  `xpDB-traces.lua`) are in the zip and in the TOC load list. They populate
  `QuestieLoader:ImportModule("QuestXP").db` exactly as they do today.
- **WoW APIs it needs:** `C_AddOns.GetAddOnMetadata(addon, key)` (the baked
  store), `C_EncodingUtil.DecodeBase64`, `C_EncodingUtil.DecompressString`
  (deflate/zlib), `C_EncodingUtil.DeserializeCBOR`, and
  `C_Seasons.GetActiveSeason`. Upstream's own offline emulator
  (`emulator/client.lua` in the source repo, not in the zip) implements
  these with LibDeflate and a vendored `BlizzardCBOR.lua`.
- **Licence:** QuestieDB is GPL-3.0. hwc is MIT and stays that way, so no
  QuestieDB code or data is committed; hwc downloads and runs it on the user's
  machine, as it already does with WoW-Pro.

## 3. Goals, non-goals, anti-goals

**Goals**
- `hwc init`, `hwc doctor` and `hwc sync questie`, as described in §4.
- QuestieDB data is stored in an hwc-owned folder under `~/.hwc/`, never in
  the repo checkout.
- The version hwc tracks is the **QuestieDB release tag**, compared with
  GitHub's `releases/latest`.
- hwc loads the **unmodified** Forever release through its own TOC loader and
  fake WoW API, so QuestieDB's corrections are applied by QuestieDB's code.
- The catalog reads quests, NPCs, items, objects and XP through that loaded
  QuestieDB instead of parsing raw files.
- Findings record the QuestieDB tag and build commit in use.

**Non-goals**
- **Wowhead.** `init`, `sync` and `doctor` don't touch the Wowhead extract
  (`wh.json`, `objs.json`, `rate_overrides.json`). Decided by the user: browser
  scraping isn't a viable long-term way to sync it, so a proper sync is a
  separate future feature. The catalog keeps reading the extract when it is on
  disk at its configured paths, unchanged.
- Moving or syncing the supplement (`local/catalog/supplement.json`). It stays
  where it is; `doctor` only reports it.
- Flavors other than Forever, and the `Camelot` TOC.
- Installing LuaJIT or LuaRocks for the user. `doctor` diagnoses those, and the
  README covers installing them.
- Packaging hwc itself (Homebrew, rockspec).

**Anti-goals** (a failure even if it works)
- Patching, re-implementing or reformatting QuestieDB's corrections or its
  baked decoder in hwc. If hwc's data can differ from a player's, the feature
  has missed its point.
- Committing any QuestieDB file, or GPL code taken from QuestieDB's source
  repo, to this MIT repo.
- `sync` silently changing the data under a run, or deleting the version a
  previous findings file was produced with.
- `doctor` changing anything, or failing because the network is down.
- Keeping two QuestieDB loaders (raw and baked) alive side by side.

## 4. Behaviour

### 4.1 Storage

```
~/.hwc/
  questie/
    v1.1.2/            # the unpacked Forever zip: QuestieDB/QuestieDB_Forever.toc, src/, support/…
      .hwc-release.json   # what hwc downloaded: tag, asset name, asset size, sha256 of the zip, download time
    v1.1.3/
    active             # one line: the active tag, e.g. "v1.1.3"
  findings/            # unchanged
```

- The root is `~/.hwc` (`$HOME` required, consistent with `findings`). *Builder's
  call:* also honour `HWC_HOME` if that's cheap, and use it in specs.
- `active` is a plain file, not a symlink, so it behaves the same on every
  filesystem.
- Earlier versions are **kept** (*Claude's call*). Red/Green comparisons need
  both runs on identical data, and a findings file names the tag it used.
  Nothing deletes old versions automatically.
- Downloads go to a temp folder under `~/.hwc/questie/` and are renamed into
  place only after verification, so an interrupted download never leaves a
  half-written version that looks real.

### 4.2 `hwc init`

1. Create `~/.hwc/` if needed.
2. If an active QuestieDB version is already installed and intact, say so and
   do nothing else (idempotent). `--force` is not needed. Use `sync` to change
   versions.
3. Otherwise do what `hwc sync questie` does (§4.3).
4. Finish with a short `doctor` summary so the user sees what's still missing
   (for example, no WoW-Pro folder in the current directory).

`init` runs from any directory. It doesn't need a WoW-Pro folder.

### 4.3 `hwc sync questie [--tag vX.Y.Z]`

1. Ask GitHub for the target release. Without `--tag`, list the releases (one
   `GET /releases` call), skip drafts and prereleases, and walk from newest to
   oldest. With `--tag`, ask for `releases/tags/<tag>`, so you can step back to
   an older version or reproduce an old findings file.
2. Read each candidate's `release.json` and take the first release with an entry
   whose metadata flavor is `forever`. That gives the asset's file name, so hwc
   never guesses the zip's name. If a newer release has no Forever zip, it is
   skipped and the output says so (*Claude's call*: a release that can't be
   installed for Forever isn't an update for hwc). If `--tag` names a release
   without a Forever zip, that's an error.
3. If that tag is already installed and intact, just make it active and stop.
4. Download the zip, unpack it into a temp folder, and verify it:
   - `QuestieDB/QuestieDB_Forever.toc` exists;
   - `X-Flavor` is `Forever` and `X-Mode` is `baked`;
   - the contract check passes (§4.5, contract);
   - the zip's size matches the size the GitHub asset reported.
5. Write `.hwc-release.json`, move the folder into place, then update `active`.
6. Print `QuestieDB v1.1.2 → v1.1.3 (build e1652ce)`, or "already up to date".

On any failure, the previously active version stays active and untouched, and
the error says which step failed.

### 4.4 `hwc doctor`

Read-only. Each check prints **ok / warn / fail** with one line saying what to
do. The command exits non-zero if any check is **fail**. Warnings don't affect
the exit code.

| Check | ok | warn | fail |
|---|---|---|---|
| LuaJIT | 2.1 found (same search as `bin/hwc`), version shown | | missing or not 2.1 |
| Rocks | `busted`, `lfs`, `dkjson` load under Lua 5.1 | `busted` missing (only needed for specs) | `lfs` or `dkjson` missing |
| Tools | `curl` and `unzip` on `$PATH` | | either missing (needed for `init`/`sync`) |
| WoW-Pro folder | cwd resolves via `hwc.source`; branch @ commit (+ dirty) when it's git | not in a WoW-Pro folder (`run`/`matrix` need one) | |
| QuestieDB installed | active tag, build commit, path | | none installed → `hwc init` |
| QuestieDB intact | TOC present, flavor Forever, mode baked | | broken → `hwc sync questie --tag <active>` |
| QuestieDB contract | `X-Contract-Version` supported | | unsupported → name the supported range |
| QuestieDB upstream | "up to date" | newer release available → `hwc sync questie`; GitHub unreachable or rate-limited | |
| Supplement | present at its configured path | absent (optional source) | invalid JSON or an entry without `source` |

- The upstream check uses the same release selection as `sync` (§4.3): the
  newest non-draft, non-prerelease release that has a Forever zip. That's one
  list call plus a `release.json` fetch per candidate, normally one. It's
  unauthenticated, with a short timeout. A network failure is a **warn**, and the rest of the report still
  prints.
- `--json` prints the same report as JSON, matching other commands' `--json`.
- Wowhead is not checked (§3 non-goals).

### 4.5 Loading QuestieDB (the catalog's new QuestieDB source)

- `config.lua` resolves `catalog.questie_dir` to `~/.hwc/questie/<active>/QuestieDB`
  instead of the hardcoded pin. `config.load{ catalog = { questie_dir = … } }`
  still overrides it, and specs use that. The `QUESTIE_PIN` constant is deleted.
- hwc loads QuestieDB **in its own sandbox**, separate from WoW-Pro's, using
  `hwc.toc` to reproduce the load order of `QuestieDB_Forever.toc` for the
  Forever flavor. It's a data library, so isolation keeps WoW-Pro's
  missing-global accounting clean. *Builder's call* whether that's a second
  `hwc.sandbox` instance or a lighter env, as long as missing globals and errors
  are still recorded and reported.
- Stand-ins the QuestieDB sandbox needs:
  - `C_AddOns.GetAddOnMetadata("QuestieDB", key)`, backed by the TOC's `## Key: value`
    lines, parsed once into a table. Only the QuestieDB TOC is served.
  - `C_EncodingUtil.DecodeBase64`, `DecompressString` (deflate and zlib) and
    `DeserializeCBOR`, implemented in pure Lua so they run under LuaJIT. Base64
    and CBOR decoding are small enough to write in this repo. For inflate, use
    LibDeflate (zlib licence), either vendored with its licence or installed as
    a LuaRocks dependency (*builder's call*, and `doctor` checks it if it's a
    rock). **Don't copy upstream's `emulator/*.lua` or `BlizzardCBOR.lua`**:
    they're GPL (§3 anti-goals).
  - `C_Seasons.GetActiveSeason`, returning the value a Forever client returns.
    The builder confirms it against QuestieDB's source and cites the line.
  - `UnitClassBase("player")` and `UnitFactionGroup("player")`, answered from the
    character being played (`cfg.class`, `cfg.faction`). The builder greps the
    loaded files for any other `Unit*`/player reads the corrections make and
    stubs those from the character too.
- **One QuestieDB per character** (*Claude's call*, following the user's "match
  what players see"). The dynamic corrections depend on class and faction, so
  each character gets its own QuestieDB instance, loaded with that character's
  answers, exactly as a player's client loads it once at login. The expensive
  part, parsing the 17 MB TOC into a metadata table, happens **once per
  process** and is shared read-only by every instance. So `hwc matrix` pays
  for the parse once and only re-runs QuestieDB's Lua (decode is lazy) per
  combination. Findings can legitimately differ by class because of this.
- **Contract.** hwc is built against contract **4**. A release is accepted when
  `minSupportedContract <= 4 <= contractVersion`, the same rule as
  `LibQuestieDB.RequireContract`.
  - **At `sync`/`doctor` time**, without running QuestieDB: read
    `contractVersion` and `minSupportedContract` from the installed
    `src/config.lua` as text (`config.contractVersion = N`), falling back to
    the TOC's `X-Contract-Version` for the upper bound. This keeps `doctor`
    cheap and read-only.
  - **At load time**, call `RequireContract(4)`. It returns `false, msg` rather
    than raising, so hwc checks the return value and raises a hard error that
    names both versions and points to `hwc sync questie --tag`.
- The loader returns the same shape the catalog uses today (`quests`,
  `npcs`, `items`, `objects` by id → named-field records, `xp`, `missing`),
  but backed by `QuestDB.GetAll(id)` and its siblings. Two places iterate every
  item row (`Catalog:quest_rewards`, `Catalog:item_id` in
  `src/hwc/catalog/init.lua`). They switch to `ItemDB.GetAllIds()` plus `Get`,
  or `IdsByName`. The `rows`/`keys` positional access goes away.
- Field names: the catalog uses QuestieDB's key names (`questLevel`,
  `objectives`, `startedBy`, `questRewards`, …). The builder confirms each
  against the baked `Meta` schema (`LibQuestieDB.Meta.QuestMeta.questKeys`).
  Any field that was renamed or reshaped gets adapted in the loader, not
  scattered through the catalog.
- **Cost:** the TOC parse happens once per process, plus one QuestieDB load
  per character. The builder measures `hwc boot` and a two-combination
  `hwc matrix` before and after, and records the numbers in the plan.
- If no QuestieDB is installed, the catalog records `present: false`, as every
  optional source does today, and `run`/`boot` print one line suggesting
  `hwc init`.

### 4.6 Findings

The header's `questie` source line records the **tag**, the **build commit**
(`X-BUILD-COMMIT`) and the **zip's sha256** (from `.hwc-release.json`), in
place of today's per-file sha256 list. For example:
`questie: present · v1.1.2 · build e1652ce · sha256 3fa1… · ~/.hwc/questie/v1.1.2`.

### 4.7 Removed

- `tools/fetch-questie.sh` and `src/hwc/catalog/questie.lua`'s raw-file
  parser, together with their specs (`spec/catalog/questie_spec.lua` and the raw
  fixtures under `spec/fixtures/catalog/questie/`). They're replaced, not kept as
  a fallback (§3 anti-goals).
- README and CONTRIBUTING: the `fetch-questie.sh` setup steps and the pinned-commit
  table row become `hwc init`. The README gains short sections on `doctor`
  and `sync questie`.

## 5. Expected consequences

- **Findings will change.** Corrected data differs from raw data, and v1.1.2 is
  66 commits newer than the old pin. Any baseline captured against `d57637f` is
  not comparable. The plan should include one run on the old loader and one on
  the new, so the diff can be reviewed and explained in the plan's carryover.
  It shouldn't be treated as a regression.
- Integration specs that are pending when `local/questie/<pin>` is absent become
  pending when no QuestieDB is installed under `~/.hwc` (or `HWC_HOME`).
- **Testing split** (*Claude's call*). Reading the baked format and applying
  corrections is QuestieDB's GPL code, so it can't be committed as a fixture.
  - **Unit specs** cover only hwc's own parts against small hand-made inputs:
    TOC `##` metadata parsing, base64, CBOR, inflate, the stand-ins, release
    selection (with canned GitHub JSON), the install/`active` state machine
    (including an interrupted download), the contract check, and doctor's
    check results.
  - **Integration specs** load the real installed release from `~/.hwc` (or
    `HWC_HOME`) and are pending without one, like today's. They assert at least:
    Dwarven Outfitters (179) resolves; one class-specific dynamic correction
    differs between two classes; `RequireContract(4)` passes.
  - No mock QuestieDB addon is written. Testing a fake would hide exactly the
    drift this feature exists to catch.

## 6. Left to the builder

- CLI wiring and help text, following the existing `cli.lua` command style.
- The HTTP client: shell out to `curl` (already an optional requirement),
  using `-fsSL` with a timeout. `unzip` for unpacking (present on macOS and most
  Linux).
- The exact wording of doctor lines and the `--json` shape.
- Whether `HWC_HOME` is supported (§4.1).
- How to structure the QuestieDB sandbox (§4.5).
