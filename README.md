# Space Tower — Iso Vertical Slice

A Godot 4 prototype testing whether an isometric view should become Space Tower's baseline, replacing today's split between 3D exterior and 2D side-on sim.

This repo contains **one Garden floor**, **one controllable character**, and **one pannable/zoomable/rotatable iso camera**. That's the whole scope. No modules, no NPCs, no UI, no economy. The slice exists to answer one question: *does iso feel right as Space Tower's baseline?*

The full game lives at <https://github.com/jaredclarkgay/space-tower>. If iso doesn't pan out, this repo gets archived; the main game stays untouched.

## Run it

```sh
godot --path . --editor      # open in editor
godot --path . --debug       # run game (after Phase 3 builds the scene)
```

Godot 4.6, GL Compatibility renderer, GDScript only.

## Documents

- `docs/` — Space Tower project knowledge (read-only context for the agent).
- `agent/` — Builder Agent self-knowledge: project facts, competencies, failures, requests, session log.
- `references/` — third-party reference material installed during Phase 1.
- `LICENSES/` — third-party licenses for material in `references/`.
- `CLAUDE.md` — scope and conventions for this repo, for AI assistants.
