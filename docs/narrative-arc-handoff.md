# Space Tower Iso — Narrative-Arc Handoff

**Purpose:** a single, code-verified snapshot for the planning session that is piecing together the game's full narrative arc in Godot. Everything below was checked against the actual files (not the docs) on 2026-06-01, end of Session 9.

**Trust order when sources disagree:** the **code → `git log` → `agent/session_log.md` → `CLAUDE.md`**. `CLAUDE.md` was re-audited and corrected this session (commit `72ee172`), so it's re-synced — but if prose ever conflicts with code, the code wins.

---

## A. Project inventory (verified)

**1. STACK** — **Godot 4.6**, **GDScript** only. **GL Compatibility** renderer (keeps web export possible later). `project.godot`: `config/features=("4.6","GL Compatibility")`, `run/main_scene=res://scenes/tower/tower.tscn`. No C#/GDExtension/plugins.

**2. RENDERING (isometric)** — A **3D scene graph viewed through an orthographic `Camera3D`** locked to an iso angle (−30° X tilt, 45°/−135° yaw), parented to a `CameraPivot` that snaps in 90° steps. **Not** 2D tiles / CSS / sprite-stacking. **Verticality = real height in one continuous 3D world:** every floor is an offset child `Node3D` under `Floors/` at `y = level * 6 m`. No scene-swapping — you **walk / ride / vacuum-hop / fall** between floors; `tower_controller.gd` gates visibility to the current floor + everything below.

**3. STRUCTURE**
- `autoloads/` — 4 globals: `constants.gd` (all tunables), `game_state.gd` (single source of truth), `save_manager.gd` (**no-op stub**), `audio_manager.gd` (**no-op stub**).
- `scenes/` — one **content-named** dir per floor (`utility, garden, arboretum_ground, arboretum_canopy, residential, sky_lounge, roof`) + `shared/` (cross-floor static builders) + `tower/` (the runtime).
- `agent/` — Builder-Agent self-knowledge (`rules/` ~14 files, `session_log.md`, `request_queue.json`, `project_knowledge.json`, `competency_map.json`, `failure_log.json`). `docs/` — design docs incl. `player-journey-map-v3-final.html`, `space-tower-project-knowledge-v3.md`, `floor_design_system.md`. `references/` — cloned Godot iso demo (reference/license only). `tools/` — `anim_capture` dev tool.
- **There are NO per-floor `.tscn` files.** Each floor is a `.gd` controller (e.g. `scenes/garden/iso_floor.gd`) instanced as an offset child of `tower.tscn`, building its geometry procedurally. **`tower.tscn` is the only runtime scene.**
- **State** lives entirely in the `GameState` autoload. **No screen/scene swapping** — "screens" are floors you physically traverse; the HUD is one `CanvasLayer` whose per-floor groups toggle on the current level.
- **Key files (one line each):**
  - `scenes/tower/tower.tscn` — the whole stacked world (sole runtime scene).
  - `scenes/tower/tower_controller.gd` — positions floors at `y = level*6`, tracks current floor, gates visibility + slab collision, drives camera-pivot height + per-floor environment.
  - `autoloads/game_state.gd` — single source of truth: player/camera, per-floor state, food/cash/backpack, transit + look-out flags, sim clock.
  - `autoloads/constants.gd` — all tunables (camera, geometry, utility systems, plant types, vacuum, look-out, cityscape).
  - `scenes/shared/floor_chrome.gd` — static builders every floor calls (slab + shaft grate, walls, extension grid, elevator core, spine pipes).
  - `scenes/shared/elevator_platform.gd` — the rideable elevator car **and its floor chooser** (`State { IDLE, MOVING, CHOOSING }`); serves Floors 0,1,2,4,5.
  - `scenes/shared/vacuum_lift.gd` — ±1-floor vacuum-hop traversal.
  - `scenes/garden/iso_player.gd` — articulated player (walk/jump/plant/harvest + look-out pose).
  - `scenes/garden/iso_camera.gd` — iso camera (follow/survey/modes) + the Sky-Lounge POV look-out.
  - `scenes/garden/iso_robot.gd` — Cody GX-5, the one scripted NPC (arrival ceremony + dialogue tree).

