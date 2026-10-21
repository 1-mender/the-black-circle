extends ProgressBar

# Visual-only reservoir. The ProgressBar value remains the authoritative HUD value;
# display_ratio and all effects are deliberately absent from saves and simulation.
var liquid_color := Color("a34d49")
var icon: TextureRect
var display_ratio := 1.0
var ghost_ratio := 1.0
var restore_flash := 0.0
var damage_flash := 0.0
var ripple_age := 10.0
var shimmer_time := 0.0
var _sampled := false
var _last_value := 0.0
var _ghost_hold := 0.0
var _pulse_cooldown := 0.0

func _ready() -> void:
	show_percentage = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)

func set_vital(amount: float, capacity: float) -> void:
	max_value = maxf(1.0, capacity)
	value = clampf(amount, 0.0, max_value)
	var next_ratio := float(value / max_value)
	if not _sampled:
		_sampled = true
		display_ratio = next_ratio
		ghost_ratio = next_ratio
	else:
		var change := value - _last_value
		if change < -0.05:
			damage_flash = 1.0
			_ghost_hold = 0.28
			ghost_ratio = maxf(ghost_ratio, display_ratio)
		elif change > 0.05:
			if change >= 2.0 or _pulse_cooldown <= 0.0:
				restore_flash = 1.0 if change >= 2.0 else 0.75
				ripple_age = 0.0
				_pulse_cooldown = 0.6
	_last_value = value
	queue_redraw()

func _process(delta: float) -> void:
	var step := minf(delta, 0.1)
	shimmer_time += step
	_pulse_cooldown = maxf(0.0, _pulse_cooldown - step)
	_ghost_hold = maxf(0.0, _ghost_hold - step)
	restore_flash = maxf(0.0, restore_flash - step * 1.35)
	damage_flash = maxf(0.0, damage_flash - step * 2.2)
	ripple_age += step
	var target_ratio := float(value / max_value)
	display_ratio = move_toward(display_ratio, target_ratio, step * (2.0 if target_ratio > display_ratio else 3.0))
	if _ghost_hold <= 0.0:
		ghost_ratio = move_toward(ghost_ratio, display_ratio, step * 0.85)
	if icon != null:
		icon.modulate = Color.WHITE.lerp(liquid_color.lightened(0.35), restore_flash * 0.42)
		icon.scale = Vector2.ONE * (1.0 + restore_flash * 0.12 + damage_flash * 0.05)
	queue_redraw()

func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	var inner := Rect2(Vector2(2, 2), size - Vector2(4, 4))
	var liquid_width := floorf(inner.size.x * clampf(display_ratio, 0.0, 1.0))
	var ghost_width := floorf(inner.size.x * clampf(ghost_ratio, 0.0, 1.0))
	var frame := Color("76674d").lerp(Color("dd9d74"), damage_flash * 0.75)
	draw_rect(bounds, Color("101316"))
	draw_rect(bounds, frame, false, 1.0)
	draw_rect(inner, Color("25272a"))
	draw_line(Vector2(2, 2), Vector2(size.x - 2, 2), Color("574f42", 0.65), 1.0)
	if ghost_width > liquid_width:
		draw_rect(Rect2(inner.position + Vector2(liquid_width, 0), Vector2(ghost_width - liquid_width, inner.size.y)), liquid_color.lightened(0.48) * Color(1, 1, 1, 0.53))
	if liquid_width <= 0.0:
		return
	var liquid := Rect2(inner.position, Vector2(liquid_width, inner.size.y))
	draw_rect(liquid, liquid_color.darkened(0.16))
	draw_rect(Rect2(liquid.position + Vector2(0, 2), Vector2(liquid_width, maxf(1, inner.size.y - 5))), liquid_color)
	draw_line(Vector2(2, inner.end.y - 2), Vector2(2 + liquid_width, inner.end.y - 2), liquid_color.darkened(0.42), 2.0)
	# A thin travelling reflection keeps a full reservoir alive without a distracting loop.
	var gleam_x := fmod(shimmer_time * 16.0, inner.size.x + 22.0) - 11.0
	if gleam_x > 0.0 and gleam_x < liquid_width:
		var gleam := liquid_color.lightened(0.45)
		gleam.a = 0.27
		draw_rect(Rect2(Vector2(inner.position.x + gleam_x, 4), Vector2(minf(5.0, liquid_width - gleam_x), inner.size.y - 4)), gleam)
	# Recovery sends one brighter ripple across the current liquid and small rising bubbles.
	if restore_flash > 0.0:
		var ripple_x := minf(liquid_width, ripple_age * 230.0)
		var ripple := liquid_color.lightened(0.65)
		ripple.a = restore_flash * 0.66
		draw_rect(Rect2(Vector2(inner.position.x + ripple_x, 3), Vector2(2, inner.size.y - 2)), ripple)
		for bubble in range(3):
			var travel := fmod(ripple_age * (48.0 + bubble * 13.0) + bubble * 31.0, maxf(1.0, liquid_width))
			var rise := fmod(ripple_age * (12.0 + bubble * 3.0) + bubble * 5.0, maxf(1.0, inner.size.y - 3.0))
			var bubble_color := liquid_color.lightened(0.8)
			bubble_color.a = restore_flash * 0.65
			draw_rect(Rect2(Vector2(inner.position.x + travel, inner.end.y - 2.0 - rise), Vector2(2, 2)), bubble_color)
	if damage_flash > 0.0:
		draw_rect(inner, Color(1, 0.36, 0.29, damage_flash * 0.17))
