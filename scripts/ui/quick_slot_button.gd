extends Button
signal bind_requested(index: int, item_id: String)
signal move_requested(from: int, to: int)
var slot_index := 0
var action_id := ""
var cooldown_fraction:=0.0
var feedback_kind := ""
var feedback_success := false
var feedback_age := -1.0
const FEEDBACK_LENGTH := 0.38

func play_feedback(kind: String, success: bool) -> void:
	feedback_kind = kind
	feedback_success = success
	feedback_age = 0.0
	pivot_offset = size * 0.5
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	if feedback_age < 0.0:
		return
	feedback_age += minf(delta, 0.1)
	var t := clampf(feedback_age / FEEDBACK_LENGTH, 0.0, 1.0)
	if feedback_success:
		var squeeze := 0.94 if t < 0.18 else (1.055 if t < 0.48 else 1.0 + 0.055 * (1.0 - t) / 0.52)
		scale = Vector2.ONE * squeeze
	else:
		scale = Vector2.ONE * (0.965 if t < 0.22 else 1.0)
	if t >= 1.0:
		feedback_age = -1.0
		scale = Vector2.ONE
		set_process(false)
	queue_redraw()

func _draw() -> void:
	if cooldown_fraction>0.01:
		var center:=size/2
		var points:=PackedVector2Array([center])
		var radius:=minf(size.x,size.y)/2-4
		if cooldown_fraction>=0.99:
			draw_circle(center,radius,Color(0.025,0.03,0.035,0.72))
		else:
			for step in range(33):
				var angle: float=-PI/2+TAU*clampf(cooldown_fraction,0,1)*step/32.0
				points.append(center+Vector2.from_angle(angle)*radius)
			draw_colored_polygon(points,Color(0.025,0.03,0.035,0.72))
	if feedback_age >= 0.0:
		_draw_feedback()

func _draw_feedback() -> void:
	var t := clampf(feedback_age / FEEDBACK_LENGTH, 0.0, 1.0)
	var fade := pow(1.0 - t, 1.3)
	var center := size * 0.5
	if not feedback_success:
		draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color(0.69, 0.60, 0.48, fade * 0.65), false, 2.0)
		draw_line(Vector2(8, size.y - 7), Vector2(size.x - 8, size.y - 7), Color(0.65, 0.50, 0.42, fade * 0.55), 2.0)
		return
	var gold := Color(0.92, 0.76, 0.48, fade * 0.82)
	draw_arc(center, 19.0 + t * 8.0, -PI * 0.75, PI * 0.72, 30, gold, 2.0, false)
	match feedback_kind:
		"attack":
			var slash := Color(1.0, 0.91, 0.68, fade)
			var shift := (t - 0.35) * 11.0
			draw_line(center + Vector2(-11 + shift, 10), center + Vector2(9 + shift, -11), slash, 3.0)
			draw_line(center + Vector2(-7 + shift, 11), center + Vector2(13 + shift, -10), Color(0.80, 0.50, 0.27, fade * 0.7), 1.0)
		"block":
			draw_arc(center, 11.0 + 9.0 * t, -PI * 0.93, -PI * 0.07, 22, Color(0.92, 0.82, 0.56, fade), 3.0, false)
			draw_arc(center, 11.0 + 9.0 * t, PI * 0.07, PI * 0.93, 22, Color(0.92, 0.82, 0.56, fade), 3.0, false)
		"dodge":
			for streak in range(3):
				var y := 13.0 + streak * 9.0
				var x := 8.0 + t * (12.0 + streak * 3.0)
				draw_line(Vector2(x, y), Vector2(x + 12.0, y - 4.0), Color(0.71, 0.85, 0.68, fade * (0.9 - streak * 0.18)), 2.0)
		"heal":
			for drop in range(3):
				var x := center.x + (drop - 1) * 10.0 + sin(t * 5.0 + drop) * 2.0
				var y := center.y + 8.0 - t * (17.0 + drop * 4.0)
				draw_circle(Vector2(x, y), 2.0 + (1.0 - t), Color(0.89, 0.43, 0.37, fade * 0.9))
		_:
			draw_arc(center, 12.0 + 5.0 * t, -PI * 0.5, PI * 1.5, 24, Color(0.85, 0.75, 0.51, fade * 0.65), 2.0, false)
func show_state(available: bool, fraction: float) -> void:
	disabled=not available
	cooldown_fraction=clampf(fraction,0,1)
	add_theme_color_override("icon_disabled_color",Color(0.72,0.70,0.66,0.9))
	queue_redraw()
func _get_drag_data(_position: Vector2) -> Variant:
	if action_id.is_empty():
		return null
	var preview := Label.new()
	preview.text = tooltip_text
	set_drag_preview(preview)
	return {"item_id": action_id, "quick_index": slot_index}
func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("item_id") is String
func _drop_data(_position: Vector2, data: Variant) -> void:
	if data.get("quick_index", -1) >= 0:
		move_requested.emit(int(data.quick_index), slot_index)
	else:
		bind_requested.emit(slot_index, data.item_id)
