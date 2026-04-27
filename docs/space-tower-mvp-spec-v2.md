# Space Tower — MVP Spec
## Updated March 2026 · Reflects current codebase

---

## MVP Definition

The MVP is a complete, playable loop of Segment 1 ("Goodbye Earth"): title screen → exterior construction (physically building floors) → sim interior exploration (discovering what you built) → all 10 floors → The Reckoning → The Keeper → passage to Segment 2. The exterior is where you build. The interior is what you unlock. All modes connected, all set-piece events functional, one character moving through the full arc.

---

## What's Done

### Title Screen & Exterior ✅
- Three.js procedural city with hoverable buildings and windows
- Tower mesh with vertex-colored beams, windows, structural columns
- Star constellation clicking system
- Orbital Earth view with atmosphere glow and orbiting moon
- Day/night sky transition tied to gameplay transition
- Forward transition: orbit zoom → sky shift → exterior activates
- Reverse transition: return to title orbit from exterior
- Third-person camera with spring physics, orbit, collision raycasting
- Player character: WASD, charged jump, sprint, wall slide, wall jump
- Tower climbing: 4-face ladders, perimeter beams as one-way platforms
- Playable crane: boom rotation, trolley, winch, pendulum physics, charge-and-launch, 20 projectiles
- Playable bulldozer: drive, turn, blade toggle, terrain deformation, speed-responsive engine rumble
- Scaffolding seesaw game: crate launch, bullseye targets, 3-beat camera, floor building
- Construction site: fence, porta-potties, materials, scaffolding
- Ground NPCs: semi-workers patrol, business people on sidewalk
- Tab key and front door toggle between exterior ↔ sim
- Buildout syncs to sim save via localStorage

### Sim Interior ✅
- 10 themed floors with 5 buildout stages each (50 physical interaction points) — **reducing to 3 stages (30 points), see Remaining section**
- 12-block system per floor: 7 buildable, 2 windows, 1 elevator, 2 flanks
- 40 modules (4 per floor) with unique animated Canvas art
- Named floor flanks with fixed identity (corner store, diner, seed bank, etc.)
- Per-floor activation effects: unique particles, sounds, screen shake/flash
- NPC arrival system: queue → walk through door → ride elevator → arrive at destination
- 4 NPC types: casual, business, construction worker, alien (+ Gene recurring)
- 3-line sequential dialogue per NPC, 36+ discoverable characters
- Gene appears on floors 1, 3, 5, 7 as forgettable business NPC
- Parallax city (0.35x) + treeline (0.6x) + tower (1x)
- Altitude-aware sky gradient (blue → sunset → space)
- Elevator with door animation + Control Room basement access
- **Platforming is a core strength**: charged jump, charged drop (multi-floor), wall slide, wall jump — traversal feels athletic
- Compendium: character collection with mini-sprites, dialogue history, type filters
- 30+ procedural Web Audio SFX
- Tone.js MIDI music system with radio widget (volume, track name, scrub)
- Mobile touch controls
- Save/load (v14) with auto-save, migration from v11-v13

### Economy ✅
- Credits (starting 500, spent on modules)
- Food chain: diner + planters → food production/consumption → foodChainComplete event
- Builder happiness: rises from food surplus, residential, activations; falls from deficit/demolition
- Bulldozer unlock: happiness threshold (20) + foodChainComplete
- Bulldozer: terrain deformation via Float32Array heightmap, bounce off tower walls, dust particles
- Corner store upgrade: buyable for +1 food and +10 happiness

### The Reckoning ✅
- Triggers: Floor 8 stage 5 + all floors stage ≥ 1
- Contested floors: 6 (Observation), 7 (Storage), 8 (Observatory)
- Phases: INTRO (typewriter briefing) → COUNTDOWN → ACTIVE (90s) → FLOOD → RESULT → COLOR_PICK → DONE
- Player claims blocks by standing (150 frames)
- 12 builder AI: any floor, any block, slower claim (210 frames)
- 18 suit AI in 6 squads: wave-locked bottom→top, faster claim (45 frames), squad coordination
- Wave advancement when floor is fully claimed
- Score tracking with pulse animation
- Block flash effects on claim
- Timer urgency: heartbeat ticks in last 5 seconds
- FLOOD: 30 civilian NPCs pour in (population explosion)
- RESULT: builders or suits win, unique sound + visual
- COLOR_PICK: 8 colors, arrow keys to browse, E to confirm
- Post-reckoning: rematch bell, color wheel station for recolor
- Gene hidden during reckoning, returns with injected dialogue
- Outcome persisted in save, feeds Keeper context

### The Keeper ✅
- LLM path: BYOK via OpenRouter or Anthropic API direct
- System prompt with full tower context (health score, floors, satisfaction, reckoning outcome)
- Difficulty scaling: health ≥75 → near-deferential (2-4 exchanges), 40-74 → gentle (4-6), <40 → relentless (6-10)
- Chat UI: DOM overlay, message log, text input, Enter to send, Escape to exit
- Resolution via `[RESOLVED]` token
- Scripted fallback: 5 lines adapting to tower state (floors built, satisfaction, reckoning outcome)
- Typewriter effect for scripted dialogue
- Proximity-triggered zoom state machine (idle → zooming_in → zoomed → zooming_out)
- Camera locks to desk area during encounter
- Keeper character art: desk, globe, papers, lamp, walking stick
- Warm gold glow effect when floor 10 is complete
- Return visits: single dismissive line, auto-zoom-out

