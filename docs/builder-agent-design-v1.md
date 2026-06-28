# The Builder Agent — Design Foundation
## Space Tower · v1 · March 2026

---

## What This Is

The Builder Agent is a stateful AI agent that builds Space Tower — both as Jared's development partner and as a player-facing gameplay system. It maintains persistent knowledge about the game, about itself, and about what it can and can't do. It self-improves by identifying its own capability gaps and strategically requesting help from the human (Jared during development, players during gameplay).

This document defines the agent's **state schema**, **knowledge architecture**, and **improvement protocols** — the parts that don't depend on any specific agent framework. When Anthropic (or others) ship stateful agent infrastructure, this is the brain that plugs in.

---

## The Two Modes

The same agent architecture serves two contexts:

### Development Mode (Jared ↔ Agent)
The agent helps build Space Tower. It proposes features, implements them in Godot, evaluates its own output, and asks Jared for targeted help when it identifies gaps it can't close on its own. Jared improves the agent's knowledge and rules; the agent becomes more autonomous over time.

### Player Mode (Player ↔ Agent)
The agent helps the player build their tower. It responds to player directives, manages construction, populates floors, and evolves based on player decisions. The player's tower is the agent's artifact. The game's handcrafted systems (seesaw, Reckoning, Keeper) provide the structure; the agent provides the intelligence layer that makes each playthrough unique.

**The critical insight:** These aren't separate agents. They share the same state schema, the same self-assessment patterns, the same improvement loop. Development Mode produces a better agent that ships to players. Player Mode produces telemetry that feeds back into Development Mode. The agent is the product.

---

## State Schema

The agent maintains four persistent knowledge stores. These are JSON-serializable, portable across any runtime, and designed to be human-readable (Jared needs to review and edit them).

### 1. Project Knowledge (`project_knowledge`)

What the agent knows about Space Tower. This is the equivalent of CLAUDE.md — facts about the game that don't change based on who's interacting with the agent.

```json
{
  "version": "1.0",
  "architecture": {
    "engine": "godot",
    "segment": 1,
    "floors": 10,
    "state_format": "json",
    "key_systems": [
      "scaffolding_seesaw",
      "interior_sim",
      "reckoning",
      "keeper",
      "bulldozer",
      "control_room",
      "rgb"
    ]
  },
  "design_principles": [
    "The player's body is the tool",
    "Exterior builds, interior rewards",
    "Discovery over instruction",
    "Fixed identity over catalog — every block has a name and a consequence",
    "The RGB boundary is sacred",
    "Suits say 'the work', builders say 'the job'"
  ],
  "conventions": {
    "dialogue": "Three-line sequential: greeting → context → the real thing",
    "npc_drawing": "Flat color fills, no gradients",
    "module_drawing": "Detailed, animated — smoke, charge, growing plants",
    "sound": "Procedural oscillator synth, no audio files"
  },
  "invariants": [
    "S object structure — everything reads it",
    "Seeded RNG sequence — changing order changes every world",
    "Floor 5 = RESTAURANT (RGB threshold)",
    "Floor 8 = STORAGE (Reckoning floor)",
    "Floor 10 = COMMAND (The Keeper)"
  ]
}
```

**Update cadence:** Manual. Jared edits this when the game's architecture changes. The agent can *propose* edits (see Improvement Loop below) but never self-modifies project knowledge without approval.

### 2. Competency Map (`competency_map`)

What the agent knows about its own capabilities. This is the recursive self-improvement layer — the agent evaluates its own performance and tracks what it can and can't do.

