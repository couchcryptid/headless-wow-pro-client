# headless-wow-pro-client: design

**Status:** draft for approval, 2026-11-11.
**Owner:** the user (Brendan). The project lives at `~/Projects/headless-wow-pro-client` and will eventually be pushed to the user's own git account.
**Inputs:** Phase 0 discovery of the WoW-Pro addon (bootstrap and load order, step engine, prior art) and the brainstorming conversation of 2026-11-11.

## 1. Why this exists

Today the only way to check a WoW-Pro guide fix is to level an alt in the game client until the step is reached. That takes an unknown amount of time, so it can't run as a regular gate. The validation work on issues #3530, #3534 and #3535 showed that many guide bugs come from how the real step engine treats guide data: `PRE`/`ACTIVE` gates, C/T quest-log checks, sticky pairs and `LVL` gates. Python re-implementations of the engine (`docs/issue-03-validation/simulate_pre.py`, the `FIX1`–`FIX6` switches in `wow-pro-leveling/sim/sim.py`) only approximate it. They drift from it, and they agree with whatever the author believed the engine does.

**The goal:** run the **real, unmodified WoW-Pro addon code** outside the game, play the guides as a simulated player who follows every step, and write down everywhere the guide breaks. This serves two purposes:

1. **Bug finding (primary).** A full Forever Alliance run from 1 to 25 for each race and class combination, to find bugs that have been missed.
2. **Red/Green for fixes (secondary).** The same scenario run against `main` (Red) and a fix branch (Green), in place of alt levelling as the CLAUDE.md Red step.

## 2. Goals, non-goals, anti-goals

