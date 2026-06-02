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

---

## Session 2 (2026-04-26 → 2026-04-30) — Iterative polish, "the slice became the game"

The brief's hard STOP gates were overridden once the operator started iterating live. Each cycle: operator screenshots → diagnose → fix → commit/push → operator F5s. The loop ran 30+ rounds. This entry summarises what was built across that arc rather than listing every commit.

### What landed
- **Garden floor scaled up**: 12-block strip (brief) → 22 → 30 cells per side. Voronoi crop clustering with per-type seed_count for natural patches and tunable scarcity.
- **Player polish**: WASD + arrows, sprint (Shift, 1.75×), jump with hold-to-charge up to 4× height + tuck-and-flip rotation synced to airtime, harvest E with green progress bar.
- **Cody GX-5 helper robot**: arrival ceremony (rises from elevator on a beam of light, banner "joined the team", Slippy-style intro panel with 3D portrait), snake-scan harvest loop, hopper capacity 30, "I'M FULL" attention indicator, top-down spotlight during arrival, drag-rotate during chat.
- **Cody dialogue tree**: 22 nodes covering daily life (counting wheel rotations, the Foreman, climbing stairs), about (origin in the foundry, decommissioned predecessors, admiration for human free will), tricks (spin, LED rainbow, dance) with per-trick reflection follow-ups. Number-key + click activation. State-aware root with text_func/choices_func callbacks.
- **Camera close-up on chat**: zooms to player↔Cody midpoint, picks an entry yaw that frames both side-by-side, slowly orbits while chat is open, drag to manually rotate (orbit pauses on press, resumes on release).
- **Schematics modal**: full-screen with 3D Cody preview (drag-rotatable, mirrors live customisation), status, chassis/dome colour pickers, 7-node skill tree placeholder. Bouncy reveal animation. Hidden until 10 plants harvested.
- **Plant value gradient (ROYGBV)**: Tomato 1, Pumpkin 1, Pepper 2, Cucumber 3, Blueberries 5 (NEW crop), Eggplant 15 (3× blue, 60 s regrow cycle, ~10% of grid). Floater colours/sizes scale with value.
- **Resources HUD**: warmer earth-tone Resources panel with active/dim row markers (◆/◇), Schematics button revealed at the unlock threshold.

### Notable failures + their fixes
- **F-007** Tween `modulate:a` on MeshInstance3D — that property is CanvasItem-only. Fade 3D meshes via StandardMaterial3D's albedo_color:a + emission_energy_multiplier instead.
- **F-008** Default Button.focus_mode = FOCUS_ALL + project rebinding Space to jump → the SchematicsButton was activating on the first jump because Space also fires Godot's ui_accept on the focused button. Fix: focus_mode = 0.
- **F-009** Godot editor cache. After the F-008 fix, the modal kept appearing at game start in the running editor. Cause: stale .godot/ cache held an older scene state. Fix: rm -rf .godot/, close-and-reopen Godot. Three rounds of code fixes were required to convince me the runtime wasn't the bug.
- **F-010** class_name CodyPortrait wasn't visible in headless harness on first parse. Fix: drop class_name, instantiate via preload + set_script.

### Operator iteration patterns (worth remembering)
- Wants moments to FEEL like moments. Don't ship a state change as a bare visibility toggle.
- Wants visual consistency across surfaces — same 3D Cody in chat, schematic, world.
- Aesthetic feedback ("elevate the design sensibility") = license to make taste-driven choices and ship. The operator critiques after seeing it.
- "+2 units" means an integer count of grid cells, translated literally rather than computed by the metric.
- "Out the gates" bugs: suspect (1) .tscn defaults missing, (2) editor cache, (3) UI input quirks.

### Architecture seams worth noting
- **GameState boolean flags** (dialogue_open, schematic_open) as cross-module handshake. Camera + player + robot read these to gate input/movement. Cleaner than signals or direct refs for pause-style interactions.
- **Shared 3D component** cody_3d_view.gd extends SubViewportContainer with rotatable + auto_spin flags. Used by chat dialogue and schematic. Pattern is reusable for future characters.
- **Robot state machine** in iso_robot.gd is the LLM-control seam. Replace _find_next_plot() with an LLM-driven picker, or add a REMOTE state, and the rest of the loop unchanged.

### Confidence shifts
- godot_isometric: medium → high
- New domains added: godot_ui_modal, godot_subviewport_3d, godot_tween_3d, operator_iteration_loop, dialogue_tree_design (see competency_map.json)

### Next
- No active stop gate. Operator's call. Likely directions: actual skill-tree unlock logic (food cost + applied effects), Cody's personal-experience counter to vary dialogue lines, camera-follow on the player, save/load, the second floor.

---

## Session 3 (2026-04-30 → 2026-05-05) — Player-driven planting, camera modes, articulated body

Three big arcs in this session: a complete crop planting loop, three camera modes
the operator can toggle between, and a full procedural body-animation system on
the player. The slice has now become a small living game with most of the
"feel a moment" beats wired up.

### What landed

**Crop planting v1**:
- Replaced auto-Voronoi fill with a player-driven loop. Starter garden seeds a
  contiguous radial ring around the elevator (`STARTER_GARDEN_RADIUS = 6.7`); the
  rest of the floor is empty tilled plots ready for the player to plant into.
- New south-wall **seed dispenser** (`scenes/iso_prototype/iso_dispenser.gd`)
  with six windows, per-type stock + independent refill timers. Number keys 1–6
  dispense the corresponding type directly when the player is in range; outside
  the dispenser the same keys just select the seed type. E still works as a
  fallback for the currently-selected seed.
- Per-window number labels + stock count gauges in 3D, plus a `SEEDS` overhead
  beacon that fades in on player approach.
- New **seed pouch** + `selected_seed_type` in GameState. Pouch starts empty;
  HUD hidden until the player's first successful dispense (avoids confusing
  "× 0" rows pre-tutorial).
- Bottom-of-screen seed selector HUD (`seed_hud.gd`) with sequential staggered
  reveal — header + six cells slide up from below with TRANS_BACK overshoot.
  Each cell shows number-key, fruit-color swatch, name, pouch count, and a
  current/max stock gauge that tints red when low.
- New `P` plant verb: kneel for 0.5 s, then `iso_floor.plant(coord, seed_key)`
  converts the empty plot to a stage-1 sprout via a sprout-emerge tween +
  dirt-poof + "Planted X" floater.
- Public iso_floor API: `find_nearest_empty_plot_near()`, `plant(coord, key)`
  parameterised by Vector2i + lowercase seed key — same surface a future
  Builder-Cody can call.

**Camera modes** (`camera_modes_hud.gd` + iso_camera mode-switch):
- Three-button toggle in HUD top-right (under Resources): ISO / PROFILE /
  OVER-SHOULDER.
- **ISO** = current free-pan iso (default).
- **PROFILE** = side-on follow-cam, pivot tracks player XZ, yaw locked at
  mode-entry to perpendicular-of-current-facing so the player walks through
  the frame without rotating it.
- **OTS** = over-the-shoulder chase, pivot tracks player, yaw lerps toward
  facing+π at 6 rad/s so camera stays behind the body.
- Saves iso pose on leave-iso, restores on return. Pan/Q-R-rotate disabled
  in non-iso modes (zoom always works). Dialogue close-up still wins.
- Default `CAMERA_YAW_DEG_INITIAL` flipped 45° → −135° so the south-wall
  dispenser is in front of the camera on first spawn instead of behind it.
- Cody park position now snaps to a cardinal face of the elevator (computed
  from yaw, snapped to dominant axis) rather than the diagonal corner —
  the diagonal had him intersecting the elevator's StaticBody3D shaft.

**Articulated body + procedural animation** (the big one):
- Refactored player visual hierarchy into real joint pivots: `_legs_pivot`
  at hip, `_torso_pivot` at waist, `_arms_pivot` at shoulder, `_head_pivot`
  at neck. Plus per-side limb pivots `_leg_l/r_pivot`, `_arm_l/r_pivot` so
  left and right can alternate.
- Defined named poses (idle / kneel / charge / tuck / land), each a dict
  of joint rotations. Per-frame `_blend_joint` lerps each pivot toward
  the target pose at 18 rad/s. Charge + land linearly blend with progress
  for smooth ramp-in.
- `is_holding_pose()` exposed for OTS to freeze its yaw chase during
  rooted moments (mid-plant, mid-harvest, charging) so the camera doesn't
  spin around the player at the exact moment they're standing still.
