# SPEC: Game Object Anatomy (v2)

Status: draft reference (2026-06). Defines the canonical structure of every
paintable level object, as the single source of truth shared by the level
loader, the in-game editor, and the runtime systems (nav, blend, sight,
detection). Built so that adding an object is "declare these facets," which is
also exactly what an `/add-obj` skill fills in.

## Scope and the three schemas

A level is described by THREE separate schemas. This doc specs the first; the
other two are noted at the boundaries and specced separately. Keeping them
apart is deliberate: do NOT force links or level rules into the object anatomy.

1. **Object registry** (this doc): spatially-placed, grid-bound, self-contained
   objects.
2. **Relationship layer**: directed links between specific instances (teleporter
   pairs, switch/door). Summarized under "Links" below.
3. **Level config / rules**: global, non-spatial settings and objectives (par
   time, global modifiers, environment, win/lose). Not objects, no footprint or
   token.

## The facets

Every object is fully defined by these nine facets. Each one exists because a
specific consumer needs it, so this is the union of what storage, the loader,
the runtime systems, and the editor each require.

1. **Identity**: `id` (stable key, e.g. `tall_wall`), `display_name`, and
   `token` (a single grid glyph). Token applies to parameterless tiles only
   (see Placement). *Consumed by: storage, everything.*

2. **Placement (storage kind)**: `glyph_tile` (one character per grid cell, the
   spatial substrate) or `typed_instance` (an entry in the object list, carrying
   params). **Rule: glyph if and only if parameterless.** Anything with params
   is a typed instance with no glyph, including param-bearing terrain (a falling
   floor is a typed instance that supplies a floor cell). Independent of paint
   mode. Tiles additionally declare a `layer`: base terrain (floor, wall, safety_edge, start, end) or surface overlay (ink, water, painted on top of base). *Consumed by: storage, loader.*

3. **Footprint**: the cells occupied plus height in units. May be derived from
   an orientation or extent param (those live in Params, not here). E.g. tall
   wall = 1 cell at 1u; safety_edge = 1 cell, no visible body (red line only); lock zone = 1 cell (the min
   corner; the required cuboid is a param). *Consumed by: collision, nav,
   render.*

4. **Params**: typed per-instance fields with defaults (the schema). Tiles
   usually have none; instances do (enemy `speed` + waypoints, zone `mode` +
   `required_dims`, gate `facing`, pickup `unlock_id`). The same schema drives
   serialization AND the editor's param panel (and rotate/resize gizmos for
   `facing` / extent). *Consumed by: storage, editor.*

5. **Semantics**: STATIC cross-system flags only: `walkable`, `blocks_move`,
   `blocks_sight`, `blendable`, `lethal_on_contact`, `is_goal`, `marks`,
   `cleanses`, and so on. These are what other systems QUERY. Runtime logic is
   NOT here (see Build). Flags are per-object, not per-category: a patrol sphere
   is `lethal_on_contact`, a cone slammer is not. *Consumed by: nav, blend,
   sight, detection.*

6. **Presentation**: mesh / shape, material / colour, height, and any telegraph
   or blueprint. *Consumed by: render, editor preview.*

7. **Build**: how the loader instantiates the object (a packed scene or a
   builder) plus conventions (named `Wall*` so enemy nav sees it, collision
   layer 1). **The object's behavior (its script and state machine: the timed
   fall, the slam + wave + debuff, collect/carry/deliver) lives here, inside the
   instantiated scene.** The Semantics-vs-Behavior split: Semantics is flags
   systems read, Behavior is logic the object owns. *Consumed by: loader.*

8. **Authoring**: palette group + icon, **paint mode** (closed vocabulary
   below), default params, and validation rules (exactly one Start; waypoints on
   floor; `required_dims` fits on floor; a teleporter has a partner). Paint mode
   is independent of storage kind. *Consumed by: editor.*

