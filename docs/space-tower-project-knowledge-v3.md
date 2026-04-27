# Space Tower & The RGB — Project Knowledge
## Updated March 2026 · Synced with codebase snapshot

---

## The Vision

**Space Tower** is a tower-building game where you ARE the builder — a physically strong human in a hardhat constructing a space elevator by hand. You build the tower on the outside (launching crates, climbing, driving machines) and explore what you've created on the inside (platforming through floors, discovering NPCs and story). Multiple interconnected modes in a single web app: a 3D title screen and exterior (Three.js), a 2D side-on sim interior (Canvas 2D), a basement Control Room, and connection to the RGB (LLM-powered immersive experience). One tower, one character, multiple cameras.

**The core loop: exterior builds, interior rewards.** Physical construction happens in 3D — the scaffolding seesaw launches crates onto the roof, and successfully landing them builds floors. The sim interior is what you unlock by doing that: a living cross-section populated with NPCs, story, and economy. The interior's platforming (charged jump, wall slide, drop-through-floors) is a core strength — traversing the tower feels athletic, not managerial.

**The RGB** is a self-contained rendering and intelligence engine the player crosses into. It does not bleed back into the sim. The sim stays handcrafted and deterministic. The RGB is alive and responsive. The boundary between them is sacred — walking through those doors should feel like crossing into somewhere else entirely.

**The Keeper is the exception.** Floor 10's mayor is LLM-powered inside the sim. The only character who actually responds to you. That contrast — one living thing among scripted NPCs — is what makes encountering him feel special.

**BYOK** is the culmination. The player connects their own LLM via OpenRouter or direct API key. Powers The Keeper's LLM conversation. The credential storage lives at `rgb_llm_connection` in localStorage — owned by the RGB, not Space Tower.

---

## Segment 1: "Goodbye Earth" — Three-Act Structure

### Act 1: Build (Floors 1–4)
Learn the game. Build floors physically on the exterior (scaffolding seesaw), then enter to explore them. Interior has 3 stages per floor — discovery moments, not chores. Fixed floor flanks (corner store, diner, seed bank). Economy starts: food chain, builder happiness, bulldozer unlock. Static NPCs arrive when floors activate. Deterministic world.

### Act 2: Discover (Floors 5–8)
**Floor 5 — The Restaurant.** RGB threshold. Door hums when nearby. BYOK moment (not yet wired). First RGB experience (separate repo).

**Floor 8 — The Reckoning.** Builders vs. Suits. Triggers when Storage (floor 8) hits stage 5 and all floors are at least stage 1. Three contested floors (6–8). Player claims blocks physically. 12 builder AI vs. 18 suit AI in squads. Flood of 30 civilian NPCs. Post-reckoning: choose builder color, rematch bell, Gene returns. **Fully implemented and replayable.**

### Act 3: Prove (Floors 9–10)
**Floor 10 — The Keeper (Gene).** LLM-powered or scripted fallback. Proximity-triggered zoom to desk. System prompt built from live tower state (health score = floors 40%, satisfaction 30%, modules 15%, NPCs met 15%). Difficulty scales inversely with health. Chat UI overlaid on canvas. Resolves when model outputs `[RESOLVED]`. **Fully implemented.** Scripted path has 5 adaptive lines. Return visits get a single dismissive line.

---

## Game Modes (All In One Repo)

### Title Screen
Three.js. Night city skyline with procedural buildings and hoverable windows. Tower with vertex-colored beams and windows. Stars with constellation clicking. Orbital Earth view (toggle). Mouse-orbit camera. Day/night sky transition into exterior gameplay. Forward transition: zoom in → sky shifts to day → exterior activates. Reverse transition available via home button.

### Exterior (3D)
Third-person. Three.js. **The primary construction layer — this is where you build the tower.** The scaffolding seesaw game is the main building mechanic: jump on one end to launch crates toward bullseye targets on the roof. Successfully landing crates builds floors in the 3D tower, which unlocks their interiors in the sim. Player also climbs the tower (ladders on 4 faces, beams as one-way platforms), operates the crane (launcher, not cargo lifter — for now), and drives the bulldozer. Construction site with fence, porta-potties, material piles. Ground-level semi-circular patrol workers and sidewalk business NPCs. Tab key or walking through the door enters the sim. Buildout syncs to sim save.