- Charge pose tuned to match flip direction — operator caught that arms-
  back read as backflip wind-up, fixed to arms-up-forward (diver load).
- New walk + run cycle: speed-derived cycle rate
  `cycle_rate = π · speed / (2 · amp_z)` plus piecewise foot trajectory
  (half cycle plant with foot fixed in world, half cycle swing through
  air with sin-based lift). Result: feet plant on the ground, body
  translates over them — no more skating. Arms swing counter-phase to
  legs at 65% amplitude. Body bobs (sinks) at each foot strike.
- Movement locks once `_charge_time > CHARGE_MOVE_LOCK_THRESHOLD = 0.12`
  so the player no longer slides around in a charged-jump pose. Quick
  taps stay free for run-and-jump.

### Notable failures + fixes

- **F-011** Script `.uid` files must exist for `ExtResource` references in
  `.tscn` to resolve cleanly — newly-added `iso_dispenser.gd` had no `.uid`,
  and the scene silently fell back to a script-less Node3D (dispenser
  invisible + non-interactable). Fix: `--headless --path . --import` to
  generate the `.uid`, then pin its value in the `.tscn`.
- **F-012** Animation pose body-language must match upcoming physics:
  arms-back charge pose reads as backflip wind-up, but our flip is forward,
  so the takeoff felt surprising. Operator caught it instantly. Fix: arms
  up-and-forward (diver load) for the front-flip wind-up.
- **F-013** Procedural locomotion with fixed cycle rate + sin trajectory
  makes feet skate — they're always moving so they slide along the body
  vector. Fix: speed-derived cycle rate + piecewise plant/swing trajectory
  with inverse-sin solving leg rotation from desired foot Z.
- **F-014** Diagonal Cody park position (`(sin(yaw), cos(yaw)) · offset`)
  with offset = 2.7 puts him at distance 2.7 from elevator centre, but
  the elevator core extends to ±2 on each axis — diagonally his chassis
  intersects the StaticBody3D shaft. Snap to dominant cardinal axis +
  bump offset to 1.0 m clearance.

### Operator iteration patterns (observed this session)

- "It's just kind of an awkward look" / "isn't really making sense" / "doesn't
  feel quite right" — taste-driven feedback, not a spec. Read the current
  pose against the surrounding physics + body-language conventions; usually
  there's an animation principle being violated.
- Will surface real animation-principle gaps. Notable: foot-doesn't-plant
  observation, charge-pose-vs-flip-direction. These are insightful and
  almost always worth implementing.
- Prefers the procedural / programmatic approach so the operator can tune
  via constants. Don't reach for animation files / AnimationPlayer; do it
  in code.

### Architecture seams worth noting

- **GameState `camera_mode` string** decouples HUD from camera node directly.
  HUD writes the mode; iso_camera reads it once per frame and tweens. Easy
  to add new modes (TOP_DOWN, CINEMATIC) without touching the HUD wire-up.
- **Pose dicts as data** (POSE_KNEEL, POSE_CHARGE, etc.) make tuning a
  matter of editing constants, no logic changes. New poses cost ~5 lines.
- **Per-limb pivots compose with parent pose pivots**. A kneel still has
  arms reaching down even while the locomotion cycle is gated off. The
  composition is multiplicative rotation; the gait pivots add on top of
  the pose pivots.
- **Capture rig at `tools/anim_capture.tscn`** (gitignored, not shipped):
  drives Input.action_press from a script, writes PNG sequence via
  `--write-movie`, supports cmdline args for capture kind + camera mode.
  Made animation analysis tractable from chat. Pattern is reusable for
  any future animation iteration.

### Confidence shifts

- New domain: `procedural_character_animation` — high confidence after the
  body refactor + speed-synced gait work.
- `godot_isometric` reaffirmed at high; camera mode toggle math worked
  on first try once the yaw/distance/tilt formula was clear.
- New rules:
  - `rules/godot_locomotion_cycle.md` (speed-synced piecewise gait pattern)
  - `rules/godot_script_uid.md` (uid files matter; run --import)
  - `rules/animation_pose_alignment.md` (body language must match physics)

### Next

- No active stop gate. Operator's call. Open threads: animation polish
  (e.g. tuck flip rotation rate scaling with charge, forward arc on jump),
  Cody experience counter for varied dialogue, save/load, second floor,
  skill tree unlock logic.

---

## Session 4 (2026-05-05 → 2026-05-06) — Agent loop hardening + second-floor design

Brief session — no gameplay code commits since the Session 3 capture. Two
agent-infrastructure commits landed (auto-capture hook + rule lookup index
+ specialized subagent), and an in-flight design conversation about adding
a second floor surfaced as the next likely direction.

### Agent loop infrastructure

- **Auto-capture hook** (`agent/capture_session.sh`, wired in
  `.claude/settings.json` as `SessionEnd:clear` and `PreCompact:auto`):
  when the operator runs `/clear` or context auto-compacts, the script
  backgrounds a Claude headless run that distills new takeaways into
  `agent/` and creates a single `chore(agent): capture session takeaways`
  commit. The hook itself returns in milliseconds so `/clear` isn't
  blocked. The script self-suppresses if no commits have landed since the
  last touch of `agent/`, so empty-session clears no longer spam. Default
  is no-push; operator reviews and pushes manually.
- **Rule lookup index** added to CLAUDE.md mapping work-area → rule file
  (locomotion → `godot_locomotion_cycle.md`, .tscn-fixes-not-taking-effect
  → `godot_editor_cache.md`, fading 3D meshes → `godot_3d_fade.md`, etc.).
  Reading the matching rule before non-trivial work is a 30-second tax
  that prevents repeating a failure already in the log.
- **godot-iso-builder subagent** (`.claude/agents/godot-iso-builder.md`)
  pre-loads project conventions and the rule index for specialized Godot
  work — callable when a task is clearly Godot-iso-specific.

### Design conversation in flight

Operator open to a second floor as a method for building stubs into the
next piece of narrative via how the floor lands. Two directions surfaced
in chat:

- **Floor 2 (descend) — planters / food production.** Elevator drop is
  the narrative beat: Garden's sunlit utopia gives way to the working
  level beneath. Lands into Cody's existing backstory threads (foundry he
  misses, predecessors in a vault — could literally render an older
  Cody-model frozen mid-task). Mechanically extends the harvest loop —
  planters at stage 4 produce food, points at the Floor 1 diner pipeline.
  Stubs the predecessors-vault and food-chain → diner.
- **Floor 4 (ascend) — last Act 1 floor before the RGB threshold.**
  Landing teases the Floor 5 RGB door humming above; first hint that
  something different lives further up. Less canonical material to
  anchor the arrival moment, more invention required.

Recommendation surfaced: Floor 2, since there's more existing thread to
pull on (vault, foundry, melancholy) and the harvest mechanic gives the
new floor an immediate purpose. Floor 4 is the bolder pick if the
operator wants conflict-seeding instead of memory-seeding. Decision
pending — tracked as Q-001 in `request_queue.json`.

### What this session also affirmed

- The capture loop is cheap enough to run unattended. The script's
  "skip if nothing new since last `agent/` commit" guard worked: there
  was nothing new to capture from gameplay code, and the only material
  worth keeping was meta (the loop itself + the design conversation).
  This is the loop catching its own steady state.

### Next

- Operator decision on the second floor (Q-001). If Floor 2 lands:
  descent arrival ceremony, planter mechanic that produces food, vault
  stub showing GX-1..4 predecessors. If Floor 4 lands: ascent ceremony,
  hum of the Floor 5 RGB door audible from below, no other floor
  mechanics required (the landing IS the beat).
- Other open threads unchanged from Session 3.

---

## Session 5 (2026-05-07 → 2026-05-08) — Floor 1 utility floor + multi-floor architecture

Q-001 resolved: operator picked **descend → Floor 1 (utility)** over
ascend → Floor 4. Floor numbering shifted: Garden = Floor 2 (was Floor 3),
Floor 1 = the utility/infrastructure floor that feeds it. Drove a brief
from `b1-utility-floor-godot-brief.md` (operator-local) through M1–M6
in eleven commits. The slice is no longer a one-floor prototype — it's a
two-floor system with a shared chrome module, a universal floor design
doc, and a rideable elevator that scene-swaps with full ceremony.

### What landed

