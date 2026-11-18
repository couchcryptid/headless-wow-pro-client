# Reputation from quest rewards

Status: draft for review · 2026-11-18 · Branch `fix/xp-to-60` (reputation steps are only
reached once characters level past 26).

## 1. Intent

With XP to 60, a Dwarf Warrior run now reaches `30_41_Alliance.lua` and stalls at line 542.
WoWPro's `NextStep` evaluates `C Strange Alliance|…|REP|Gelkis Clan Centaur;91;hated-neutral|`
(line 544). Its reputation check calls `C_Reputation.GetFactionDataByID`
(`WoWPro_CompatUtil.lua:240-243`), which the harness doesn't define, so every guide refresh
crashes and the active step never moves.

The user wants reputation modelled the way XP is: points per faction, standings derived
from points, and gains from **quest reputation rewards only** (QuestieDB `reputationReward`).
Kills and item turn-ins are not modelled.

**Success:**
- The Dwarf Warrior run plays past line 544 and evaluates every `REP|` step against a real
  standing.
- Quests gated on reputation (QuestieDB `requiredMinRep`/`requiredMaxRep`) are refused when
  the standing is out of range, and that refusal is a finding with its own reason.
- `REP` tags that name the wrong faction show up as findings.

## 2. Facts and their evidence

Every rule below names its source. A Classic-only source is labelled **unverified for
Forever** in code and README (memory: Forever is not Classic).

| Fact | Value | Evidence |
|---|---|---|
| API | `C_Reputation.GetFactionDataByID(id)` returns a table or nil; `GetFactionInfoByID` is **nil** | Forever client, `/dump`, 2026-11-18 |
| Unmet faction | `GetFactionDataByID` returns nil | Forever: Orgrimmar (76) on a Human |
| Scale | Points are cumulative with Neutral starting at 0. Neutral 0–3000, Friendly 3000–9000, Honored 9000–21000 | Forever: Gelkis 2000 in 0–3000; Ironforge/Stormwind in 9000–21000 |
| Other bands | Hated −42000…−6000, Hostile −6000…−3000, Unfriendly −3000…0, Revered 21000–42000, Exalted 42000–42999 | Band widths from warcraft.wiki.gg/wiki/Reputation; **unverified for Forever** |
| `reaction` | 1 Hated … 4 Neutral, 5 Friendly, 6 Honored, 7 Revered, 8 Exalted | Forever: 4 at 2000, 5 at 3100/4000, 6 at 9475/16362; 1-3, 7 and 8 **unverified for Forever** |
| Dwarf start | Ironforge (47) 4000, Gnomeregan Exiles (54) 3100, Darnassus (69) 3100, Stormwind (72) 3100, Alliance (469) 3300 | Forever: fresh level-1 Dwarf, 2026-11-18 |
| Orc start | Orgrimmar (76) 4000, Thunder Bluff (81) 3100, Darkspear Trolls (530) 3100, Undercity (68) 500, Horde (67) 3500 | Forever: fresh level-1 Orc, 2026-11-18 |
| Undead start | Undercity (68) 4000, Orgrimmar (76) 2000, Darkspear Trolls (530) 2000, Thunder Bluff (81) 500, Horde (67) 3500 | Forever: fresh level-1 Undead, 2026-11-18 |
| Headers | Alliance (469) and Horde (67) report `isHeader` true, `isHeaderWithRep` false | Forever, 2026-11-18 |
| Met at | Gelkis Clan Centaur (92) 2000, Magram Clan Centaur (93) 2000 | Observed in Forever (level-29 Human, no centaur quests) |
| Known on first reward | A faction becomes known on its first quest reward | **Inferred** |
| Faction 91 | Galak Centaur, not Gelkis | Forever, user, 2026-11-18 |
| Gains | `reputationReward` `{ {factionId, value}, … }`, negative values allowed (e.g. 1382: Gelkis +100, Magram −500) | QuestieDB (Forever) |
| Gates | `requiredMinRep` / `requiredMaxRep` `{factionId, value}` on the same scale | QuestieDB (Forever) |
| Racial bonus | **None.** Human Diplomacy was removed in Forever | User, 2026-11-18 |
| Reward scaling | Rewards apply in full, regardless of level | **Unverified**: no source either way |

## 3. Goals, non-goals, anti-goals

**Goals**
- A pure rules module, like `xp.lua`: bands, the `reaction` for a point value, starting tables,
  and met-at values, each with its source.
- World state: points per faction, which factions are known, gains on turn-in.
- The `C_Reputation` stub WoWPro calls, returning nil for unknown factions.
- Accept gates from `requiredMinRep`/`requiredMaxRep`, with a `reputation` refusal reason.
- A Lua error that indexes a global the harness never defined is a harness error, not an
  addon one.