**Playable Crane**: Full tower crane. Boom rotation (A/D), trolley extension (Q/E), winch (W/S), grab/release (Space), charge-and-launch (F). Pendulum physics on cable. 20-projectile pool with bouncy collisions. Recoil on launch.

**Playable Bulldozer**: Driveable construction vehicle. W/S forward/reverse, A/D turn, F blade toggle, Shift boost. Terrain deformation: blade-down pushes vertices down, piles ahead. Dust particles. Speed-responsive engine rumble.

**Scaffolding Game**: Seesaw launch mini-game. Player jumps on one end, launching GPC Supply crate toward a bullseye target on the roof. 3-beat camera system. 2 crates per floor (floors 1–5), 4 per floor (floors 6–10). Successfully landing crates builds floors in the 3D tower.

### Sim (2D)
Side-on cross-section. Canvas 2D. **The interior you unlock by building outside.** 10 themed floors, each with 3 interior stages (discovery moments — see what your construction created). 12 blocks per floor (7 buildable + 2 windows + 1 elevator + 2 flanks), 4 modules per floor. Economy: credits, satisfaction, food, builder happiness. The platforming is a core strength: charged jump, charged drop-through-floors, wall slide, wall jump — traversing the tower feels athletic. NPC arrival system, altitude-aware sky, parallax city, elevator with Control Room access, compendium. **14,600 lines of JS.**

**Note: Codebase currently has 5 stages per floor. Reducing to 3 is a planned change.**

### Control Room (Basement)
Canvas 2D. Perspective room below Floor 1. 4-phase entry: black → doors open → walk forward → interactive. Console screen shows wireframe tower (clickable floors), population/satisfaction/credits stats, "Next Step" panel, task checklist. Features: rotating contextual log quips, red button (fake alarm), gold button (+1 credit per visit), jump-on-console gag, SAT-responsive heartbeat, low-SAT screen flicker, zero-credit screen glitch, floor-tracking LEDs. Full-screen monitor toggle (F) with pannable artboard. Visiting grants +2 satisfaction (60s cooldown).

---

## Key Characters

### Gene / The Keeper — Floor 10
- **Recurring NPC**: Appears as `isGene` business NPC on floors 1, 3, 5, 7. Dialogue: forgettable bureaucrat ("Do you know how many forms it takes to approve a floor? Seventeen."). Designed to be overlooked on first playthrough, devastating in hindsight.
- **Absence**: Hidden during The Reckoning (`_hidden=true`). Returns afterward with injected dialogue: "Not seen since the Reckoning."
- **Keeper encounter**: On Floor 10 (Command), proximity triggers zoom to desk. Deep purple suit, gold star tie, too-long beard, walking stick, globe, papers, lamp.
- **LLM persona**: Corporate oracle meets reluctant sage. Poetic about departure. 2–3 sentences max. Dry humor. References specific tower details. Gates Segment 2 via conversation. Health score determines difficulty: ≥75 = near-deferential (2–4 exchanges), 40–74 = gentle probing (4–6), <40 = relentless challenge (6–10). Always lets player through eventually.

### Floor Leaders (Reckoning)
Rodriguez (F1), Kim (F2), Paz (F3), Murphy (F4), Okafor (F6), Tanaka (F7). Named builder leaders on contested floors during The Reckoning.

---

## Economy & Progression

### Food Chain
Floor 1 diner (right flank) → produces food at stage 4+. Floor 2 planters → grow through 4 stages (~30s each), produce food at stage 4. Corner store upgradeable. Bunks consume food. Surplus → happiness, deficit → happiness drain. `foodChainComplete` fires when diner active + 2 mature planters.