**4. EXISTING SYSTEMS (vs. the arc's needs)**
- **(a) Phase/state director — NONE.** No in-game step sequencer / quest / objective system. Closest is *ad hoc per-floor scripted flow* (Utility activation sequence; Cody's arrival triggered by a harvest count).
- **(b) Day/night / time — PARTIAL.** `GameState.sim_time_msec` + `sim_speed` is a **monotonic sim clock that drives tree growth only**; "sunlight" is static spotlights. **No day/night cycle, no time-of-day, no hour field, no wrap.**
- **(c) Build/placement — PARTIAL.** Player **placement exists for crops** (seed→plot, sapling). **Floors are built procedurally at startup, not by the player.** The Roof is a static "under construction" vista with a *cosmetic* crane (no lifting).
- **(d) Hire/character — PARTIAL.** **One scripted NPC (Cody).** No hire/roster mechanic; Residential is explicitly empty.

**5. THE 7 STEPS — what's implemented**
1. **Empty lot + resource → partial.** No empty-lot→build, but the **Utility/basement floor** is the resource layer (pull breaker, connect+activate 6 sources; lit spine-pipes propagate up). Implemented.
2. **Hire a partner → partial.** Cody arrives as the partner (scripted, not a hire choice).
3. **Build structure layer by layer → not implemented.** Floors pre-built at startup; Roof crane is cosmetic.
4. **Build each floor interior → not a mechanic.** Garden + Arboretum interiors exist; **Residential + Sky Lounge are blank wired shells** awaiting fill.
5. **Activate floors with characters → partial.** "Activate" exists only as the Utility systems flow; floors aren't populated with characters.
6. **Share → stub only.** Vacuum tubes "sell produce → cash" (`food_count`/`cash`), but **nothing consumes the output** (no diner/population).
7. **Temporal day/night flow → partial.** Only the growth sim clock; **no day/night.**

**6. RUN**
- Open editor: `godot --path . --editor` (binary on this Mac: `/Applications/Godot.app/Contents/MacOS/Godot`).
- Run game: `godot --path .` (launches `tower.tscn`) or `--debug`.
- **No build/export configured** (no `export_presets.cfg`). GL Compatibility keeps web export viable later.
- Verify visually with a **windowed screenshot harness** (NOT `--headless`, which renders nothing) — see `agent/rules/godot_screenshot_harness.md`.

**7. LEFTOVERS / STALE** — `SaveManager` + `AudioManager` are no-op stubs. `references/godot_iso_demo/` + `tools/anim_capture.*` are not game code. **No orphan floor scenes** (`tower.tscn` is the sole runtime scene). (Prior CLAUDE.md staleness — incl. a dead `elevator_handler.gd` reference — was corrected in `72ee172`.)

---

## B. Resolved contradictions (the three the planner flagged)

**1. `elevator_handler` — the inventory was right; CLAUDE.md was wrong (now fixed).** There is **no `elevator_handler.gd`** in the repo. The car *and* chooser both live in **`scenes/shared/elevator_platform.gd`** (a `State { IDLE, MOVING, CHOOSING }` machine; chooser UI = `_build_chooser_ui()` / `_set_chooser_text()`). CLAUDE.md's two references were stale scene-swap-era prose, corrected this session.

**2. The "four-autoload locked" constraint — true today, but it's a convention, not enforced.** `project.godot` declares exactly four autoloads (`Constants, GameState, SaveManager, AudioManager`); CLAUDE.md calls them "the only globals." Nothing in code prevents a 5th. **Recommendation: add a 5th autoload (`GameDirector`)** for the phase sequencer — see Section C. (This relaxes a constraint Jared set, so it needs his explicit yes; once given, the CLAUDE.md constraint line gets updated.)

**3. GameState has a clock — but it's a growth timer, not a day/night cycle.** Confirmed in `game_state.gd`: `var sim_time_msec: float` + `var sim_speed: float`, advanced every frame (`sim_time_msec += delta * 1000.0 * sim_speed`). It's *monotonic* (ms since start), built to decouple growth from real engine time. **A `time_of_day` system must INTRODUCE the day/night concept** (derive a wrapping phase from `sim_time_msec`, or run its own clock) — it can't just read an existing field. Reuse `sim_speed` as the one global time-scale knob.

---

## C. `GameDirector` — proposed 5th autoload

**One-liner:** the global **sequencer** that owns *where in the 7-step arc the game is* and the rules that advance it; `GameState` stays pure data, scenes stay renderers.

- **Registration:** `autoloads/game_director.gd`, added to `project.godot [autoload]` after `AudioManager`.
- **Owns:** a `Phase` enum for the 7 steps (`EMPTY_LOT → HIRE_PARTNER → BUILD_STRUCTURE → BUILD_INTERIORS → ACTIVATE_FLOORS → SHARE → TEMPORAL`), a `current_phase`, and the **transition gates** (the condition that advances each step).
- **Reads** `GameState` to evaluate gates (e.g. `utility.pipe_active` all-on, `plants_harvested ≥ N`, floor-built flags) and **emits a `phase_changed(phase)` signal** + sets one `GameState.phase` field for pollers.
- **Consumers (react to the signal, don't poll):** `tower_hud.gd` (per-phase objective/wayfinding line), floor controllers (gate/enable content for the active phase), `tower_controller.gd` (phase-driven environment; later the day/night driver).
- **Migration (proof the pattern works on existing content):** hoist today's scattered scripted beats into the director — the Utility "activate 6 systems" completion and **Cody's harvest-threshold arrival** become *director transitions* instead of floor-local logic.
- **Time tie-in:** the `TEMPORAL` phase / any `time_of_day` drives off `GameState.sim_time_msec` / `sim_speed` — `GameDirector` flips it on.
- **Litmus test for the split:** *"what is true in the world"* → `GameState`. *"what should happen next and when"* → `GameDirector`.

---

## D. Open decisions for Jared (the operator)

1. **Relax the "four autoloads only" constraint** to allow `GameDirector` as a 5th? (Required for Section C; recommended.)
2. **The worldbuilding / narrative direction itself** (logged as `Q-005` in `agent/request_queue.json`): who lives in Residential, what the Sky Lounge becomes, and what the city/world *is* (replacing the placeholder `scenes/shared/cityscape.gd`). The two blank floors + placeholder skyline are deliberately empty, waiting for this.