- **Floor 1 (M1–M6)**: utility floor with a master breaker that lights
  the room when pulled, six color-coded systems (water/power/atmosphere/
  data/waste/cargo) with per-system mechanical detail (wheel valve, knife
  switches, fan + grille, 4×4 LED matrix, sluice lever, dispatcher
  console + lamps), Manhattan-routed floor pipes that lay on connect, a
  spine-fill cylinder that rises bottom-up on activate, and yellow
  attention chevrons (`floor_1_arrows_hud.gd`) projecting 3D positions
  to 2D HUD via `camera.unproject_position` to point at whatever the
  next interactable should be.
- **Shared chrome module** (`scenes/shared/floor_chrome.gd`): static-
  method module that builds slab + walls + extension grid + elevator
  core. New floors call `FloorChrome.build_slab(self, _c)` etc.
  Loaded via `preload`, NOT `class_name` (per F-010).
- **Universal floor design doc** (`docs/floor_design_system.md`):
  codifies what every floor inherits — 30×30 footprint, FloorChrome
  builders, central elevator/spine column with chamfered corner pipes,
  iso_camera setup, player follow-spotlight, top-left header / top-right
  status / bottom-right modes HUD layout, tap-E grammar, state-dict-on-
  GameState pattern. Linked from CLAUDE.md.
- **Rideable elevator** (`scenes/shared/elevator_handler.gd`): octagonal
  cross-section (4×4 m square with 0.7 m corner chamfers), 8 sliding
  door panels (2 per cardinal face), six spine pipes distributed 1-2-1-2
  across the four chamfer corners. Box collision on the core was removed;
  chamfer panels carry their own thin collision shapes so corners stay
  solid but cardinal faces are passable — player walks INTO the elevator
  through any open door (F-016). Three-state machine
  PROXIMITY/DEPARTING/ARRIVING with `GameState.in_transit` coordinating
  the receiving scene's fade-in; yellow inner-core glow ramps with the
  door close, leaks visibly through panel seams.
- **Cross-floor passive state sync**:
  `FloorChrome.build_passive_spine_pipes` builds visual-only pipe copies
  on every floor reading `GameState.floor_1.pipe_active` to choose
  cold-vs-fill. No tweens, no per-frame state — built fresh on `_ready`
  reflecting whatever was online when you left. Garden now shows water
  glowing if you activated it on Floor 1.
- **Camera + HUD unified across floors**: Floor 1 uses `iso_camera.gd`
  (Q/R rotate, scroll/=- zoom, drag pan, mode toggle). Camera modes HUD
  moved bottom-right on every floor; floor name became a top-left amber
  header; bottom-left + bottom-centre reserved for floor-specific tools.
- **Backpack + vacuum tubes** (separate but shipped same window):
  cap = 20, mesh scales 0.55× → 1.05× as it fills, four corner tubes on
  the Garden empty backpack for cash. Half-width Cody chat panel.
- **GDScript shadow-warning sweep** (F-015): cleared 10 `tan`/`scale`/
  `plant` shadow + unused-var warnings.

### Architecture observations

- **One repo, multiple floors.** The brief proposed a separate `space
  -tower` repo for production; we adopted the iso slice itself as the
  Godot repo. Each floor lives at `scenes/<floor_name>/` and shares
  autoloads + conventions. Cheaper than coordinating two repos for
  what is now clearly the production project.
- **Tap-E throughout, no holds.** The Floor 1 brief specified
  1.6/1.2/0.9 s holds for connect/activate/breaker. Adapted to the iso
  slice's existing tap-and-tween idiom (~0.5 s, no charge bar) so
  cross-floor interaction grammar stays consistent. Operator confirmed
  the simpler grammar.
- **Bundle milestones when they share state.** M3 + M4 (connect +
  activate) shipped together because the prompt code and source-state
  machinery were 80% shared. M5 (visuals) + M6 (elevator wiring)
  shipped together for the same reason. Operator pre-approved bundling:
  *"if they're simple, let's just blast through them and refine after"*
  — captured in operator_iteration_loop confidence.
- **Universal rules emerged organically, then got codified.** Operator
  asked for camera consistency, then for HUD consistency, then for
  player-spawn-facing-camera consistency. After the third one I drafted
  `docs/floor_design_system.md` — surfacing the implicit rules made
  the next few changes (HUD relocation, footprint match) much faster.

### Rules added

- `rules/godot_shared_module_pattern.md` — preload + static-methods +
  parent-Node-ref pattern for cross-scene shared builders. The shape
  that lets `FloorChrome` work on any floor without runtime class
  registration headaches.
- `rules/gdscript_builtin_shadow.md` — GDScript silently shadows
  built-in functions and Control properties. Common offenders: `tan`,
  `sin`, `cos`, `scale`, `position`, `rotation`. Rename locals to
  domain-specific names.

### Failures captured

- **F-015**: GDScript identifier shadowing (`tan`, `scale`, `plant`)
  triggers reload warnings; fix is renaming locals.
- **F-016**: Rideable elevator was blocked by the core's box collision.
  Replaced with per-chamfer-panel collision so cardinal faces are
  passable. The lesson: when the design says "you can walk INTO this
  geometric thing through specific faces," the collision shape can't be
  a single box that wraps the whole geometry.

### Confidence shifts

- New domain: `multi_floor_architecture` — high confidence after
  shipping Floor 1 + shared chrome + cross-floor elevator + universal
  design doc.
- `godot_isometric` reaffirmed at high; the camera unification across
  floors went smoothly because of the existing `iso_camera.gd`
  abstraction.
- `operator_iteration_loop` confidence reinforced: bundle when
  milestones share state; codify universal rules into a doc the moment
  they emerge as patterns; aesthetic consistency requests are
  permission to draft systemic constraints, not just one-off fixes.

### Next

- Operator playthrough of the rideable elevator end-to-end (round-trip
  Garden ↔ Floor 1 with state visibly persisted across both floors).
- Audio (M5.1) — breaker_pull, pipe_lock, chime per system, hum_loop
  still placeholders. Synthesizing via AudioStreamGenerator vs baking
  from a prototype is its own pass.
- Remaining open threads from prior sessions:
  Cody experience counter for varied dialogue, save/load, skill tree
  unlock logic, animation polish (tuck flip rotation rate scaling with
  charge, forward arc on jump), stairs/ladder alternate vertical travel
  per Cody's "stairs" dialogue branch.
- Q-001 closed.

---

## Session 6 (2026-05-22 → 2026-05-28) — Arboretum (Floors 3 & 4) + multi-destination elevator + plant verb

Worked off a Floors-3-4 brief: Arboretum ground + Canopy deck, edge-only
tree plots, two-story trees that emerge through pre-cut Floor 4 slab
holes, water + sunlight as future gating sources, stairs as a peer to
the elevator. Shipped a runnable scaffold, then iterated the spiral
staircase three times (over-engineered → patched → deleted), wired a
multi-destination elevator chooser to reach any of three floors from
any other, landed the plant verb + continuous 60 s tree growth across
two floors, and fixed two operator-reported regressions (invisible
labels at wide zoom, dead number keys in the chooser) by extracting
two reusable shared modules.

### What landed

- **Floor 3 (Arboretum ground)** — `scenes/floor_3/{floor_3.gd,
  floor_3.tscn}`. FloorChrome chrome, edge-only plots on a stride of 2
  (~52 plots), spiral-then-straight stairs going south from the
  elevator. Header amber, green-tinted ambient + warm overhead lamp.
  ElevatorHandler wires down to Garden and Utility.
- **Floor 4 (Canopy deck)** — `scenes/floor_4/{floor_4.gd,
  floor_4.tscn}`. Slab built tile-by-tile (NOT FloorChrome.build_slab)
  so three regions can be punched out: central elevator square,
  rectangular stairwell, edge tree-hole discs. Thin TorusMesh rim
  around each tree hole reads as a fitted aperture. NO ElevatorHandler
  — stairs-only access (codified in `docs/floor_design_system.md` §11).
- **Multi-destination elevator chooser** — `ElevatorHandler` grew an
  `@export destinations: Array` of `{scene, label, direction}` dicts.
  New `CHOOSING` state above PROXIMITY/DEPARTING/ARRIVING; opens when
  E is tapped with 2+ destinations. Number-key picks via polled
  InputMap actions (primary) + event-keycode-AND-physical_keycode
  fallback (secondary) so macOS keyboard quirks don't softlock the
  chooser (F-018). Backward-compatible: 0 destinations + legacy
  target_scene_path synthesizes one entry.
