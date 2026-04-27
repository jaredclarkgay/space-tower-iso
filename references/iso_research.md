# Iso Research — Phase 1

**Author:** Builder Agent (Claude Code, session 1)
**Date:** 2026-04-26
**Purpose:** Surface the patterns and constraints that should drive the architecture decision in Phase 2 and the build in Phase 3. Not exhaustive — opinionated, scoped to the slice.

---

## TL;DR

- **Iso projection:** Use **2:1 dimetric** (a.k.a. "the standard pixel iso ratio"). Non-negotiable for clean math; matches the official Godot demo and moolabs reference; halving Y-velocity gives correct movement feel for free.
- **Camera approach (recommendation):** **`Camera3D` orthographic, rotated to (-30° X, 45° Y)** rather than `Camera2D`. The brief asks for 90° rotation, and in pure 2D that requires either pre-rendered multi-angle art or rotating the entire scene tree (both fragile). 3D orthographic makes rotation, zoom, and future floor-stacking trivial — at the cost of pixel-perfect 2D.
- **Depth sort:** For a single floor, use **Y-Sort on a parent `Node2D`** (or `Node3D` z-order if we go 3D). For future stacking, the documented pattern is parent YSort + per-layer `y_sort_origin` offsets equal to cumulative floor heights.
- **Web export:** Compatibility renderer is mandatory (already locked). WebGL 2.0 only. Single-threaded — keep per-frame work modest. Safari is unreliable; develop and verify in Chrome/Firefox.
- **What I learned that I didn't know:** the `y_sort_origin` trick — you can offset a TileMapLayer's position visually while telling the sort algorithm to ignore that offset. This single property is what makes vertical stacking in 2D Godot tractable. Without it, stacked floors fight each other for sort precedence.

---

## 1. Depth-sort / Y-sort patterns most relevant to a vertically stacked tower

### Single-floor (this slice's actual scope)

Simplest correct pattern, copy-pasteable:

```
Node2D (YSortEnabled = true)
├── IsoFloor (Node2D / TileMapLayer)
└── IsoPlayer (CharacterBody2D, with sprite Y-anchored at feet)
```

