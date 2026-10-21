extends SceneTree
## Run Godot --headless --path . --script res://tools/build_ui_theme.gd
func _initialize() -> void:
	var error:=ResourceSaver.save(preload("res://scripts/ui/dark_theme.gd").make_theme(),"res://themes/dark_theme.tres")
	quit(error)
