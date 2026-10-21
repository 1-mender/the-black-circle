extends CanvasLayer
const UIStyle=preload("res://scripts/ui/dark_theme.gd")
signal quick_requested(index: int)
signal quick_bind_requested(index: int, item_id: String)
signal quick_move_requested(from: int, to: int)
signal recovery_requested
signal defeat_load_requested
signal menu_requested
signal map_requested
const MapView=preload("res://scripts/ui/map_view.gd")
const MapGeometry=preload("res://scripts/data/map_geometry.gd")
const Icons=preload("res://scripts/ui/item_icons.gd")
const VitalGauge=preload("res://scripts/ui/vital_gauge.gd")
var minimap: PanelContainer
var mini_view: Control
var map_window: PanelContainer
var full_map: Control
var map_title: Label
var location_toast: Label
var toast_left:=0.0
const QuickButton = preload("res://scripts/ui/quick_slot_button.gd")
var location_label: Label
var time_slot: HBoxContainer
var menu_slot: HBoxContainer
var header: PanelContainer
var prompt: Label
var dialogue: PanelContainer
var dialogue_name: Label
var dialogue_text: Label
var vitals: PanelContainer
var hp_bar
var stamina_bar
var quick_panel: PanelContainer
var quick_buttons: Array[Button] = []
var target_panel: PanelContainer
var target_label: Label
var defeat_panel: PanelContainer
var help_panel: PanelContainer
var menu_button: Button
var quick_hint: Label
var hint_left:=0.0

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	header = _panel(root, UIStyle.BACKGROUND)
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	header.grow_horizontal=Control.GROW_DIRECTION_BEGIN
	header.offset_left = -630
	header.offset_right = -16
	header.offset_top = 12
	header.offset_bottom = 66
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	header.add_child(row)
	location_label = _label("Златогорье", 18, UIStyle.GOLD)
	location_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(location_label)
	location_label.hide()
	time_slot = HBoxContainer.new()
	row.add_child(time_slot)
	menu_slot = HBoxContainer.new()
	menu_slot.add_theme_constant_override("separation", 6)
	row.add_child(menu_slot)
	menu_button=Button.new()
	menu_button.icon=preload("res://assets/ui/menu.svg")
	menu_button.tooltip_text="Меню игры · Esc"
	menu_button.focus_mode=Control.FOCUS_NONE
	menu_button.custom_minimum_size=Vector2(40,36)
	menu_button.pressed.connect(func():menu_requested.emit())
	menu_slot.add_child(menu_button)
	vitals = _panel(root, UIStyle.BACKGROUND)
	vitals.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	vitals.offset_left = -248
	vitals.offset_right = -16
	vitals.offset_top = -164
	vitals.offset_bottom = -100
	vitals.add_theme_stylebox_override("panel",UIStyle.style(8))
	var bars := VBoxContainer.new()
	bars.add_theme_constant_override("separation", 4)
	vitals.add_child(bars)
	var health_row := HBoxContainer.new()
	health_row.add_theme_constant_override("separation", 6)
	bars.add_child(health_row)
	var health_icon := _vital_icon(health_row, preload("res://asset/ui/vitals/health.svg"), "Здоровье")
	hp_bar = _bar(health_row, Color("a34d49"))
	hp_bar.icon = health_icon
	hp_bar.tooltip_text = "Здоровье"
	var stamina_row := HBoxContainer.new()
	stamina_row.add_theme_constant_override("separation", 6)
	bars.add_child(stamina_row)
	var stamina_icon := _vital_icon(stamina_row, preload("res://asset/ui/vitals/stamina.svg"), "Выносливость")
	stamina_bar = _bar(stamina_row, Color("548e6b"))
	stamina_bar.icon = stamina_icon
	stamina_bar.tooltip_text = "Выносливость"
	quick_panel = _panel(root, UIStyle.BACKGROUND)
	quick_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	quick_panel.offset_left = -320
	quick_panel.offset_right = -16
	quick_panel.offset_top = -90
	quick_panel.offset_bottom = -16
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 6)
	quick_panel.add_child(slots)
	for index in range(4):
		var button := QuickButton.new()
		button.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		button.add_theme_stylebox_override("normal",UIStyle.style(6,Color("171a1e"),Color("76694f")))
		button.add_theme_stylebox_override("hover",UIStyle.style(6,Color("23262a"),UIStyle.GOLD))
		button.add_theme_stylebox_override("pressed",UIStyle.style(6,Color("23262a"),UIStyle.GOLD))
		button.add_theme_stylebox_override("disabled",UIStyle.style(6,Color("171a1e"),Color("4d473d")))
		button.slot_index = index
		button.custom_minimum_size = Vector2(56, 48)
		button.clip_text = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 14)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func(): quick_requested.emit(index))
		button.bind_requested.connect(func(i: int, id: String): quick_bind_requested.emit(i, id))
		button.move_requested.connect(func(from: int, to: int): quick_move_requested.emit(from, to))
		slots.add_child(button)
		quick_buttons.append(button)
	target_panel = _panel(root, UIStyle.BACKGROUND)
	target_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	target_panel.offset_left = -266
	target_panel.offset_right = -16
	target_panel.offset_top = 82
	target_label = _label("", 16, UIStyle.GOLD)
	target_label.custom_minimum_size.x = 214
	target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	target_panel.add_child(target_label)
	target_panel.hide()
	prompt = _label("", 17, UIStyle.TEXT)
	root.add_child(prompt)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_left = -180
	prompt.offset_right = 180
	prompt.offset_top = -64
	prompt.offset_bottom = -32
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_color_override("font_shadow_color", UIStyle.BACKGROUND)
	prompt.add_theme_constant_override("shadow_offset_x", 2)
	prompt.add_theme_constant_override("shadow_offset_y", 2)
	dialogue = _panel(root, UIStyle.BACKGROUND)
	dialogue.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	dialogue.offset_left = -330
	dialogue.offset_right = 330
	dialogue.offset_top = -90
	dialogue.offset_bottom = 140
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	dialogue.add_child(box)
	dialogue_name = _label("", 20, UIStyle.GOLD)
	box.add_child(dialogue_name)
	dialogue_text = _label("", 17, UIStyle.TEXT)
	dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_text.custom_minimum_size.x = 600
	box.add_child(dialogue_text)
	box.add_child(_label("E / Esc — завершить разговор", 15, UIStyle.MUTED))
	dialogue.hide()
	defeat_panel = _panel(root, UIStyle.BACKGROUND)
	defeat_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	defeat_panel.offset_left = -270
	defeat_panel.offset_right = 270
	defeat_panel.offset_top = -90
	defeat_panel.offset_bottom = 100
	var defeat_box := VBoxContainer.new()
	defeat_box.add_theme_constant_override("separation", 12)
	defeat_panel.add_child(defeat_box)
	defeat_box.add_child(_label("Поражение · тестовый бой", 23, UIStyle.GOLD))
	defeat_box.add_child(_label("Предметы сохранены. Выберите продолжение.", 17, UIStyle.TEXT))
	for entry in [["Загрузить сохранение · L", func(): defeat_load_requested.emit()], ["Вернуться в безопасную точку", func(): recovery_requested.emit()]]:
		var button := Button.new()
		button.text = entry[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(entry[1])
		defeat_box.add_child(button)
	defeat_panel.hide()
	help_panel = _panel(root, UIStyle.BACKGROUND)
	help_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	help_panel.offset_left = -330
	help_panel.offset_right = 330
	help_panel.offset_top = -170
	help_panel.offset_bottom = 170
	var help_box := VBoxContainer.new()
	help_box.add_theme_constant_override("separation", 12)
	help_panel.add_child(help_box)
	help_box.add_child(_label("Управление", 23, UIStyle.GOLD))
	help_box.add_child(_label("WASD — движение · E — взаимодействие · I — вещи\nЛКМ — атака / выбор цели · ПКМ — удерживать блок\nShift — уклонение в сторону движения\n1–4 — быстрые действия / предметы\nSpace / P — общая пауза · Q — 0,25× / 1×\nНа паузе: ЛКМ по противнику — подготовить атаку\nЧасы сверху — скорости времени · J — жители\nK — сохранить · L — загрузить · N — навыки · M — карта\n\nПолигон — южнее площади. Снаряжение — в I.\nИконку предмета перетащите в быстрый слот.", 17, UIStyle.TEXT))
	var close_help := Button.new()
	close_help.text = "Закрыть · Esc"
	close_help.focus_mode = Control.FOCUS_NONE
	close_help.pressed.connect(func(): help_panel.hide())
	help_box.add_child(close_help)
	help_panel.hide()
	_build_map(root)
	quick_hint=_label("",14,UIStyle.TEXT)
	quick_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	quick_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(quick_hint)
	quick_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	quick_hint.offset_left=-320
	quick_hint.offset_right=-16
	quick_hint.offset_top=-205
	quick_hint.offset_bottom=-170
	quick_hint.hide()

func _build_map(root: Control) -> void:
	minimap=_panel(root,UIStyle.BACKGROUND)
	minimap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	minimap.offset_left=16
	minimap.offset_right=248
	minimap.offset_top=-180
	minimap.offset_bottom=-16
	minimap.mouse_filter=Control.MOUSE_FILTER_STOP
	minimap.tooltip_text="Карта · M"
	minimap.gui_input.connect(func(event:InputEvent):
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
			map_requested.emit()
			minimap.accept_event())
	minimap.add_theme_stylebox_override("panel",UIStyle.style(6))
	var box:=VBoxContainer.new()
	minimap.add_child(box)
	mini_view=MapView.new()
	mini_view.custom_minimum_size=Vector2(216,148)
	mini_view.size_flags_vertical=Control.SIZE_EXPAND_FILL
	box.add_child(mini_view)
	map_window=_panel(root,UIStyle.BACKGROUND)
	map_window.mouse_filter=Control.MOUSE_FILTER_STOP
	map_window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_window.offset_left=70
	map_window.offset_right=-70
	map_window.offset_top=84
	map_window.offset_bottom=-110
	var contents:=VBoxContainer.new()
	map_window.add_child(contents)
	var row:=HBoxContainer.new()
	contents.add_child(row)
	map_title=_label("",20,UIStyle.GOLD)
	map_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(map_title)
	var close_button:=Button.new()
	close_button.text="Закрыть · M / Esc"
	close_button.pressed.connect(func():map_requested.emit())
	row.add_child(close_button)
	full_map=MapView.new()
	full_map.large=true
	full_map.size_flags_vertical=Control.SIZE_EXPAND_FILL
	contents.add_child(full_map)
	contents.add_child(_label("Светлая стрелка — вы · золото — известный переход · тёмное — не исследовано",14,UIStyle.MUTED))
	map_window.hide()
	location_toast=_label("",22,UIStyle.GOLD)
	root.add_child(location_toast)
	location_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	location_toast.offset_left=-280
	location_toast.offset_right=280
	location_toast.offset_top=86
	location_toast.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	location_toast.add_theme_color_override("font_shadow_color",UIStyle.BACKGROUND)
	location_toast.add_theme_constant_override("shadow_offset_y",2)
	location_toast.hide()

func announce_location(area: String) -> void:
	location_toast.text=MapGeometry.title(area)
	toast_left=3.0
	location_toast.show()

func refresh_map(state: RefCounted, modal: bool, delta: float) -> void:
	mini_view.refresh(state)
	minimap.visible=not modal
	vitals.visible=not modal
	quick_panel.visible=not modal
	hint_left=maxf(0,hint_left-delta)
	quick_hint.visible=hint_left>0 and not modal
	if map_window.visible:
		full_map.refresh(state)
		map_title.text=MapGeometry.title(state.location_id)
	toast_left=maxf(0,toast_left-delta)
	location_toast.visible=toast_left>0 and not modal
	location_toast.modulate.a=minf(1,toast_left)


func refresh_rpg(state: RefCounted, target: String = "", hide_target: bool = false) -> void:
	header.offset_left=-header.get_combined_minimum_size().x-16
	header.offset_right=-16
	var stats: Dictionary = state.rpg.stats(state.catalog)
	hp_bar.set_vital(state.rpg.fighter.hp, stats.max_hp)
	stamina_bar.set_vital(state.rpg.fighter.stamina, stats.max_stamina)
	var names := {"attack": "Атака", "block": "Блок", "dodge": "Уклонение", "": "Пусто"}
	for index in range(4):
		var id: String = state.rpg.quick[index]
		quick_buttons[index].action_id = id
		var caption: String = names.get(id, "Предмет")
		if state.catalog.items.has(id):
			caption = "Лечение ×%d" % state.inventory.count(id) if id == "test_heal" else state.catalog.item_name(id).replace(" (тест)", "")
		quick_buttons[index].icon=Icons.quick_texture(id) if not id.is_empty() else null
		quick_buttons[index].expand_icon=true
		quick_buttons[index].add_theme_constant_override("icon_max_width",40)
		quick_buttons[index].text = ""
		quick_buttons[index].tooltip_text = caption+" · "+str(index+1)
		var fighter: Dictionary=state.rpg.fighter
		var recovery: float=0.0
		var available: bool=fighter.hp>0
		match id:
			"attack":
				recovery=fighter.cooldown/maxf(0.01,state.rpg.stats(state.catalog).attack_recovery/fighter.attack_scale)
				if fighter.attack_elapsed>=0:
					recovery=1.0-fighter.attack_elapsed/(state.combat.windup(fighter)+state.combat.active_duration(fighter))
				available=available and fighter.stamina>=12 and fighter.cooldown<=0 and fighter.attack_elapsed<0 and fighter.dodge_left<=0 and not fighter.blocking and fighter.hurt<=0
			"dodge":
				recovery=fighter.dodge_cooldown/0.9
				available=available and not state.life.clock.paused and fighter.stamina>=25 and fighter.dodge_cooldown<=0 and fighter.dodge_left<=0 and fighter.hurt<=0
			"block":
				available=available and not state.life.clock.paused and fighter.stamina>0 and fighter.attack_elapsed<0 and fighter.dodge_left<=0
			_:
				available=available and not state.life.clock.paused and state.inventory.count(id)>0
				if state.catalog.items.has(id) and state.catalog.items[id].has("heal"):
					recovery=fighter.heal_cooldown/3.0
					available=available and fighter.heal_cooldown<=0 and fighter.hp<stats.max_hp
		quick_buttons[index].show_state(available,recovery)
	var target_lines:=target.split("\n")
	var visible_lines: Array[String]=[]
	for index in range(target_lines.size()):
		var text: String=target_lines[index]
		if index==0:
			visible_lines.append(text.replace(" · прототип","").replace(" (тест)",""))
		elif text.begins_with("HP ") or text=="Побеждён":
			visible_lines.append(text)
		elif text.contains("Сильная атака"):
			visible_lines.append("Сильный удар!")
		elif text.contains("Подготовка атаки"):
			visible_lines.append("Готовит удар")
		elif text.contains("Атака подготовлена"):
			visible_lines.append("Действие подготовлено")
	target_label.text = "\n".join(visible_lines)
	target_panel.visible = not target.is_empty() and not hide_target

func _bar(parent: Control, color: Color) -> Control:
	var bar := VitalGauge.new()
	bar.custom_minimum_size = Vector2(184, 20)
	bar.liquid_color = color
	var clear := StyleBoxEmpty.new()
	bar.add_theme_stylebox_override("background", clear)
	bar.add_theme_stylebox_override("fill", clear)
	parent.add_child(bar)
	return bar

func _vital_icon(parent: Control, texture: Texture2D, caption: String) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.tooltip_text = caption
	parent.add_child(icon)
	icon.pivot_offset = Vector2(10, 10)
	return icon

func set_near_npc(near: bool) -> void:
	prompt.text = "[ E ]  Поговорить с жителем" if near else ""
	prompt.visible = near and not dialogue.visible

func show_dialogue(display_name: String, message: String) -> void:
	dialogue_name.text = display_name
	dialogue_text.text = message
	dialogue.show()
	prompt.hide()

func close_dialogue() -> void:
	dialogue.hide()

func _panel(parent: Control, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := UIStyle.style()
	style.bg_color = color
	style.border_color = UIStyle.BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel

func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label




func reveal_quick(index: int) -> void:
	quick_hint.text=quick_buttons[index].tooltip_text
	hint_left=1.3
	quick_hint.show()

func animate_quick(index: int, action: String, success: bool) -> void:
	if index >= 0 and index < quick_buttons.size():
		quick_buttons[index].call("play_feedback", action, success)