9. **Dependencies**: the game systems or sibling objects this type requires,
   e.g. the status-effect/debuff system, the noise system, the carry mechanic,
   meta-progression unlocks, the End tile. Lets the editor and `/add-obj` warn
   "needs system X, not built yet" and informs sequencing. *Consumed by: editor,
   planning.*

## Paint mode vocabulary (closed)

The Authoring facet declares exactly one placement mode. The editor builds one
tool per mode, shared across every object that declares it, plus one relational
tool. Orientation (`facing`) and shape/extent (`required_dims`) are PARAMS shown
as gizmos, not modes.

- **`paint`**: bulk-fill cells with a tile type (brush / rectangle / bucket).
  Tile layer, many cells. (floor, wall, safety_edge, void, falling floor; ink and water are overlay tiles, see Tile layers)
- **`single`**: one placement at a clicked cell. (start, end, lock/unlock zone,
  gate, pickup, stationary enemy, teleporter pad)
- **`region`**: drag a rectangle, get ONE instance with that footprint. (trigger volume, platform; puddles are overlay tiles now, not region instances) Deferrable until the first multi-cell
  instance exists.
- **`path`**: click ordered nodes with an optional loop; one instance owns the
  route, first node is the spawn. (patrolling enemy, conveyor)

## Links (the relationship layer, summarized)

**Settled 2026-06 (via grill; see memory `project_link_layer_design`).** The
implemented edge is `{from, to, kind}` where `kind` is an opaque string (current
kinds: `opens` for lock->gate, `released_by` for lock->unlock). Coupling is
EXPLICIT-LINKS-ONLY: nothing reacts unless an edge says so, and optionality is
simply "not linked" (no flag). The richer constraint model below (declared
cardinality, aggregation policy) is deferred until a second linkable type needs
it. The loader parses + validates edges (slice 1, done: structure + endpoints,
dropping malformed/dangling with a warning); the runtime resolves them
decentrally (slice 2).

`link` is a relational tool that runs on already-placed instances; it authors
the relationship layer, not the object registry.

- A relationship is a **directed edge**: `(source, target, role)`. The store is
  a set of such edges.
- **Cardinality is emergent, and all forms are supported:**
  - 1:1, e.g. teleporter pad A to pad B (usually drawn both ways).
  - 1:N (one-to-many), e.g. one lever opening three gates.
  - N:1 (many-to-one), e.g. three pressure plates feeding one door.
- Each object declares its **link constraints**: which roles it can be a source
  or target of, and min/max cardinality (teleporter: exactly 1 outgoing
  `teleport`; door: 0..N incoming `trigger`).
- For many-to-one, the **target declares an aggregation policy**: how to combine
  incoming signals (ANY / ALL / count threshold). A door is "opens when ANY
  linked plate is pressed" or "ALL."
- **Referential integrity**: deleting an instance drops its edges; the editor
  flags dangling or under-constrained links.

Note: today's extend lock/gate/unlock coordinate through a single GLOBAL player
flag (`is_extend_locked`), so only one such puzzle works per level. Moving them
onto this link layer (a gate referencing its lock) is what would enable multiple
independent puzzles in one level.

## Worked examples

| Facet | Tall wall | Extend-lock zone | Cone slammer |
|---|---|---|---|
| Identity | `tall_wall`, glyph `#` | `extend_lock_zone`, no glyph | `cone_slammer`, no glyph |
| Placement | glyph_tile | typed_instance | typed_instance |
| Footprint | 1 cell, 1u | 1 cell (min corner) | 1 cell, cone |
| Params | none | `mode`, `required_dims` | `slam_interval`, `wave_radius`, `debuff_moves` |
| Semantics | blocks move + sight, blendable | trigger, sets lock state, blocks nothing | NOT lethal_on_contact, emits hazard |
| Presentation | 1x1x1 box, wall material | pulsing ghost + marker, colour by mode | cone point-down, slam + wave VFX |
| Build | StaticBody3D `Wall*`, layer 1 | `extend_lock_zone.tscn` | scene + slam/wave/debuff script |
| Authoring | `paint` | `single`, dims-fit validation | `single` |
| Dependencies | none | player lock state | status-effect system, noise system |