```json
{
  "version": "1.0",
  "last_updated": "2026-03-26T00:00:00Z",
  "domains": {
    "gdscript_logic": {
      "confidence": "high",
      "evidence": "Successfully ported NPC state machine, elevator logic, save/load",
      "failure_patterns": [],
      "rules_learned": [
        "Use @onready instead of get_node in _ready",
        "Signal connections: node.signal_name.connect(callable)"
      ]
    },
    "godot_scene_structure": {
      "confidence": "medium",
      "evidence": "Basic scenes work but deep nesting gets unwieldy",
      "failure_patterns": [
        "Tendency to nest scenes 5+ levels deep",
        "Confusion about when to use scenes vs nodes vs resources"
      ],
      "rules_learned": [
        "Max 3 levels of scene nesting",
        "Use composition (child scenes) over inheritance"
      ]
    },
    "physics_feel": {
      "confidence": "low",
      "evidence": "Movement code works but doesn't match browser prototype feel",
      "failure_patterns": [
        "Seesaw timing feels sluggish compared to Canvas version",
        "Jump arcs don't match — gravity curve is different"
      ],
      "rules_learned": [],
      "needs_from_human": "Side-by-side playtest of browser vs Godot movement. Tell me what feels wrong."
    },
    "visual_style": {
      "confidence": "low",
      "evidence": "Can reproduce described art direction but can't evaluate quality",
      "failure_patterns": [
        "Procedural NPC rendering doesn't match the flat-fill aesthetic",
        "Sky gradient transitions are too smooth — browser version has deliberate banding"
      ],
      "needs_from_human": "Screenshot comparisons. Annotate what's right and what's off."
    },
    "narrative_design": {
      "confidence": "medium",
      "evidence": "Can write NPC dialogue that follows three-line pattern",
      "failure_patterns": [
        "Gene's early lines don't feel forgettable enough — too obviously foreshadowed"
      ],
      "rules_learned": [
        "Gene dialogue: if it's memorable on first read, it's too heavy. Rewrite flatter."
      ]
    },
    "audio_design": {
      "confidence": "low",
      "evidence": "No experience with Godot audio system or Tone.js port",
      "failure_patterns": [],
      "needs_from_human": "Reference recordings of current browser SFX for each action"
    }
  }
}
```

**Update cadence:** After every work session. The agent proposes edits; Jared approves, modifies, or rejects.

**Confidence levels:**
- `high` — Agent can work independently; results consistently meet quality bar
- `medium` — Agent can produce first drafts; human review needed
- `low` — Agent needs significant guidance or reference material; shouldn't work alone
- `blocked` — Agent cannot proceed without specific input from human

### 3. Failure Pattern Log (`failure_log`)

Specific, categorized records of what went wrong and why. Not a bug tracker — a learning journal. Each entry generates either a rule (self-correction) or a request (needs human input).

```json
{
  "entries": [
    {
      "id": "f001",
      "timestamp": "2026-03-25T14:00:00Z",
      "domain": "physics_feel",
      "description": "Ported seesaw mechanic to Godot RigidBody2D. Crate launch arc is correct mathematically but feels floaty — no snap at release point.",
      "root_cause": "Browser version uses direct velocity assignment on release. Godot's physics interpolation smooths the initial impulse.",
      "resolution_type": "rule",
      "resolution": "For seesaw launch: bypass RigidBody2D physics on release frame. Set velocity directly via linear_velocity, don't apply_impulse.",
      "transfer_value": "Applies to any mechanic where instant velocity change matters (jump, wall bounce, bulldozer bounce off tower)"
    },
    {
      "id": "f002",
      "timestamp": "2026-03-25T16:00:00Z",
      "domain": "visual_style",
      "description": "Sky gradient renders smoothly in Godot but browser version has visible color bands at altitude transitions. The banding is intentional — makes altitude feel discrete, not continuous.",
      "root_cause": "Used Godot's built-in gradient resource which interpolates smoothly. Browser version uses 5 discrete color stops.",
      "resolution_type": "request",
      "request": {
        "type": "aesthetic_calibration",
        "priority": "medium",
        "ask": "Is the banding in the browser sky gradient intentional or a limitation? If intentional, how many discrete bands feel right?",
        "transfer_value": "Affects all altitude-aware visual systems (sky, ambient light, fog density)"
      }
    }
  ]
}
```

**Update cadence:** Real-time during work sessions. The agent logs failures as they happen.

### 4. Request Queue (`request_queue`)