**Non-goals**
- Reputation from kills, item turn-ins, cloth donations or other repeatables.
- Faction "encounters" from exploring or aggro. A faction becomes known only through a
  quest reward.
- Reputation UI APIs WoWPro doesn't call.

**Anti-goals**
- Inventing a Forever fact. Unknown starting values are labelled assumed in the report's
  "About this run", never silently guessed.
- Reputation affecting XP or anything other than reputation.

## 4. Behaviour

### 4.1 Rules module `src/hwc/world/reputation.lua` (pure)

- `reputation.BANDS`: the eight bands with lower and upper bounds as in §2, Exalted's upper
  bound 42999 (the cap). Each band is marked verified or not.
- `reputation.standing(points) -> reaction, lower, upper`. A value at a lower bound belongs
  to that band, so 3000 is Friendly.
- `reputation.clamp(points)`: between −42000 and 42999.
- `reputation.START[race]`: `{ [factionID] = points }` for the factions a fresh character
  of that race has. `Dwarf`, `Orc` and `Undead` are captured. Other races use the inferred
  tables in §4.6.
- `reputation.MET_AT[factionID]`: the value a faction starts at when first met. Gelkis and
  Magram are 2000 (observed in Forever on a level-29 Human with no centaur quests; that a
  faction becomes known on its first quest reward is inferred). Any other faction falls back to **0 (Neutral), assumed**, and
  the run reports it (§4.5).
- `reputation.NAMES[factionID]`: display names, built from QuestieDB's
  `corrections/enum/factions.lua` constants (`GELKIS_CLAN_CENTAUR` → "Gelkis Clan
  Centaur"). Read at catalog load, never committed. An id with no constant (91, Galak, has
  none) is shown as "Faction <id>" (my call).

### 4.2 World state

- `Player` (or a new `world.reputation` object; builder's call) holds `points[factionID]`
  for known factions, initialised from `START[race]`.
- On every successful turn-in (`QuestLog:turn_in`), for each `{faction, value}` in the
  quest's `reputation_reward`:
  - if the faction is unknown, it becomes known at `MET_AT[faction]` (or the assumed 0);
  - then `points = clamp(points + value)`.
- No event is fired: WoWPro doesn't listen for `UPDATE_FACTION` (no occurrence in the addon,
  checked 2026-11-18). It reads reputation when `NextStep` evaluates a `REP` step.
- The run log records each change: quest, faction, value, the new total, and whether the
  starting value was assumed.

### 4.3 Catalog

`build_quest` adds:
- `reputation_reward`: an array of `{ faction = id, value = n }` from QuestieDB
  `reputationReward` (supplement may override).
- `min_rep` / `max_rep`: `{ faction = id, value = n }` from `requiredMinRep` /
  `requiredMaxRep`.

`hwc quest <id>` shows them.

### 4.4 Stub

`env.C_Reputation = trap(sb, "C_Reputation", { GetFactionDataByID = … })`:
- An unknown faction returns nil.
- A known faction returns `{ factionID, name, reaction, currentStanding = points,
  currentReactionThreshold = lower, nextReactionThreshold = upper, hasBonusRepGain = false,
  isHeader = (id is 469 or 67), isHeaderWithRep = false, isWatched = false, isChild = false,
  atWarWith = false, canToggleAtWar = false, isCollapsed = false, canSetInactive = false,
  description = "" }`.
- `GetFactionInfoByID` stays undefined, as in Forever.

Any other `C_Reputation` member WoWPro reads goes through `trap`, so it shows up as a
missing global, not a crash.

### 4.5 Accept gates and findings

- `QuestLog:refusal` returns `reputation` when `min_rep` is set and the faction's points are
  below the value, or when `max_rep` is set and the points are at or above the value.
  Required level and prerequisites are checked first, in today's order.
- An unknown faction is compared at its `MET_AT` value (0 when assumed), because the server
  holds a value before the client lists the faction (my call). A negative `min_rep` passes,
  as it does in game.
- **A reputation refusal is an `accept-refused` finding with reason `reputation` and
  confidence `unverified`** (user decision, 2026-11-18). Its sentence says reputation from
  kills, item turn-ins and encounters isn't modelled, so a real player may have the standing.
  The driver treats it like `below-level`: it clicks the step off and carries on.
