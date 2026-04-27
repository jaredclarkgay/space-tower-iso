# Session Log — Iso Vertical Slice

## Session 1 — 2026-04-26
**Goal:** Build iso vertical slice. Decide whether to commit to the pivot.

### Phase 0 — Bootstrap
- Created project structure (autoloads, agent, references, LICENSES, scenes/iso_prototype).
- Wrote four GDScript autoloads scoped to slice needs (Constants, GameState, SaveManager, AudioManager).
  Stubs preserved for SaveManager/AudioManager so future phases grow without churning call sites.
- Authored Builder Agent files from scratch (not copied from sibling repo).
  Synthesis sources: `docs/space-tower-project-knowledge-v3.md`,
  `docs/player-journey-map-v3-final.html`, `docs/builder-agent-design-v1.md`.
- Wrote scoped CLAUDE.md, README, project.godot (Godot 4.6, GL Compatibility,
  full input map per brief).
- Bootstrap commit pending: `chore: bootstrap iso prototype repo`.

### Decisions made
- **Camera rotate keys:** Q (left) / R (right). Brief suggested Q/E, but E is
  reserved for `interact`. Q+R keeps both verbs available without a chord.
- **Movement:** four-direction proposed for Phase 3, justified in plan
  (matches iso cardinal axes, simpler depth-sort). Final call deferred until
  Phase 3 build, since it could change after Phase 1 research.
- **Iso demo acquisition method:** clone `godotengine/godot-demo-projects`
  from GitHub into `references/godot_iso_demo/` (rather than AssetLib install).
  Operator-confirmed. Reason: scriptable, version-pinnable.

### Open questions for Phase 1
- 2:1 dimetric vs 30° classic vs other iso projection?
- Y-sort vs hand-rolled depth-sort for one floor (with eye toward future stacking)?

### Phase 1 — Setup and research
- Cloned `godotengine/godot-demo-projects` (`--depth 1`) to `/tmp`,
  copied `2d/isometric/` into `references/godot_iso_demo/`, copied
  upstream `LICENSE.md` to `LICENSES/godot_iso_demo.md`, deleted the temp
  clone. Repo is self-contained; no external dependency on the temp dir.
- Read `references/godot_iso_demo/player/goblin.gd` end-to-end and
  documented the `motion.y /= 2` pattern as the canonical 2:1 dimetric
  player input mapping.
- Reviewed four community references via web search: moolabs "Intro to
  stacking isoBlocks" (itch.io), `mfdeveloper/godot-isometric-framework`,
  `marinho/isometric-3d-toolkit`, Chris' Tutorials Grid Placement Plugin.
  Cited the relevant patterns in `references/iso_research.md` § 5.
- Fetched two Godot forum threads on stacked TileMapLayer Y-sort patterns
  (Godot 4.4 best practice, multi-layer stacking). Documented the
  parent-YSort + per-layer `y_sort_origin` compensation pattern.
- Confirmed web-export constraints: Compatibility renderer required,
  WebGL 2.0 single-threaded, Safari unreliable, no Forward+ features.
- Wrote `references/iso_research.md` covering the brief's five required
  sub-bullets plus a "what I learned" paragraph plus an open question for
  Phase 2.

### Confidence change
- `godot_isometric` domain: low → **medium**. Evidence and rules captured
  in `agent/competency_map.json`.

### Recommendation forming for Phase 2
- Path B (renderer swap) realized as **Camera3D orthographic on a 3D
  scene graph**, rotated -30° X / 45° Y, parented to a pivot for
  rotation. Rationale fully written in `iso_research.md` final section.
  Will formalize and stop for approval at Phase 2.

### Migration note
- Repo moved 2026-04-26 from `~/Library/CloudStorage/Dropbox/Unwind/10-Dev/space-tower-iso/`
  to `~/Developer/Unwind/space-tower-iso/`. Sync services + `.git/` is a known
  footgun; GitHub remote unchanged; history intact. Sibling repos
  (`space-tower/`, `Space-Tower-Browser-Prototype/`) still in Dropbox,
  pending separate migration.

### Phase 2 — Architecture decision

**Recommendation: Path B (renderer swap), realized as `Camera3D` orthographic on a 3D scene graph.**

The brief frames the choice as Path A (pure iso, the iso prototype is the canonical view) vs Path B (renderer swap, `GameState` is the single source of truth and iso is one renderer of many). I'm recommending Path B, with a slight strengthening: the iso "renderer" is a 3D scene graph viewed through an orthographic `Camera3D` rotated to (-30° X, 45° Y), not a 2D scene with iso-projected sprites.

#### Why Path B over Path A

