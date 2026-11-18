# Number the parts of quest chains that share a name

Status: approved in conversation · 2026-11-18 · Small change.

## Intent

Many Forever chains reuse one name for every part ("Raene's Cleansing" is 11 quests;
"The Missing Diplomat" 17). Findings then read as one quest repeated. The user wants each
part numbered as `(part/total)`, e.g. `"Raene's Cleansing" (8/11)`. They chose that over
`- Step #`, which would collide with "step" meaning a guide line.

## Rule

- A quest is **in a named chain** when a quest with the same name is its direct
  predecessor or successor. The data comes from QuestieDB:
  - predecessor: `preQuestSingle` / `preQuestGroup` members
  - successor: `nextQuestInChain`
- **Part** = 1 + the number of same-name predecessors walked back (one predecessor per step;
  when several share the name, take the lowest id).
- **Total** = the length of the same-name run, walking forward from part 1 through
  `nextQuestInChain`, plus a guard against cycles.
- A quest with no same-name neighbour has no part number. Its text is unchanged.

Example, Raene's Cleansing: 991 (1/11), 1023, 1024, 1026, 1027, 1028, 1055, 1029 (8/11),
1030, 1045, 1046 (11/11). An Aggressive Defense (1025, which branches off 1023) has no number.

## Where it shows

- **Finding titles** that name a quest: `"Raene's Cleansing" (9/11) is never offered`.
- **Sentences** that name another quest:
  - the never-shown-accept prerequisite: `…its prerequisite, quest 1029 "Raene's Cleansing"
    (8/11), is never completed`
  - missing prerequisites on accept refusals
  - left-in-log: `Quest "Raene's Cleansing" (8/11) (1029) is left in the log`
- **Not** the step labels. They keep the guide's own text, because that's what is under test.

## Constraints

- The part and total come from catalog data only, never from guide text.
- Pure computation in the catalog (`Catalog:chain_part(qid) -> part, total | nil`).
  The driver attaches `chain = { part, total }` to signals; text renders it.
- Findings format stays 2 (additive fields). Finding ids are unchanged, since names aren't in the key.
- Determinism holds.