### Builder Happiness
Rises from: food surplus (+1/tick), residential placement (+2), floor activations (+10 for quarters), corner store upgrade (+10), mature planters (+3 each). Falls from: food deficit (-1/tick), residential demolition (-2), mature planter removal (-3). Threshold of 20 + foodChainComplete → bulldozer unlock.

### Satisfaction
Decayed system. Feeds into political power (conceptual). Control room visit grants +2 (60s cooldown).

### Credits
Starting: 500. Spent on modules. Earned from module production (not yet active — future). Gold button in control room: +1 per visit.

---

## BYOK & LLM Connection

The Keeper reads BYOK credentials from `localStorage('rgb_llm_connection')`. Two paths:

**OpenRouter** (default): OpenAI-compatible chat completions format. Model default: `anthropic/claude-sonnet-4-20250514`. Endpoint: `https://openrouter.ai/api/v1/chat/completions`.

**Direct Anthropic API**: Messages API format with `anthropic-dangerous-direct-browser-access` header. Model default: `claude-sonnet-4-20250514`.

Both paths feed into `_callLLM()` in keeper.js. System prompt built by `_buildSystemPrompt()` with full tower context. Chat UI: DOM overlay (`#keeper-chat`) with message log, text input, Enter to send, Escape to exit. `[RESOLVED]` token in LLM response triggers resolution.

Graceful fallback: no API key = scripted dialogue (5 adaptive lines based on tower state).

---

## Technical Architecture

### State
Single mutable object `S` from `state.js`. ~55 top-level fields. Everything reads/writes directly.

### Game Loop
`requestAnimationFrame` → `update()` → `draw()` → `renderPanel()`. Control room intercepts: when `S.cr.active`, sim update is skipped, control room update runs instead.

### Rendering
- **Sim**: Canvas 2D. Procedural. Parallax: city 0.35x, trees 0.6x, tower 1x. Altitude-aware sky gradient. Per-floor detailed module art with animation (smoke, charge, grow lights, data rain, sparkles).
- **Exterior**: Three.js. Vertex-colored merged geometries (minimal draw calls). No textures except crate labels. FogExp2. Third-person camera with critically-damped spring.
- **Control Room**: Canvas 2D. Perspective-faked 3D room (trapezoid walls, depth-scaled player). Virtual screen resolution 1600×900 mapped to canvas.

### Sound
Web Audio API. Procedural oscillator/noise SFX (30+ unique sounds). Altitude-aware ambient drone. Bulldozer engine rumble (pitch tracks speed). RGB door hum. All procedural — no audio files for SFX.

### Music
Tone.js + @tonejs/midi. MIDI files served from `/public/midi/`. `skip.txt` filters playlist. Artist metadata embedded in music.js. Shuffle, volume, scrub. State persists via localStorage across mode transitions. Shared AudioContext with SFX.

### Save
localStorage `spacetower_v14`. Full state serialization. Module save: ID string or `{id, growStage}` for planters. Reckoning map persisted as 2D array. Terrain as flat array. Auto-save every 60s. Migration from v11–v13.

### Key Constants
`TW=3600`, `FH=160`, `NF=10`, `PG=300`, `BPF=12`, `GY/TB=2400`, `UW=1400`, `TL/TR=±1800`, `ELEV_X=150`, `TERRAIN_RES=800`

---

## Design Principles

- **The player's body is the tool.** You climb, jump, swing, drive, launch. The game is best when the player physically does the thing, not when they press E on a waypoint.
- **Exterior builds, interior rewards.** Physical construction happens outside. The interior is the living consequence — populated, alive, reactive. You enter a floor you built with your hands.
- **The interior is for traversal and discovery.** The sim's platforming (charged jump, wall slide, drop-through-floors) is a core strength. Interior stages should feel like exploring what you created, not activating scripted checkpoints. Three stages, not five.
- **Discovery over instruction.** No tutorials. Redesign, don't tooltip.
- **Character dignity.** Three-line reveals. Nobody is disposable.
- **The RGB boundary is sacred.** Sim = handcrafted. RGB = alive. Mayors are the rare exception.
- **Meaningful consequence over choice.** Fixed block identities with direct causal consequences beat a shopping-list catalog.
- **Unlocks should be fun or gate something fun.** The bulldozer is inherently fun AND unlocks terrain shaping.
- **Floor 8 = identity.** Builders vs. suits. Who are you?
- **The Keeper = readiness.** Can you lead higher? He calibrates to your answer.
- **BYOK = culmination.** Earn the right to bring your mind in.
- **Narrative seeding.** Gene's early dialogue is designed to be forgettable first, devastating in hindsight.
- **Flat characters, detailed infrastructure.** Simple people, complex machines.
- **Browser-native is strategic for now, not permanent.** Core systems should stay portable to Unity/Godot/Unreal.

