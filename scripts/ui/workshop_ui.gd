extends CanvasLayer
const UIStyle=preload("res://scripts/ui/dark_theme.gd")
## Окно мастерской не изменяет имущество: только запросы в WorldState.

signal craft_requested(recipe_id: String)
signal transfer_requested(item_id: String, to_workshop: bool)
signal close_requested

var window: PanelContainer
var tabs: TabContainer
var stock_rows: VBoxContainer
var recipe_rows: VBoxContainer
var report: Label
var player_job: Label
var stock_controls: Dictionary = {}
var recipe_controls: Dictionary = {}
var built := false

func _ready() -> void:
	layer = 2
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	window = PanelContainer.new()
	root.add_child(window)
	window.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	window.offset_left = -400
	window.offset_right = 400
	window.offset_top = -200
	window.offset_bottom = 220
	var style := UIStyle.style()
	style.bg_color = UIStyle.BACKGROUND
	style.border_color = UIStyle.BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(18)
	window.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	window.add_child(box)
	box.add_child(_label("Мастерская · тестовый общий склад", 23))
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size = Vector2(760, 260)
	box.add_child(tabs)
	stock_rows = _tab("Склад")
	stock_rows.add_child(_label("Материалы общие: передачи уменьшают запас отправителя.", 16))
	recipe_rows = _tab("Ремесло")
	player_job = _label("", 16)
	player_job.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	recipe_rows.add_child(player_job)
	var debug_box := _tab("Производство")
	report = _label("", 16)
	report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	debug_box.add_child(report)
	_button(box, "Закрыть · E / Esc / I", func(): close_requested.emit())
	window.hide()

func _tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	scroll.add_child(box)
	return box

func open(state: RefCounted) -> void:
	if not built:
		_build(state)
	window.show()
	refresh(state)

func close() -> void:
	window.hide()

func _build(state: RefCounted) -> void:
	for id in state.catalog.items:
		if state.catalog.items[id]["category"] == "product":
			continue
		var row := HBoxContainer.new()
		stock_rows.add_child(row)
		var label := _label("", 16)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 360
		row.add_child(label)
		var take := _button(row, "Взять 1", func(): transfer_requested.emit(id, false))
		var give := _button(row, "Положить всё", func(): transfer_requested.emit(id, true))
		stock_controls[id] = [label, take, give]
	for recipe_id in state.catalog.recipes:
		var recipe: Dictionary = state.catalog.recipes[recipe_id]
		var row := VBoxContainer.new()
		recipe_rows.add_child(row)
		var description := _label("%s · %d мин. · %s" % [recipe["name"], recipe["minutes"], _items(recipe["inputs"], state.catalog)], 16)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(description)
		var button := _button(row, "Начать из своих материалов", func(): craft_requested.emit(recipe_id))
		recipe_controls[recipe_id] = button
	built = true

func refresh(state: RefCounted) -> void:
	if not window.visible or not built:
		return
	var production = state.economy
	var ledger = production.ledger
	for id in stock_controls:
		var controls: Array = stock_controls[id]
		controls[0].text = "%s\nСклад: %d · у вас: %d" % [state.catalog.item_name(id), ledger.count("workshop", id), state.inventory.count(id)]
		controls[1].disabled = state.life.clock.paused or ledger.count("workshop", id) == 0
		controls[2].disabled = state.life.clock.paused or state.inventory.count(id) == 0
	for id in recipe_controls:
		recipe_controls[id].disabled = state.life.clock.paused or not production.jobs["player"].is_empty() or not ledger.has_inputs("player", state.catalog.recipes[id]["inputs"])
	player_job.text = "Ваш заказ: %s\n%s\nРабота идёт, пока вы у верстака." % [_job(production.jobs["player"], state.catalog), "Игра на паузе" if state.life.clock.paused else production.status["player"]]
	report.text = ("Шахтёр: %s\nДобыто всего: %s\nУ шахтёра: %s\n\nКузнец: %s\nТекущий заказ: %s\nСклад: %s\nМатериалы в заказе: %s\n\nГотово в мастерской: %s\nИзготовлено всего: %s\n\nТорговец: %s\nВ приёмке: %s\nВ магазине: %s"
		% [production.status["miner"], _items(production.mined, state.catalog), _items(ledger.owners["npc:test_miner"].items, state.catalog),
		production.status["smith"], _job(production.jobs["smith"], state.catalog), _items(ledger.owners["workshop"].items, state.catalog), _items(ledger.owners["process:smith"].items, state.catalog),
		_items(ledger.owners["finished"].items, state.catalog), _items(production.produced, state.catalog), production.status["merchant"],
		_items(ledger.owners["npc:test_merchant"].items, state.catalog), _items(ledger.owners["shop:test_merchant"].items, state.catalog)])

func _job(job: Dictionary, catalog: RefCounted) -> String:
	if job.is_empty():
		return "нет"
	var recipe: Dictionary = catalog.recipes[job["recipe"]]
	return "%s · %d/%d мин." % [recipe["name"], job["progress"], recipe["minutes"]]

func _items(items: Dictionary, catalog: RefCounted) -> String:
	var parts: PackedStringArray = []
	for id in items:
		if int(items[id]) > 0:
			parts.append("%s × %d" % [catalog.item_name(id), items[id]])
	return ", ".join(parts) if not parts.is_empty() else "пусто"

func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", UIStyle.TEXT)
	return label

func _button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