- **Plant verb + tree growth** — `scenes/shared/arboretum_tree.gd`
  static-method module (per `rules/godot_shared_module_pattern.md`).
  Two varieties (sphere-crown apple, cone-crown pine) alternate on
  plant. growth_t in [0..1] over `TREE_GROWTH_DURATION_MS` (60 s)
  drives trunk height + radius + crown diameter lerps. Floor 3
  renders the full tree; Floor 4 lazily builds the SAME tree once
  growth_t crosses `TREE_FLOOR_4_VISIBLE_THRESHOLD` (0.55) so trunk
  emerges through the pre-cut slab hole.
- **Straight stairs** — `scenes/shared/stairs.gd` static-method
  module. Replaces the spiral entirely (see F-019). Single inclined
  slab (5.5 m × 3 m, ~28°), step-riser visuals on top (no collision),
  side rails. Polled trigger zones at top + bottom call
  `scene_change_to_file`; `GameState.arrived_via_stairs` mirrors
  `in_transit` for stair-side traversal.
- **Label3D auto-scaling** — `scenes/shared/label_scaler.gd` (F-017).
  Per-frame `pixel_size = base × camera.size / default_ortho` keeps
  all 3D prompts at constant on-screen height across wheel zoom.
  Applied to elevator E + Travel + chooser labels, plant prompt, and
  the stairs-down marker.
- **Lighting + slab colour pass on Floors 3 + 4** — ambient bumped
  0.85 → 1.6 (F3), 1.0 → 1.7 (F4); directional 0.85 → 1.25 (F3),
  1.0 → 1.35 (F4); new central overhead lamp at y=5.5; slab colours
  lightened from inky to lived-in. Caught at the same time as the
  spiral-stairs rewrite because the operator couldn't see the
  geometry to navigate it.

### Architecture observations

- **Two flag families for vertical traversal.** The elevator uses
  `GameState.in_transit` (fade + arrival ceremony). The stairs use
  `GameState.arrived_via_stairs` (no fade; player just walks off the
  matching end). Both follow the same shape — set on depart, consumed
  by the receiving floor's `_ready`, cleared after positioning. Adding
  a third travel mode in the future (ladder? lift?) would slot in the
  same way.
- **Cross-floor entity render via growth threshold.** Trees show on
  Floor 4 only after growth_t passes a threshold; below it, Floor 4
  doesn't even instantiate the geometry. State persists across scene
  swaps via `GameState.floor_3.trees`. Pattern generalises: any
  vertically-spanning entity (vine, pipe, tower) can be rendered
  on whichever floors its current state is visible from.
- **Iterating a flagship mechanic by deletion.** Spiral staircase v1
  (over-engineered) → v2 (patched with more segments + proportional
  overlap) → v3 (deleted, replaced with straight stairs). The fixes
  in v2 worked technically but the input/camera mismatch with a
  curving heading was always going to be a player-feel tax. Worth
  ~30 minutes of patching to see the limit, then ~30 minutes deleting
  to recover. Captured the full story in F-019.
- **Operator screenshot-driven loop scales to integration bugs.**
  Five rounds of "labels invisible," "labels too small," "labels
  back," "chooser keys dead," "chooser cleaner please" landed in one
  session. The operator's screenshots routed each round directly to
  a specific surface to fix. The fixes coalesced into two reusable
  modules (`label_scaler.gd`, the chooser pattern in
  `elevator_handler.gd`) without explicit refactor passes.

### Rules added

- `rules/godot_label3d_orthographic_zoom.md` — pixel_size must scale
  with `camera.size` when the camera is orthographic, or labels
  collapse at wide zooms. Includes the LabelScaler usage shape and a
  comparison vs. `fixed_size`.
- `rules/godot_input_keynum_macos.md` — number-key input on macOS
  is unreliable when handled via `event.keycode` only. Prefer
  `InputMap` action polling as the primary path; keep `_input` as a
  secondary path that checks both `keycode` and `physical_keycode`.

### Failures captured

- **F-017**: Label3D pixel_size at constant value invisible when
  camera zooms out (orthographic). Fix: per-frame scale by
  `camera.size / default_ortho`.
- **F-018**: macOS chooser number keys dead when handled via
  `event.keycode` comparison only. Fix: primary path via polled
  InputMap actions; secondary path checks both keycode + physical.
- **F-019**: Discrete spiral-collision approximation left wedge gaps
  at the outer arc (8 tilted boxes, 45° each), AND camera-relative
  WASD fought the curving heading. v2 bumped segments + overlap; v3
  deleted the spiral and shipped straight stairs (a single inclined
  slab with no possible gaps).

### Confidence shifts

- New domain `arboretum_cross_floor_system` — high confidence after
  shipping Floors 3 + 4 + plant verb + cross-floor tree growth + the
  multi-destination chooser. Includes the growth-threshold pattern
  for cross-floor entity render and the two-flag pattern for
  vertical traversal.
- `godot_isometric` reinforced with the orthographic Label3D scaling
  rule (failure pattern + LabelScaler evidence). Added a sub-rule:
  camera-relative WASD fights continuously-curving heading geometry;
  prefer straight segments where possible.
- `multi_floor_architecture` extended with the discrete-collision
  curve approximation failure (F-019) — informs future builds that
  contain helical or rounded traversable geometry.

### Next

- **Phase 2B**: water + sunlight gating for tree growth. Operator
  designed the gate; Phase 2A grew trees immediately so the geometry
  could be tuned first. Need confirmation on whether the gate becomes
  "plant → connect water → activate skylight → growth begins" or some
  softer-gating variant.
- Operator playthrough of the multi-destination elevator end-to-end
  (Garden → Arboretum → Utility → Garden), and the plant + 60 s
  growth on Floor 3 with the canopy emerging on Floor 4 at the
  33 s mark.
- Remaining open threads from prior sessions stand: Cody experience
  counter, save/load, skill tree unlock logic, jump animation polish,
  Cody's "stairs" dialogue branch can now point to actual stairs.

## Session 7 — 2026-05-31
**Goal:** Collapse the four scene-swap floors into one continuous stacked
world, ride-able through a physical elevator, and replace placeholder
tree crowns with genome-driven trees.

### What landed
- **Unified stacked-world tower** (`scenes/tower/tower.tscn` +
  `tower_controller.gd`). The four floors are now offset child Node3Ds at
  `y=(level-1)*FLOOR_3D_STORY_HEIGHT` (story height **6 m**) under one
  player / camera / HUD. Scene-swapping is gone; you walk, fall, and ride
  between floors in continuous space. The dir rename `iso_prototype/ →
  floor_2/` (fd68120) made the layout self-documenting first.
- **Floors built in LOCAL space** (slab top at local y=0); the tower sets
  each node's `position.y`, so floor controllers / `floor_chrome.gd` need
  zero `base_y` awareness. Clean separation — geometry rides up with the
  node transform.
- **Ride-able elevator car** (`scenes/shared/elevator_platform.gd`): one
  physical car in an open shaft (cut through Floors 2 & 3 via an optional
  shaft hole in `FloorChrome.build_slab`). On E it opens a framed 2D
  chooser, then carries the player floor-to-floor. While travelling the car
  OWNS the rider's transform (`GameState.riding_elevator` → `iso_player`
  skips its own physics), so visibility + camera follow naturally. Replaces
  `elevator_handler.gd`'s scene-swap.
- **Genome-driven trees** (`scenes/shared/arboretum_tree.gd`): 12-gene
  genome + apple/pine archetypes over one shared gene space, recursive
  SurfaceTool branch skeletons (merged to 2 meshes/tree) with CUSTOM0
  baking each vertex's growth origin + birth time. A shared reveal+wind
  shader unfolds growth trunk→limbs→foliage on a **GameState sim clock**
  while wind sways on **real TIME** — decoupled so fast-forward doesn't
  shimmy the wind.
- **Per-floor ambience** eased from `tower_controller` (Utility dark/cool →
  Garden warm-dim → Arboretum/Canopy bright green).

### Key non-obvious patterns
- **Scene-swap floors can't model falling across a floor boundary.** Once
  the shaft was open, the swap-on-trigger model looped forever (F-020).
  Continuous space is the only honest representation of vertical traversal.
- **Floor change ONLY when grounded.** Jumping / ceiling-bonk never reveals
  the floor above or moves the camera; you change floors by *landing*
  (`tower_controller._update` gates on `is_on_floor()`).
