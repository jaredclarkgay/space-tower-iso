extends Node

# Save manager stub. The iso vertical slice has nothing worth persisting
# (no economy, no progress). Shape preserved here so Phase 3+ can grow it
# without touching call sites elsewhere. Pattern mirrors
# sibling space-tower/autoloads/save_manager.gd.

const SAVE_PATH := "user://iso_slice_save.json"
const SAVE_VERSION := 1

func save_game() -> void:
	pass

func load_game() -> bool:
	return false
