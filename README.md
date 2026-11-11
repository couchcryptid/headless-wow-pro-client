# headless-wow-pro-client

Loads the real WoW-Pro addon (Lua 5.1) under LuaJIT outside the game.
The addon is read-only input, read from a configured path
(default `~/Projects/WoW-Pro-Guides`).

- Run: `bin/hwc --help`
- Test: `~/.luarocks/bin/busted` (the integration specs are pending when the
  addon checkout is absent)

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