- **A `REP|` step whose faction the character never met is a finding, confidence
  `unverified`** (user decision, 2026-11-18). The new signal `rep-faction-unmet` names the
  faction id and the guide line, and its sentence says the faction was never met and that
  kill and exploration reputation isn't modelled. The stub records each id it returned nil
  for (`unmet_lookups`) at lookup time, so a faction met later in the same guide still
  counts; the signal fires for a step the run reached (below `Driver:close`'s limit) whose
  `REP` id is in that set. Its title names the tag's own faction name (first `;` field,
  trimmed) and the checked faction: "REP step names Gelkis Clan Centaur but checks
  Faction 91, which this character never met". This is what surfaces
  `REP|Gelkis Clan Centaur;91;…` (Galak) at `30_41_Alliance.lua:544`.
- `text.lua` gets the label `reputation` → "Reputation too low/high", and a sentence naming
  the faction, the standing needed and the character's standing.
- About this run, Gaps: "reputation is gained from quest rewards only (no kills, item
  turn-ins or encounters)" goes in the static `report.GAPS`. Each assumption in force for this
  run is appended to the findings header's existing `gaps` array (no format change, and
  `hwc diff` is unaffected; my call):
  - "reward scaling by level is unverified for Forever"
  - "starting reputation for <race> is inferred, not captured"
  - "factions first met at an assumed Neutral 0: <names>"

### 4.6 Other races (inferred, unverified for Forever)

Dwarf, Orc and Undead are captured (§2). Until fresh-character captures exist for the
others, they use a captured table on their own side:
- Human, Gnome, Night Elf: the Dwarf table with the race's home city at 4000 and Ironforge
  at 3100 (Alliance 469 stays 3300).
- Troll, Tauren: the Orc table with the race's home city at 4000 and Orgrimmar at 3100
  (Undercity 500 and Horde 67 3500 stay).
- Skyborne has no known home faction. SkyborneAlliance: all four Alliance capitals
  (Stormwind 72, Ironforge 47, Gnomeregan Exiles 54, Darnassus 69) at 3100 plus Alliance
  469 at 3300. SkyborneHorde: Orgrimmar 76, Thunder Bluff 81 and Darkspear Trolls 530 at
  3100, Undercity 68 at 500, Horde 67 at 3500.

Home cities: Human → Stormwind, Gnome → Gnomeregan Exiles, Night Elf → Darnassus,
Troll → Darkspear Trolls, Tauren → Thunder Bluff.

Each inferred table is labelled in the run's Gaps (§4.5). A captured dump replaces it row
for row.

### 4.7 Harness-error classification

`boot.is_harness_error(e)` also returns true when the message is
`attempt to index (field|global) '<name>' (a nil value)` or
`attempt to call (field|global) '<name>' (a nil value)` and `<name>` is in the sandbox's
missing-globals list for that run, `<name>` does not start with `WoWPro` (the addon's
own), and `<name>` is not in `boot.EXPECTED_ABSENT`: the APIs absent in Forever
(`GetFactionInfoByID`, in-game check 2026-11-18; retail-only probes such as
`GetQuestLogTitle`, `C_Garrison`), other addons (`Grail`, `Nx`, `TourGuide`) and
`LibStub`, which the addon ships. The sandbox records every nil global read, so `missing`
alone over-counts. `TomTom` is not in the set: the guides expect it installed, so it is a
harness gap until stubbed. The Ghost-o-plasm crash (`C_Reputation`) counts as a harness
error until the stub exists.

The list arrives as an optional second argument, `is_harness_error(e, missing)`, where
`missing` is the sandbox's `missing` set; callers that have it pass it. The match uses the
bare name, so `ns.field` keys match on their last part. An addon bug indexing a field of the
same name would also match; that's accepted as rare (my call). Findings files already
written aren't reclassified.

## 5. Constraints

- LuaJIT 2.1; no new dependencies. `reputation.lua` is pure.
- No third-party data committed. The starting tables are first-party in-game captures with
  dates. Faction names come from the installed QuestieDB at run time.
- Determinism: same inputs give the same findings, including the reputation changes in the
  run log.
- Specs at three levels:
  - rules: standing boundaries
  - world: turn-in gains, met-at, clamp
  - stub: nil for unknown
  plus a gate test. The slow anchors must still pass, with #3535 still Red.

## 6. Expected effect (to check after building)

- `C Strange Alliance` (line 544) gives a `rep-faction-unmet` finding for faction 91.

- The Dwarf Warrior run plays past `30_41_Alliance.lua:542`, with no `C_Reputation` crash.
- The stub returns nil for Galak (91), so WoWPro logs "Bad Faction number" and skips the
  step.

## 7. Left to the builder

- Whether points live on `Player` or a separate world object.
- The run-log field names.
- How `rep-faction-unmet` is detected (§4.5), with the line it relies on cited.