- **One-way-up via collision layers** (F-021, new rule): regular slabs on
  layer 2, canopy ceiling on layer 1; player drops layer 2 from its mask
  while rising. Lets jumps pass UP through a floor and land on it from
  above, while the glass ceiling still blocks. Pairs with the grounded-gate.
- **Decouple sim-clock animation from real-time animation in one shader.**
  Growth on `GameState` sim time (pausable / fast-forwardable), wind on
  `TIME` (always real) — same material, two clocks, no cross-talk.

### Rules added
- `rules/godot_one_way_collision_passthrough.md` — velocity-gated collision
  mask for selective floor pass-through in a stacked world.

### Failures captured
- **F-020**: infinite respawn loop — scene-swap floors over an open shaft
  hole. Fix: unified stacked world + gravity fall-through.
- **F-021**: solid floor-above blocked upward jumps. Fix: two-layer
  collision + velocity-gated player mask.

### Confidence shifts
- New domain `stacked_world_tower` (high) — one continuous multi-floor
  world with local-space floors, grounded-gated visibility, ride-able
  elevator car, and one-way-up traversal. Supersedes the prior
  scene-swap `multi_floor_architecture` approach (kept for history).
- `godot_isometric` reinforced: dual-clock shader (sim vs real TIME) for
  growth + wind without cross-talk.

### Next
- **Phase 2B** still open: water + sunlight gating for tree growth.
- Interactive play-test of the elevator ride feel (verified headless +
  windowed, but ride feel wants hands-on).
- CLAUDE.md now carries a top callout flagging the unified-tower
  architecture; deeper sections still describe the old separate-scene
  model and should be rewritten when touched.

---

## Session 8 — 2026-06-01 — Ascending tubes, living camera, the Vista + crane, and the stacked-tower invariants

A long screenshot-driven session: shipped the ascending vacuum tubes (Q-002),
reworked the camera into a "living" iso camera, added a 5th floor (construction
Vista) with a drivable crane, fixed a batch of operator-reported regressions, and
— most importantly for the next phase — distilled the recurring failure modes
into `rules/stacked_tower_invariants.md`.

### What landed (feature)
- **Ascending vacuum tubes (Q-002).** `scenes/shared/vacuum_tube.gd` static
  builder renders one-story corner segments built per-floor, tiling corner-to-
  corner up the whole stack like the spine pipes. `scenes/shared/vacuum_lift.gd`
  (top-level, mirrors `elevator_platform`) adds the player ±1-floor **vacuum hop**
  (jump = up, down key = down — a third vertical-traversal method) plus rising
  produce "item transit" capsules. The Garden's `iso_tubes` sell flow now calls
  the shared builder.
- **Living iso camera.** Closer default (ortho 20→16), gentle horizontal follow
  with deadzone + velocity look-ahead, **survey/diorama** on hold-`Tab` + a brief
  auto-pulse on floor arrival, **traversal reveal** (widen/lower during tube hop /
  elevator ride), and motion juice (sprint pull-back, landing dip scaled to impact,
  vertical jump-follow). All knobs in Constants (`CAMERA_FOLLOW_*`, `_SURVEY_*`,
  `_REVEAL_*`, etc.).
- **Floor 5 Vista + crane.** `scenes/floor_5/` — open concrete/steel construction
  deck, the shaft topping out, tube-reachable (`VACUUM_HOP_TOP_LEVEL` 4→5),
  open-sky ambience. `scenes/floor_5/crane.gd` is a drivable crane: E to get in,
  WASD drives + turns it (camera-relative, clamped to the deck), E to get out;
  rides the cab via `GameState.driving_crane`.
- **Edge-fall catch** ("reappear where you jumped from"): plunge up to 5 floors /
  past the bottom off an open edge, then return to the launch point; tree-hole
  drops land on the Arboretum.

