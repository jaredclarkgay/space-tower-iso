# Graph Report - .  (2026-06-28)

## Corpus Check
- 67 files · ~225,887 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 168 nodes · 203 edges · 24 communities (13 shown, 11 thin omitted)
- Extraction: 78% EXTRACTED · 22% INFERRED · 0% AMBIGUOUS · INFERRED: 44 edges (avg confidence: 0.8)
- Token cost: 307,014 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Cross-Floor Invariants & Screenshot Harness|Cross-Floor Invariants & Screenshot Harness]]
- [[_COMMUNITY_Core Architecture & GameState|Core Architecture & GameState]]
- [[_COMMUNITY_The RGB & Narrative World|The RGB & Narrative World]]
- [[_COMMUNITY_Session-Summary Analysis Script|Session-Summary Analysis Script]]
- [[_COMMUNITY_Godot Gotcha Rules & Animation Rig|Godot Gotcha Rules & Animation Rig]]
- [[_COMMUNITY_GameDirector & Narrative Spine|GameDirector & Narrative Spine]]
- [[_COMMUNITY_Project Conventions & Agent Loop|Project Conventions & Agent Loop]]
- [[_COMMUNITY_Builder Agent Self-Knowledge|Builder Agent Self-Knowledge]]
- [[_COMMUNITY_Floor Population Lifecycle|Floor Population Lifecycle]]
- [[_COMMUNITY_Iso Demo Assets (Player & Tileset)|Iso Demo Assets (Player & Tileset)]]
- [[_COMMUNITY_Isometric Projection Research|Isometric Projection Research]]
- [[_COMMUNITY_Crypt Decoration Sprites|Crypt Decoration Sprites]]
- [[_COMMUNITY_Lighting & VFX Sprites|Lighting & VFX Sprites]]
- [[_COMMUNITY_Session Capture Script|Session Capture Script]]
- [[_COMMUNITY_Camera Modes|Camera Modes]]
- [[_COMMUNITY_Claude Settings Config|Claude Settings Config]]
- [[_COMMUNITY_Crow Animation Sprites|Crow Animation Sprites]]
- [[_COMMUNITY_Fabric Furnishing Sprites|Fabric Furnishing Sprites]]
- [[_COMMUNITY_Cinematic Camera Easing|Cinematic Camera Easing]]
- [[_COMMUNITY_Roof Plunge Beat|Roof Plunge Beat]]
- [[_COMMUNITY_Arboretum Stairs|Arboretum Stairs]]
- [[_COMMUNITY_App Icon|App Icon]]
- [[_COMMUNITY_Coin Pile Sprite|Coin Pile Sprite]]
- [[_COMMUNITY_Paw Prints Sprite|Paw Prints Sprite]]

## God Nodes (most connected - your core abstractions)
1. `godot-iso-builder subagent` - 9 edges
2. `Space Tower & RGB project knowledge (canonical brief)` - 9 edges
3. `Space Tower Iso project (CLAUDE.md conventions)` - 8 edges
4. `Floor Design System` - 8 edges
5. `summarize()` - 7 edges
6. `Stacked-tower invariants` - 7 edges
7. `main()` - 6 edges
8. `Developing-Polaroid branching DAG system` - 6 edges
9. `STATUS.md current-state snapshot` - 6 edges
10. `Windowed screenshot harness skill` - 6 edges

## Surprising Connections (you probably didn't know these)
- `Cody GX-5 helper robot` --implements--> `Opening sequence: Cody as director`  [INFERRED]
  agent/session_log.md → docs/opening_sequence_spec.md
- `godot-iso-builder subagent` --references--> `class_name vs preload+set_script caveat`  [EXTRACTED]
  .claude/agents/godot-iso-builder.md → agent/rules/gdscript_class_name_caveats.md
- `Graph is representation, SceneTree is one render` --conceptually_related_to--> `Single stacked-world tower.tscn / tower_controller`  [INFERRED]
  ARCHITECTURE_REPORT.md → CLAUDE.md
- `godot-iso-builder subagent` --references--> `Animation pose direction must match upcoming physics`  [EXTRACTED]
  .claude/agents/godot-iso-builder.md → agent/rules/animation_pose_alignment.md
- `godot-iso-builder subagent` --references--> `Button focus_mode vs ui_accept conflict`  [EXTRACTED]
  .claude/agents/godot-iso-builder.md → agent/rules/godot_button_focus.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Developing-Polaroid system synthesis (DAG store, build queue, hot-swap re-bake, environment mouth)** — architecture_report_polaroid_dag, architecture_report_gamestate_puredata, architecture_report_genome_system, architecture_report_build_queue, architecture_report_hot_swap, architecture_report_environment_mouth [EXTRACTED 0.90]
