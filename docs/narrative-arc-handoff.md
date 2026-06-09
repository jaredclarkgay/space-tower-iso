# Space Tower Iso — Narrative-Arc Handoff (corrected)

> **⚠️ SUPERSEDED (2026-06-08).** This was a one-time snapshot frozen at Session 9
> (2026-06-01). It is now stale — e.g. it lists 4 autoloads, but `GameDirector`
> and `TimeOfDay` shipped since, making 6. For current state use **`STATUS.md`**
> (repo root); for the arc, trust `autoloads/game_director.gd`. Kept for the
> historical reasoning in §C/§D only.

**Purpose:** a single, code-verified snapshot for the planning session piecing together the game's full narrative arc in Godot. Checked against the actual files on 2026-06-01, end of Session 9.

**Trust order when sources disagree:** code → `git log` → `agent/session_log.md` → `CLAUDE.md`. CLAUDE.md was re-audited + corrected this session (`72ee172`); if prose ever conflicts with code, the code wins.

**Corrections applied in this revision (2026-06-01 follow-up):** the original conflated the *human partner hire* (a new exterior beat) with *Cody* (the already-built interior robot). They are separate; see §A.4(d), §A.5 steps 1–2, §B.4, and §C. The exterior step mappings were corrected to reflect that **no exterior space exists yet**, and §D was updated (autoload greenlit; exterior-shape + construct-from-empty added).

---

## A. Project inventory (verified)

**1. STACK** — Godot 4.6, GDScript only. GL Compatibility renderer (web export possible later). `run/main_scene=res://scenes/tower/tower.tscn`. No C#/GDExtension/plugins.

**2. RENDERING (isometric)** — A 3D scene graph viewed through an orthographic `Camera3D` locked to an iso angle (−30° X tilt, 45°/−135° yaw) on a `CameraPivot` that snaps 90°. NOT 2D tiles/CSS/sprite-stacking. Verticality = real height in one continuous 3D world: every floor is an offset child `Node3D` under `Floors/` at `y = level * 6 m`. No scene-swapping — you walk/ride/vacuum-hop/fall between floors; `tower_controller.gd` gates visibility to the current floor + below.

**3. STRUCTURE**
- `autoloads/` — 4 globals: `constants.gd` (tunables), `game_state.gd` (single source of truth), `save_manager.gd` (no-op stub), `audio_manager.gd` (no-op stub).
- `scenes/` — content-named dir per floor (`utility, garden, arboretum_ground, arboretum_canopy, residential, sky_lounge, roof`) + `shared/` (cross-floor builders) + `tower/` (runtime).
- `agent/` — Builder-Agent knowledge (`rules/` ~14, `session_log.md`, `request_queue.json`, etc.). `docs/` — design docs. `references/` — cloned Godot demo (reference only). `tools/` — dev tool.
- There are NO per-floor `.tscn` files. Each floor is a `.gd` controller instanced as an offset child of `tower.tscn`, built procedurally. `tower.tscn` is the only runtime scene.
- State lives entirely in `GameState`. No screen/scene swapping — "screens" are floors you traverse; HUD is one `CanvasLayer` whose per-floor groups toggle on current level.
- Key files: `tower.tscn` (whole world); `tower_controller.gd` (positions floors, tracks current floor, gates visibility/collision, drives camera + environment); `game_state.gd` (source of truth); `constants.gd` (tunables); `shared/floor_chrome.gd` (static builders every floor calls); `shared/elevator_platform.gd` (rideable car + its floor chooser, serves 0,1,2,4,5); `shared/vacuum_lift.gd` (±1-floor hop); `garden/iso_player.gd` (articulated player); `garden/iso_camera.gd` (iso camera + Sky-Lounge POV); `garden/iso_robot.gd` (Cody, the one scripted NPC).

