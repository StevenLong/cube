# Glossary (Ubiquitous Language)

One agreed word per concept, used the same way in conversation, design docs, and code
(the "ubiquitous language" idea from *Domain-Driven Design*). When a term is ambiguous or
being coined, add it here and pin it down before building on it, so we are not arguing past
each other. Code (class/var names) and design docs should use the **Term** spelling.

Status tags:
- **[settled]** agreed and in use.
- **[proposed]** suggested, not yet agreed; settle (grill the word) before it drives a build.
- **[contested]** in use but means different things to each of us; needs a decision.

The grid/movement primitives (unit, cell, face, tumble, grid position) live in CLAUDE.md
"Terminology" and are all [settled]; this file is for the gameplay/systems vocabulary.

---

## Stealth & detection

- **Blend** [settled] — the player state of being hidden by standing flush between an opposite
  pair of walls at the cube's exact height (`player.is_blending` / `_is_in_cover`). Defeats a
  guard's vision. Glass does **not** count as blend cover (it is see-through).
- **Cover** [settled] — the walls that *enable* a blend. "In cover" = currently able to blend.
- **Detection** [contested] — overloaded. Pin which is meant:
  - **Guard detection** — a guard's graduated awareness meter `_detection` in [0,1] driving its
    PATROL -> SUSPICIOUS -> INVESTIGATE -> PURSUIT ladder (vision/noise driven, recoverable).
  - **Pyramid catch** — see **Catch**. A discrete event, not a meter. Prefer "catch" for the
    pyramid so it is not confused with guard detection.
- **Spotted / Pursuit** [settled] — a guard at full detection actively chasing. Break line of
  sight long enough and it de-escalates.
- **Seek** [proposed] — a guard's aggressive directed state when an echo-pyramid **catch** hands it
  the player's exact cell. It beelines to that cell faster than INVESTIGATE but below PURSUIT, cone
  aimed ahead (so it escalates to PURSUIT if it actually sees you). Each pulse refreshes the target;
  reaching a stale cell drops it to INVESTIGATE. Tell: electric cyan. (Name not yet ratified.)

## Echo Pyramid

- **Echo Pyramid** [settled] — the stationary floating sonar enemy. Defeats cover.
- **Zone** [settled] — the pyramid's circular danger area, radius R. Drawn as a filled per-tile
  area on the floor: full colour where a tile's centre is within R (a catch lands there), a dimmer
  wash on tiles the radius only clips (rounds out the silhouette).
- **Pulse** [settled] — one firing of the pyramid on its fixed beat (charge tell, then fire).
- **Scan / Front** [settled] — the detection wave that expands from the pyramid's centre to R on
  a pulse, lighting the floor tiles per tile (step-wave style). "Front" = its leading edge.
- **Catch** [settled] — the pulse front reaching the player while inside the zone. A catch puts
  every guard currently inside the zone into **Seek** (perfect intel on the player's cell) and
  applies **Overheat** + **Exposed** + **Revealed** to the player. It is **not** a guaranteed alert
  or instant fail.

## Player resource / status

- **Dodge cooldown** [settled] — the recovery timer after a dodge before another can fire
  (`_dodge_cooldown_t`, scales with dodge distance / heat). Shown on the cube display as heat.
- **Overheat** [settled] — the dodge cooldown driven to its max by an event, so the player
  cannot dodge for one full dodge-reset. A pyramid **catch** maxes it (re-maxed on each catch).
  One shared cooldown timer; a separate tunable for the catch amount (default = the dodge cooldown)
  so it can be bumped without changing normal dodging. Also the parked **worming** nerf reserve.
- **Exposed** [settled] — the debuff a pyramid **catch** applies, riding the catch's overheat
  timer (clears when the dodge cooldown finishes): you cannot **blend** (a current blend is
  force-broken, re-entry blocked). SPECIFIC to pyramid catches, not to overheat generally (so
  non-pyramid overheat, e.g. worming, never denies blend). You can still walk/tumble out; dodge +
  blend are what's locked. Shown by a distinct cube-display look (red, vs the normal amber
  dodge-heat) for the duration -- it doubles as the overheat tell, since a catch always triggers both.
- **Revealed** [settled] — the debuff a pyramid **catch** applies alongside **Exposed**, on the
  SAME shared overheat timer (clears when the dodge cooldown finishes). While revealed, every
  pyramid re-feeds its in-range guards your LIVE cell each tick (throttled), so guards track you
  THROUGH cover -- a post-catch dodge, walk, or duck-behind-a-wall can't shake the **Seek**. The
  escape is to run it out (walk/tumble/sprint stay free) and break contact after it clears, or leave
  the zone so the next pulse can't re-catch and re-arm it. A sibling flag to Exposed (`_revealed`),
  kept separate so it can later be split off the timer into a "clears only when you leave the zone"
  version if same-timer proves too weak. No distinct visual yet -- shares Exposed's red wash, since
  the two always co-occur.
- **Worming** [proposed] — emergent tech: repeated extend-then-collapse to travel silently/fast.
  Watched, not yet nerfed; the reserve lever is extend **overheat**.
