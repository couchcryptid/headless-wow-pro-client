# Say what happened to a missing prerequisite

Status: approved in conversation · 2026-11-18 · Small change.

## Intent

An accept refused for a prerequisite reads "…needs quest 98387 "Blackrock Blockade", which
isn't done yet." That doesn't say *why* it isn't done. For Tharil'zun (`25_30_Alliance.lua:85`,
quest 19, `pre_group` {20, 98387}), no Forever guide offers Blackrock Blockade at all, so the
quest is never accepted. That's the guide bug (the user confirmed it in game, 2026-11-18). The
user asked for wording that mirrors the hidden-accept sentence's "is never completed".

## Rule

For each missing prerequisite id on an `accept-refused` / `prerequisite` finding, the run's
outcome for that quest, decided at the end of the run from the quest log:
- **`never-accepted`:** never accepted during the run. Ending: `which is never accepted`.
- **`never-completed`:** accepted at some point, never completed. Ending: `which is never completed`.
- **`completed-later`:** completed, but after this refusal. Ending: `which isn't done until later in the run`.

Sentences:
- **One missing quest:** `The guide shows this accept, but the quest data says it needs quest
  98387 "Blackrock Blockade", which is never accepted.`
- **Several, all required (`pre_group`):** each gets its own ending, joined with `, and `:
  `…needs quest A "…", which is never accepted, and quest B "…", which is never completed.`
- **Any-of (`pre_single`, 2+ ids):** if all share one outcome, `…needs one of quest A or quest
  B, none of which is ever accepted` / `…none of which is ever completed`. If the outcomes are
  mixed, list them as above, joined with `, or `.
- A finding with no recorded outcome (e.g. an older findings file) keeps today's wording.

## Constraints

- Outcomes come from the run's own quest log: the accept and turn-in records plus history, with
  turn-in order compared with the refusal's step number. Never from guide text.
- Findings format 2, with additive fields (`missing_outcome = { ["<id>"] = "never-accepted" | … }`).
  Finding ids unchanged. Deterministic.
