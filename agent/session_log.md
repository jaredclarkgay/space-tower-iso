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

### Next
- Phase 2 (Architecture decision). STOP gate after recommendation lands.
