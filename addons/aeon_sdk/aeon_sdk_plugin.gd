@tool
extends EditorPlugin
# Registers the Aeon autoload so the game can call Aeon.unlock("first_win") anywhere.
func _enter_tree() -> void:
	add_autoload_singleton("Aeon", "res://addons/aeon_sdk/aeon.gd")
func _exit_tree() -> void:
	remove_autoload_singleton("Aeon")
