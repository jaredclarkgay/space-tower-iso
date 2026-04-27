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

### Next
- Phase 1: clone iso demo, review listed references, write
  `references/iso_research.md`.