### Control Room ✅
- Basement (Floor -1) accessible via elevator
- 4-phase entry: black → elevator doors open → walk to screen → interactive
- Perspective-faked 3D room with canvas rendering
- Console screen: wireframe tower (clickable floors), stats, "Next Step" panel, task checklist
- Floor detail panel with descriptions
- Log quips: contextual (population, satisfaction, credits, reckoning) + generic rotation
- Red button: fake alarm sound + quip
- Gold button: +1 credit per visit + quip
- Jump-on-console gag: screen glitch + shake + quip
- SAT-responsive features: heartbeat speed, screen flicker (<25 SAT), zero-credit glitch
- Floor-tracking LEDs on side racks
- Full-screen monitor toggle (F key) with pannable artboard (3× resolution)
- WASD movement with sprint, charge jump, depth (pz) movement
- E to exit (near elevator)
- +2 satisfaction per visit (60s cooldown)

---

## What Remains for MVP

### Priority 1: Direction Shift — Exterior Builds, Interior Discovers
- **Reduce interior buildout to 3 stages.** Currently 5 stages × 10 floors = 50 waypoints. Compress to 3: Power On → Structure → Activate. Each should feel like a discovery moment (walk through, see what changed), not a chore. The platforming between stages is the real gameplay — keep that athletic and fun.
- **Exterior as primary construction.** The scaffolding seesaw already builds floors in 3D. This should be the canonical way floors get built. When a floor is completed on the exterior, its interior becomes explorable in the sim. The sim save sync (`_syncBuildoutToSave`) already exists.
- **Interior stages as exploration.** Reframe the 3 remaining stages: player enters a newly built floor, walks through it, and discovers what their construction created. NPCs appear, systems activate, the floor comes alive. The act of moving through the space IS the interaction.

### Priority 2: Core Loop Gaps
- **Hunger system**: Not implemented. Was a key design pillar (pulls player toward Floor 5/restaurant). Need `S.player.hunger` decaying over time, felt through the body — jump height decreases, movement slows. Food physically restores it. Creates a reason to visit the restaurant (RGB threshold).
- **Credit income**: Modules have production values defined but no tick runs. Need periodic credit generation from placed modules.
- **Control Room as mission briefing**: Currently charming but purposeless. Should become *how you decide what to build next* — the place where you see what's needed and choose your next physical construction task on the exterior.

### Priority 3: RGB Connection
- **Floor 5 as RGB threshold**: The door hum exists, but no actual transition to the RGB. Need: page navigation to RGB app (or iframe), state handoff via localStorage.
- **BYOK connection UI**: The Keeper already reads `rgb_llm_connection` from localStorage. Need a user-facing settings panel or the RGB's connection modal accessible from the sim.

### Priority 4: Polish & Feel
- **Reckoning intro impact**: Blackout → reveal could hit harder. Suit AI readability during active phase.
- **Post-Reckoning exhale**: The transition from COLOR_PICK → DONE is abrupt. Need a moment of calm.
- **Exterior ↔ Sim continuity**: Player position doesn't map between modes. Entering the door from exterior always places you at the elevator on Floor 1.
- **Altitude-aware music**: MIDI playlist exists but isn't mapped to altitude. Design called for 7 songs mapped to altitude bands.
- **First 60 seconds**: Player spawns on the exterior. The scaffolding seesaw should be the obvious first action — make it unmissable and immediately rewarding.

---

## Technical Debt

- `render.js` is 2,330 lines and growing. The Reckoning HUD, Keeper overlay, module drawing, terrain, bulldozer, and RGB door effects are all inlined. Could benefit from extraction into focused render modules.
- `game-init.js` at 718 lines handles physics, economy, all input routing, and the main update loop. The bulldozer/crane driving modes add significant branching.
- No performance profiling done. The five-phase architecture upgrade plan (layer separation → simulation worker → spatial indexing → ECS) exists conceptually but hasn't started.
- The sim and exterior use completely different coordinate systems and character representations. No shared spatial model.
- Mobile touch controls exist but haven't been tested against current feature set (reckoning, keeper, control room).

---

## Build Order (Remaining)

1. **Reduce interior to 3 stages** — Compress buildout, reframe as discovery
2. **Wire exterior building → interior unlock** — Scaffolding seesaw completion unlocks sim floor exploration
3. **Hunger as a felt mechanic** — Decaying jump height / movement speed, food restores physically
4. **Control Room as mission briefing** — Show what to build next, give it purpose in the loop
5. **Credit income tick** — Modules generate credits over time
6. **BYOK connection UI** — Let players configure their LLM from within the game
7. **RGB threshold on Floor 5** — Wire the door transition
8. **Reckoning polish** — Intro impact, post-reckoning exhale, suit readability
9. **Playtest** — Friends test the full Segment 1 loop end-to-end
10. **Performance baseline** — Profile with Chrome DevTools, decide on optimization phase
