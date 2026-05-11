# Handoff - 2026-05-11

## Where we are
Phases 1-4 complete. Phase 5 (renamed "Environmental Detection") partially
done: enemy reacts to audio waves; ink puddles + face tracking + footprints +
slide streak in place. Remaining in Phase 5: enemies reacting to footprints
(visual), water puddle dilution.

## Completed this session
- **Phase 4 (first playable level)**: state machine (READY/PLAYING/COMPLETE),
  start/end tiles with pulsing emissive material, "Move to begin" prompt,
  results panel (moves, time, spotted). End tile completes only on landing
  for tumbles; passing through during a dodge counts as completion (slide
  truncates to land on end tile cleanly).
- **Phase 5 — audio reaction**: player emits noise_emitted signal at each
  tumble; enemy queues pending sounds with delay = dist * duration /
  max_radius so reaction lines up with the visible wave. Triggers SUSPICIOUS
  at the noise origin unless already in PURSUIT.
- **Phase 5 — ink puddles, side marking, splash**: logical orientation
  tracked in `_orient: Basis` (quantized each tumble to prevent drift) so
  face tracking persists even though the visual cube snaps back to identity.
  Six-bool `_face_marks` array; mark the down face on tumble end if over
  a puddle. Generated splash sound on first mark per face.
- **Phase 5 — footprints + streak**: ground shader extended with
  `footprint_positions/alphas[64]` uniforms; a marked face landing or sliding
  deposits ink blobs. Slide deposits 4 sub-positioned footprints per cell
  along slide direction so adjacent prints merge into a continuous streak.
- **Dodge refinements**: dodge truncates to the first wall in its path
  rather than being blocked. Duration scales so slide speed is constant.
  End-tile entry during a slide retargets the dodge end position and
  rescales duration so the cube decelerates to a stop on the end tile.

## Bugs found and fixed
- **Basis rotation broke movement**: preserving Player.basis across tumbles
  rotated all child colliders' local frames. Reverted to snap-to-identity
  for the visual; added `_orient` for logical orientation only.
- **Footprints persisted across scene reload**: `ShaderMaterial_1` was
  shared between scene instances. Fixed by setting
  `resource_local_to_scene = true` on the sub_resource.
- **Footprint shader loop**: bumped `MAX_FOOTPRINTS` to 64 in code but the
  shader for-loop bound stayed at 16 (the replace_all only caught `[16]`),
  so only the oldest 16 footprints rendered. Fixed.

## Phase status
- [x] Phase 1 — core movement
- [x] Phase 2 — extension
- [x] Phase 3 — detection and hiding
- [x] Phase 4 — first playable level
- [ ] Phase 5 — environmental detection
  - [x] Ink puddle object
  - [x] Ink mark on cube side on contact, splash sound
  - [x] Ink footprints on ground from marked side
  - [ ] Suspicious state triggered by enemy seeing footprints
  - [ ] Water puddle dilutes ink (10 steps to 3)
  - [x] Enemy reacts to movement noise

## Deferred / known limitations
- **Per-face cube visualisation** (slice 2): cube currently shows a whole-cube
  tint when any face is marked. Per-face shader rendering using `_orient`
  was planned but skipped; can be folded into the "enemy sees footprints"
  work or done separately.
- **Sphere passes through walls** — patrol path is level-designer's
  responsibility for now.
- **Extended cuboid footprints**: one deposit at cuboid centre, not per
  contact cell.
- **No fail-state results screen**: enemy contact still instantly reloads.
  Polish backlog has the symmetric "Caught" panel.
- **Camera pop**: minor sub-1u pop possible on first move; not noticeable
  with `process_mode = ALWAYS`.

## Polish backlog (parked)
- sfx + particles for end/caught
- smooth respawn camera transition
- spawn elevator animation
- symmetric "Caught" results panel
- per-face ink visualisation on cube

## Phase 5 next steps
**Slice 4 — enemy sees footprints**:
- Enemy's existing raycast hits the ground (layer 1). Need to detect
  footprints. Options: separate Area3D probes per footprint, or check the
  enemy's facing direction against the player's footprint list with LoS
  raycast. Cleanest: each footprint is an Area3D (collision_layer = some new
  layer) and the enemy's raycast scans for it.
- On detection, transition to SUSPICIOUS with the footprint position as
  `_last_seen_pos`.

**Slice 5 — water dilution**:
- Water puddle object (cyan, transparent visual).
- On contact, reduce remaining "ink steps" for the marked face from 10 to 3.
- Each footprint deposit decrements a per-face step counter; at 0 the mark
  is cleared.

## Key files
- `player.gd` — tumble + extension + dodge + blend + face tracking + ink + audio waves
- `enemy_sphere.gd` — patrol/suspicious/pursuit, raycast LoS, noise reaction
- `level.gd` — state machine (READY/PLAYING/COMPLETE), stats, end tile, pause
- `camera_controller.gd` — fixed follow + tilt; `process_mode = ALWAYS`
- `main.tscn` — Player + colliders + audio, Enemy, Walls, Ground, StartTile,
  EndTile + Area, Puddle + Area, Level, UI (CanvasLayer)
- `shaders/grid_ground.gdshader` — grid + waves + footprints

## Input map
| Action | Controller | Keyboard |
|--------|-----------|---------|
| Move | D-pad / left stick | WASD / arrows |
| Sprint | R2 | Left Shift |
| Dodge | Circle (hold + dir) | Space |
| Extend mode | R1 | E |
| Extend depth fwd | L1 (+ R1) | Q |
| Extend depth back | L2 (+ R1) | C |
| Blend (hide) | Square | V |
| Camera tilt | Right stick Y | R / F |
| Quit | — | Escape |

## Memory notes worth checking
- Transform3D is row-major in .tscn
- GDScript can't infer types from untyped Array element access
- Commit/push cadence: end of session
- Task list at `/mnt/c/Users/steve/Documents/game-dev/Cube Game Tasks.md`

## Task list source
`/mnt/c/Users/steve/Documents/game-dev/Cube Game Tasks.md`
