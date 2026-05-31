# One-way-up floor pass-through via collision layers

**When:** A stacked-world iso build where the player can jump UP through the
floor above (landing on it from below) but must never bonk their head on it
while rising — except for a designated "solid ceiling" floor (e.g. a glass
canopy) that should still block.

## The trick

Split floor slabs across two collision layers and toggle the player's *mask*
by vertical velocity:

- **Regular floor slabs → collision layer 2.** These are the floors you want to
  rise through.
- **The one solid ceiling → collision layer 1.** Always blocks.
- **Player mask:** drop layer 2 from the mask whenever rising; keep layer 1.

```gdscript
# iso_player.gd, in _physics_process just before move_and_slide():
# While rising, ignore regular slabs (layer 2) so the jump passes UP through
# them; the canopy ceiling (layer 1) still blocks. Falling re-enables layer 2
# so we land on every floor from above.
set_collision_mask_value(2, velocity.y <= 0.1)
move_and_slide()
# default state (in _ready): set_collision_mask_value(2, true)
```

The `<= 0.1` (not `<= 0.0`) gives a small dead-band so grounded jitter doesn't
flicker the mask.

## Why this over alternatives

- `CollisionShape3D.one_way_collision` is per-shape and orients to the shape's
  local +Y — fine for a single platform, fragile across a tiled slab with holes
  and varied transforms. The mask toggle is global and order-independent.
- Don't try to gate on `is_on_floor()` — by the time you're on the floor it's
  too late; you must drop the mask *before* `move_and_slide()` resolves the
  rising frame.

## Pairs with: grounded-only floor changes

The tower controller only re-evaluates which floor you're "on" when
`is_on_floor()` is true (`tower_controller.gd` `_update`). So a jump or a
ceiling bonk never reveals the floor above or moves the camera — you change
floors by *landing*: walk up the stairs, or jump up through an aperture ring and
land on the slab above. Keep these two rules together; the pass-through is what
makes "jump up through a ring" reachable, the grounded-gate is what keeps the
view stable mid-jump.