---

## What's Built vs. What's Planned

### Built & Working
- Full title screen with city, orbital view, constellations, transitions
- 3D exterior with climbing, ladders, beams, NPC workers
- Playable crane with pendulum physics and launch mechanic
- Playable bulldozer with terrain deformation (both 2D sim and 3D exterior)
- Scaffolding seesaw game that builds floors
- Complete sim with 10 floors, 5 buildout stages each, 40 modules
- NPC arrival system, 4 NPC types + Gene recurring character
- Economy: food chain, builder happiness, bulldozer unlock progression
- The Reckoning: full mini-game with AI, scoring, color pick, rematch, flood
- The Keeper: LLM + scripted paths, zoom state machine, chat UI
- Control Room: full basement with console, quips, interactive buttons, jumping gag
- Music system (Tone.js MIDI), radio widget, 30+ procedural SFX
- Save/load with migration, auto-save, cross-mode sync
- Mobile touch controls

### Not Yet Built / Wired
- RGB integration (separate repo exists, not connected)
- Restaurant floor as RGB threshold (floor exists in sim, 3D interior not built)
- Hunger system (was in old design docs, not implemented — `S.player.hunger` not in state)
- Political power as a composite stat (conceptual, not computed)
- Credit income from modules (no production tick running)
- Altitude-aware generative music (MIDI playlist exists, not altitude-mapped)
- Performance architecture (dirty-rect tracking, simulation worker, ECS migration)

---

## Development Approach

- **Claude Chat (Opus):** Architecture, design, creative direction, document generation
- **Claude Code (Sonnet):** Implementation within established patterns, using CLAUDE.md as context
- **Two-file handoff:** Design conversations produce a brief + prototype/reference file as paired artifacts for Claude Code
- **Prototype-then-integrate:** React/Canvas prototypes validate interactions, then ~70% ports to vanilla JS
- **Playtesting before expansion:** Validate existing mechanics before adding features

---

## Vocabulary

| Term | Meaning |
|------|---------|
| **The RGB** | Reality Generation Box — self-contained LLM-powered experience engine |
| **Segment** | 10-floor narrative arc. Segment 1 = "Goodbye Earth" |
| **The Keeper / Gene** | Floor 10 mayor. Corporate Merlin. LLM-powered. Gates Segment 2. |
| **The Reckoning** | Floor 8 builders vs. suits territory-claim mini-game |
| **Block** | One buildable unit (300px). 12 per floor. |
| **Module** | Buildable placed in a block (generator, bunk, planter, etc.) |
| **Flank block** | Blocks 5 and 7, flanking the elevator. Fixed identity per floor. |
| **Buildout stage** | 0–3 progression per floor. 3 = activated. (Currently 0–5 in code, reducing to 3.) |
| **Lit floor** | Floor with stage ≥ 1. |
| **The Critic** | Floor 5 RGB restaurant scenario (designed, not built) |
| **Food chain** | Diner + mature planters = foodChainComplete |
| **Builder happiness** | Resource tracking builder morale, gates bulldozer |
| **BYOK** | Bring Your Own Key. Player connects their LLM. |
| **OpenRouter** | Unified LLM API gateway. Recommended BYOK path. |
| **altFrac** | 0–1 altitude value. Drives sky, mood, sound. |
| **S** | Global state object in the sim |
| **GPC Supply** | The fictional supply company whose crates you launch in the scaffolding game |