- **Lower blast radius if iso is wrong.** Path A bets the architecture on iso. Path B treats iso as a viewing strategy. If Phase 4 evaluation says iso doesn't feel right, a renderer-swap architecture lets the next experiment (re-introducing a side-on view, trying a third-person 3D camera) reuse the entire world without rewriting it. Path A would require unwinding the architecture to do that.
- **The Reddit-RTS precedent the brief cites** — vanilla Next.js + canvas for 2D, three.js bolted on for 3D, "same world state under the hood" — maps directly to the same pattern in Godot: `GameState` is the world, scenes are renderers.
- **Future Space Tower context.** The full game eventually needs The Reckoning (multi-floor combat), the Restaurant transition (interior 3D), and the RGB threshold. A renderer-swap architecture is the natural shape for a game where one world is read from multiple perspectives — which Space Tower is.

#### Why 3D-orthographic over 2D-iso (within Path B)

The brief doesn't specify 2D vs 3D — it's an implementation choice inside the Path B framing. Three reasons to go 3D-orthographic:

1. **Camera rotation in 90° increments is required by the brief.** In pure 2D, this means either (a) maintaining four pre-rendered art angles per object, or (b) rotating the entire 2D scene tree, which breaks any sprite that wasn't drawn isometric-symmetric. In 3D-orthographic, rotation is a single line: tween the camera-pivot's `rotation.y` by ±90°.
2. **Future floor stacking is automatic.** In 2D with stacked TileMapLayers, the `y_sort_origin` pattern (documented in `iso_research.md` § 1) works but is fiddly — three coordinated properties per layer, plus sides-only tile variants to mask seams. In 3D, vertical stacking is just true Z position; depth sort is intrinsic.
3. **The Garden visual signature translates cleanly.** Translucent water pipes = `BaseMaterial3D` with `transparency = ALPHA`. Grow lights = `OmniLight3D` or emissive material + billboarded halo. Plant sway = a one-uniform vertex shader. All Compatibility-renderer compatible, all web-export compatible.

#### What we forfeit

Pixel-perfect 2D iso. The look you get when sprites are hand-drawn at 64×32 for a specific projection and the camera locks 1:1 with screen pixels. We're not making pixel art; we're making a vertical slice with programmatic placeholder visuals. The forfeit is at the polish layer, not the prototype layer. If Phase 4 evaluation says "this needs to be pixel art," we revisit — but the architecture doesn't have to change, only the renderer's draw calls.

#### Architecture shape (concrete)

```
Autoloads (Phase 0, already in place):
  Constants    ← BPF, BLOCK_WIDTH, FLOOR_HEIGHT, ISO_TILE_*, garden colors
  GameState    ← single source of truth: player_pos (Vector3), camera state
  SaveManager  ← stub
  AudioManager ← stub

scenes/iso_prototype/iso_prototype.tscn  (Phase 3)
└── Node3D (root)
    ├── World (Node3D)
    │   ├── IsoFloor (Node3D)        ← iso_floor.gd, programmatic Garden Floor 3
    │   └── IsoPlayer (CharacterBody3D)  ← iso_player.gd, WASD on horizontal plane
    ├── CameraPivot (Node3D)         ← rotates 90° on Y for camera_rotate_*
    │   └── Camera3D (orthographic)  ← iso_camera.gd, manages zoom and pan
    └── EnvLight (DirectionalLight3D) ← single sun, warm tone for grow-light feel
```

GameState reads/writes player_pos and camera state; iso_player and iso_camera both refer to GameState rather than referencing each other. A future renderer (e.g., `scenes/side_on_prototype/`) would consume the same GameState without touching iso code.

#### Acceptance for Phase 3 (writing it down so Phase 4 evaluation has criteria)

- One Garden floor visible, recognizable as the Garden (planters, water pipes, grow lights).
- Character walks via WASD/arrows; movement maps correctly to iso-screen-space (no diagonal feels weird).
- Camera pans (middle-click drag), zooms (mouse wheel), rotates 90° in either direction (Q/R) with a tween.
- Runs at 60 FPS in the editor; runs without errors when built for web Compatibility export.
- Zero plugins, zero C#.

#### Open questions intentionally deferred

- **Player movement: 4-direction vs 8-direction.** Default to 4-direction (cardinal axes), but build the input vector as a normalized Vector2 and let the Phase 3 implementer flip to 8-direction trivially if it feels stiff. Not architecture-level.
- **Lighting fidelity.** Programmatic placeholder visuals do not need shadows. Start with a single DirectionalLight3D and an AmbientLight contribution. Revisit if the Garden reads dead.
- **Character art.** Programmatic CSG primitives or a single sprite billboard? Defer to Phase 3 — try the simpler thing first (a CapsuleMesh + cylinder for "head" and "body", 30 minutes of work) and only escalate if it reads as a robot rather than a person.