- **Builder Agent self-knowledge loop (rules, reports, capture hook)** — claude_md_builder_agent_loop, claude_md_capture_session_hook, agent_audit_report_core_systems, agent_overnight_report_2026_06_19 [INFERRED 0.75]
- **Floor-lifecycle generalization (Garden→Residential via declared config)** — status_md_floor_lifecycle, agent_overnight_report_2026_06_19, agent_rules_generalize_single_instance_via_declared_config_rule [EXTRACTED 0.85]
- **Vertical traversal methods in the stacked world** — agent_session_log_elevator_platform, agent_session_log_stairs, agent_session_log_vacuum_lift, agent_rules_stacked_tower_invariants_transit_ownership [EXTRACTED 0.90]
- **Builder Agent state schema in the improvement loop** — docs_builder_agent_design_v1_project_knowledge, docs_builder_agent_design_v1_competency_map, docs_builder_agent_design_v1_failure_log, docs_builder_agent_design_v1_request_queue, docs_builder_agent_design_v1_improvement_loop [EXTRACTED 0.90]
- **Director-to-mouth channel born in the opener** — docs_vision_director_and_mouths, agent_session_log_game_director, docs_opening_sequence_spec_director_mouth_channel, agent_session_log_cody_gx5 [EXTRACTED 0.85]
- **Crypt / Dungeon Decoration Set** — references_godot_iso_demo_decorations_banner_banner, references_godot_iso_demo_decorations_bone_pile_1_bone_pile, references_godot_iso_demo_decorations_bone_pile_2_bone_pile, references_godot_iso_demo_decorations_candle_candle, references_godot_iso_demo_decorations_coin_pile_coin_pile [INFERRED 0.75]
- **Lighting & VFX Effects Set** — references_godot_iso_demo_decorations_fire_fire, references_godot_iso_demo_decorations_glow_glow, references_godot_iso_demo_decorations_sparkle_sparkle, references_godot_iso_demo_decorations_shadow_gradient_shadow_gradient [INFERRED 0.85]
- **Isometric Dungeon Decoration Set** — references_godot_iso_demo_decorations_vase_1_vase, references_godot_iso_demo_decorations_vase_2_vase, references_godot_iso_demo_decorations_wall_skull_wall_skull [INFERRED 0.85]
- **Assembled Isometric Demo Assets** — references_godot_iso_demo_screenshots_isometric_isometric, references_godot_iso_demo_tileset_isotiles_isotiles, references_godot_iso_demo_player_goblin_goblin, references_godot_iso_demo_decorations_vase_1_vase [INFERRED 0.75]

## Communities (24 total, 11 thin omitted)

### Community 0 - "Cross-Floor Invariants & Screenshot Harness"
Cohesion: 0.09
Nodes (28): Two collision layers (regular slabs=2, canopy ceiling=1), Grounded-only floor changes gate, Per-floor slab-layer gating for jump pass-through, Two capture modes (override camera / game camera), Grounding gates _current_level gotcha, Windowed screenshot harness skill, WINDOWED, never --headless rule, FloorChrome shared builder module (+20 more)

### Community 1 - "Core Architecture & GameState"
Cohesion: 0.16
Nodes (18): Overnight floor-lifecycle generalization report, Director→mouth channel pattern, class_name vs preload+set_script caveat, Generalize single-instance system via declared config, Scene build-job pipeline (missing/greenfield), Environment mouth + highlight helper, GameState pure-data world model, Genome system (12-scalar gene dict) (+10 more)

### Community 2 - "The RGB & Narrative World"
Cohesion: 0.12
Nodes (17): BYOK (Bring Your Own Key) LLM connection, Mayors (rare LLM-powered sim characters), OpenRouter BYOK path, Floor 8 The Reckoning (builders vs suits), Floor 5 Restaurant (first RGB deployment), The RGB (Reality Generation Box), The sim/RGB boundary is sacred, The Critic scenario (Margaux Bellefleur) (+9 more)

### Community 3 - "Session-Summary Analysis Script"
Cohesion: 0.33
Nodes (13): first_event(), fmt_ms(), load_events(), main(), print_aggregate(), print_list(), print_report(), Reduce one session's event list to a structured summary dict. (+5 more)

### Community 4 - "Godot Gotcha Rules & Animation Rig"
Cohesion: 0.20
Nodes (12): godot-iso-builder subagent, anim_capture.tscn capture rig, Pivot-based articulated player rig, Animation pose direction must match upcoming physics, GDScript identifier shadowing rule, Fade 3D meshes via material not modulate, Button focus_mode vs ui_accept conflict, Godot editor cache (.godot/) holds stale state (+4 more)

