# Core-systems audit — 2026-06-11

Manual focused review of the load-bearing systems (floor visibility/collision
gating, vertical traversal, the roof plunge + crane gag, player physics, camera,
and the state spine). Read-only except for ONE finding that was trivially safe
and verified, which is already fixed + committed.

**Result:** 1 real bug (fixed), plus a cluster of low-severity tech-debt items
(dead constants, stale constant *names*, comment-vs-code value drift) and two
docs/lore notes. No further correctness bugs found in the systems reviewed — the
floor-gating, traversal flag handling, and camera mode ownership all held up.

---

## FIXED this session

### F1 · [Medium] Chapter-jump didn't release transform-owning traversal modes
**Fixed in `6ff5db0`.** `_teardown_transient_state()` cleared `roof_falling` but
not `driving_crane` / `riding_elevator` / `tube_hopping`. Each owner
(`crane.gd`, `elevator_platform.gd`, `vacuum_lift.gd`) writes the player's
transform every physics frame while active, and its live flag freezes the
player's own `_physics_process` (`iso_player.gd:286`). So a dev chapter-jump that
interrupted a crane drive / elevator ride / vacuum hop left the owner running →
it yanked the player back onto its rig every frame and froze them on the wrong
floor. The crane was the most reachable (you can sit in it indefinitely).
Fix: added `force_release()` to all three owners + called them from teardown.
Verified with a harness (jump→Garden while driving and while mid-plunge both land
the player in the Garden with all flags cleared).

---

## Resolved after the audit
- **O1 (dead constants)** — deleted in `d66cfaa`.
- **O2 (stale constant-name families)** — renamed `FLOOR_1_*`→`UTILITY_*`,
  `FLOOR_4_*`→`CANOPY_*`, `TREE_FLOOR_4_VISIBLE_THRESHOLD`→`TREE_CANOPY_VISIBLE_THRESHOLD`
  in `d66cfaa` (smoke-clean).
- **D1 (`floor_design_system.md`)** — full rewrite for the stacked world in `bcc6d8c`.

Still open: **O3** (comment-vs-code "3 m" story-height drift) and **D2** (Cody lore).

---

## Open — low severity (tech debt; no behavioural bug)

### O1 · [Low] Dead constants — safe to delete  ✅ DONE (d66cfaa)
- `Constants.GARDEN_FLOOR_INDEX := 2` — **0 readers.** Value (2) and old "Floor 3"
  label both predate the locked numbering (the Garden is Floor 1).
- `Constants.PLAYER_FALL_RESPAWN_Y := -3.0` — **0 readers.** The real fall backstop
  in `iso_player.gd` (~L805) uses a hardcoded `-100.0`, not this const. *(This also
  retires the earlier worry that -3.0 sits above the re-anchored basement at y=-6:
  the value is never read, so it can't misfire.)*
- **Recommendation:** delete both. Trivial, but a code change — left for review.

### O2 · [Low] Stale constant-NAME families (mechanical cross-file rename)  ✅ DONE (d66cfaa)
Identifiers embed old floor numbers; renaming touches every reader, so the doc
sweep left them and annotated the comments instead:
- `FLOOR_1_*` (camera, ambient mults, emergency lights, breaker spot, spine-pipe
  top-y) name the **Utility** floor — now **Floor 0**.
- `FLOOR_4_*` (slab alpha/glass/ring/ceiling-pulse/tree-hole/stairwell/tile…) and
  `TREE_FLOOR_4_VISIBLE_THRESHOLD` name the **Canopy** — now **Floor 3**.
- **Recommendation:** a single rename pass (`FLOOR_1_*`→`UTILITY_*`/`FLOOR_0_*`,
  `FLOOR_4_*`→`CANOPY_*`/`FLOOR_3_*`) when convenient. Pure renames, low risk, but
  cross-file — worth doing deliberately, not piecemeal.

### O3 · [Low] Comment-vs-code value drift (story height + stair geometry)
Comments assume a **3 m** story, but `FLOOR_3D_STORY_HEIGHT = 6.0`. And the stair
comments cite the pre-resize geometry (`STAIRCASE_RUN` is now `10.0`, slope ~31°,
base offset ~-5.8 m), not the old `5.5 m` / `~28°` / `~-2.8 m`. Spots:
- `constants.gd:281` `(3 m)` (EXTENSION_GRID_UNIT = story = 6 m)
- `constants.gd:877` `FLOOR_3D_STORY_HEIGHT (3 m) in STAIRCASE_RUN (5.5 m) — ~28°`
- `constants.gd:944` `story (3 m)`
- `arboretum_tree.gd:18` `-FLOOR_3D_STORY_HEIGHT (-3 m)`
- `stairs.gd:9` `~28° (atan(3/5.5))`, `stairs.gd:22` `(~-2.8 m)`
- **Recommendation:** a tiny comment-only follow-up sweep (deliberately left out of
  the floor-number pass to keep that scoped). No logic impact.

---

## Docs / lore notes

### D1 · `docs/floor_design_system.md` needs a full rewrite  ✅ DONE (bcc6d8c)
Stale at the architecture level (per-floor `.tscn`, scene-swap elevator + spiral
staircase, deleted `floor_4.gd`/`spiral_staircase.gd`, `GameState.floor_1/floor_3`
keys, old 1-indexed numbers). Banner-flagged in `bc61b24` pointing to current
truth; the body still wants a proper rewrite.

### D2 · Cody "floor-three" dialogue vs his Garden home
`iso_robot.gd:1195` — Cody's line "Built for floor-three operations." He's the
Garden (Floor 1) helper. Could be intentional backstory (a robot built for an
Arboretum-class floor, reassigned) or stale lore. **A narrative call for the
operator** — left untouched (it's player-facing dialogue, not a code comment).

---

## Reviewed and clean (no findings)
- **Floor visibility/collision gating** (`tower_controller._update` + the
  below-grade rule + per-floor slab-layer toggling) — careful and correct.
- **Traversal flag handling** — `vacuum_lift` and `elevator_platform` set/clear
  `tube_hopping` / `riding_elevator` correctly on their own transitions, gate
  hops on `driving_crane`/dialogue/etc., and the construct-from-empty "can't hop
  to an unbuilt floor" guard holds.
- **Crane gag re-review** — re-plunge re-uses the recorded entry pose, beams
  restore, bottom-out is reliable (crane falls from y≈30 past bottom_y=-12); no
  conflict between the player's own roof-fall and the crane's (player physics is
  skipped while `driving_crane`).
- **Camera mode ownership** (`iso_camera._process` gate) — each exclusive mode
  (constructing / exterior_walk / arrival_cine / reentry / lookout / dialogue)
  returns early and releases cleanly; pivot.y owned by the controller, xz by the
  camera, no double-owner.