### Operator-reported fixes (the instructive ones)
- **Cody dialogue camera** aimed at hardcoded world `y=1.0` → ~5 m below the
  characters in the stacked tower. (Invariant #1.)
- **Cody arrival** was occluded by the now-parked elevator car; re-staged beside
  the elevator + a camera focus onto him. (Invariant #7.)
- **Lit spine-pipe state** stopped at Floor 1 — built cold once at startup before
  any utility was online. Now driven live from `tower_controller`. (Invariant #3.)
- **Elevator "walls" missing** on tube-reached floors — the static shaft had bare
  cardinal faces (only the car made it read enclosed). Added framed-doorway walls
  in `build_elevator_core`; every floor inherited it. (Invariant #4.)
- **Trees grew on the tube corners**; **dispenser labels punched through** from the
  Arboretum (`no_depth_test`). (Invariants #5, #6.)

### The durable learning
All of the above are one of a handful of stacked-world failure modes, now written
down in **`rules/stacked_tower_invariants.md`**: (1) never hardcode world-Y;
(2) transit-ownership + the tower must track `_current_level` during ANY transit
or the destination slab gates off and you fall through; (3) cross-floor visual
state must be live, not baked at `_ready`; (4) shared builders are the unit of
cross-floor consistency; (5) mirror linked per-floor layouts; (6) Y-gate
`no_depth_test` labels; (7) stage ceremonies clear of shared moving infra;
(8) edge-fall plays then returns. Read it before the next floor/vehicle/traversal.

### Next
- Operator is clearing context to start a BIG new production phase. The invariants
  doc + this log are the handoff. Crane boom/hook are cosmetic (no lifting yet) —
  a natural pickup. CLAUDE.md still has stale separate-scene sections to rewrite.


## Session 9 — 2026-06-01 — Scaffolding: Floor 0 renumber, two new floors, the Sky Lounge look-out

**Goal (operator-set):** lay scaffolding for the next big *worldbuilding* phase.
Three asks, all decided up front via a structured question: (1) Utility becomes
**Floor 0 / the basement** and every number drops by one; (2) add two new BLANK
floors — **Residential (4)** and a **Sky Lounge (5)** sky-bar with a "look out the
window" camera — keeping the construction Vista as the unnumbered **Roof**; (3) a
**full self-documenting rename** (dirs + GameState keys + node names).

Built + verified in three committed phases (the windowed screenshot harness was
the gate at each step — NOT `--headless`, which renders nothing):

### Phase A — renumber + rename (`82d982e`)
Internal `level` went **0-indexed to match the display** (`base_y = level*story`,
dropped the `-1` in the tower, elevator, and vacuum lift). The bottom four floors
keep their exact world-Y; only their displayed number dropped. Full rename:
`scenes/floor_1..5` → `utility / garden / arboretum_ground / arboretum_canopy /
roof` (+ controller scripts renamed to match), `GameState.floor_1/3/4` →
`utility / arboretum / canopy`, `Floors/Floor1..5` nodes → content names. Done
with `git mv` (history preserved) + `perl` word-boundary key renames + targeted
`sed` for paths (BSD sed has no `\b` — use perl). Knock-ons: elevator
`SERVED`/`NAMES`, vacuum hop range, HUD wayfinding keys + group-visibility checks,
env presets, `_shot_harness`, and a **new `seed_select_0`** action (key 0) so the
elevator chooser can pick the basement. `vacuum_lift` now finds a floor node by
world-Y, not by `"Floor%d"` name, so the rename can't break the tube-glow lookup.

### Phase B — two new floors + float the roof (`cc433fa`)
`scenes/residential/` + `scenes/sky_lounge/` — blank shells from the shared chrome
(slab w/ shaft hole + walls + extension grid + elevator core + lit spine pipes +
corner vacuum tubes). The Vista/Roof floated from y=24 → y=36 (level 4 → 6) to sit
atop them. Transit reaches everything: vacuum hop range 0..6, elevator serves
0,1,2,4,5 (Canopy 3 stairs-only, Roof 6 tube-only). Harness hops 1→6, lands solid
on every floor.

### Phase C — the Sky Lounge look-out (`46a1b77`)
Operator picked **free-orbit (player drives)** + a **placeholder skyline**. The
Sky Lounge gets floor-to-ceiling glass; `scenes/shared/cityscape.gd` is a seeded
ring of distant buildings the tower reveals only from Floor 4 up
(`CITY_REVEAL_LEVEL`). Walk to the glass → `[E] look out` → the camera detaches to
an exterior vantage (`GameState.looking_out`): Q/R orbit, arrows pan, wheel zoom,
E/Esc ease back. Implemented as a **new modal camera owner** in `iso_camera`
(`_update_lookout`) that drives the pivot and renders via the existing
`_apply_orbit`, so it composes with the normal machinery. Per invariant #2 the
player freezes, the tower stops driving the pivot, and the vacuum lift defers.
Verified with a dedicated `_lookout_harness.tscn` using the tower's OWN camera.

### Durable learnings
- **BSD `sed` has no `\b`.** For word-boundary renames on macOS use `perl -i -pe`.
  (Cost a wasted no-op sed pass before the perl redo.)
- **A camera-only modal owner is a lighter case of invariant #2:** freeze the
  player + defer other input owners, but skip the `_current_level` tracking (the
  player doesn't move). Captured in the invariants doc.
- **Inserting a floor mid-stack pushes everything above it up** — the roof's
  content didn't change, only its `level` + transform. Clean because base_y is
  derived, never literal (invariant #1 paying off).

### Open / next
- **The big worldbuilding phase** is the operator's next direction — the two blank
  floors (Residential units + residents; Sky Lounge fit-out) and a real skyline are
  its natural first fills. Logged as Q-005.
- **Look-out framing** is a reasonable first pass (tilt/distance/anchor are all
  `LOOKOUT_*` constants) — open to a feel pass.
- **Not yet screenshot-verified:** an actual elevator *ride* to the new floors 4/5
  (logic is wired — `SERVED` + travel math; the hop path was verified). Catch in
  interactive play or a follow-up harness.
- Docs brought current: CLAUDE.md floor table + architecture callout, the
  invariants doc base_y formula + floor numbers.

### Addendum — look-out redesigned to a third-person POV (operator feedback)
First look-out (free-orbit around the tower exterior) felt wrong and the operator
hit a "super loop." Rewrote it into a **third-person POV**: on `[E]` the camera
drops just over/behind the player's head and switches to **perspective** (the
rest of the game is orthographic), you **drag** the mouse (or Q/R + ↑↓ as a
keyboard fallback) to free-look any direction, and the **body + head turn to
follow** the look angle (iso_camera publishes `look_view_yaw/pitch`;
`iso_player._apply_lookout_pose` turns `_visual` + tilts `_head_pivot`). You see
the back of the head with the city beyond — in the body, not through the eyes.
- **Loop fix:** the whole mode was rewritten with one clean enter/exit + a
  `LOOKOUT_REENTER_COOLDOWN` so a single E can't re-arm instantly.
- **Exit-restore bug caught + fixed:** the ease-back originally fired the
  ortho-restore on a *distance* threshold, which stalls at high frame rates (the
  camera returned to position but stayed perspective). Switched to a
  fixed-duration (`LOOKOUT_EXIT_DUR`) time-based ease so the restore ALWAYS
  completes regardless of fps. (Learning: don't gate a state transition on
  convergence distance when frame-rate varies — use a timer.)
- Verified via `_lookout_harness.tscn`: POV shows the back of the head + skyline
  in perspective; drag/keys turn the body + head; exit restores the ortho iso
  view (`proj` 0→1). Camera tunables are all `LOOKOUT_*` in constants.

### Addendum 2 — three operator polish asks
- **Shaft fall fixed (Q-004 resolved).** Operator: tube-hop to a floor, walk into
  the elevator, and you fall down the open shaft. Fix: an invisible collision
  **shaft grate** across the opening on every holed floor (in
  `FloorChrome.build_slab` + the Canopy's tiled slab). Collision-only so it never
  blocks the cabin view; child of `SlabBody` so the tower's existing per-floor
  gating handles it (jumps still pass up; rides own the transform so they pass).
  You now stand at the shaft and call/ride instead of dropping. `_shaft_harness`
  confirms the player HOLDS at floor level over the shaft.
- **Glass elevator core.** The inner shaft column now uses the Canopy-glass feel
  (`build_elevator_core` `inner_mat` → translucent bluish, alpha 0.18) so you
  watch the cabin rise/fall through it; the grey chamfer corners + door-frame
  beams stay opaque. Nothing drives `inner_mat`'s glow, so the restyle was safe.
- **"Drag to look" retires itself.** Once the player actually starts looking
  (look angle deviates from entry), the "drag to look" line slides off +x and
  fades (`sky_lounge` `_hint_anim`); the "E/Esc back inside" line stays.

## Session 10 — 2026-06-01 — GameDirector spine, Step 1: decision log + autoload scaffold

**Goal:** stand up `GameDirector`, the missing phase/state director (handoff system
gap (a)), as the 5th autoload — scaffold only this step. No exterior, no boot flag,
no hire UI, no HUD wiring, no phase stubs (those are steps 2–5). Existing interior
systems (Cody, Garden, Utility, Arboretum) untouched.

**Trust note:** a `Downloads/CLAUDE.md` draft handed in at session start listed
`game_director.gd` + "construct-from-empty" as already shipped — neither was in code.
Trusted code → git log → session_log → repo CLAUDE.md (accurate). Verified clean
green-field before building: no `GameDirector`/`phase_changed`/`EMPTY_LOT` symbols
anywhere, no `phase` field in `game_state.gd`.

### What shipped (uncommitted — operator reviews + commits)
- **`autoloads/game_director.gd`** (new). `Phase` enum
  `EMPTY_LOT → HIRE_PARTNER → BUILD_STRUCTURE → BUILD_INTERIORS → ACTIVATE_FLOORS →
  SHARE → TEMPORAL`; `current_phase` (defaults `EMPTY_LOT`); `phase_changed(phase)`
  signal; `set_phase()` (idempotent guard, mirrors + emits) as the manual entry point
  the hire beat + debug affordance will call in later steps; `_mirror()` publishes into
  `GameState.phase`. Transition GATES deferred to steps 3/5. Litmus honored:
  GameState = "what is true in the world" (pure data); GameDirector = "what should
  happen next and when". Director reads + mirrors GameState, never a parallel copy.
- **`autoloads/game_state.gd`** — added one scalar `var phase := 0` (mirror of
  `GameDirector.Phase.EMPTY_LOT`). Literal `0`, not a `GameDirector.Phase` ref, so
  GameState keeps zero load-order dependency on the director (GameState loads first;
  the director overwrites in its own `_ready`).
- **`project.godot`** — registered `GameDirector` in `[autoload]` AFTER `AudioManager`
  (the four originals untouched). `run/main_scene` unchanged (`tower.tscn`).
- **`agent/request_queue.json`** — logged D-001 (5th autoload, resolved), D-002
  (exterior is in-world inside tower.tscn, no scene swap, resolved), D-003 (deferrals:
  construct-from-empty / consequential hire / time_of_day-wrapping / interior-beat
  mapping — queued).

### Verify (per rules/godot_screenshot_harness.md)
- `--headless --import` → `game_director.gd.uid` generated.
- Headless parse/smoke on `tower.tscn` (`--quit-after 90`): silent = clean.
- Windowed `_director_harness` (gitignored): `current_phase=0` (EMPTY_LOT),
  `GameState.phase=0`, `phase_changed` signal + `set_phase` present, `RESULT ok=true`.
  Boot PNG (`_shots/director/1_boot.png`) shows the normal Floor 1 / Garden launch —
  unregressed. No errors.

### Open / next
- Step 2: minimal in-world `EMPTY_LOT` exterior + boot flag in `constants.gd` (old
  direct-to-tower boot behind the flag); reuse the `scenes/shared/cityscape.gd`
  ground-plane pattern.
- Step 3 watch-out: the five hire-name buttons must set `focus_mode = 0` — `jump` is
  bound to Space (keycode 32) which is also `ui_accept`, so a focused button would be
  auto-activated by the first jump press (failure F-008 class; see
  `rules/godot_button_focus.md`).

### Step 2 — minimal exterior empty lot (`EMPTY_LOT`) + boot flag

Built the game's new front door: a stand-alone empty dirt lot you open on, in-world
inside `tower.tscn` (decision D-002 — no scene swap, `run/main_scene` unchanged). A
boot flag picks the START STATE within the one scene.

- **`constants.gd`** — `BOOT_TO_EXTERIOR` (true = open on the lot; false = dev
  straight-to-Garden) + `LOT_CENTER`/`LOT_SIZE`/`LOT_GROUND_Y`/`LOT_DIRT_COLOR`. Lot
  staged at x=+40, clear of the tower stack (x~0), so the exterior needs zero
  special-casing of floor collision / the elevator shaft.
- **`scenes/shared/empty_lot.gd`** (new, mirrors `cityscape.gd`) — flat dirt PlaneMesh
  + a thin StaticBody3D collider (layer 2, like the slabs) so the player stands on it;
  `spawn_position()` returns the lot centre at the surface.
- **`tower.tscn`** — `EmptyLot` node under the root + `empty_lot_path` export.
- **`tower_controller.gd`** — boot branch in `_ready`: if `BOOT_TO_EXTERIOR` and the
  director is at `EMPTY_LOT`, spawn on the lot and set `_exterior=true`; else the
  existing Garden spawn (factored into `_spawn_in_garden()`, shared). `_update()` early-
  routes to `_update_exterior()` while `_exterior`: hides all floors + cityscape, shows
  the lot, drives pivot.Y to the lot (camera XZ-follow is automatic via iso_camera),
  pushes a neutral "EXTERIOR / EMPTY LOT" header (`set_floor(-1, …)` hides every floor
  panel for free), and a new `_preset_for(-1)` open-daylight environment. Added a public
  `enter_tower()` (clears exterior, hides lot, drops to the Garden spawn) — the
  continuous-world handoff, stubbed now, called by the Step 3 hire.

**HUD sentinels:** `_hud_level` initial value is -1, so the exterior-pushed marker uses
-2 (distinct from -1 = force-repush and from real levels >=0) — otherwise the first
exterior frame wouldn't push the header.

**Verify (windowed harness):** exterior boot → `_exterior=true`, player at LOT_CENTER
(40,0,0); `2_lot.png` shows the dirt lot + player under the iso camera, daylight sky, no
tower. Dev path (phase forced past EMPTY_LOT, same branch BOOT_TO_EXTERIOR=false hits)
→ `_exterior=false`, player at the Garden spawn (0,6,-6); `2_tower.png` is the normal
Floor 1 / Garden, unregressed. Headless parse clean; no errors.

**Minor follow-up (not blocking):** the always-on wayfinding chrome still reads
"E ride elevator" on the lot — out of place; fold into the Step 4 HUD objective work or
a later polish.

### Step 3 — trivial one-of-five partner hire (`HIRE_PARTNER`)

The hire beat, on the exterior, with zero mechanical consequence (pure story): pick one
of five names → stored → phase advances → hand off into the tower (today's Garden spawn).

**Flow (two walkable exterior beats):** boot `EMPTY_LOT` → lot + a centered card "AN EMPTY
LOT" with a single "▸ HIRE A PARTNER" CTA. Click → `set_phase(HIRE_PARTNER)` → card becomes
"CHOOSE YOUR PARTNER" + the five names. Click a name → `GameState.partner_name = <name>`,
`set_phase(BUILD_STRUCTURE)`, `tower_controller.enter_tower()` → land on the Garden, card
self-hides (phase no longer EMPTY_LOT/HIRE_PARTNER).

- **`scenes/garden/hire_partner.gd`** (new) — the card. Mirrors `camera_modes_hud.gd`:
  clickable `PanelContainer` cells via `gui_input` (NOT `Button`), so nothing can steal the
  Space/Enter `ui_accept` that jump binds (F-008 sidestepped by construction, not a
  `focus_mode` patch). Shrink-wrapped centered card (anchors 0.5 + GROW_BOTH) so the CTA is
  compact and the name list grows it. Hover restyle. Self-shows by phase via `phase_changed`.
- **`game_state.gd`** — `var partner_name := ""`.
- **`constants.gd`** — `PARTNER_NAMES := ["MARA","TOBIN","REESE","IRIS","VANCE"]`
  (placeholders — rename freely; worldbuilding is Q-005).
- **`tower_controller.gd`** — `add_to_group("tower_controller")` in `_ready` so the panel
  reaches `enter_tower()` without a brittle path. (`enter_tower()` from Step 2 gets its first
  real caller.)
- **`tower.tscn`** — `HUD/HirePartner` node after `HudManager` (draws on top).

**Verify (windowed harness, full flow):** boot → phase 0, CTA shown (`3_lot_cta.png`); CTA
click → phase 1, five names (`3_choose.png`); pick index 2 → `partner_name=="REESE"`, phase 2
(BUILD_STRUCTURE), `_exterior=false`, player at Garden spawn (0,6,-6), card hidden, Garden
renders normally (`3_in_tower.png`). Parse clean; no errors; Cody/interiors untouched.

**Minor (Step 4 territory):** the tower_hud title still reads "EMPTY LOT" during
HIRE_PARTNER (exterior header is static) — the per-phase objective line will drive that.

### Step 4 — per-phase HUD objective line

`tower_hud.gd` now shows an arc-objective line at the top of the wayfinding panel, driven
off `GameDirector.phase_changed` (independent of the per-floor `set_floor`). `OBJECTIVE` map
phase→string (placeholder copy). Reuses `_hint_label()` + `_format_hint()` + `_divider_style()`
— objective line, divider, then the existing move/verb lines. Connects to `phase_changed` in
`_ready` and seeds from `current_phase`. Verified: line reads "Survey your empty lot." on the
lot and "Raise the tower, floor by floor." (BUILD_STRUCTURE) after the hire-handoff into the
Garden. Committed `071cc47`.

### Step 5 — stub remaining phases + debug advance

The enum transitions are already no-ops (`set_phase` just mirrors + emits), so this makes the
mid/late phases reachable + proves they emit cleanly.
- `game_director.gd`: `advance_phase()` — `set_phase((current_phase + 1) % (Phase.TEMPORAL + 1))`,
  wraps.
- `project.godot`: `debug_advance_phase` input action on `]` (keycode 93), mirroring the
  existing `\` `debug_floor_switch`.
- `tower_controller.gd`: `_process` handles the action via `_debug_advance_phase()`, which
  advances the director AND keeps the world coherent — advancing out of the exterior beats
  (phase ∉ {EMPTY_LOT, HIRE_PARTNER}) calls `enter_tower()`; wrapping back to EMPTY_LOT calls
  the new `enter_exterior()` helper (factored from the Step-2 boot branch; the boot branch now
  calls it too). HUD sentinel `-3` forces the exterior header to re-push on re-entry.

**Verify (windowed):** walked all 8 advances from boot — phase 0→1 stay on the lot
(`_exterior=true`, y=0), 1→2 enters the tower (`_exterior=false`, y=6), 2→6 stay in the tower,
6→0 wraps back onto the lot (`_exterior=true`, y=0). Objective line updates each step; no
errors. `5_build_interiors.png` shows the Garden rendering normally under the BUILD_INTERIORS
objective.

### GameDirector phase — DONE
All 5 steps shipped (`097463b`, `7ba9f19`, `257db09`, `071cc47`, + step 5). The director
sequences the arc end to end; the two real opening beats (EMPTY_LOT + HIRE_PARTNER) work; the
old direct-to-Garden boot is preserved behind `BOOT_TO_EXTERIOR`; the hire has zero mechanical
consequence; GameState stays pure data (the director mirrors into it); exactly one new autoload;
Cody + all interiors untouched. Decisions D-001/D-002 logged resolved, D-003 deferrals queued.

### Step 5 follow-up — verified real clicks + fixed the exterior wayfinding wart

- **Verified real mouse input** routes to the hire card (not just direct handler calls):
  pushed genuine `InputEventMouseButton` events at the cell rects through the CanvasLayer +
  `mouse_filter` stack — CTA click → HIRE_PARTNER, name click → `partner_name="REESE"`, phase
  2, `_exterior=false`. The hire beat works in-game.
- **Fixed:** the lot wayfinding still showed the interior MOVE_LINE ("[E] ride elevator …
  [Tab] survey") — wrong on the exterior. Added `MOVE_LINE_EXTERIOR` (move/sprint/jump/turn/
  zoom only) + a `WAYFIND[-1]` here-line ("your plot of land · bring on a partner to break
  ground"); `set_floor` picks them when `level < 0`. The lot HUD now reads coherently.

### Follow-up — the two flagged low-priority items, fixed

1. **Debug-advance key hardened for the macOS keynum quirk** (`rules/godot_input_keynum_macos.md`).
   `debug_advance_phase` now has TWO events — one `keycode=93`, one `physical_keycode=93` — so
   the action fires whether the OS populates keycode or physical (a `keycode=93`-only binding
   silently misses macOS events that arrive `keycode=0` + `physical=93`). Verified with
   `InputMap.event_is_action`: matches both event shapes (true/true). (Note: synthetic
   `push_input`/`parse_input_event` of key events doesn't reliably drive `is_action_just_pressed`
   in a headless-launched window — `event_is_action` is the authoritative binding check; real OS
   input updates the action.)
2. **Phase-aware exterior header.** `tower_controller._update_exterior` now drives the header off
   the arc phase (re-pushing when it changes), tracked by `_ext_hud_phase`: EMPTY_LOT →
   "EXTERIOR / EMPTY LOT", HIRE_PARTNER → "EXTERIOR / CHOOSE A PARTNER" (was a static
   "EMPTY LOT" through both beats). `enter_exterior` resets the tracker so re-entry re-pushes.

## Session 11 — 2026-06-01 — Time-of-day (TEMPORAL): the day/night clock

**Direction (operator brief):** introduce TIME-OF-DAY as a SECOND axis. Hard principles:
two axes (narrative Phase = linear/pass-through; time-of-day = cyclic/always-on, NOT an enum
value); the clock BROADCASTS, holds zero per-location logic (locations subscribe + interpret
locally); gradients not switches (smooth ramps, soft thresholds, hysteresis); litmus (what is
true → GameState; what happens next/when → GameDirector; scenes render; clock broadcasts).
Forward-looking substrate for later emergent character tension — build a clean broadcaster
now, NO character logic yet. Method: decision-gated stages, surface-don't-guess.

### Stage 0 — GameDirector polish (no behavior change)
- `advance_phase()` wrap now uses `Phase.size()` instead of the magic `(… % (TEMPORAL+1))`,
  so it survives enum edits. Comment marks the modulo wrap as DEBUG-only (real play is forward
  pass-through).
- Added `phase_name(p)` helper (readable logging; bounds-guarded → `PHASE_n`).
- Header comment now states the TWO-AXIS principle explicitly (Phase linear; time-of-day is a
  cyclic layer that lives elsewhere, switched on only at the TEMPORAL moment).
Verified: `Phase.size()==7`, full walk wraps to EMPTY_LOT (same as before), `phase_name`
incl. out-of-bounds. Parse clean.

### Stage 1 — the clock (decision: new TimeOfDay autoload, derived from sim clock)
Operator decisions: (1) clock lives in a NEW `TimeOfDay` autoload (6th global — the
cyclic-axis sibling of GameDirector); (2) derive from `sim_time_msec` with its own
`DAY_LENGTH_MSEC` (sim_speed stays the global time-scale).

- **`autoloads/time_of_day.gd`** (new) — broadcaster: each frame derives
  `t = fmod(sim_time_msec, DAY_LENGTH_MSEC) / DAY_LENGTH_MSEC`, mirrors into
  `GameState.time_of_day`, emits `tick(t)`. Zero per-location logic. `hour_string()`
  formats 0..1 → "HH:MM". `running` defaults true (free-runs) — **Stage 2 flips it to
  dormant + latches on at TEMPORAL.**
- **`game_state.gd`** — `var time_of_day := 0.0` (world-truth mirror; 0=midnight,
  0.25=dawn, 0.5=noon, 0.75=dusk).
- **`constants.gd`** — `DAY_LENGTH_MSEC` (~4 min) + `DAWN_CENTER`/`DUSK_CENTER`/
  `TWILIGHT_HALF_WIDTH` (soft windows for the Stage-3 lighting modulation).
- **`project.godot`** — `TimeOfDay` autoload registered after `GameDirector`.
- **`tower_hud.gd`** — debug top-centre "TIME HH:MM" readout (always on, every floor +
  exterior).

Verified (windowed): driving `sim_time_msec` to 0/0.25/0.5/0.75/1.25×day →
time_of_day 0.0/0.25/0.5/0.75/0.25 → "00:00/06:00/12:00/18:00/06:00" (wraps correctly);
HUD readout renders top-centre. Parse clean. No visuals touched (Stage 3).

### Stage 2 — TEMPORAL latches the clock on (one-way), starts at a set hour
Decision: the day starts at a fixed hour on latch (anchored, repeatable "first light").

- `time_of_day.gd`: `running` now defaults FALSE; the clock SELF-LATCHES by subscribing to
  `GameDirector.phase_changed` and calling `start()` when it sees `Phase.TEMPORAL` (the
  director never commands the clock). One-way: stays on under every later phase. `start()`
  captures `_start_offset_msec` so the first day begins at `CLOCK_START_FRAC` (07:00)
  regardless of elapsed sim-time.
- `constants.gd`: `CLOCK_START_FRAC := 7/24`.
- `tower_hud.gd`: debug readout shows `TIME --:--` while dormant.

Verified (windowed): boot dormant (--:--, time_of_day 0); at TEMPORAL → running, 07:00; +6h
sim → 13:00; debug-wrap phase back to EMPTY_LOT → clock STILL running (one-way); +6h → 19:00.
Parse clean. Still no visuals (Stage 3).

### Stage 3 — time-of-day lighting: floor identity × time modulation
Decisions: per-floor sky exposure; moonlit-dim nights (not near-black).

- `_preset_for` floors gain `sky_exposure` (0..1): Utility 0.0 (windowless), Garden 0.18,
  Arboretum 0.40, Canopy 0.60, Residential 0.50, Sky Lounge 1.0, Roof/exterior 1.0.
- `_sky_state(t)` — pure function of the hour, NO location logic: `elev = -cos(TAU*t)`
  (−1 midnight, 0 dawn/dusk, +1 noon); smooth `intensity` (moonlit floor `TOD_NIGHT_INTENSITY`
  → 1 at noon), `warmth` (cool moon → golden horizon → white noon), `sky_tint` bg, and the sun
  `pitch`/`yaw` (the sun ROTATION, which didn't exist before).
- `_drive_environment` composes: targets start at the floor IDENTITY, then time modulates on
  top scaled by `sky_exposure` — ambient tinted by warmth, ambient/sun energy × intensity, bg
  toward sky_tint; the single light's DIRECTION is global + time-driven (harmless on
  low-exposure floors since their sun energy stays low). The existing k=0.06 lerp is the
  hysteresis. **Clock dormant or exposure 0 → no-op, so pre-TEMPORAL the look is exactly
  today's.** Constants: `TOD_NIGHT_INTENSITY`, `TOD_SUN_PITCH_MIN/MAX`, `TOD_SUN_YAW_SWEEP`.

Verified (windowed): Sky Lounge (exposure 1.0) swings cool-blue noon → golden dusk → dark
moonlit night; Residential (0.5) keeps its warm interior identity and shifts gently — per-floor
exposure differentiates them. Parse clean; Cody/elevator/geometry untouched.

**Note for the operator:** the clock only LATCHES at TEMPORAL (the last phase), so day/night
isn't visible in normal early play — walk to TEMPORAL with the debug `]` to see it. Absolute
brightness/feel is screenshot-tunable via the TOD_* constants + per-floor sky_exposure.

### Time-of-day phase — DONE (Stages 0-3)
Two-axis clock shipped: GameDirector (linear narrative) + TimeOfDay (cyclic, broadcasting,
zero location logic), latched on at TEMPORAL, driving per-floor lighting modulation composed on
each floor's identity. Commits d03caae, 4d5ee3d, 5c9d5f9, + this stage.

### Follow-ups (operator: push + debug key + feel pass)
- **Pushed** Stages 0-3 (c0936bb..ec79999).
- **Debug `[` key** (`debug_start_clock`, robust two-event binding): calls `TimeOfDay.start()`
  on demand so the day/night swing is testable without walking the arc to TEMPORAL. Commit
  6158888.
- **Lighting feel pass.** Noon read too dark because the modulation capped at the floor
  identity (intensity 1.0 at noon). Added `TOD_DAY_INTENSITY` (1.40) as a midday GAIN —
  `intensity = lerp(NIGHT,1,day) + (DAY-1)*high` — so noon reads brighter than identity and
  night dimmer. Lightened `day_sky` (0.58,0.73,0.95), warmed `horizon_sky` (0.76,0.46,0.28).
  Verified (windowed, measured): Sky Lounge amb energy noon 2.24 / dusk 0.42 / night 0.24,
  sun pitch -62/-27/+8; Residential swings 1.26->0.60 (gentler — exposure 0.5). Bright cool
  noon, warm low dusk, dark moonlit night.
  - **Harness learning (logged):** when jamming `GameState.sim_time_msec` directly and calling
    `_drive_environment(true)` to snap, FIRST wait a frame so `TimeOfDay._process` refreshes
    `GameState.time_of_day` — else the snap reads the stale hour and the slow per-frame lerp
    lags. (Real play is unaffected: time advances continuously and the lerp tracks it.)