### Community 5 - "GameDirector & Narrative Spine"
Cohesion: 0.23
Nodes (12): Cody GX-5 helper robot, Construct-from-empty (BUILD_STRUCTURE), GameDirector phase sequencer (5th autoload), TimeOfDay broadcasting clock (6th autoload), GameDirector proposed 5th autoload, Narrative-arc handoff snapshot (superseded), Human partner hire vs Cody distinction, The 7 steps of the game arc (+4 more)

### Community 6 - "Project Conventions & Agent Loop"
Cohesion: 0.24
Nodes (10): Core-systems audit (2026-06-11), F1 chapter-jump traversal-mode release bug, Builder Agent loop (agent/ self-knowledge), Auto-capture-on-session-end hook (capture_session.sh), Content-named per-floor scene dirs + shared modules, Space Tower Iso project (CLAUDE.md conventions), Single stacked-world tower.tscn / tower_controller, Three traversal methods (elevator/stairs/vacuum-lift) (+2 more)

### Community 7 - "Builder Agent Self-Knowledge"
Cohesion: 0.20
Nodes (10): Script .uid files must be generated via --import, The Builder Agent, Competency Map, Control Room console (agent home), Failure Pattern Log, The Improvement Loop, Project Knowledge store, Request Queue (+2 more)

### Community 8 - "Floor Population Lifecycle"
Cohesion: 0.24
Nodes (10): Alive threshold + bloom moment, Floor lifecycle: blank shell to lush, BLANK / POPULATING / ALIVE states, Population as grid-snapped placement mechanic, Planter bed component (activates 3x3 zone), Telemetry autoload (component_placed / floor_alive), Opening sequence: Cody as director, Utilities-first hard gate + payoff (+2 more)

### Community 9 - "Iso Demo Assets (Player & Tileset)"
Cohesion: 0.33
Nodes (7): Blue Ceramic Vase (variant 1), Blue Ceramic Vase (variant 2, gold trim), Vine-Wrapped Wall Skull Decoration, Goblin Project Icon, Goblin Player Sprite Sheet, Isometric Demo Scene Screenshot, Isometric Dungeon Tileset

### Community 10 - "Isometric Projection Research"
Cohesion: 0.47
Nodes (6): Godot isometric demo (TileMap depth sort), Compatibility renderer / web export constraints, 2:1 dimetric projection, Iso research (Phase 1), motion.y /= 2 iso movement mapping, y_sort_origin stacking pattern

### Community 11 - "Crypt Decoration Sprites"
Cohesion: 0.50
Nodes (4): Purple Skull Banner, Bone Pile (Skull Variant), Bone Pile (Ribs Variant), Melting Candle

### Community 12 - "Lighting & VFX Sprites"
Cohesion: 0.67
Nodes (4): Animated Fire Flame Sprite Sheet, Soft Radial Glow, Soft Shadow Gradient Blob, Sparkle / Star Flare Sprite Sheet

## Knowledge Gaps
- **50 isolated node(s):** `$schema`, `capture_session.sh script`, `anim_capture.tscn capture rig`, `Runtime hot-swap / re-bake pattern`, `In-game LLM autoload (absent/greenfield)` (+45 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **11 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Floor lifecycle: blank shell to lush` connect `Floor Population Lifecycle` to `Cross-Floor Invariants & Screenshot Harness`?**
  _High betweenness centrality (0.121) - this node is a cross-community bridge._
- **Why does `Floor Design System` connect `Cross-Floor Invariants & Screenshot Harness` to `Floor Population Lifecycle`?**
  _High betweenness centrality (0.114) - this node is a cross-community bridge._
- **Why does `Make-it-playable and make-it-agentic converge` connect `Floor Population Lifecycle` to `The RGB & Narrative World`, `Builder Agent Self-Knowledge`?**
  _High betweenness centrality (0.096) - this node is a cross-community bridge._
- **What connects `$schema`, `Return (chosen_file, all_session_files). chosen_file is None for --list/--all.`, `Reduce one session's event list to a structured summary dict.` to the rest of the system?**
  _59 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Cross-Floor Invariants & Screenshot Harness` be split into smaller, more focused modules?**
  _Cohesion score 0.0873015873015873 - nodes in this community are weakly interconnected._
- **Should `The RGB & Narrative World` be split into smaller, more focused modules?**
  _Cohesion score 0.125 - nodes in this community are weakly interconnected._