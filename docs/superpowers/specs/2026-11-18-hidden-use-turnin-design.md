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
  `log.offguide = { { gid, file, line, qid, action = "U", for_line = <T line> } … }`.
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

## Part 2: a run-to step that names an objective (Cornelius)

Same principle: emulate what the game does.

`01_12_Dun_Morogh.lua:158` is `R Secure the Mountain|ACTIVE|98319|QO|1|…|N|Locate Mountaineer
Cornelius' body…|`. Quest 98319's only objective is NPC 278166, "Mountaineer Cornelius" (the
body). In game, reaching him credits the objective; anyone on the quest finds him (user,
2026-11-18). The harness's run-to action only moves the player, so 98319 stays incomplete and
13 findings cascade from it: 98319's turn-in refused, 98323 never offered, and The Reports
(291) refused for its `pre_group` {287, 98323}.

**Rule:** when an `R` step has a `QO` tag and names a quest in the log (`ACTIVE|<qid>` or
`QID|<qid>`), arriving credits a named objective's progress only when both hold:

- **(a)** the objective is not an `item` objective. Arriving never loots an item.
- **(b)** no other step in the guide loaded now works on that objective. That means no `C`,
  `K`, `U`, `l` or `B` step with that QID (whatever its `QO`), and no other step with
  `ACTIVE|<qid>` whose `QO` names the same index or that has no `QO`.

In WoWPro, `R …|QO|n` usually means "head there; this step stays up until objective n is
done", and later steps do the kills or the loot. Examples are `:209 R Shimmer Ridge|ACTIVE|315|QO|1|`
before the `C` step that loots Shimmerweed (2676), and `:214 R Frostmane Hold|ACTIVE|287|QO|1;2|`
before the `C` steps at :215-218. Crediting those on arrival would let a step pass that a
player can't do by following the guide. Cornelius (`:158`, quest 98319, no other step
covering it) still meets both conditions.

An arrival records progress only and gives **no kill XP**, because an objective credited
here is a body or person to find, and the generic objective code would otherwise credit
kills. Without a `QO`, for a quest not in the log, or for an objective that (a) or (b)
excludes, the run-to step only moves the player. The action reads the loaded guide's steps
through the engine (`engine:num_steps()` / `engine:step(j)`, as the Camping 101 turn-in
check does).

Each credit is recorded in the run log, and the list is `[]` when there are none:
`log.arrivals = { { gid, file, line, qid, objective = <index> } … }`.

*Considered and not adopted:* crediting only when the objective's NPC is unique (one spawn).
That needs spawn data the catalog doesn't carry, and (a)+(b) already gives the right answer
on every Forever case checked (`:158` credited; `:209` and `:214` not).

**Prerequisite refusals name what's missing.** `QuestLog:refusal` also returns the
prerequisite ids that aren't done. The `accept-refused` signal carries them as `missing`. Its
sentence names them ("needs quest 98323, Secure the Mountain, which isn't done"), and the
linker attaches the refusal under the missing quest's own failure: a refusal,
hidden-use-step, incomplete turn-in or never-shown accept of that id. The report then shows
one root cause.

**Expected effect (Dwarf Warrior):** 98319 completes, 98323 is offered and done, The Reports
is taken, and the chain's findings go away.

`objective-not-credited` (objectives the harness can't simulate) and faithful NPC
interactions (flight take-off and landing with real zone text, vendor buys) are a separate
plan.
