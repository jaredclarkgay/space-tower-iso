extends Node

# Audio manager stub for the iso slice. No music, no SFX in scope yet.
# Stubs exist so iso_player / iso_floor can call them harmlessly during
# Phase 3 prototyping. Pattern mirrors sibling
# space-tower/autoloads/audio_manager.gd; real implementation can land later.

func play_sfx(_path: String) -> void:
	pass

func play_music(_path: String, _fade_in: float = 0.5) -> void:
	pass

func stop_music(_fade_out: float = 0.5) -> void:
	pass
