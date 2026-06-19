# Handoff, 2026-06-19 (session 6)

## Headline: continued from session 5. Cleared a shadowed-variable warning (enemy_sphere
`basis` -> `beam_basis`, commit 1226f83). Then a long DESIGN pass on the lock/gate guide
lines (N5). Tried snap-endpoints + route-as-far + dashed-over-gap + translucency (committed
as a WIP checkpoint), but on playtest the dev rejected BOTH the "give up at the gap" and ANY
mark drawn over void. DECISION reached for next session: teach the router to navigate.
The WIP is a checkpoint only; its gap-RENDERING (route-as-far + dash) gets replaced.

## DESIGN DECISION (N5 real fix -- agreed, build next session)
Guide lines should follow the cube's REAL traversal. Build it as:
- KEEP the floor BFS (it already routes AROUND walls/safety edges correctly). Do NOT switch
  to greedy "nearest tile closer to dest": that stalls in local minima on concave / U-shaped
  walls (you must sometimes move AWAY from the goal to round an obstacle), which stealth
  puzzles are full of.
- ADD jump edges to the BFS graph: from a floor cell, a straight CARDINAL hop up to
  DODGE_DISTANCE (5 -> a gap of up to 4 void cells) landing on floor, with ONLY void in the
  span and NO safety_edge in it. A safety edge is the one thing you can't dodge/bridge over
  (real collision blocker + the "no crossing" marker), so jumps must not cross one. Bridging
  is shorter and also lands you across, so a single "jump up to N" rule approximates both for v1.
- RENDER: solid line along the floor steps (current look, now translucent); at each jump draw
  NO line over the void -- instead an ARROW on the floor at the gap edge pointing to where the
  line resumes / the destination. (Dev's idea: shows the crossing without marking void.)
- Scope is SMALL: we already have BFS + _nearest_walkable. New bits = a jump-edge generator
  (scan 4 dirs out to 5 for a landing floor cell, void-only span, no edge) + an arrow mesh and
  placement. KEEP translucency (LINK_ALPHA/LINK_EMISSION) and _nearest_walkable.

## WIP committed this session (provisional, on main, level_loader.gd)
- _nearest_walkable: snap a line endpoint to the closest floor cell (fixes a gate bbox-centre
  or zone centre landing on void). KEEP.
- _route: floor BFS returning {path, connected}; when disconnected, path runs to the reachable
  cell nearest the goal (route-as-far). The route-as-far half + _draw_dashed get REPLACED by
  jump-edge routing + edge arrows.
- _draw_dashed: dashes across the gap. REMOVE next session.
- Translucent, dimmed segments: LINK_ALPHA 0.5, LINK_EMISSION 0.55 (constants up top). KEEP.

## Verification done (headless, ~/.local/bin/godot v4.6)
- Parse clean throughout (incl. the SHADOWED warning grep).
- Routing logic test (throwaway, removed): connected route; disconnected stops at nearest cell;
  routes AROUND a void without crossing it; off-floor endpoint snaps to adjacent floor. 7/7.

## FEEL-CHECKS -- dev reports the earlier batch plays well
- N11 (Next button), N15 (pursuit catch-in-cover), N16 (footprint trail-follow), tutorials 6
  (Dodge) + 7 (Convergence): dev says "everything is working well for now," still test-driving
  and will report regressions. Treat as confirmed unless something resurfaces.

## OPEN / NEXT (pick ONE)
1. **N5 real fix: jump-edge router + gap-edge arrows** (the decision above). Self-contained,
   small, and the dev is keen on it. Strongest next pick.
2. **Link layer** (N14/N5 deeper): explicit lock<->unlock pairing. Biggest; only anchored.

## Verify recipe (unchanged; ~/.local/bin/godot v4.6; FROM cube dir; exit 0 even on errors)
- Parse: godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR|SHADOWED"
- Logic test: throwaway `extends SceneTree`. For pure level_loader helpers you can
  `LevelLoader.new()` and call _route / _nearest_walkable directly (no scene/tree needed).
  Type-annotate locals off Dictionary/Variant access or inference fails. Clean up .gd + .uid.

## Tutorial pipeline / memory (unchanged from session 5)
- See memory project_tutorial_pipeline; 7 tutorials promoted, all in tutorials_menu.gd.