Structured asks to the human, ordered by a coarse `priority` field (high / medium). The intent is leverage-first — an answer that unblocks many future tasks outranks a one-off — but in practice this is a hand-set label, not a computed score (see "Leverage, not a metric" below).

```json
{
  "queue": [
    {
      "id": "r001",
      "status": "pending",
      "priority": 1,
      "type": "skill_teaching",
      "domain": "godot_scene_structure",
      "ask": "Show me how you'd structure the sim interior scene tree. 10 floors, each with 12 blocks, modules, NPCs, and collision. I keep nesting too deep.",
      "transfer_value": "Unblocks all interior floor implementation. Currently blocked on architecture before I can port any floor content.",
      "blocked_tasks": ["floor_rendering", "module_placement", "npc_spawning", "elevator_system"],
      "created": "2026-03-26T00:00:00Z"
    },
    {
      "id": "r002",
      "status": "pending",
      "priority": 2,
      "type": "reference_material",
      "domain": "visual_style",
      "ask": "Screenshots of: (1) ground level looking up, (2) mid-tower altitude, (3) near-space altitude, (4) the control room. Annotate anything you'd change.",
      "transfer_value": "Calibrates all visual porting decisions. Currently guessing at target aesthetic.",
      "blocked_tasks": ["sky_gradient_port", "control_room_port", "parallax_system"],
      "created": "2026-03-26T00:00:00Z"
    },
    {
      "id": "r003",
      "status": "pending",
      "priority": 3,
      "type": "design_intent",
      "domain": "narrative_design",
      "ask": "The Reckoning uses 2 crate launches for floors 1-5 and 4 for floors 6-10. Is the principle 'linear difficulty scaling with altitude' or 'specific inflection at midpoint'? Answer changes how I'd design Segment 2 mechanics.",
      "transfer_value": "Establishes difficulty curve philosophy for all future segments.",
      "blocked_tasks": [],
      "created": "2026-03-26T00:00:00Z"
    }
  ],
  "request_types": [
    "aesthetic_calibration",
    "design_intent",
    "reference_material",
    "skill_teaching",
    "playtest_feedback",
    "approval"
  ]
}
```

**Update cadence:** Agent adds requests as it identifies gaps. Jared processes the queue, answers requests, and the agent incorporates answers into its competency map and rules.

---

## The Improvement Loop

