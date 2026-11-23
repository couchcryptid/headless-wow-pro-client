# Aura stub (short design)

Date: 2026-11-23. Status: approved approach (A), design awaiting review.

## Why

WoW-Pro `2026.11.21.A` adds `BUFF|1229451` (Boosted Rest) to `C The Great Outdoors`
(`01_12_Dun_Morogh.lua:112`). Any visible step with a `BUFF` tag makes the addon read the
player's auras through `WoWPro.UnitAura` (`WoWPro_CompatUtil.lua:385-400`). hwc stubs no
aura API, so the addon raises `attempt to index field 'C_UnitAuras' (a nil value)`, its
step update stops, and every Alliance run is stuck at that step. Forever `BUFF` tags:
Dun Morogh 1, Teldrassil 3, Horde Barrens 4.

## Facts (user, in game, 2026-11-23)

`/dump UnitAura, C_UnitAuras and C_UnitAuras.GetAuraDataByIndex` printed only
`[2]=<function>`: Forever has no `UnitAura` and has `C_UnitAuras.GetAuraDataByIndex`. So
the addon always takes the `C_UnitAuras` branch, and `UnitAura` stays absent.

## Where the addon reads auras

- `WoWPro_Broker.lua:3481-3496`: the next-step pass skips a `BUFF` step whose buff the
  player has.
- `WoWPro_AutoComplete.lua:177-186` (`AutoCompleteBuff`, on `UNIT_AURA`): completes a
  visible `BUFF` step when the buff is present.
- Both go through `WoWPro.AuraScan`, which calls `GetAuraDataByIndex("player", i, filter)`
  for `HELPFUL` and `HARMFUL` until it returns nil.

## Approaches

- **A. Model no auras (picked, user 2026-11-23).** The stub reads a player aura list
  that starts empty and nothing fills. `BUFF` steps advance or stall on their other
  conditions (e.g. `QO`). A `BUFF` step that stalls is a harness notice, never a guide
  finding. Small, and hides nothing.
- **B. Model buffs.** Emulate `/sit` at the campfire granting Boosted Rest and fire
  `UNIT_AURA`. More faithful, but every buff source becomes a fact to capture in game.
  Later, only if A's notices show it's worth it.

## Design

1. `env.C_UnitAuras = trap(sb, "C_UnitAuras", { GetAuraDataByIndex = ... })` in
   `hwc.stubs.core`: returns the `index`-th entry of `world.player.auras` that matches
   the filter (`HELPFUL`/`HARMFUL`), as an aura data table (`name`, `icon`,
   `applications`, `spellId`, ...), else nil. `world.player.auras` starts `{}`; no
   action adds to it. `UnitAura` is not defined.
2. `buff` joins `Engine.TAG_KEYS` (Parser `DefineTag("BUFF","buff",...)`, `:535`).
3. A step with a `buff` tag that didn't advance, and has no stall reason of its own (a
   refusal such as `not-in-log`, or an arrival mismatch, stays a `did-not-advance` so the
   notice never hides a guide bug; final review, 2026-11-23), gets the harness notice reason
   `aura-not-emulated`, key `<gid>:<line>`, in place of `did-not-advance`, out of every
   count like the arrival notices. Wording: "the buff the step checks isn't emulated".
   *My call:* it is a new harness signal `emulation-gap`, not an `arrival-data-gap`
   reason, since a buff isn't an arrival; `waypoint-arrival-not-emulated` stays where
   it is.
4. Tests: the stub returns nil with no auras and the entry with one; the Dun Morogh
   anchor runs past `The Great Outdoors` on `2026.11.21.A` with no Lua error.

## Non-goals

`/sit`, buff sources, `UNIT_AURA` events, `MAW`/anima powers, combat secret values.

## Left to the builder

*My call:* built on `feat/arrival-emulation`, since that branch can't be checked against
`2026.11.21.A` without it.