### Migration cleanup note (still pending, not blocking)
- Sibling repos `space-tower/` and `Space-Tower-Browser-Prototype/` are still in Dropbox. Operator deferred their migration to a separate task; not blocking this slice.

### Operator approval
- 2026-04-26: Operator approved Path B + Camera3D orthographic. Phase 3 build commenced.

### Phase 3 — Build the vertical slice

**Files produced (under `scenes/iso_prototype/`):**

- **`iso_prototype.tscn`** — root scene, set as `run/main_scene`. Tree:
  `Node3D > World{IsoFloor, IsoPlayer} + EnvLight + WorldEnvironment + CameraPivot{Camera3D}`. WorldEnvironment provides ambient
  fill (warm grey-blue), DirectionalLight3D adds a warm 60°-down "sun".
- **`iso_floor.gd`** — procedural Garden floor. 12 blocks along X. Buildable
  blocks (per `Constants.is_buildable`) get a soil planter + green sphere
  plant + small red "fruit"; a grow-light fixture above with an emissive
  bulb + an OmniLight3D that pulses on a 2.5s sin cycle. Window blocks
  (3, 7, 11) render as fence posts; elevator block (6) renders as a
  translucent shaft hint. Two long translucent water-pipe cylinders run
  along the front and back of the floor.
- **`iso_player.gd`** — `CharacterBody3D` with WASD/arrow movement.
  4-direction (justified inline). Input is camera-relative — rotated by
  the camera pivot's yaw so "up" on screen is always "into the scene"
  after a 90° rotation. Visual: capsule body in hardhat orange, box
  head, yellow hardhat dome, dark facing-nub on the front.
- **`iso_camera.gd`** — orthographic Camera3D parented to a CameraPivot
  Node3D. `_ready()` sets projection, tilt (-30° X), initial yaw (45° Y),
  ortho size (14 m). `_unhandled_input` handles Q/R rotate (tween 0.2s
  on pivot.rotation_degrees.y), mouse-wheel + `=`/`-` zoom (multiplicative,
  clamped 6–36), middle-click drag pan (basis-relative on XZ plane).
  Mirrors state into `GameState.camera` every frame.

**Constants additions (`autoloads/constants.gd`):**
- `BLOCK_3D_W=2`, `BLOCK_3D_D=4`, `FLOOR_3D_SLAB_THICKNESS=0.2`,
  `FLOOR_3D_STORY_HEIGHT=3`, `FLOOR_3D_WIDTH=24`.
- `CAMERA_TILT_DEG=-30`, `CAMERA_YAW_DEG_INITIAL=45`,
  `CAMERA_ROTATE_DURATION=0.2`, `CAMERA_ORTHO_SIZE_DEFAULT=14`,
  `CAMERA_ORTHO_SIZE_MIN=6`, `CAMERA_ORTHO_SIZE_MAX=36`,
  `CAMERA_ZOOM_FACTOR=0.9`.
- `PLAYER_MOVE_SPEED=4` m/s.

**GameState additions:** `player.iso_pos: Vector3`, `camera.target: Vector3`,
`camera.ortho_size: float`, `camera.angle_step: int`.

**`project.godot`:** `run/main_scene` set to `res://scenes/iso_prototype/iso_prototype.tscn`.

**Failure caught and fixed:**
- First import surfaced 4 GDScript parse errors in `iso_floor.gd` —
  `:=` walrus inference failed on autoload-derived expressions because
  Godot types autoload property accesses as `Variant`, not their concrete
  type. Fixed by changing the affected locals to explicit `: float =`
  annotations. Logged to `failure_log.json`.
- Initial `EnvLight` transform matrix had the light pointing up (rookie
  Godot Transform3D mistake — `-basis_z` is the directional cast).
  Replaced with a clean Rx(-60°) rotation matrix; light now points
  mostly down with a slight forward tilt. Cosmetic, but important for
  the Garden to read warm.

**Verification:**
- `Godot.app --headless --import` exits 0, no script errors, no
  warnings beyond the (benign) "another project.godot at
  references/godot_iso_demo" — that vendored demo is correctly skipped.
- `Godot.app --headless --quit-after 60` runs the scene for 60 frames
  and exits 0 with no runtime errors.
- Visual verification (camera framing, garden read, controls feel) is
  the operator's job — see `iso_slice_summary.md` (Phase 5) for the
  ask.

### Next
- Phase 4 self-evaluation. Will pause for operator playthrough notes
  before writing findings to `failure_log.json` and answering the
  brief's five evaluation questions.
