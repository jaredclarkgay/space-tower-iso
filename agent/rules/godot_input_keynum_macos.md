# Number-key input on macOS — prefer InputMap polling over keycode comparison

## The problem

Godot dispatches `InputEventKey` events with three distinct fields:
`keycode`, `physical_keycode`, and `unicode`. On macOS in particular —
and on non-US keyboard layouts generally — the top-row number keys can
arrive with `keycode == 0` and only `physical_keycode` or `unicode`
populated, depending on the layout, modifier state, and IME.

A handler that only checks `event.keycode` therefore silently misses
the press. Headless tests pass because they don't trigger any real OS
input dispatch.

## Symptoms

- "Pressing 1/2/3 to pick an option does nothing."
- Same code works in the editor on one machine, fails on another with
  a different keyboard layout.
- Adding a `print(event.keycode)` shows `0` for the key presses you
  expected.

## The fix

Make the **primary** input path go through `InputMap` actions polled
each frame:

```gdscript
# In project.godot, bind KEY_1..KEY_N to actions:
#   action_pick_1, action_pick_2, ...
# Then in _process:
for i in range(N):
    if Input.is_action_just_pressed("action_pick_%d" % (i + 1)):
        _on_pick(i)
        break
```

InputMap consults all event sources (keycode, physical_keycode,
unicode, joypad, etc.), so a binding to KEY_1 fires regardless of
which field the OS populated.

Keep the `_input(InputEventKey)` path as a **secondary** robustness
layer that checks BOTH keycode and physical_keycode:

```gdscript
func _input(event):
    if event is InputEventKey and event.pressed:
        var kc = event.keycode if event.keycode != 0 else event.physical_keycode
        if kc >= KEY_1 and kc <= KEY_9:
            _on_pick(kc - KEY_1)
            get_viewport().set_input_as_handled()
```

Don't choose between the two paths — both are cheap, and the polled
path is the one that actually rescues the failure mode while the
event path catches anything the action bindings miss.

## Why both paths

- **Polled (primary):** survives keyboard-layout quirks and OS-level
  routing. Works on US, French AZERTY, German QWERTZ, etc.
- **Event (secondary):** has access to `set_input_as_handled()` so
  the press doesn't fall through to other handlers (e.g. you don't
  want pressing `1` in a chooser to also nudge the camera or the
  player).

## What NOT to do

- Don't rely on `event.unicode` for digits. It's text-input oriented
  and the value depends on IME state.
- Don't try to fix this by emitting `InputEventAction.parse_input_event`
  fakes from `_input` — InputMap polling already gives you what you
  want, simpler.
- Don't add per-platform `OS.get_name()` branches. The same polled
  pattern works on all platforms.

## Verification

Print on press to make sure both paths see the key:

```gdscript
func _input(event):
    if event is InputEventKey and event.pressed:
        print("kc=%d phys=%d uni=%d" %
              [event.keycode, event.physical_keycode, event.unicode])
```

If `keycode` is consistently 0 on the operator's machine, the polled
path is doing all the real work — that's fine.
