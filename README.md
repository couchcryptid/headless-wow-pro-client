# headless-wow-pro-client

Loads the real WoW-Pro addon (Lua 5.1) under LuaJIT outside the game.
The addon is read-only input, read from a configured path
(default `~/Projects/WoW-Pro-Guides`).

- Run: `bin/hwc --help`
- Test: `~/.luarocks/bin/busted` (the integration specs are pending when the
  addon checkout or the local catalog is absent)

## Booting the addon

```sh
bin/hwc boot --race Dwarf --class WARRIOR            # text summary
bin/hwc boot --race Gnome --class MAGE --json        # full result as JSON
bin/hwc boot --addon /path/to/WoW-Pro-Guides         # another checkout
```

`hwc boot` loads `WoWPro/WoWPro.toc`, then `WoWPro_Leveling/WoWPro_Leveling.toc`,
for the Forever flavor (TOC 16001). It then fires `ADDON_LOADED`, `PLAYER_LOGIN`
and `PLAYER_ENTERING_WORLD` and settles the virtual clock until the startup
lockdown releases and the timers drain. It prints:

- the addon branch, commit and dirty flag;
- the loaded guide GID;
- the rows the engine shows;
- error counts (harness and addon);
- the number of missing globals;
- the stand-ins that were called.

A checkout without a git commit is refused, so an unidentified run can't be
mistaken for a real one. With the addon's defaults (`autoresize = true`,
`numsteps = 1`, WoWPro.lua:348-349) the engine shows one row.

## Running characters and findings

```sh
bin/hwc run --race Dwarf --class PRIEST --out /tmp/findings          # one character
bin/hwc run --race Dwarf --class WARRIOR --variant alch-herb         # with professions
bin/hwc run --race Dwarf --class WARRIOR --stop-level 6 --date 2026-11-12
bin/hwc matrix --races Dwarf,Gnome --date 2026-11-12                 # the whole matrix
```

`hwc run` plays one character through the guide chain with the real engine
(stop level 25 unless `--stop-level N` says otherwise); `hwc matrix` plays every
combo and groups all the signals into one findings file. Both exit 0 once the
findings are written, whatever they contain, 1 on a harness failure and 2 on a
usage error (a missing `--class`, a race outside Human/Dwarf/Gnome/NightElf).

Output, under `--out DIR` (default `findings/` in the current directory):

- `DIR/<date>-<scope>.md`: the findings (design spec §7.2). The scope is
  `forever-alliance-<races lower, joined by '-'>-1-25` for `matrix` and
  `<race>-<class>-<variant>` for `run`.
- `DIR/<date>-<scope>/<race>-<class>-<variant>.json`: one run log per character
  (git-ignored).

`--date` (default: the host date) is an input, so with a fixed `--date` the same
addon commit, catalog, config and seed give byte-identical markdown. The
header's `Client` line is this repo's own HEAD commit.

Matrix combos (`src/hwc/driver/matrix.lua`): for each race, every class that
the race's start guide names in a `C|` tag (on lines with no `R|` tag, or whose
`R|` includes the race) at the `baseline` variant, plus each other variant on
the race's first class in sorted order. The start guide is
`WoWPro.Leveling.ForeverStartGuides[race]`, read from the Leveling source text
and matched to its guide file by `WoWPro:GuideName` (or GID); the addon is not
executed. Variants (skills start at rank 1, max 75) cover every
`A Camping 101: <Profession>` quest in the 1-25 guides:

| Variant | Professions |
|---|---|
| `baseline` | none |
| `secondary` | Cooking, First Aid, Fishing |
| `alch-herb` | Alchemy, Herbalism |
| `bs-mining` | Blacksmithing, Mining |
| `lw-skin` | Leatherworking, Skinning |
| `eng-ench` | Engineering, Enchanting |
| `tailoring` | Tailoring |

## World and catalog

The stubs answer from a simulated world (`src/hwc/world/`): the player, bags,
XP and a 40-slot quest log. Quest, NPC and item facts come from a catalog
(design spec §6) merged from three local sources. The guide lines are never a
source.

**Data policy: no third-party data is committed.** QuestieDB and the Wowhead
extract stay on your machine, under `local/` (git-ignored) or at external
paths. The repo holds only the loaders, `tools/fetch-questie.sh` and the
structure-only `catalog/supplement.example.json`.

Setup:

```sh
tools/fetch-questie.sh d57637f490c9dfcdbbc967dab47a8b0d8fe1b3cc   # the pinned QuestieDB commit
```

This writes the Forever quest, NPC, item, object and XP files to
`local/questie/<commit>/` with a `SHA256SUMS`. It won't overwrite a copy whose
hashes differ.

Default source paths (`src/hwc/config.lua`; override with
`config.load{ catalog = { ... } }`). Relative paths resolve against the repo
root, not the working directory.

| Key | Default |
|---|---|
| `questie_dir` | `local/questie/d57637f490c9dfcdbbc967dab47a8b0d8fe1b3cc` |
| `wh_json`, `objs_json`, `rate_overrides` | `~/Projects/wow-pro-leveling/sim/data/{wh,objs,rate_overrides}.json` |
| `supplement` | `local/catalog/supplement.json` (format: `catalog/supplement.example.json`) |

Every source is optional. A missing source is recorded in `sources` with
`present: false`, never treated as an error; a partial QuestieDB copy is recorded as `present: "partial"` with the missing files listed. `hwc boot` loads the catalog into
the world.

```sh
bin/hwc quest 179      # the merged quest as JSON, with each source's path, presence and sha256
```

The integration spec `spec/integration/world_engine_spec.lua` drives the real
engine through Dwarven Outfitters (179) for a Dwarf Warrior and a Gnome Mage.
It is pending when the addon checkout or `local/questie/<pin>` is absent.

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

## Missing globals (Dwarf Warrior boot)

The sandbox records every global read that has no value. These are the reads
left after a Dwarf Warrior boot, in first-read order. None of them blocks the
boot.

| Globals | Status |
|---|---|
| `LibStub`, `WoWProDB`, `WoWProData`, `TourGuide` | addon/library probes before they're defined |
| `GetNumQuestLogEntries`, `GetQuestLogTitle` | probed by `WoWPro_CompatUtil.lua`; Forever uses the `C_QuestLog` path |
| `TomTom`, `Nx` (Carbonite), `Grail` | optional integrations, absent |
| `PlayerGetTimerunningSeasonID`, `C_Seasons`, `C_PetBattles`, `C_Covenants`, `C_QuestLine`, `C_QuestInfoSystem`, `C_Garrison`, `SetSuperTrackedQuestID` | guarded probes for other flavors |
| `LE_EXPANSION_*` (12 constants) | feed `guide.expansion` (`WoWPro_GuideRegistry.lua:309`), read only by the guide-list UI |
| `FACTION_HORDE`, `FACTION_ALLIANCE`, `OKAY`, `CANCEL`, `GameFontNormal`, `GameFontNormalSmall`, `BackdropTemplateMixin` | UI strings, fonts and templates |
| `GetBindLocation` | guarded probe (`WoWPro_Events.lua:249`). The hearth location is player state for a later plan, so `WoWProDB.char.hearth` stays unset. |

Frame methods the mock doesn't model show up as `Frame:<Name>`, and
unstubbed namespaced APIs show up as `<Namespace>.<Field>`. The Dwarf boot
has neither.
