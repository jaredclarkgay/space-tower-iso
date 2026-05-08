# Shared static-method modules in Godot

## Rule

When several scenes need to build the same kind of geometry (slabs, walls,
elevator cores, anything procedural), extract the builders into a single
`.gd` file under `scenes/shared/`, expose them as **`static func`** on a
`extends RefCounted` script, and have callers `preload` the script. Don't
use `class_name` for shared modules.

## Why

- **No autoload bloat.** Builders aren't global state; they're functions.
  Adding them to the autoload list would clutter the global namespace and
  pay an autoload init cost for code that's only run on `_ready`.
- **No `class_name` headache.** Per F-010, `class_name` identifiers aren't
  reliably available in the headless `--import` harness — global class
  registration runs after some import-time code, so a `MyModule.new()`
  call can fail with "identifier not declared." `preload` resolves at
  parse time and never has this problem.
- **Composability.** Static methods that take `(parent: Node3D, c: Node)`
  let any scene call them in any order. Floor 1 calls `build_slab,
  build_walls, build_extension_grid, build_elevator_core` in `_ready`;
  Floor 2 (Garden) does the same. New floors get the same chrome for free.
- **Returns plain dicts when the caller needs handles back.** When a
  builder needs to expose internal references (e.g. `inner_mat` so the
  elevator handler can drive the glow), return a `Dictionary` from the
  builder. Static methods can't expose instance state — and that's a
  feature: the dict is the explicit contract.

## Shape

```gdscript
# scenes/shared/floor_chrome.gd
extends RefCounted

static func build_slab(parent: Node3D, c: Node, color: Color = Color(0.18, 0.18, 0.20)) -> void:
    var body := StaticBody3D.new()
    body.name = "SlabBody"
    parent.add_child(body)
    # ... build mesh + collision ...

static func build_elevator_core(parent: Node3D, c: Node) -> Dictionary:
    # ... build geometry ...
    return {"inner_mat": inner_mat, "doors": door_panels, "size": size}
```

```gdscript
# scenes/floor_1/floor_1.gd (caller)
const FloorChrome = preload("res://scenes/shared/floor_chrome.gd")

func _ready() -> void:
    FloorChrome.build_slab(self, _c)
    FloorChrome.build_walls(self, _c)
    FloorChrome.build_extension_grid(self, _c)
    _elevator_data = FloorChrome.build_elevator_core(self, _c)
```

## When to reach for this

- Two or more scenes need the same procedural geometry.
- The geometry is parameterized only by the parent node + a constants ref
  (no per-scene state).
- You want the option of running the builder on a fresh `Node3D` in
  isolation (e.g. for a debug viewer or test scene).

## When NOT to reach for it

- The geometry is single-use or scene-specific. Inline it in the scene's
  controller script.
- The builder needs persistent state across calls (timers, signals,
  shared mutable references). Then it's an instanced node, not a static
  module.

## Related

- F-010 (`gdscript_class_name_caveats.md`) — why `preload` beats
  `class_name`.
- The same pattern works for any cross-scene helper: input remappers,
  audio bus configurators, debug overlays. As long as the function is
  pure-ish and takes its dependencies as arguments, static is fine.
