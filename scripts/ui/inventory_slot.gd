extends Button
const UIStyle=preload("res://scripts/ui/dark_theme.gd")
## Представление ссылки на предмет; не владеет вещами и не меняет Ledger.
signal chosen(item_id: String, source_slot: String)
signal activated(item_id: String, source_slot: String)
signal context_requested(item_id: String, source_slot: String, point: Vector2)
signal dropped(target: String, data: Dictionary)
const Icons = preload("res://scripts/ui/item_icons.gd")
var item_id := ""
var source_slot := ""
var target_slot := ""
var quick_index := -1
var amount := 0
var empty_icon := 208
var caption := ""
var selected := false
var suitable := false
var select_on_focus := true
var validator: Callable
var image: TextureRect
var count_label: Label
var mark: Label

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(60, 60)
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	image = TextureRect.new()
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(image)
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.offset_left = 4 if quick_index >= 0 else 10
	image.offset_top = 4 if quick_index >= 0 else 7
	image.offset_right = -4 if quick_index >= 0 else -10
	image.offset_bottom = -4 if quick_index >= 0 else -13
	count_label = Label.new()
	count_label.add_theme_font_size_override("font_size", 12)
	count_label.add_theme_color_override("font_color", UIStyle.TEXT)
	count_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	count_label.add_theme_constant_override("shadow_offset_x", 1)
	count_label.add_theme_constant_override("shadow_offset_y", 1)
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(count_label)
	count_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count_label.offset_right = -5
	count_label.offset_bottom = -3
	mark = Label.new()
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.position = Vector2(4, 2)
	mark.add_theme_font_size_override("font_size", 11)
	mark.add_theme_color_override("font_color", UIStyle.GOLD)
	add_child(mark)
	pressed.connect(func(): chosen.emit(item_id, source_slot))
	focus_entered.connect(func():
		if select_on_focus:
			chosen.emit(item_id, source_slot))
	refresh()

func refresh() -> void:
	if image == null:
		return
	image.texture = Icons.quick_texture(item_id) if quick_index >= 0 and not item_id.is_empty() else Icons.texture(item_id, empty_icon)
	image.modulate = Color.WHITE if not item_id.is_empty() else Color(0.7, 0.72, 0.65, 0.28)
	count_label.text = str(amount) if amount > 1 else ""
	mark.text = caption
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := UIStyle.style()
		style.bg_color = UIStyle.HOVER if selected else UIStyle.BACKGROUND
		style.border_color = UIStyle.GOLD if selected or state == "focus" else (UIStyle.GOLD if suitable else (UIStyle.GOLD if state == "hover" else UIStyle.BORDER))
		style.set_border_width_all(2 if selected or state == "focus" or suitable else 1)
		style.set_corner_radius_all(4)
		add_theme_stylebox_override(state, style)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			context_requested.emit(item_id, source_slot, get_global_mouse_position())
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			activated.emit(item_id, source_slot)
			accept_event()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		activated.emit(item_id, source_slot)
		accept_event()
	if event is InputEventKey and event.pressed and event.keycode == KEY_MENU:
		context_requested.emit(item_id, source_slot, global_position + size * 0.5)
		accept_event()

func _get_drag_data(_position: Vector2) -> Variant:
	if item_id.is_empty():
		return null
	var preview := TextureRect.new()
	preview.texture = Icons.quick_texture(item_id) if quick_index >= 0 else Icons.texture(item_id)
	preview.custom_minimum_size = Vector2(48, 48)
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_drag_preview(preview)
	var result := {"item_id": item_id, "source_slot": source_slot}
	if quick_index >= 0:
		result.quick_index = quick_index
	return result
func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and validator.is_valid() and validator.call(target_slot, data)
func _drop_data(_position: Vector2, data: Variant) -> void:
	dropped.emit(target_slot, data)

