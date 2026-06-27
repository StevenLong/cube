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

## Echo Pyramid

- **Echo Pyramid** [settled] — the stationary floating sonar enemy. Defeats cover.
- **Zone** [settled] — the pyramid's circular danger area, radius R. Drawn as a persistent
  **outer ring** on the floor tiles.
- **Pulse** [settled] — one firing of the pyramid on its fixed beat (charge tell, then fire).
- **Scan / Front** [settled] — the detection wave that expands from the pyramid's centre to R on
  a pulse, lighting the floor tiles per tile (step-wave style). "Front" = its leading edge.
- **Catch** [settled] — the pulse front reaching the player while inside the zone. A catch feeds
  the player's exact position to every guard currently inside the zone (and, proposed, overheats
  the player). It is **not** a guaranteed alert or instant fail.

## Player resource / status

- **Dodge cooldown** [settled] — the recovery timer after a dodge before another can fire
  (`_dodge_cooldown_t`, scales with dodge distance / heat). Shown on the cube display as heat.
- **Overheat** [proposed] — the dodge cooldown driven to its max so the player cannot dodge.
  Proposed triggers: a pyramid **catch** (new); extend/collapse spam (the parked **worming**
  nerf reserve). OPEN: is overheat a single shared timer across all sources?
- **Debuff** [proposed] — a temporary negative status on the player. First concrete one:
  **no-blend** (cannot blend) applied by a pyramid catch, ending when that catch's overheat ends.
  OPEN: is no-blend universal to all overheat, or specific to pyramid catches? (Leaning specific.)
- **Worming** [proposed] — emergent tech: repeated extend-then-collapse to travel silently/fast.
  Watched, not yet nerfed; the reserve lever is extend **overheat**.