**4. EXISTING SYSTEMS (vs. the arc's needs)**
- (a) Phase/state director — NONE. Closest is ad hoc per-floor scripted flow (Utility activation; Cody arrival on harvest count).
- (b) Day/night / time — PARTIAL. `GameState.sim_time_msec` + `sim_speed` is a monotonic sim clock that drives tree growth only. No day/night, no time-of-day, no hour field, no wrap.
- (c) Build/placement — PARTIAL. Crop placement exists (seed→plot, sapling). Floors are built procedurally at startup, not by the player. Roof crane is cosmetic.
- (d) Hire/character — PARTIAL, and PREVIOUSLY MISDESCRIBED. The one scripted NPC is **Cody GX-5 — the INTERIOR robot counterpart** met on the Garden floor (already built: arrival ceremony, dialogue tree, Schematics modal). **Cody is NOT the partner hire.** The intended **human-partner hire is a separate, unbuilt EXTERIOR beat** (see §A.5 step 2). No hire/roster mechanic exists; Residential is empty.

**5. THE 7 STEPS — what's implemented**
1. **Empty lot + resource** → NOT built as an exterior. **No exterior / ground-level space exists** in the iso build (interior tower only). The Utility/basement floor is *interior* infrastructure (pull breaker + activate 6 sources: water, power, atmosphere, data, waste, cargo; lit spine-pipes propagate up) — a separate beat, **not** the exterior step 1.
2. **Hire a partner** → NOT built. This is a **NEW EXTERIOR beat** among the very first moments of the game: hire one of five **human** helpers ("pick 1 of 5, this is your biz partner"). **Cody** (the interior Garden robot) is a *different*, already-built counterpart and is **not** this step.
3. **Build structure layer by layer** → not implemented (floors pre-built; Roof crane cosmetic). Intended mechanic = construct-from-empty (player-built floors) — see §C / §D.
4. **Build each floor interior** → not a mechanic (Garden + Arboretum have interiors; Residential + Sky Lounge are blank wired shells).
5. **Activate floors with characters** → partial ("activate" = Utility systems flow only; floors not populated with characters).
6. **Share** → stub only (tubes sell produce → cash, but nothing consumes it).
7. **Temporal day/night flow** → partial (growth sim clock only; no day/night).

**6. RUN** — Open editor: `godot --path . --editor` (`/Applications/Godot.app/Contents/MacOS/Godot`). Run: `godot --path .` or `--debug`. No build/export configured (no `export_presets.cfg`). Verify visually with a windowed screenshot harness (NOT `--headless`) — see `agent/rules/godot_screenshot_harness.md`.

**7. LEFTOVERS / STALE** — `SaveManager` + `AudioManager` are no-op stubs. `references/godot_iso_demo/` + `tools/anim_capture.*` aren't game code. No orphan floor scenes. (Prior CLAUDE.md staleness incl. a dead `elevator_handler.gd` ref was fixed in `72ee172`.)

---

## B. Resolved contradictions

**1. `elevator_handler`** — There is NO `elevator_handler.gd`. The car + chooser both live in `scenes/shared/elevator_platform.gd` (`State { IDLE, MOVING, CHOOSING }`). CLAUDE.md's references were stale, now fixed. The inventory was right.

**2. "Four-autoload locked" constraint** — True today, but it's a convention, not code-enforced. Recommendation: add a 5th autoload (`GameDirector`) for the phase sequencer (§C). **Status: Jared has greenlit the 5th autoload.**

**3. GameState clock** — `sim_time_msec` + `sim_speed` exist but are a *monotonic growth timer*, not a day/night cycle. A `time_of_day` system must INTRODUCE day/night (derive a *wrapping* phase from `sim_time_msec` or run its own clock); reuse `sim_speed` as the global time-scale knob.

**4. Human partner vs. Cody (NEW)** — Two distinct counterparts, previously conflated into one `HIRE_PARTNER` beat. The hire is a **NEW exterior** moment: choose one of five **human** helpers, near the start of the game, outside. **Cody GX-5 is the already-built INTERIOR robot** met on the Garden floor — he is *not* the hire and must not be migrated, modified, or re-wired into the director. Confirmed by Jared (Session 9 follow-up). The original §A.5/§C "Cody = HIRE_PARTNER" mapping is discarded.

---

## C. `GameDirector` — proposed 5th autoload

One-liner: the global sequencer that owns *where in the 7-step arc the game is* and the rules that advance it; `GameState` stays pure data, scenes stay renderers.

- Registration: `autoloads/game_director.gd`, after `AudioManager` in `project.godot [autoload]`.
- Owns: a `Phase` enum (`EMPTY_LOT → HIRE_PARTNER → BUILD_STRUCTURE → BUILD_INTERIORS → ACTIVATE_FLOORS → SHARE → TEMPORAL`), `current_phase`, and the transition gates.
  - `EMPTY_LOT` + `HIRE_PARTNER` are the **new exterior opening beats** (no exterior exists yet — they get built fresh).
  - `BUILD_STRUCTURE`'s intended mechanic is **construct-from-empty** (player builds the tower up, floors spawned in build order rather than pre-placed) — a larger architectural change deferred to its own phase (§D).
- Reads `GameState` to evaluate gates (`utility.pipe_active` all-on, `plants_harvested ≥ N`, floor-built flags) and emits `phase_changed(phase)` + sets one `GameState.phase` field for pollers.
- Consumers (react to the signal): `tower_hud.gd` (per-phase objective line), floor controllers (gate content for active phase), `tower_controller.gd` (phase-driven environment; later day/night).
- **Migration (corrected):** the early phases are NEW beats, **not** migrations of existing interior systems. **Do NOT fold Cody's arrival into `HIRE_PARTNER`** — Cody is an already-built interior Garden beat and stays untouched. Existing interior beats (Utility activation, etc.) *may later* be mapped onto mid/late phases, but that is a separate, logged decision — don't assume it now.
- Time tie-in: the `TEMPORAL` phase / `time_of_day` drives off `sim_time_msec` / `sim_speed` (introducing a wrapping day/night per §B.3).
- Litmus: *"what is true in the world"* → `GameState`. *"what should happen next and when"* → `GameDirector`.

---

## D. Open decisions for Jared

1. **Fifth autoload — GREENLIT.** Relax the "four autoloads only" convention to allow `GameDirector` (required for §C). Log the resolution in `request_queue.json` for the record.
2. **Worldbuilding / narrative direction (`Q-005`):** who lives in Residential, what the Sky Lounge becomes, what the city/world is (replacing placeholder `cityscape.gd`). Still open.
3. **Exterior shape — RESOLVED (Jared, Session 9 follow-up): IN-WORLD, no scene swap.** The exterior empty lot is an **in-world space inside `tower.tscn`** — NOT a separate intro scene, and **no `change_scene_to_file`**. `run/main_scene` stays `tower.tscn`. A boot flag in `constants.gd` selects the START STATE *within the same scene* (real opening → `EMPTY_LOT` phase + exterior spawn; dev fallback → straight to the tower, today's Garden spawn) — it does NOT point at a different scene. "Handing off into the tower" = the player traverses in (or the camera moves up to Floor 0), reusing the existing camera/player/HUD, NOT a load. Reuse the ground-plane pattern already in `scenes/shared/cityscape.gd`. Because it's the same scene, `tower_hud.gd` persists, so the per-phase objective line works during the exterior beats with no separate HUD. This honors the one-continuous-world architecture (`rules/stacked_tower_invariants.md`).
4. **Construct-from-empty (DECIDED, DEFERRED):** Jared has chosen this as the `BUILD_STRUCTURE` direction — floors become player-built. It touches `tower_controller._FLOORS` + the elevator `SERVED` list, so it is built as **its own phase after** the director spine, with its own logged decision. Not part of the spine phase.