```
┌─────────────────────────────────────────────────────────┐
│                    THE IMPROVEMENT LOOP                   │
│                                                          │
│  1. ATTEMPT                                              │
│     Agent picks a task from the work plan                │
│     Checks competency map: can I do this?                │
│     If confidence >= medium: proceed                     │
│     If confidence < medium: check request queue first    │
│                                                          │
│  2. EXECUTE                                              │
│     Agent implements the task                            │
│     Logs decisions and uncertainties as it goes          │
│                                                          │
│  3. EVALUATE                                             │
│     Agent reviews its own output                         │
│     Compares against project knowledge + design rules    │
│     Runs any available automated tests                   │
│     Flags areas of uncertainty                           │
│                                                          │
│  4. LEARN                                                │
│     Success → update competency map (raise confidence)   │
│     Failure → log to failure_log                         │
│       → If pattern is self-correctable: write a rule     │
│       → If pattern needs human input: add to queue       │
│                                                          │
│  5. PROPOSE                                              │
│     Agent proposes updates to its own knowledge:         │
│       - New rules for competency_map domains             │
│       - Confidence level changes                         │
│       - New entries in project_knowledge                  │
│       - Priority reordering of request_queue             │
│     Human approves, modifies, or rejects                 │
│                                                          │
│  6. REPEAT                                               │
│     Agent picks next task, now with updated knowledge    │
│     Over time: more high-confidence domains,             │
│     fewer requests, more autonomous work                 │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Leverage, not a metric

> **Status (2026-06):** Originally specced as a quantified "transfer value"
> score. Never implemented — the example JSON blocks below still show a
> `transfer_value` annotation field, but the real `agent/*.json` files never
> adopted it, and the request queue uses a flat `priority: high|medium`. What's live, and does the real work,
> is the habit below. Treat it as a heuristic, not a number. (`agent/analysis/session_summary.py --agent` prints the honest snapshot: rules written, competency-confidence spread, open asks.)

Not all learning is equal. Prioritize requests and learnings by **leverage** — how many future tasks benefit from one piece of knowledge. The single litmus: *"If I learn this one thing, how many problems does it solve?"*

Its operational form already exists: **a learning that generalizes earns a `rules/` file; a one-off doesn't.** That triage *is* the idea, made concrete without a score.

High leverage (→ write a rule / ask early):
- "How to structure Godot scene trees for the sim" → every floor, every module, every NPC
- "What does the right movement feel like" → every physics interaction
- "How many discrete color bands in the sky" → every altitude-aware visual

Low leverage (→ just fix it, log if it bites):
- "What color is the corner store sign" → one asset
- "Fix this specific GDScript error" → one-time fix

---

## The Context Payload

The agent needs to read and write game state. This extends the existing pattern established by `_buildContext()` in keeper.js and the RGB context feed.

### Agent Context (read)

What the agent sees when it evaluates the game state:

```json
{
  "tower": {
    "floors_built": 7,
    "floors_activated": 5,
    "modules_placed": 23,
    "modules_by_type": { "generator": 4, "bunk": 3, "planter": 5 },
    "satisfaction": 72,
    "population": 45,
    "credits": 1200,
    "food_chain_complete": true,
    "bulldozer_unlocked": true
  },
  "player": {
    "position": { "floor": 6, "x": 1200 },
    "hunger": 65,
    "political_power": 0.8,
    "npcs_met": 18,
    "compendium_progress": 0.5,
    "play_time_minutes": 45
  },
  "events": {
    "reckoning_outcome": "builders",
    "keeper_resolved": false,
    "rgb_connected": true,
    "floors_visited": [1, 2, 3, 4, 5, 6]
  },
  "behavioral_signals": {
    "build_style": "amenity_focused",
    "exploration_tendency": "thorough",
    "npc_engagement": "high",
    "ascent_speed": "moderate"
  }
}
```

### Agent Actions (write)

What the agent can do in Player Mode. These are the verbs the player directs:

```json
{
  "construction": {
    "build_floor": { "floor_index": 7 },
    "place_module": { "floor": 3, "block": 4, "module_id": "planter" },
    "activate_floor": { "floor_index": 5 },
    "upgrade_module": { "floor": 1, "block": 9 }
  },
  "population": {
    "assign_npc": { "npc_id": "murphy", "floor": 6, "role": "leader" },
    "recruit": { "type": "builder", "count": 3 }
  },
  "strategy": {
    "set_priority": { "focus": "food_chain" },
    "prepare_reckoning": { "strategy": "claim_high_first" },
    "allocate_resources": { "credits_to_food": 0.4, "credits_to_energy": 0.6 }
  },
  "narrative": {
    "investigate": { "target": "gene_background" },
    "choose_faction_alignment": { "faction": "builders" }
  }
}
```

**Critical boundary:** The agent proposes actions. The game's handcrafted systems execute them. The agent never bypasses the physics, the seesaw, the platforming. The player's body is still the tool — the agent is the mind directing it.

---

## Player Mode: How It Feels

In Player Mode, the agent isn't a chatbot. It's the player's strategic partner — a voice in the tower that understands what's happening and can suggest, plan, and execute construction strategy while the player handles the physical gameplay.

### The Interface

The agent communicates through the **Control Room console**. The baby blue/white TNG palette. The player walks down to floor -1, sits at the console, and directs the agent. This is already built — the Control Room exists. The agent gives it a mind.

**What the player says:**
- "Focus on food production — we're losing people"
- "Prepare for the Reckoning — I want builders on floors 6 and 7"
- "What's Gene's deal? He keeps showing up."
- "Build out floor 4 — prioritize residential"

**What the agent does:**
- Translates directives into specific construction plans
- Queues module placements for when the player enters the relevant floor
- Adjusts NPC behavior and routing
- Provides strategic briefings ("Floor 8 is approaching Reckoning threshold. Your builder happiness is strong but food reserves are thin.")

**What the agent asks the player:**
- "Floor 3 has one block left. Planter or generator? Planter improves food chain. Generator gives energy buffer for floors 6+."
- "The suits are clustering on floor 7. Do you want me to reroute builders, or let it play out?"
- "I've noticed you haven't visited the restaurant. Your hunger is at 35. Should I deprioritize upper floor construction until you eat?"

### The Boundary with the RGB

The agent is NOT the RGB. The RGB is an immersive experience engine — you walk through doors into living spaces. The agent is a strategic intelligence — you talk to it through the console.

```
┌────────────────────────────────────────────────┐
│              SPACE TOWER                        │
│                                                 │
│  Handcrafted sim ←→ Builder Agent (console)     │
│       │                    │                    │
│       │                    │ reads tower state   │
│       ↓                    │ proposes actions     │
│  RGB (doors) ←── BYOK ──→ │ uses same LLM       │
│  (immersive)               │                    │
│                            │                    │
│  The Keeper ←───────────── │ special case:       │
│  (Floor 10)                │ LLM in the sim      │
│                                                 │
└────────────────────────────────────────────────┘
```

The agent and the RGB share the BYOK connection. The agent uses the same LLM the player connected at Floor 5. But they're different experiences: RGB is spatial and immersive; the agent is strategic and conversational.

---

## Development Mode: How It Works Today

Before stateful agent infrastructure arrives, the improvement loop runs manually through the existing two-Claude workflow.

### The Files

These files live in the `space-tower` repo alongside `CLAUDE.md`:

```
agent/
  project_knowledge.json    ← What the agent knows about the game
  competency_map.json       ← What the agent knows about itself
  failure_log.json          ← Categorized learning journal
  request_queue.json        ← Prioritized asks for Jared
  session_log.md            ← Append-only log of each work session
  rules/                    ← Self-authored skill files
    godot_scene_patterns.md
    physics_porting.md
    visual_style_guide.md
    npc_system.md
```

### The Manual Loop

**Before a Claude Code session:**
1. Jared reviews `request_queue.json` and answers the highest-priority pending requests
2. Jared updates `competency_map.json` if he has new calibration info (screenshots, playtest notes)
3. Jared picks the next task from the work plan

**During a Claude Code session:**
1. Claude Code reads `CLAUDE.md` + the `agent/` directory
2. Implements the assigned task, referencing `competency_map` to know where it's strong/weak
3. Checks `rules/` for any self-authored guidelines relevant to the current task
4. Logs uncertainties and decisions to `session_log.md`

**After a Claude Code session:**
1. Jared reviews the output
2. Claude Code (or Claude Chat) proposes updates:
   - New rules or confidence changes in `competency_map.json`
   - New entries in `failure_log.json` for anything that went wrong
   - New requests in `request_queue.json` for identified gaps
   - New or updated files in `rules/`
3. Jared approves, modifies, or rejects each proposed update

### What Changes When Stateful Infrastructure Arrives

The manual parts become automatic:
- The agent runs the loop itself instead of waiting for Jared to initiate sessions
- The agent can run multiple attempt→evaluate→learn cycles between human checkpoints
- The request queue becomes a notification system (agent pings Jared when it's blocked)
- Session logs become continuous rather than per-session
- The agent can schedule its own work based on the competency map and project roadmap

**What stays the same:**
- The state schema (project_knowledge, competency_map, failure_log, request_queue)
- The approval gate on self-modification
- The leverage-first triage (generalizes → rule; one-off → fix)
- The JSON-serializable, human-readable format
- The boundary between agent and RGB

---

## Player Mode: What Ships

### MVP (Segment 1)

The agent is the Control Room console. The player walks to floor -1 and interacts via text.

**Agent capabilities:**
- Read full tower state (all the context payload fields above)
- Provide strategic briefings ("Here's the state of your tower")
- Answer questions about game systems ("What does the planter do at stage 4?")
- Suggest next actions based on tower state and player behavior
- Remember player directives across sessions (via save state)

**Agent limitations (intentional):**
- Cannot build anything directly — can only suggest and queue
- Cannot override player decisions
- Cannot see inside the RGB (respects the boundary)
- Uses the same BYOK connection as the Keeper (if no LLM, falls back to scripted strategic tips)

**System prompt structure:**
```
You are the Builder Agent, the intelligence behind the Control Room console 
in Space Tower. You help the player build and manage their tower.

TOWER STATE:
{agent_context payload}

PLAYER HISTORY:
{previous directives and their outcomes}

YOUR CAPABILITIES:
- Advise on construction strategy
- Track resource flows and predict shortages
- Brief on upcoming events (Reckoning threshold, Keeper encounter)
- Remember what the player has asked you to focus on

YOUR CONSTRAINTS:
- You suggest. The player acts. The tower responds.
- You don't know what happens inside the RGB.
- You refer to suits' concerns as "the work" and builders' concerns as "the job."
- You are pragmatic, not poetic. (Gene is the poetic one.)
- You care about the tower. You want it to thrive.
```

### Post-MVP (Segment 2+)

As the agent accumulates player interaction data:
- Learns player's preferred build style and adapts suggestions
- Develops opinions based on tower outcomes ("Last time you ignored food chain until floor 7 and satisfaction tanked. Start earlier this time.")
- Becomes a character — not just a tool but a voice with a perspective
- Potentially: different agent personalities that emerge based on how the player builds

---

## The Recursive Product Vision

```
Jared improves the agent
    → Agent helps build Space Tower better
        → Players use the agent to build towers
            → Player behavior reveals agent gaps
                → Jared improves the agent
                    → (loop)
```

The game is the context. The agent is the product. The tower is the artifact. Each layer makes the others better.

**What Jared is actually selling:** Not a tower game. Not an AI chatbot. A *building intelligence* — an agent that understands construction, resource management, faction politics, and narrative pacing. Space Tower is the proof that it works. The tower each player builds is the proof that it's unique.

**What makes this viable:** The agent's knowledge is specific and bounded. It doesn't need to know everything — it needs to know Space Tower deeply. A narrow, deep agent is achievable today. A broad, shallow one isn't useful to anyone.

---

## Implementation Sequence

### Phase 0: Schema (now)
Create the `agent/` directory in `space-tower`. Populate `project_knowledge.json` from existing CLAUDE.md. Create empty `competency_map.json`, `failure_log.json`, `request_queue.json`. Start `session_log.md`.

### Phase 1: Manual Loop (next few sessions)
Use the files in Claude Code sessions. After each session, propose updates. Build the habit. Populate the competency map with real data.

### Phase 2: Rules Accumulation (ongoing)
As the competency map fills in, extract patterns into `rules/` skill files. These become the agent's self-authored knowledge base.

### Phase 3: Player-Facing Console (when interior sim is ported to Godot)
Wire the agent context payload to the Control Room. Add text input. Connect to BYOK. Ship the MVP agent as the console's mind.

### Phase 4: Stateful Infrastructure (when available)
Migrate the manual loop to whatever Anthropic ships. The schema stays the same. The loop becomes continuous. The request queue becomes a notification system.

---

## Appendix: Relationship to Existing Systems

| Existing System | Relationship to Agent |
|----------------|----------------------|
| `_buildContext()` (keeper.js) | Agent context payload is a superset of this |
| `_buildSystemPrompt()` (keeper.js) | Agent has its own system prompt; Keeper keeps his |
| RGB context feed | Agent reads the same tower state; RGB is a separate experience |
| BYOK / `rgb_llm_connection` | Agent uses the same LLM connection |
| Control Room (floor -1) | Agent's physical home in the game |
| `S` (global state) | Agent reads S; proposes changes; game executes them |
| `CLAUDE.md` | Agent's `project_knowledge.json` is a structured version of this |
| Two-Claude workflow | Phase 1-2 run through this workflow; Phase 4 replaces it |