## Adding an object (and the /add-obj skill)

Adding a type is: fill the nine facets, register it, scaffold its Build scene,
opt into a paint mode, declare params + validation + dependencies, test. An
`/add-obj` skill walks these as prompts and generates the registry entry plus
scaffold. The completeness test for this anatomy: every facet must be answerable
as a clear prompt; if one cannot be, it is underspecified. Build the skill once
the registry/loader/editor pattern is stable, and note that most new objects
still need real Behavior code, which the skill scaffolds but does not write.

## Tile layers

Tiles live on one of two layers (declared in Placement):
- **base terrain**: floor, wall, safety_edge, void, start, end (and param-bearing
  terrain like a falling floor, stored as a typed entry that supplies a base cell).
- **surface overlay**: ink, water, painted on top of an existing base tile.

This is why ink and water are tiles, not instances: you paint them onto a cell
that already has floor, and a wide puddle is just many painted overlay cells, not
one region instance. The storage format therefore wants a base grid plus an
overlay grid plus the object list.

## Two corrections this catalog caught

1. **`safety_edge` (was mislabeled "low rail").** One object: an INVISIBLE blocker
   (stops the cube and enemy nav), you see OVER it (does not block sight), no
   blend, and its only visual is a thin red line just above the edge it blocks. It
   had drifted into two artifacts: a visible half-height box (`=` in level_loader)
   and an auto-generated red strip (level.gd). The formalized object collapses
   both: invisible body plus red-line render, no visible wall, no separate derived
   strip. IMPLEMENTED in level_loader (a cell-occupying invisible 0.4u `Wall*` blocker with a red line on each floor-facing side; the level.gd auto-strip is removed). Still open: "see over" for enemy sight, since the safety_edge is a `Wall*` body it currently blocks line-of-sight like the rail did.
2. **ink / water are surface-overlay tiles**, not region instances (see Tile
   layers). This retires the "puddles need region" finding; `region` remains for
   true multi-cell instances (trigger volumes, platforms).

## Current objects (catalog)

- **Base tiles:** `floor` (`.`), `tall_wall` (`#`), `safety_edge` (was `=`),
  `glass_wall` (`g`), `void` (space), `start` (`S`, placed single, exactly-one),
  `end` (`E`, single, exactly-one).
  - **`glass_wall`**: a 1u solid the body can't pass (a `Wall*` body on layer 1, so
    it blocks the cube's tumble and routes enemy nav around it) but enemy vision and
    detection see straight THROUGH it. Implemented by tagging the body into group
    `glass`; `enemy_sphere` adds those RIDs to the `exclude` list of its three LoS
    rays. Sits on its own floor tile (a clear pane can't mask a void) and its mesh is
    not named `MeshInstance3D`, so the player's floor vision-cone reads through it.
    Purpose: a risk-free window to teach guard behaviour. (See `_make_glass_rect`.)
- **Overlay tiles:** `ink`, `water`.
- **Instances:** `enemy_sphere` (`path`; `lethal_on_contact`; needs `Wall*` nav
  plus a grid_ground cone slot), `extend_lock_zone` (`single`; params `mode` +
  `required_dims`; grid-checked trigger), `extend_lock_gate` (`single`; opens
  while the player is locked or still on the gate cell; rides the GLOBAL lock
  flag, so one puzzle per level until it moves to the link layer).
- **Not in the registry:** the safety-edge auto-strip and the visible-rail box
  (both fold into `safety_edge`), FloorRect / FloorMissing (authoring helpers),
  player / camera / light / environment (singleton + level config), the ink
  footprint trail (a player effect).
- **Constants that relocate** into registry entries: wall/rail heights + materials
  (level_loader), enemy view/cone/colour/speed consts (enemy_sphere), zone and
  gate colours (extend_lock_*). The safety-edge consts in level.gd become
  `safety_edge`'s Presentation, not a separate system.
