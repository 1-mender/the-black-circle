extends CanvasLayer
signal action_requested(action: String)
signal interaction_changed(value: bool)
signal volume_changed(value: float)
signal fullscreen_changed(value: bool)
const UIStyle=preload("res://scripts/ui/dark_theme.gd")
const Icons=preload("res://scripts/ui/item_icons.gd")
var window: Control
var panel: PanelContainer
var box: VBoxContainer
var feedback: Label
var page:="pause"
var settings_origin:="pause"
var show_interaction:=true
var master_volume:=1.0
var fullscreen:=false
var buttons: Dictionary={}
var toggle: CheckButton
var volume_slider: HSlider
var volume_label: Label
var fullscreen_toggle: CheckButton
var shade: ColorRect
const ACTIONS={"move_up":"Вверх","move_down":"Вниз","move_left":"Влево","move_right":"Вправо","attack":"Атака","block":"Блок","dodge":"Уклонение","pause_game":"Тактическая пауза","combat_speed":"Скорость боя","quick_1":"Быстрый слот 1","quick_2":"Быстрый слот 2","quick_3":"Быстрый слот 3","quick_4":"Быстрый слот 4","interact":"Взаимодействие","inventory":"Инвентарь","social_journal":"Журнал","skills":"Навыки","save_game":"Сохранение","load_game":"Загрузка","world_map":"Карта","cycle_resident":"Выбор собеседника","npc_debug":"Отладка жителей","debug_labels":"Отладка подписей","time_speed":"Скорость времени","ui_cancel":"Меню / назад"}
func _ready() -> void:
	layer=12
	window=Control.new()
	window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(window)
	shade=ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color=Color(0.015,0.018,0.022,0.55)
	window.add_child(shade)
	panel=PanelContainer.new()
	panel.add_theme_stylebox_override("panel",UIStyle.style(18))
	window.add_child(panel)
	box=VBoxContainer.new()
	box.add_theme_constant_override("separation",7)
	panel.add_child(box)
	window.resized.connect(_layout)
	window.hide()
func _layout() -> void:
	var viewport:=get_viewport().get_visible_rect().size
	var height:=minf(600,viewport.y-80) if page=="controls" else panel.get_combined_minimum_size().y
	panel.position=Vector2((viewport.x-380)/2,maxf(24,(viewport.y-height)/2))
	panel.size=Vector2(380,height)
func show_page(value: String="pause") -> void:
	page=value
	buttons.clear()
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	window.show()
	shade.color=Color(0.06,0.067,0.078,1) if page=="title" else Color(0.015,0.018,0.022,0.55)
	var title:=Label.new()
	title.text={"pause":"Пауза","title":"Златогорье","settings":"Настройки","controls":"Управление","confirm":"Несохранённые изменения"}.get(page,"Меню")
	title.add_theme_font_size_override("font_size",23)
	title.add_theme_color_override("font_color",UIStyle.GOLD)
	box.add_child(title)
	match page:
		"pause":
			for entry in [["resume","Продолжить"],["inventory","Инвентарь"],["journal","Журнал"],["skills","Персонаж и навыки"],["save","Сохранить игру"],["load","Загрузить игру"],["settings","Настройки"],["main","В главное меню"]]:
				_button(entry[0],entry[1])
		"title":
			_button("resume","Продолжить текущую игру")
			_button("load","Загрузить игру")
			_button("settings","Настройки")
		"settings":
			volume_label=Label.new()
			volume_label.text="Общая громкость: %d%%"%roundi(master_volume*100.0)
			box.add_child(volume_label)
			volume_slider=HSlider.new()
			volume_slider.min_value=0
			volume_slider.max_value=100
			volume_slider.step=5
			volume_slider.set_value_no_signal(master_volume*100.0)
			volume_slider.value_changed.connect(func(volume_percent:float):
				master_volume=volume_percent/100.0
				volume_label.text="Общая громкость: %d%%"%roundi(volume_percent)
				volume_changed.emit(master_volume))
			box.add_child(volume_slider)
			fullscreen_toggle=CheckButton.new()
			fullscreen_toggle.text="Полный экран"
			fullscreen_toggle.set_pressed_no_signal(fullscreen)
			fullscreen_toggle.toggled.connect(func(enabled:bool):fullscreen=enabled;fullscreen_changed.emit(enabled))
			box.add_child(fullscreen_toggle)
			toggle=CheckButton.new()
			toggle.text="Подсказки взаимодействия"
			toggle.set_pressed_no_signal(show_interaction)
			toggle.toggled.connect(func(enabled:bool):show_interaction=enabled;interaction_changed.emit(enabled))
			box.add_child(toggle)
			_button("controls","Управление")
			_button("back","Назад")
		"controls":
			var scroll:=ScrollContainer.new()
			scroll.custom_minimum_size=Vector2(0,390)
			scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
			box.add_child(scroll)
			var grid:=GridContainer.new()
			grid.columns=2
			grid.add_theme_constant_override("h_separation",14)
			grid.add_theme_constant_override("v_separation",10)
			scroll.add_child(grid)
			for action in ACTIONS:
				if not InputMap.has_action(action):
					continue
				for text in [ACTIONS[action],binding_text(action)]:
					var label:=Label.new()
					label.text=text
					label.add_theme_font_size_override("font_size",14)
					grid.add_child(label)
			_button("back","Назад")
		"confirm":
			var note:=Label.new()
			note.text="Есть несохранённые изменения.\nВернуться в главное меню?"
			note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			box.add_child(note)
			_button("back","Остаться в игре")
			_button("save_title","Сохранить и перейти")
			_button("title","Перейти без записи")
	feedback=Label.new()
	feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_color_override("font_color",UIStyle.MUTED)
	feedback.hide()
	box.add_child(feedback)
	panel.reset_size()
	_layout.call_deferred()
	if not buttons.is_empty():
		buttons.values()[0].grab_focus()
func _button(id: String, title: String) -> void:
	var button:=Button.new()
	button.text=title
	button.custom_minimum_size=Vector2(0,38)
	button.pressed.connect(func():action_requested.emit(id))
	box.add_child(button)
	buttons[id]=button
func notice(text: String) -> void:
	feedback.text=text
	feedback.show()
	_layout.call_deferred()
func back() -> void:
	if page=="controls":
		show_page("settings")
	elif page=="settings":
		show_page(settings_origin)
	elif page=="confirm":
		show_page("pause")
	else:
		action_requested.emit("resume")
static func binding_text(action: String) -> String:
	var names: Array[String]=[]
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
			var key_name:=OS.get_keycode_string(key)
			if key_name not in names:
				names.append(key_name)
		elif event is InputEventMouseButton:
			names.append("ЛКМ" if event.button_index==MOUSE_BUTTON_LEFT else "ПКМ" if event.button_index==MOUSE_BUTTON_RIGHT else event.as_text())
	return " / ".join(names)
