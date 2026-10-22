extends CanvasLayer
const UIStyle=preload("res://scripts/ui/dark_theme.gd")

signal pause_requested
signal speed_selected(value: float)
signal debug_requested

const Definitions = preload("res://scripts/data/resident_definitions.gd")
var time_label: Label
var pause_button: Button
var speed_buttons: Dictionary = {}
var residents_button: Button
var state_label: Label
var pace_label: Label
var debug_panel: PanelContainer
var debug_text: Label
var picker: OptionButton
var debug_enabled := false
var selected_id := "test_npc"
var clock_panel: PanelContainer
var clock_button: Button

func _ready() -> void:
	layer = 3
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	clock_panel = _panel(root)
	clock_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	clock_panel.offset_left = -468
	clock_panel.offset_right = -16
	clock_panel.offset_top = 78
	clock_panel.hide()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	clock_panel.add_child(box)
	var heading := HBoxContainer.new()
	box.add_child(heading)
	time_label = Label.new()
	time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_label.add_theme_font_size_override("font_size", 20)
	time_label.add_theme_color_override("font_color", UIStyle.TEXT)
	heading.add_child(time_label)
	state_label = Label.new()
	state_label.add_theme_font_size_override("font_size", 11)
	state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_child(state_label)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(controls)
	pause_button = _button(controls, "Пауза", func(): pause_requested.emit())
	pause_button.toggle_mode = true
	pause_button.custom_minimum_size = Vector2(74, 32)
	pause_button.tooltip_text = "Пауза / продолжить · P"
	var group := ButtonGroup.new()
	for speed in [0.25, 1, 4, 12, 60]:
		var button := _button(controls, str(speed) + "×", func(): speed_selected.emit(speed))
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(52, 32)
		button.tooltip_text = "Выбрать %d×. Пауза сохраняется.\nT — следующая скорость." % speed
		speed_buttons[speed] = button
	var footer := HBoxContainer.new()
	box.add_child(footer)
	residents_button = _button(footer, "Жители · J", func(): debug_requested.emit())
	residents_button.toggle_mode = true
	residents_button.tooltip_text = "Открыть / закрыть панель жителей · J"
	pace_label = Label.new()
	pace_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pace_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pace_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pace_label.add_theme_font_size_override("font_size", 13)
	pace_label.add_theme_color_override("font_color", UIStyle.MUTED)
	footer.add_child(pace_label)
	debug_panel = _panel(root)
	debug_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	debug_panel.offset_left = 16
	debug_panel.offset_right = 372
	debug_panel.offset_top = 90
	var debug_box := VBoxContainer.new()
	debug_box.add_theme_constant_override("separation", 12)
	debug_panel.add_child(debug_box)
	picker = OptionButton.new()
	picker.focus_mode = Control.FOCUS_NONE
	for id in Definitions.PEOPLE:
		picker.add_item(Definitions.PEOPLE[id]["name"])
		picker.set_item_metadata(picker.item_count - 1, id)
	picker.item_selected.connect(func(index: int): selected_id = picker.get_item_metadata(index))
	debug_box.add_child(picker)
	debug_text = Label.new()
	debug_text.custom_minimum_size = Vector2(328, 320)
	debug_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	debug_text.add_theme_font_size_override("font_size", 16)
	debug_box.add_child(debug_text)
	debug_panel.hide()

func attach_to_hud(slot: Control) -> void:
	clock_button = _button(slot, "", func(): clock_panel.visible = not clock_panel.visible)
	clock_button.tooltip_text = "Управление временем · Space — пауза · Q — замедление"

func toggle_debug() -> void:
	debug_enabled = not debug_enabled
	residents_button.set_pressed_no_signal(debug_enabled)

func refresh(life: RefCounted, player_location: String, modal: bool) -> void:
	for index in range(picker.item_count - 1, -1, -1):
		if not life.people.has(picker.get_item_metadata(index)):
			picker.remove_item(index)
	if not life.people.has(selected_id):
		selected_id = str(life.people.keys()[0])
	for id in life.people:
		var found := false
		for index in range(picker.item_count):
			if picker.get_item_metadata(index) == id:
				found = true
				break
		if not found:
			picker.add_item(life.definitions[id].name)
			picker.set_item_metadata(picker.item_count - 1, id)
	if modal:
		clock_panel.hide()
	if clock_button != null:
		clock_button.disabled = modal
	time_label.text = life.clock.display()
	if clock_button != null:
		clock_button.text = life.clock.display().get_slice(" · ",1)+( " Ⅱ" if life.clock.paused else "")
		clock_button.tooltip_text=life.clock.display()+" · "+str(life.clock.speed)+"×\nУправление временем"
	state_label.text = "НА ПАУЗЕ" if life.clock.paused else "ВРЕМЯ ИДЁТ"
	state_label.add_theme_color_override("font_color", UIStyle.GOLD if life.clock.paused else UIStyle.MUTED)
	pause_button.text = "Пуск" if life.clock.paused else "Пауза"
	pause_button.set_pressed_no_signal(life.clock.paused)
	for speed in speed_buttons:
		speed_buttons[speed].set_pressed_no_signal(speed == life.clock.speed)
		speed_buttons[speed].disabled = life.clock.threatened and speed > 1
	pace_label.text = "Опасность: до 1×" if life.clock.threatened else {0.25: "Замедление", 1.0: "Сутки: 12 мин", 4.0: "Сутки: 3 мин", 12.0: "Сутки: 1 мин", 60.0: "Сутки: 12 с"}.get(life.clock.speed, "")
	residents_button.set_pressed_no_signal(debug_enabled)
	debug_panel.visible = debug_enabled and not modal
	if not debug_panel.visible:
		return
	for index in range(picker.item_count):
		if picker.get_item_metadata(index) == selected_id:
			picker.select(index)
			break
	var record: Dictionary = life.people[selected_id]
	var position: Vector2 = record["position"]
	var goal: Vector2 = record["goal"]
	debug_text.text = ("%s\n%s\nПлан: %s\nПричина: %s\n\nУсталость: %.0f / 100\nНужен перерыв: %.0f / 100\n\nПозиция: %.0f, %.0f\nЦель: %.0f, %.0f\nТочек маршрута: %d\n\nРаботал: %d мин. · спал: %d мин."
		% [("Город" if record["location"] == "town" else "Шахта") + (" · на экране" if player_location == record["location"] else " · фоновая симуляция"),
		Definitions.TASK_NAMES[record["activity"]], Definitions.TASK_NAMES[record["task"]],
		Definitions.REASONS[record["reason"]], record["fatigue"], record["rest_need"],
		position.x, position.y, goal.x, goal.y, record["path"].size(), record["work_minutes"], record["sleep_minutes"]])

func _panel(parent: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := UIStyle.style()
	style.bg_color = UIStyle.BACKGROUND
	style.border_color = UIStyle.BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel

func _button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 14)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var style := UIStyle.style()
		var selected: bool = state in ["pressed", "hover_pressed"]
		style.bg_color = UIStyle.HOVER if selected else UIStyle.PANEL
		style.border_color = UIStyle.GOLD if state != "normal" else UIStyle.BORDER
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", UIStyle.TEXT)
	button.add_theme_color_override("font_pressed_color", UIStyle.TEXT)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

