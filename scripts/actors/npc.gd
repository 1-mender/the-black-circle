extends "res://scripts/actors/actor.gd"
## Только представление: цели, потребности и маршруты принадлежат симуляции.

var caption: Label

@export var npc_id := "test_npc"

func setup_resident(display_name: String, sprite_index: int) -> void:
	character_index = sprite_index
	var label := Label.new()
	caption=label
	label.visible=false
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.z_index=10
	label.position = Vector2(-82, -68)
	label.text = display_name
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_shadow_color", Color("182b2a"))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(label)
	update_sprite(Vector2.ZERO, 0.0)

func sync_resident(record: Dictionary, blend: float, delta: float, paused: bool, snap: bool = false) -> void:
	var destination: Vector2 = record["position"]
	position = destination if snap else (record["previous"] as Vector2).lerp(destination, blend)
	if snap:
		reset_physics_interpolation()
	var direction: Vector2 = destination - (record["previous"] as Vector2)
	if paused or record["activity"] != "walk":
		direction = Vector2.ZERO
	update_sprite(direction, delta)
