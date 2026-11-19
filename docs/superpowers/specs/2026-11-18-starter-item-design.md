# Item-started quests hold their starter item

Status: approved in conversation · 2026-11-18. Small change.

## Intent

In the game you can only accept an item-started quest by using the item, so you already hold it. Stolen Blasting Powder (95213, `01_12_Dun_Morogh.lua:313-314`) starts from a looted Empty Powder Keg (268548), and the keg is also its only objective. The harness accepts the quest without the keg ever being in the bags. That causes three findings that are harness bugs, not guide bugs:
- the turn-in is refused as incomplete
- the quest is left in the log
- the next quest (95214) is never offered

The user's principle: emulate the engine underneath, and never fail a step a player could do.

## Rule

- **On accepting a quest whose QuestieDB starter is an item** (catalog `starter_kind == "item"`, `starter = <item id>`): make sure that item is in the bags **before** the accept events. The player looted it and used it to start the quest. Fire `BAG_UPDATE` for it.
- **If it's already there,** add nothing.
- **Never remove the item.** Whether the game consumes a starter item on accept is unverified for Forever.
  - In QuestieDB, 162 of the 386 item-started quests name the starter item as an objective. For those the item must stay.
  - For the others, leaving it in the bags is harmless.
- **This sits alongside the existing `source_item` rule** (the quest starter hands over an item on accept), which is unchanged.

## Approaches

1. **(Chosen)** Give the starter item at the accept, from QuestieDB `startedBy` items. Faithful, small, and data-driven.
2. Simulate looting the item from its drop NPCs before the accept: kills, drop rates, XP. This is more faithful to XP, but the guide's own step ("From Rockjaw Bonesnapper") already abstracts the loot. It's a larger change for little gain. Rejected.
3. Credit the objective without the item. This isn't what the engine sees, since the turn-in checks the bags. Rejected.

## Constraints

- Data only from QuestieDB and the run. Never patch the guide or the addon.
- Deterministic. luacheck 0.
