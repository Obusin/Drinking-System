# SPEC — Mario-Kart-style hop-drift (IMPLEMENTED)

Captured 2026-07-28, built the same day in
`src/StarterPlayer/StarterPlayerScripts/KartControl.client.luau`.

**Settled:** button drift *replaced* the old slip-angle physics drift
rather than sitting alongside it. Mario Kart has no emergent drift, and
running both meant two systems fighting for the rear axle. Rear grip
(`GripBase`) is now high and stable until you press the button.

Still outstanding: sparks/speed-lines are client-local, so other players
don't see them — fine for feel-testing, needs a server signal for real
multiplayer. And `BoostSoundId` is a built-in placeholder whoosh.

## Behaviour, in order

1. **Drift button press** → quick low hop, ~0.2s airtime. The hop unloads the
   wheels: grip goes to 0 for the duration.
2. **On landing** → lock the kart into a drift in whatever direction it was
   steering at the moment of landing. Body angles into the turn while
   momentum carries the kart wide.
3. **During held drift**
   - Reduced but *stable* grip (no slip-angle state machine — the drift is a
     committed state, not an emergent one).
   - Constant inward curving pull toward the turn centre.
   - Steering input *trims* the drift angle within a range; it must not be
     able to break the drift.
   - Anti-spin assist keeps the player inside a controllable slide pocket.
4. **While drifting** → a hidden boost timer charges. Surfaced only through
   spark colour tiers under the kart: blue → orange → purple.
5. **On release** → rear snaps back to full grip, forward boost fires scaled
   to the tier reached, plus speed-line VFX and a whoosh SFX.

## Feel targets

- Snappy, low-inertia handling
- Low centre of mass
- No suspension wallow
- **Minimal speed-scrub** — drifting should almost always be faster than not

## TUNE keys

> **STALE — corrected 2026-08-06.** The list below was written against
> `KartControl.client.luau`, which no longer exists; the drift lives in
> `ReplicatedStorage/BloxKart/Simulation.luau` now. Five of these names
> were never implemented at all and cost a session's worth of hunting.
> Trust `Config/Handling.luau`, not this list.
>
> | named here | reality |
> |---|---|
> | `HopForce` | is `HopSpeed` |
> | `HopAirTime` | never existed — air time falls out of `HopSpeed` vs `Gravity`, gated by `HopSnap` |
> | `DriftInwardPull` | **never existed, and should not.** In a settled drift travel rotates with the nose whatever the grip, so there is no widening for it to pull against — see FINDINGS §2 |
> | `DriftScrubComp` | never existed. Speed scrub is `DriftScrubCurve` + `DriftSpeedKeep` |
> | `AntiSpinAssist` | never existed as a dial. `MaxSlip` is what bounds the slide pocket |
> | `BoostTier*Strength` | moved to `Config.Nitro.Stages` when release stopped firing a boost and started banking nitro |
>
> Still accurate: `DriftGrip`, `BoostTier1Time` / `2` / `3`.

`HopForce`, `HopAirTime`, `DriftGrip`, `DriftInwardPull`,
`BoostTier1Time` / `BoostTier2Time` / `BoostTier3Time`,
`BoostTier1Strength` / `BoostTier2Strength` / `BoostTier3Strength`,
`AntiSpinAssist`

## Open design questions

- Does the physics drift (current slip-angle model) stay alongside button
  drift, or does button drift replace it entirely? Mario Kart has no
  physics drift — keeping both may fight each other.
- ~~Drift button binding~~ — settled: `Space` + gamepad `R1`, with `E`/`Y`
  rebound as the seat exit. A stopgap handbrake (hold to drop rear grip to
  `HandbrakeGrip`) is already wired to that key; the hop-drift replaces its
  behaviour but keeps the binding.
- Do sparks/VFX/SFX get authored as assets, or generated from primitives?
- Boost: impulse or sustained force over a window? Sustained reads better
  and is easier to keep from launching the kart off the track.