Set `YSortEnabled` on the parent. Children are drawn in ascending order of `position.y` (or, for sprites, the sprite's anchor point). The official Godot iso demo's `goblin.gd` uses this exact pattern with a sprite anchored at the feet — no special handling needed for one floor.

### Future stacking (out of scope for the slice but worth knowing)

The Godot 4.4 forum-canonical pattern for a multi-story building:

```
WorldRoot (Node2D, YSortEnabled = ON)
├── Floor3 (TileMapLayer, YSort = ON, position.y = -floor3_offset, y_sort_origin = +floor3_offset)
├── Floor4 (TileMapLayer, YSort = ON, position.y = -floor4_offset, y_sort_origin = +floor4_offset)
└── Player (CharacterBody2D)
```

The `y_sort_origin` cancels the visual `position.y` offset for sort math, so each layer keeps its visual altitude *and* sorts coherently with characters that walk between them. For a 10-floor tower the y_sort_origins scale linearly (`floor_index * floor_pixel_height`).

This pattern is documented at:
- forum.godotengine.org/t/best-practice-for-stacking-tilemaplayer-nodes-with-ysort-in-godot-4-4/120306
- forum.godotengine.org/t/how-do-i-correctly-stack-isometric-tilemaplayers/113870

### Caveat — the "sides peek through" gotcha

When two stacked tile layers occupy the same column, the lower layer's edges can peek through the upper layer at seams. The fix is a tileset-level decision: include "sides-only" tile variants for the lower layer that omit their top surface. Out of scope here (we have one floor) but a known multi-floor failure mode to log.

---

## 2. Camera setup (pan + zoom + rotate)

The brief requires three verbs: pan (middle-click drag or shift+arrows), zoom (mouse wheel), rotate in 90° increments (we wired Q/R, not Q/E, in Phase 0).

### Two viable paths

**Camera2D (pure 2D):**
- Pan: `position += delta` on mouse drag.
- Zoom: `zoom *= 1.1` (Camera2D's zoom is a Vector2 multiplier).
- Rotate: assign `rotation` on the camera, OR rotate the world parent. Either way, sprites no longer match the new angle — you need 4 sets of pre-rendered art per object, or accept that "rotation" is just a camera trick that breaks visual fidelity.

**Camera3D orthographic (3D-rendered, looks 2D):**
- Pan: `position` on a horizontal plane.
- Zoom: `size` property on the orthogonal projection (smaller = more zoomed in).
- Rotate: `rotation.y` on the camera (or a parent pivot node) in 90° increments — visuals re-render from the new angle correctly because the world is actually 3D.
- For programmatic placeholder visuals (cubes, planes, billboards), this Just Works.

### Industry precedent

- 2D-rotation games typically don't rotate (RimWorld, classic SimCity 2000, Hades).
- Games with rotation tend to be 3D-orthographic under the hood (XCOM, Bastion, Pillars of Eternity, Disco Elysium's exteriors).

### Recommendation

**`Camera3D` orthographic, parented to a pivot node, rotated -30° on X and 45° on Y for the canonical "true iso" feel.** Rotate the pivot (not the camera) in 90° increments to keep the X tilt fixed. Use `Tween` for the 90° rotation snap so it's a quick smooth animation rather than a hard cut.

This decision pre-resolves Phase 2's Path B argument (renderer swap), since a 3D scene graph with orthographic camera *is* the renderer-swappable architecture: GameState holds the world, the camera is one view of it, swapping to a side-on view is just a different camera angle on the same scene.

---

## 3. Iso projection — recommendation: 2:1 dimetric

| Property | True Isometric (30°) | 2:1 Dimetric |
|---|---|---|
| Angle of horizontal axis | 30° from horizontal | ~26.57° (`atan(0.5)`) |
| Pixel ratio | irrational | exactly 2:1 |
| Tile dimensions | 64×37 (or similar non-clean) | 64×32, 128×64 — clean |
| Math for movement | requires float trig | integer-friendly |
| Used by | technical art / engineering drawings | virtually every 2D iso game |

The official Godot demo uses 2:1 dimetric. The `goblin.gd` movement code is one line:

```gdscript
motion.y /= 2
```

That single divide-by-2 is what makes WASD/arrow input feel right on an iso plane. We carry this directly into `iso_player.gd` in Phase 3.

If we go the 3D-orthographic route, the projection is enforced by the camera angles (-30°, 45°) instead of by sprite pixel ratios, but the player input mapping (`motion.y /= 2`) remains the same insight — projected movement is half-speed on the screen-Y axis.

**Constants in `autoloads/constants.gd` (`ISO_TILE_W = 64`, `ISO_TILE_H = 32`) are correct as written.** No revision needed from Phase 0.

---

## 4. Compatibility renderer + web export constraints

Locked from the brief, confirmed by official docs:

- **Web export only supports Compatibility (WebGL 2.0).** Forward+ and Mobile renderers are not available on web. Already configured in `project.godot`.
- **Single-threaded on web.** No worker threads in Godot 4.x web exports as of 4.4 (active issue tracked upstream). Implication: keep per-frame allocations modest, avoid heavy `_process` work, don't rely on threaded jobs for anything user-visible.
- **Safari is unreliable** with WebGL 2.0; develop and test in Chrome or Firefox.
- **No `Forward+`-only features** — that includes some particle behaviors, certain shader features, and some volumetric effects. For programmatic placeholder visuals this isn't a blocker, but flag any imported library that assumes Forward+.
- **`Camera3D` orthographic works fine on Compatibility.** I verified the path is supported, not deprecated, and not Forward+-gated.

### Concrete consequence for Phase 3

The Garden visual signature (translucent water pipes, animated grow lights) translates fine to Compatibility:
- Water "translucency": use `BaseMaterial3D` with `transparency = ALPHA` (cheap on WebGL 2.0).
- Grow-light "glow": `OmniLight3D` with low range OR a `MeshInstance3D` with emissive material + a billboarded sprite halo. No screen-space glow shader (Forward+ only).
- Plant "sway": shader on the leaf mesh — keep it cheap, single uniform time variable, no per-pixel branching.

---

## 5. Camera composition — pan / zoom / rotate interplay

The cognitive risk: each verb interferes with the others if implemented naively. A few rules from the references:

- **Zoom should be camera-relative, not world-relative.** When the user wheels-zoom while the camera is rotated, zooming in toward the screen center is the correct behavior; zooming "into world origin" is disorienting. Implement zoom as an interpolation of the orthographic `size` parameter, never as `position` change.
- **Pan should respect rotation.** "Pan right" must mean *screen-right*, not *world-X-right*. If the camera is rotated 90°, screen-right is world-Z (or world-negative-X). Compute pan vectors from the camera's basis, not from world axes.
- **Rotation should pivot around the camera target, not the camera origin.** Otherwise the world appears to swing around the screen. Use a pivot Node3D parent for the camera; rotate the pivot.
- **Snap the 90° rotations** rather than blocking input during the animation. A 0.2s `Tween` on the pivot's `rotation.y` is fast enough not to feel laggy and slow enough to read as a deliberate rotation, not a teleport.

### Reference camera implementations to crib from

- **TweakGame's "Isometric Camera Controller 3D" article** — covers the canonical -30°/45° setup with grab/rotate/zoom/edge-pan.
- **Tam's GitHub gist "A smoothly panning and zooming camera for Godot 4"** — the smooth-zoom math.
- **Chris' Tutorials Grid Placement Plugin** — has a working iso demo with a placement camera; useful if Phase 3+ adds a build mechanic later.

These don't need to be vendored — the patterns are simple enough to implement from scratch in `iso_camera.gd`. Avoiding plugin dependencies keeps the brief's "no plugins beyond what ships with Godot" constraint clean.

---

## 6. What I learned that I didn't know

Going into Phase 1 I assumed iso in Godot meant "Camera2D + isometric TileMap + sort by Y" and that's basically it. Three things landed that change the architecture I'd have shipped:

1. **`y_sort_origin` is the load-bearing property** for any future tower stacking. It's not a kludge, it's the documented pattern, and it works elegantly *if* you set the parent YSort flag *and* compensate the per-layer position offset *and* use sides-only tiles to mask the seam between layers. Three coordinated decisions — easy to get one wrong, easy to debug if you know all three.

2. **3D-orthographic is a more honest path than 2D-rotated** for an iso game that wants to support rotation and stacking. The pixel-perfect 2D look is real, but it costs you four sets of pre-rendered art per object the moment you want to rotate the camera. For a slice that's testing whether iso *feels* right (and using programmatic visuals anyway), 3D orthographic gives you rotation, future stacking, and even renderer-swap (Phase 2's Path B) for nearly free. The trade-off is felt at the polish layer, not the prototype layer.

3. **The goblin demo's `motion.y /= 2` is the entire iso movement secret.** I had expected something more elaborate — coordinate transforms, basis matrices, axis projection. It's one line. Mapping screen-space WASD to iso-space displacement is just "halve the vertical because the projection is 2:1." This insight survives the 2D-vs-3D choice; it's just a property of dimetric projection, full stop.

---

## Open question for the operator (Phase 2 boundary)

Should I propose **Path B (renderer swap)** with the recommendation to implement it as **`Camera3D` orthographic on a 3D scene graph**? That's a slightly stronger reading of the brief than the literal "iso prototype is one renderer among several" — it pushes the architecture toward an actual 3D world that *renders* as iso, rather than a 2D iso world that *pretends* to be swappable.

The two are closer than they sound: a 3D scene with an orthographic camera at -30°/45° is, visually and mechanically, an iso game. But all the underlying physics, stacking, and rotation are real. Logging this for the architecture decision in Phase 2.