**Goals**
- Load the addon's own Lua from a configurable path to any WoW-Pro-Guides checkout or worktree, so any branch can be tested. Never modify, vendor or patch it.
- Simulate a player's state well enough for the engine to make its real decisions:
  - race, class, faction, sex;
  - level and an XP bar;
  - a quest log (40 slots: confirmed as Forever's cap by the user; configurable);
  - a completed-quest history;
  - bags (item counts);
  - zone, subzone and map;
  - known flight points and hearth location;
  - professions and spells learned.
- Follow every step the engine shows, doing what each step asks.
- Gain XP from quest turn-ins and from kills, using Classic XP rules, and level up.
- Write every suspected bug to a markdown findings file for triage.
- Provide a `/triage` Claude Code skill in this repo that checks each finding against outside sources and gives a verdict.

**Non-goals (this pass)**
- **Time model.** No travel, kill or talk seconds and no hours-to-level. This is route-optimisation work, deferred to a later pass. Keep room for it without building it.
- **Route opinions.** The client doesn't add, suggest or chase quests that the guide doesn't mention, and it doesn't judge routing.
- **Horde, other guide types** (Dailies, Professions, World Events), **other flavors** (Retail, Classic Era, TBC, Mists), and Zephras Isle/Skyborne for now.
- **UI fidelity.** Frames exist only as stateful stand-ins (see §5.3). Nothing is drawn.
- **Fixing guides or the addon.** The client and triage report. People fix.

**Anti-goals (a failure even if it "works")**
- **Correcting addon bugs in the harness.** If the engine misbehaves (for example the literal `find("FHbPR")` at `WoWPro_Broker.lua:2422`, or `EnableDungeons` looking inverted), the client must reproduce that, and the misbehaviour shows up as findings. The client is faithful to the world and neutral about the addon.
- **Using the guide as the source of world facts.** Quest levels, XP, objectives and races come from the quest catalog (§6), never from guide lines. Otherwise the client would agree with every guide bug it should catch. The guide is only what's being tested.
- **Silently clicking steps off.** Every step the client completes by hand rather than through a simulated player action is logged and becomes a finding.
- **Committing licensed or third-party data** (QuestieDB, Wowhead extracts) to this repo.

## 3. Scope of the first pass

- **Flavor:** Forever only. `GetBuildInfo` returns TOC 16001, so `WoWPro.FOREVER` is true.
- **Characters:** Dwarf and Gnome, every class each race can play in Forever, as the 80/20 slice: they share the Dun Morogh start, and #3535 and the issue-01–16 work cover it best. The race and class matrix is configuration. The **class list per race must come from Forever data** (Wowhead Forever or the guides' own `C|` tags), not from Classic assumptions or memory.
- **Then:** all Alliance races: Human (Elwynn), Night Elf (Teldrassil, then Darkshore). Each race starts on its `WoWPro.Leveling.ForeverStartGuides` entry (`WoWPro_Leveling/WoWPro_Leveling.lua:49–59`). Skyborne (Zephras Isle) is listed there too but is out of scope until the user says otherwise.
- **Guide chain:** start guide, then the next guide by the engine's own `GuideNextGuide` autoload (Dun Morogh → `ClassicEasternKingdom1220` → `ClassicAlliance1925` → …). A run stops when the character reaches **level 25**, or when the engine's chain loads a guide whose range starts at or above 25, whichever comes first.
- **Professions and Camping 101 (user's decision, 2026-11-11):** all Camping 101 profession quests are in scope. The quests that require the profession to be trained first are gated on the character having that skill.
  - **In the world model:** each Camping 101 quest object carries a "requires skill" condition, for example First Aid, Fishing or Leatherworking. Per Wowhead, those end at the profession trainer, whose progress text gates on the skill. The quest can't be completed or turned in until the simulated character knows that skill.
  - **Camping 101: Cooking is the exception.** Its turn-in is completed by training Cooking at Gremlock (confirmed in game 2026-11-11), so training is the step's action.
  - **The guide's own `P|` tags** on the accepts are still applied by the real engine. The client doesn't override them in either direction.
  - **To exercise every Camping 101 quest,** the character matrix gets a profession dimension: a no-profession baseline, plus variants that know each Camping profession (or a small set of variants covering all of them).
  - **Findings in the profession variants:** a gated quest the guide still asks the character to turn in without the skill is recorded as `accept-refused` or `did-not-advance`. A gated quest the guide never offers when the character does have the skill is recorded as `never-shown-accept`.
  - **The exact variant set** is left to the builder (§11), provided every Camping 101 quest in the 1–25 guides is covered by at least one variant.

## 4. Architecture

Three layers. All the Lua runs in one LuaJIT (Lua 5.1) state per character run.

```
            ┌───────────────────────── one Lua state per run ─────────────────────────┐
 config ──▶ │ 1. WoW API stub environment  ◀── 2. Simulated world + player state       │
 (race,     │    (globals, frames, events,       (quest log, history, XP, bags, zone,  │
  class,    │     virtual clock)                  flight points, skills)               │
  guides,   │          ▲                                ▲                              │
  paths)    │          │ loads, unmodified              │ reads quest catalog          │
            │    WoW-Pro addon Lua (external path)      │                              │
            │          │                                │                              │
            │          ▼                                │                              │
            │ 3. Driver: read the engine's shown step → perform it in the world →      │
            │    fire events → settle the clock → record                               │
            └──────────────────────────────────┬──────────────────────────────────────┘
                                               ▼
                         run log (JSON) per character  ──▶  findings.md (all runs)  ──▶  /triage
```

### 4.1 Layer 1: WoW API stub environment

Its job is to let the addon load and run as if it were in the game, with the WoW globals it reads backed by layer 2. Discovery has listed the required surface:

- **Load-time globals** (needed before any addon file runs):
  - `CreateFrame`, `securecallfunction`, `GetTime`, `C_Timer.After`;
  - `geterrorhandler`/`seterrorhandler`, `GetRealmName`, `UnitName`, `UnitClass`, `UnitRace`, `UnitFactionGroup`, `GetLocale`, `GetCurrentRegion(Name)`, `GetBuildInfo`;
  - `GetAddOnMetadata`/`C_AddOns.GetAddOnMetadata` (for both `WoWPro` and `WoWPro_Leveling`), `date`;
  - `Enum.UIMapType` (all seven values), `C_ChatInfo.RegisterAddonMessagePrefix`, `StaticPopupDialogs`;
  - `UnitLevel`/`UnitXP`/`UnitXPMax` (guide files call `GuideLevels` → `PlayerLevel` when they load);
  - `DEFAULT_CHAT_FRAME:AddMessage`, the WoW Lua aliases (`tinsert`, `wipe`, `floor`, `strupper`…), and `string.split`/`strsplit` and `string.trim`/`strtrim`.
- **`strsplit` must be faithful.** The delimiter is a **set of characters**, not a pattern (`("^&"):split(...)`). Empty pieces between adjacent delimiters are kept and counted by `select("#", …)`. The optional piece limit is honoured. A wrong polyfill silently corrupts QID parsing, so it gets its own tests.
- **Virtual clock.** `GetTime` and `C_Timer.After` are backed by a simulated clock that's installed **before** the Ace libraries load, because AceTimer captures both as upvalues at load (`AceTimer-3.0.lua:30`). `settle()` advances virtual time, running timers and frame `OnUpdate` scripts in order, until the timer queue is empty. It stops on an empty queue, not on "no OnUpdate work", because the lockdown `OnUpdate` handler runs forever. Bucket coalescing and the 0.1 s quest-log snapshot refresh are real behaviour, so they're kept.
- **Frames.** A permissive `CreateFrame` mock that keeps state: Show/Hide/IsVisible, scripts, registered events, and any-method-returns-self for UI calls. Several engine paths read `WoWPro.rows[n].index` and `IsVisible()`, and `UpdateGuideReal` requires `GuideFrame:IsVisible()`. See §5.3.
- **Event bus.** `RegisterEvent` on any frame subscribes it, and firing an event delivers it to every subscribed frame, including AceEvent's and AceBucket's.
- **Error policy.** `geterrorhandler` returns a handler that **records and re-raises**, so errors swallowed by AceAddon's `safecall` and WoWPro's wrapped handler (`WoWPro.lua:200–212`) still surface. An addon Lua error is a finding, not a harness crash: the run records it with its stack and continues if it can.
- **Missing-global trap.** Reads of undefined globals are allowed, because the addon probes optional globals such as `TomTom`, `Grail` and `C_QuestInfoSystem`. Each name is logged once per run so missing stubs can be found. Writes to globals are allowed, since the addon creates `WoWPro`, `WoWProDB` and so on.
- **Libraries.** Load the real vendored LibStub, CallbackHandler, AceAddon, AceEvent, AceBucket, AceTimer and AceDB from the addon path. Stub HereBeDragons-2.0 and HereBeDragons-Migrate through LibStub (WoWPro uses only `GetZoneSize`/`GetZoneDistance`), with values derived from zone data. Skip the UI libraries (AceGUI, AceConfig, AceDBOptions, LibSharedMedia, LibDataBroker, LibDBIcon, HBD-Pins) and LibPetJournal/`WoWPro_Pets.lua`.

### 4.2 Loading the addon

- Parse `WoWPro/WoWPro.toc` and `WoWPro_Leveling/WoWPro_Leveling.toc` ourselves, expand XML `<Script file=…/>` and `<Include …/>`, and substitute `[Game]` = `Forever`, matching on-disk case. Run each file as a chunk with the addon varargs (`addonName`, private table), in TOC order.
- **Skip list** (UI-only, from discovery): Templates, Widgets, GuideList, CurrentGuide, Tutorial, Config, Command, Pets, `WoWPro_Leveling_Config`, `WoWPro_Leveling_Frames`. `WoWPro_Frames.lua` and `WoWPro_RowUpdate.lua` **are loaded**, because row state is part of the engine's behaviour. The skip list is configuration, and each entry records why it's skipped.
- **Stand-ins for what skipped files define and the engine calls:** `WoWPro.RefreshConfig` and `WoWPro.SetDefaults`, which `OnInitialize`'s AceDB callbacks require. Without them CallbackHandler errors (`CallbackHandler-1.0.lua:101–102`). Also `WoWPro:InitializeTutorial` and `QueueTutorial`, `CreateConfig`, and minimap and binding calls. Each is a no-op that logs, kept in one file so they're easy to review.
- **Guides:** load all Forever `Alliance` and `Neutral` `Guides.xml` files as the TOC does. Faction filtering is the engine's (`WoWPro_GuideRegistry.lua:266`).
- **Saved variables:** start each run with a fresh character: `WoWProCharDB = { QID2Guide = {} }` before the guide files load, and AceDB creating the rest. Pin `WoWProCharDB.DebugLevel = 0`, because the default of 1 turns `;` comment lines into steps (`WoWPro_Parser.lua:691`) and changes step indices. Seed `math.random` (`SelectHearthstone`).

### 4.3 Boot sequence

1. Install stubs, the virtual clock, frames and the event bus, then set the character and world.
2. Load the libraries, then the addon files in TOC order.
3. Fire `ADDON_LOADED("WoWPro")` and `ADDON_LOADED("WoWPro_Leveling")`, set `IsLoggedIn()` to true, and fire `PLAYER_LOGIN`. AceAddon then runs `OnInitialize` and `OnEnable` for the addon and its module.
4. Fire `PLAYER_ENTERING_WORLD`, then `settle()` until the lockdown releases. `WoWPro.LoadGuide()` then loads the race's start guide through the real Leveling `OnEnable` path.

**Open for the builder:** let the real `OnEnable` run behind frame stand-ins, or replace it with the minimal equivalent discovery describes (tag tables, `Nickname2Guide`, `Leveling:RegisterGuide` per guide). Prefer the real `OnEnable`, and fall back only for parts that can't run headless. Record which parts fell back.

### 4.4 Layer 3: the driver loop

```
boot; settle()
loop until stop condition:
  idx   = WoWPro.ActiveStep                    -- plus the visible rows from WoWPro.rows[*]
  record(step snapshot: idx, action, step text, QID, tags, why[], completion, skipped, rows, log, level/xp)
  outcome = world:perform(step)                -- §5.2: change the fake world the way a player would
  fire the matching event(s); settle()
  if the engine did not advance:               -- the player's action didn't move the guide
      record a "did-not-advance" finding; CompleteStep(idx, "Right-Click"); settle()
  watchdogs: same step N times, wall-clock or virtual-time limits, error count
```

- The **shown step** is whatever the real engine shows: `ActiveStep` plus the row state. The driver never chooses steps itself.
- **Stop conditions:** level 25 reached; the guide chain passes the 1–25 range; the engine reports no next guide; or a watchdog fires. Any watchdog stop is a finding.
- **Skipped steps** are recorded with the engine's own reason (`WoWPro.why[i]`), so "hidden because a PRE wasn't met" is visible.

## 5. Layer 2: the simulated world and player

### 5.1 Player state

| State | Backs | Notes |
|---|---|---|
| race, class, faction, sex | `UnitRace`, `UnitClass`, `UnitFactionGroup`, `UnitSex` | fixed per run; token forms as the client returns them (e.g. `"Dwarf","Dwarf"`) |
| level, XP, XP max | `UnitLevel`, `UnitXP`, `UnitXPMax` | Classic XP-to-next-level table to at least level 26 (sourced and checked; the old simulator's `TNL` covers 1–23) |
| quest log | the quest-log API under `PopulateQuestLog` (§5.4) | 40 slots (Forever's cap, confirmed by the user; configurable); accept adds, turn-in removes and records, abandon removes |
| completed history | `C_QuestLog.IsQuestFlaggedCompleted` (+ OnAccount/ForAccount = false) | the engine queries it with force=true, so this is the truth it sees |
| bags | `GetItemCount`/`C_Item.GetItemCount` (ids, numeric strings and **item names**; `B` steps pass step text) | |
| zone, subzone, map, position | `GetZoneText`, `GetSubZoneText` (always strings), `C_Map.GetBestMapForUnit`, `GetPlayerMapPosition():GetXY()` | position = the step's `M` coordinate when it has one |
| flight points, hearth | taxi API for `TAXIMAP_OPENED`, `GetBindLocation` | |
| professions, spells | the skill and `IsPlayerSpell`/`GetSpellInfo` APIs, or a seeded `WoWProCharDB.Tradeskills` | trained only when a step asks |
| combat, group, buffs | `InCombatLockdown()=false`, `IsInGroup()=false`, no auras | |

### 5.2 What "doing a step" means

Each step action maps to world changes and the events the real game fires. The sequences come from discovery (`WoWPro_Events.lua` and `WoWPro_AutoComplete.lua`). Builders should check the order against the handler code.

| Step | World change | Events |
|---|---|---|
| `A` accept | refused if the log is full or the catalog says the character can't take it (level, race, class, prerequisite; the refusal is a finding); otherwise add the quest with its catalog objectives | `QUEST_ACCEPTED(logIdx, qid)`, `QUEST_LOG_UPDATE` |
| `C`/`K` objective | complete the step's `QO` objectives, or all of them if it has no `QO`; for kill objectives credit mob XP (§5.5); for item objectives add the items to bags | `QUEST_LOG_UPDATE`, `BAG_UPDATE` as needed |
| `T` turn in | record as completed, add quest XP, remove from the log | `QUEST_TURNED_IN(qid, xp, money)`, then `QUEST_LOG_UPDATE` |
| `R`/`F`/`b`/`P`/`H` travel | set zone, subzone, map and position to the step's `Z`/`M` (and step name for subzone matches) | `ZONE_CHANGED_NEW_AREA` (and `ZONE_CHANGED`); for `F` the taxi events |
| `f` get flight point | add the flight point | `UI_INFO_MESSAGE(ERR_NEWTAXIPATH)` |
| `h` set hearth | set bind location | `HEARTHSTONE_BOUND` |
| `B` buy / `l` loot / `L`-tag item | add items | `BAG_UPDATE` |
| `U` use item | apply the step's effect: objective progress, item consumed or created per `U`/`L` tags | `BAG_UPDATE`, `QUEST_LOG_UPDATE` |
| grind (`L` level step / `LVL` gate) | kill generic mobs at the character's level until the target is met; credit mob XP | none directly; force `UpdateGuide` after each level-up |
| train skill / spell | add the skill or spell | `SKILL_LINES_CHANGED` + `SPELLS_CHANGED` |
| `N` note, `D` done, sticky with nothing to do | no world change | none; the driver's manual-completion path applies and is logged |

- **When the world refuses an action (user's decision, 2026-11-11):**
  - **Race, class, missing prerequisite or full log:** the world stays truthful. The quest never enters the log or the history. Its later steps become `orphan-turnin`, and anything gated on it stays hidden. Those downstream findings are **linked to their root-cause finding** ("caused by F-…"), so one guide bug reads as one finding with its consequences listed under it, not dozens of separate ones.
  - **Under-levelled only:** the player grinds to the quest's required level (generic mobs at their own level, mob XP credited), then accepts. A `below-level` finding is recorded at **medium-high severity, tagged for routing triage**. The guide sent the player to a quest they couldn't take yet.
- **Camping 101 quests (user's decision, 2026-11-11):**
  - **On accept, the client immediately completes and turns in a Camping 101 quest**, crediting its XP. The real objective is to level the profession to 20, and players do that in many ways: farming materials, the auction house, materials mailed from another character. The client abstracts it.
  - This is the one place the client acts on a quest without a guide step. It's logged as an `abstracted-turnin` event, not a finding.
  - **Gate:** quests that require the profession to be trained first (§3) are turned in only when the character knows that skill. Otherwise they stay in the log and surface as `leftover-quests`.
  - Camping 101: Cooking keeps its guide steps (train at Gremlock, then turn in) if the guide has them. The immediate turn-in applies only when the guide has no turn-in step for the quest.
- **Level-up:** the addon has no level-up handler, so after every ding the driver forces `WoWPro:UpdateGuide("sim:level")`.
- **Elites:** there's no party (solo). Elite kill steps succeed, flagged as elite, with mob XP ×2 split by a configurable party size (default 1, as in the old simulator). Each elite step is noted in the run log so "the guide expects a solo player to kill an elite" stays visible.

### 5.3 Frames and rows

`WoWPro_Frames.lua` and `WoWPro_RowUpdate.lua` run against the frame mock, so `WoWPro.rows[i].index`, visibility, `GetActiveStickyCount()` and `GuideFrame:IsVisible()` behave as the engine expects. The guide frame is shown. Rows exist up to the engine's normal count.

### 5.4 Quest log API (fake underneath, not injected)

Fake the WoW quest-log API that `PopulateQuestLog` (`WoWPro_Broker.lua:3991–4152`) reads; never write `WoWPro.QuestLog` directly. The engine's old/new log diff (`oldQuests`, `delta`, `missingQuest`) drives turn-in and abandon detection, and `QUEST_LOG_UPDATE` returns early when there's no change (`WoWPro_Events.lua:892`). The surface is about 9 functions:
- `QuestLog_GetInfo` (Classic `GetQuestLogTitle` 17 values or `C_QuestLog.GetInfo`, whichever the compat layer selects for Forever). It **must return nil past the end**, or the loop never ends.
- `GetNumQuestLeaderBoards`, `GetQuestLogLeaderBoard`, `C_QuestLog.GetQuestObjectives` (`text`, `finished`, `type`, `numFulfilled`, `numRequired`), `IsComplete`/`QuestLog_IsComplete` (1/-1/nil), `GetQuestProgressBarPercent`.

### 5.5 XP rules

From the existing simulator (`wow-pro-leveling/sim/sim.py`), all Classic rules. Builders should check them against a cited source before use:
- **Quest XP:** catalog XP × level-difference factor. ×1 up to 5 levels over the quest level, then ×0.8, 0.6, 0.4, 0.2, and ×0.1 beyond.
- **Mob XP:** `level × 5 + 45`.
  - Mobs above the character's level: +5% per level, up to 4 levels.
  - Mobs below: reduced by the zero-difference table, and 0 at or below grey level.
  - Elites: ×2.
- **Mob levels:** catalog NPC level (mid of min/max).
- **Item-drop objectives:** for the XP from the kills it takes, the kill count is the number of kills to collect the needed items with 90% confidence at the catalog drop rate, with the overrides file correcting rates. A named elite with one or two spawns always drops. Generic grind mobs are at the character's level.
- **Not modelled this pass:** rested XP, Forever's Boosted Rest from campfires, and party XP for non-elites. Each is a deliberate gap, listed in every findings file header.

## 6. The quest catalog (world facts)

A quest is an object: id, name, quest level, required level, races, classes, prerequisites (single and group), objectives (kind npc/item/object, ids, count, text), XP reward, starter and ender. NPCs are objects with level range, rank (elite) and spawns. Items have drop sources and rates.

- **Sources, in priority order:**
  1. The Wowhead Forever extract (`wow-pro-leveling/sim/data/wh.json`: xp, level, reqlevel, reqrace, reqclass for 476 quests, including Forever-only 9xxxx quests) and its `objs.json` (objective → target) and `rate_overrides.json`.
  2. QuestieDB Forever (quest, NPC, item and object DBs, plus the `QuestXP` support file) at a pinned commit.
  3. A small, hand-checked supplement for quests missing from both, built with the triage skill's Wowhead method.
- **Pins and provenance (my call, after the builder check):**
  - Pin QuestieDB at `d57637f490c9dfcdbbc967dab47a8b0d8fe1b3cc`, the commit used for the #3535 validation. Fetch its `data/Forever/*` and `support/Forever/QuestXP/*` files (QuestXP is the per-quest XP source above level 20, where `wh.json` thins out: only 20 of its 476 quests are level 20 or above).
  - The provenance of `db2.pickle` is unclear: it holds 872 quests with ids of 90000 or more, which pinned QuestieDB Forever lacks. The builder traces it from the wow-pro-leveling docs. If it can't be traced, it's used only as a cross-check, never as a primary source.
- **Precedence is per field, not per source (my call):** carry over the old simulator's evidence-based rules (`sim.py:804–817`).
  - Wowhead's race masks are unreliable on Forever-added 9xxxx quests (Elwynn quests listed as Gnome/Night Elf only), so race comes from QuestieDB where it has the quest.
  - Class is only partly trusted from Wowhead.
  - Each rule is written in the catalog code with its citation. A disagreement between sources on a field is noted on the quest object, so triage can see it.
- **A quest missing from every source** gets placeholder values: required level 1, no race or class limits, objectives taken from the step's `QO` numbers, 0 XP. Every finding touching it is marked **"unverified quest data"**. The run continues.
- **Licensing and storage:** catalog sources are read from **external paths given in configuration** and never committed here. QuestieDB is GPLv3 only for consenting contributors and "all rights reserved" otherwise. Wowhead data isn't openly licensed. A one-time exporter converts the old simulator's Python formats (`db2.pickle` is a pickle) into a plain JSON or Lua catalog under a gitignored local directory. The exporter itself is committed; its output isn't. Each catalog records its source commit or date and a SHA-256.
- **Known source gaps** (also checked by triage): QuestieDB Classic and Forever swap quests 26 and 27; QuestieDB Forever has no 9xxxx quests; Wowhead tooltips round coordinates to 0.2.

## 7. Findings

### 7.1 Signals the client records

| Signal | Meaning |
|---|---|
| `never-shown-accept` | an `A` step was skipped for the whole run, with the engine's reason (e.g. `PRE&(...): A mandatory prereq was not met: 96629`) |
| `orphan-turnin` | a `T` (or `C`) step for a quest the character never had |
| `did-not-advance` | the simulated action didn't move the engine; the driver clicked the step off |
| `stuck` | the same step was active past the watchdog limit, or no step could be advanced |
| `log-full` | an accept was refused because the log was full |
| `accept-refused` | the catalog says the character can't take the quest (level, race, class, prerequisite) but the guide shows the accept |
| `below-level` | an accept shown while the character is below the quest's catalog required level; the player grinds, then accepts. **Severity medium-high, tagged `needs-routing-triage`** (user's decision) |
| `wrong-race-class` | a step shown to a race or class the catalog excludes |
| `leftover-quests` | quests still in the log when a guide in the chain ends, or at the end of the run |
| `lua-error` | the addon raised an error (with stack) |
| `missing-global` | the addon read a WoW global with no stub (harness completeness, not a guide bug) |
| `manual-completion` | any step completed by the driver rather than by an event (`N`, `D`, notes and stickies are expected and listed separately from real failures) |

### 7.2 Findings file

One markdown file per invocation: `findings/YYYY-MM-DD-<scope>.md`, for example `findings/2026-11-12-forever-alliance-dwarf-gnome-1-25.md`.
- **Header:**
  - the addon repo path, branch and commit;
  - the catalog sources, with commit or date and hash;
  - the client version;
  - the character matrix;
  - the non-modelled gaps (§5.5).
- **One finding per suspected defect, not per character:** grouped by guide file, line and signal, with the list of affected race/class combinations. "Only Gnome Warlocks" stands out by contrast.
- **Each finding:** a severity (my call: high for hidden or unreachable quests and Lua errors, medium-high for `below-level`, medium for `did-not-advance`/`stuck`, low for `leftover-quests` and `missing-global`); root-cause links (`caused by` / `causes`); a stable id; guide file:line; step text; signal; the engine's `why`; affected combinations; the steps just before and after; the quest log and level at that moment; and a data-confidence flag (verified catalog data, or "unverified quest data").
- **Each finding has an empty `Triage:` block** for `/triage` to fill in.
- **Per-character run logs** (JSON) sit beside it, uncommitted by default, so any finding can be traced step by step.

## 8. `/triage` skill

A Claude Code skill in this repo (`.claude/skills/triage/SKILL.md`), run on demand with `/triage findings/<file>.md`.

- **Purpose:** check each finding against outside sources and record a verdict and its evidence in the finding's `Triage:` block. It does **not** fix guides, edit the addon repo, open issues or push anything.
- **Verdicts:**
  - `guide-bug`: the guide data is wrong.
  - `engine-bug`: the addon code misbehaves on valid guide data.
  - `sim-error`: the client or its catalog modelled the world wrong. This feeds back into the client.
  - `not-a-bug`: expected or intended behaviour.
  - `needs-routing-triage`: the guide data isn't wrong, but its routing puts the player somewhere they can't progress yet (every `below-level` finding starts here). It goes to the later route-optimisation work.
  - `needs-human`: only the game, or a human check like a CAPTCHA, can settle it. These come with exact in-game repro steps.

  Each verdict has a confidence and cited evidence: quoted raw data, file:line, URL.
- **Agents and models:**
  - **Lead:** runs at the session's model (Opus). It groups findings that share a question (for example every finding touching quest 314), dispatches work and writes verdicts. It **never takes a subagent's claim without the quoted raw data**.
  - **QuestieDB reader:** Sonnet, read-only. Reads the pinned catalog files from the external path and quotes raw rows.
  - **Guide cross-checker:** Sonnet, read-only. Compares other WoW-Pro flavors (Vanilla, TBC, Horde copies), checks `git log -S` for where a line came from, and reads engine code for `engine-bug` candidates.
  - **Wowhead reader:** Sonnet. There's **at most one at a time**, since there's one browser.
    - It uses the Claude in Chrome tools: a new tab, same-origin `fetch`, Quick Facts, Series and comments, and saves raw captures locally.
    - It paces requests 2 seconds or more apart.
    - On a "Human Verification" page it **leaves that tab open, stops, and returns** so the lead can show the user the check right away and wait. It never bypasses it and never closes that tab.
    - The browser tool blocks some output: text containing `?`, `=` or `&`, and encoded data. Don't work around that filter. Fall back to rendered page text and label it.
- **Rules written into the skill:**
  - work through findings in file order; batch by shared question;
  - external sources over in-game checks, and `needs-human` only when no source can settle it;
  - the known source gaps (§6);
  - sticky `S`/`US` coordinates are route hints, not errors (from the issue-02 review);
  - evidence stays local; nothing is committed upstream;
  - no edits outside the findings file and the local evidence directory.
- **Output:** the findings file updated in place, a summary table at the top (counts per verdict), and evidence captures under a gitignored `evidence/` directory.

## 9. Constraints and environment

- **Runtime:** LuaJIT 2.x (Lua 5.1) at `/opt/homebrew/bin/luajit`. Tests use `busted` 2.3.0, which is already installed for 5.1 at `~/.luarocks/bin/busted` (penlight, luafilesystem, dkjson available). Homebrew's `lua` is 5.5 and must not be used.
- **Language:** Lua for the stub layer, the world, the driver and the specs, since they share the state with the addon. Small offline tools (the catalog exporter, the findings renderer) may be Python 3 stdlib, run with `python3 -I`. No third-party installs without asking.
- **Addon path:** configuration, defaulting to `~/Projects/WoW-Pro-Guides`. The client reads the checkout's current branch and commit for the findings header. **Use a git worktree** for branch comparisons: the game's Forever AddOns folder is symlinked to that checkout, so switching its branch changes what the game loads.
- **Licence of this repo:** the user's choice, still to be decided. Don't copy code from GPL projects (for example Mechanic) unless the user picks a compatible licence. Reading them for ideas is fine. Ketho's vscode-wow-api (MIT) may be used to generate stub signatures and enums.
- **Determinism:** the same inputs (addon commit, catalog hashes, config, seed) give byte-identical findings.

## 10. Verification of the client itself

- **Unit specs (busted):** `strsplit`/`strtrim` semantics; virtual clock ordering; the event bus; the quest-log API contract (nil past the end, objective fields); XP rules against a table of known values.
- **Engine-in-the-loop specs, anchored on known results:**
  - **#3535 Red/Green:**
    - On `main`, a Dwarf Warrior never sees Tools for Steelgrill, Flintfire's Shipment or Farsen's Watch, and the findings name `PRE … 96629`.
    - On `fix/forever-prereq-gates` those findings are gone.
    - The issue-03 report expects 46 hidden accepts on `main` and 0 on the branch (from its Python model; the real engine may differ, and any difference is itself worth explaining).
  - **#3554 U-step:** on `main` the Divining Scroll `U` step isn't shown, and on `fix/u-step-loot-result` it is.
  - **Rhapsody Malt (QID 384):** the `C` step at `01_12_Dun_Morogh.lua:110` shows as `did-not-advance` when the malt is bought.
- **Harness completeness:** a full Dwarf Warrior run with zero `lua-error` findings caused by the harness, and the `missing-global` list reviewed.
- **CI:** later, and optional. A GitHub Actions job running the busted specs, with catalog-dependent specs skipped when no catalog path is configured.

## 11. Left to the builder

- Module layout inside the repo, and the config format (Lua table or JSON).
- Whether to run the real `OnEnable` or its minimal equivalent (§4.3, prefer the real one).
- Exact watchdog limits.
- The profession variant set for Camping 101 coverage (§3), provided every Camping 101 quest is exercised by at least one variant.
- The findings-grouping key details and the finding id scheme (must be stable across reruns).
- Which XP-table and zero-difference sources to cite, provided they're cited in the code.
- How the run log is structured, provided §7.2's fields can be produced from it.

## 12. Calls made by the author (not decided by the user; check these)

- The no-profession baseline trains only when a step says so. Profession variants start with their skill already known. (The user decided that all Camping 101 quests are in scope and that skill-requiring ones are gated on the skill; how the variants start is my call.)
- A run stops at level 25 or when the guide chain passes the 1–25 range.
- Skyborne/Zephras Isle is out of scope until the user says otherwise.
- Elite kills always succeed solo (party size 1), flagged in the log.
- Finding severities (§7.2).
- Pinning QuestieDB at `d57637f49` and per-field source precedence carried over from `sim.py` (§6).
- Quests missing from every catalog get placeholder values and an "unverified quest data" flag, and the run continues.
- The Lua core, with Python allowed only for offline tooling.
- The real Frames and RowUpdate files are loaded against a frame mock rather than replaced.
