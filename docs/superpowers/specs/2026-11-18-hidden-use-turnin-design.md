# A player performs a hidden use step when the turn-in needs its item

Status: approved in conversation · 2026-11-18 · Small change.

## Intent

The harness emulates the game underneath the guide; it never corrects the guide. In
`19_25_Alliance.lua` (#3554), WoWPro hides `U Divined Scroll|QID|1016|U|5456|L|5455|`
(an L-gated use step, `WoWPro_Broker.lua:2182`) and moves straight to `T Elemental Bracers`.
The hidden step is the guide bug, and `hidden-use-step` correctly reports it.

But the player isn't blocked. When the turn-in fails because quest 1016 needs the Divined
Scroll (5455), they combine the scroll themselves and turn in (user, in game, 2026-11-18).
Today the harness treats the player as stuck, which adds `did-not-advance` and
`leftover-quests` follow-on findings that don't happen in game.

## Rule (user decision)

When a `T` step's turn-in is refused with reason `incomplete`, **and** a required item
objective of that quest is short in the bags, **and** the guide loaded now has a `U` step
for the same quest that:
- has not been shown (`info.seen` is false),
- is held back by WoWPro for missing items (its `why` contains `run.HIDDEN_USE_WHY`), and
- has an `L` result naming that short item,

then the driver performs that `U` step's action (the existing U-step code in
`actions.lua`) and retries the turn-in once.

In every other case nothing changes. A turn-in refused for any other reason, or with no
such hidden step, gets today's findings. The guide never cares about a missing step for
advancing.

## Effects

- `hidden-use-step` is still reported. Performing the step off-guide doesn't mark it shown.
- No `did-not-advance` / `leftover-quests` for the quest when the retry succeeds.
- The run log records each off-guide action:
  `log.offguide = { { gid, file, line, qid, action = "U", for_step = <T line> } … }`.
  It's logged like the Camping 101 abstracted turn-in.
- The #3554 anchor is unchanged: the U step is hidden on `main` and shown on the fix branch.

## Approaches

- **Emulate the player's fallback at the refused turn-in (chosen).** It keeps the guide as
  the test subject, and the finding that reports the bug.
- **Correct the quest data** (objective 12220 ×5): rejected. QuestieDB is right, because
  the scroll is required.
- **Drop `hidden-use-step` when the quest still completes:** rejected. The hidden step is
  the bug.

## Constraints

- Only the driver changes (`src/hwc/driver/run.lua`, plus `actions.lua` only if it needs
  exposing), with specs in `spec/driver/run_spec.lua`.
- Real check: a Dwarf Warrior run keeps the `hidden-use-step` at `19_25_Alliance.lua:449`
  (quest 1016) and drops the `did-not-advance` at :450 and the `leftover-quests` for 1016.
- The slow suite must still pass, including the #3554 anchor.
