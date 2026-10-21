extends PanelContainer
const UIStyle=preload("res://scripts/ui/dark_theme.gd")
## RPG-окно: только представление существующих Inventory/RPGState/PropertyLedger.
signal equip_requested(item_id: String, slot: String)
signal unequip_requested(slot: String)
signal use_requested(item_id: String)
signal bind_requested(index: int, item_id: String)
signal equipment_move_requested(from: String, to: String)
signal quick_move_requested(from: int, to: int)
signal kit_requested
signal drop_requested(item_id: String)
signal close_requested
const Icons = preload("res://scripts/ui/item_icons.gd")
const Slot = preload("res://scripts/ui/inventory_slot.gd")
const Bag = preload("res://scripts/ui/inventory_bag.gd")
const CATEGORIES := ["all", "weapon", "armor", "consumable", "material", "other"]
const CATEGORY_NAMES := ["Всё", "Оружие", "Броня", "Расходники", "Материалы", "Прочее"]
const STAT_NAMES := {"attack": "Атака", "defense": "Защита", "max_hp": "Макс. здоровье", "max_stamina": "Макс. выносливость", "move_speed": "Скорость хода", "attack_speed": "Скорость атаки", "attack_recovery": "Восстановление", "block_reduction": "Защита блока"}
var state: RefCounted
var selected_item := ""
var selected_slot := ""
var developer_mode := false
var category := "all"
var filter_text := ""
var sort_mode := 0
var snapshot := ""
var timer := 0.0
var heading: Label
var character_name: Label
var stats_label: Label
var portrait: TextureRect
var grid: GridContainer
var bag_scroll: ScrollContainer
var equipment_box: Control
var gear_slots: Dictionary = {}
var bag_slots: Dictionary = {}
var quick_slots: Array = []
var details: Label
var actions: VBoxContainer
var search: LineEdit
var category_picker: OptionButton
var sorter: OptionButton
var purse: Label
var bag_count: Label
var detail_title: Label
var detail_category: Label
var detail_icon: TextureRect
var properties: Label
var comparison: RichTextLabel
var requirements: Label
var primary: Button
var second_accessory: Button
var quick_assign: Button
var drop_button: Button
var message: Label
var quick_menu: PopupMenu
var context_menu: PopupMenu
var kit_button: Button
var dev_label: Label
var character_panel: PanelContainer
var bag_panel: PanelContainer
var detail_panel: PanelContainer
var footer: HBoxContainer
var empty_label: Label
var close_button: Button
var context_quick_target := -1
var card_tabs: HBoxContainer
var property_group: VBoxContainer
var description_tab := false
var property_tab_button: Button
var description_tab_button: Button

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _style(UIStyle.BACKGROUND, UIStyle.BORDER, 16))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	heading = _label("СНАРЯЖЕНИЕ", 22, UIStyle.GOLD)
	header.add_child(heading)
	var subtitle := _label("  /  персонаж и имущество", 14, UIStyle.MUTED)
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(subtitle)
	close_button = _button(header, "Закрыть  ×", func(): close_requested.emit())
	close_button.tooltip_text = "Закрыть инвентарь · I / Esc / E"
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	character_panel = _panel(body, 12)
	character_panel.custom_minimum_size.x = 228
	var character := VBoxContainer.new()
	character.add_theme_constant_override("separation", 8)
	character_panel.add_child(character)
	character_name = _label("", 17, UIStyle.GOLD)
	character_name.clip_text = true
	character_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	character_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	character.add_child(character_name)
	equipment_box = Control.new()
	equipment_box.custom_minimum_size = Vector2(204, 252)
	character.add_child(equipment_box)
	portrait = TextureRect.new()
	portrait.position = Vector2(54, 54)
	portrait.size = Vector2(96, 96)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	equipment_box.add_child(portrait)
	var positions := {"head": Vector2(76,0), "main_hand": Vector2(2,67), "off_hand": Vector2(150,67), "body": Vector2(76,144), "feet": Vector2(76,200), "accessory_1": Vector2(2,177), "accessory_2": Vector2(150,177)}
	var captions := {"head": "Голова", "main_hand": "Рука I", "off_hand": "Рука II", "body": "Тело", "feet": "Обувь", "accessory_1": "Акс. I", "accessory_2": "Акс. II"}
	for slot in positions:
		var button := Slot.new()
		button.target_slot = slot
		button.source_slot = slot
		button.empty_icon = Icons.EMPTY[slot]
		button.caption = captions[slot]
		button.validator = can_drop
		button.custom_minimum_size = Vector2(52, 52)
		button.position = positions[slot]
		button.size = Vector2(52, 52)
		_connect_slot(button)
		equipment_box.add_child(button)
		gear_slots[slot] = button
	stats_label = _label("", 15, UIStyle.TEXT)
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	character.add_child(stats_label)
	bag_panel = _panel(body, 12)
	bag_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_panel.custom_minimum_size.x = 330
	var bag := VBoxContainer.new()
	bag.add_theme_constant_override("separation", 8)
	bag_panel.add_child(bag)
	var bag_header := HBoxContainer.new()
	bag.add_child(bag_header)
	bag_header.add_child(_label("СУМКА", 16, UIStyle.GOLD))
	bag_count = _label("", 13, UIStyle.MUTED)
	bag_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_header.add_child(bag_count)
	purse = _label("", 15, UIStyle.GOLD)
	bag_header.add_child(purse)
	var tools := HBoxContainer.new()
	bag.add_child(tools)
	search = LineEdit.new()
	search.placeholder_text = "Поиск предмета…"
	search.custom_minimum_size.x = 120
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.add_theme_font_size_override("font_size", 14)
	search.text_changed.connect(func(value: String): filter_text = value; rebuild_bag())
	tools.add_child(search)
	sorter = OptionButton.new()
	for text in ["Имя ↑", "Имя ↓", "Количество", "Категория"]:
		sorter.add_item(text)
	sorter.add_theme_font_size_override("font_size", 13)
	sorter.item_selected.connect(func(index: int): sort_mode = index; rebuild_bag())
	tools.add_child(sorter)
	category_picker = OptionButton.new()
	for category_name in CATEGORY_NAMES:
		category_picker.add_item(category_name)
	category_picker.add_theme_font_size_override("font_size", 14)
	category_picker.item_selected.connect(func(index: int): category = CATEGORIES[index]; rebuild_bag())
	bag.add_child(category_picker)
	bag_scroll = Bag.new()
	bag_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bag_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bag_scroll.follow_focus = true
	bag_scroll.item_returned.connect(func(data: Dictionary): unequip_requested.emit(data.source_slot))
	bag_scroll.resized.connect(_layout_grid)
	bag.add_child(bag_scroll)
	grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 7)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bag_scroll.add_child(grid)
	detail_panel = _panel(body, 12)
	detail_panel.custom_minimum_size.x = 288
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 8)
	detail_panel.add_child(card)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(detail_scroll)
	var detail_box := VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 8)
	detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(detail_box)
	detail_title = _label("Выберите предмет", 20, UIStyle.GOLD)
	detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(detail_title)
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 12)
	detail_box.add_child(identity)
	detail_icon = TextureRect.new()
	detail_icon.custom_minimum_size = Vector2(64,64)
	detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	identity.add_child(detail_icon)
	detail_category = _label("", 13, UIStyle.MUTED)
	detail_category.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_category.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(detail_category)
	card_tabs = HBoxContainer.new()
	detail_box.add_child(card_tabs)
	property_tab_button = _button(card_tabs, "Свойства", func(): description_tab = false; _card_page())
	description_tab_button = _button(card_tabs, "Описание", func(): description_tab = true; _card_page())
	for tab_button in [property_tab_button, description_tab_button]:
		tab_button.toggle_mode = true
		tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	property_group = VBoxContainer.new()
	property_group.add_theme_constant_override("separation", 6)
	detail_box.add_child(property_group)
	properties = _label("", 16, UIStyle.TEXT)
	properties.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	property_group.add_child(properties)
	comparison = RichTextLabel.new()
	comparison.bbcode_enabled = true
	comparison.fit_content = true
	comparison.scroll_active = false
	comparison.add_theme_font_size_override("normal_font_size", 14)
	comparison.mouse_filter = Control.MOUSE_FILTER_IGNORE
	property_group.add_child(comparison)
	details = _label("", 14, UIStyle.MUTED)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(details)
	requirements = _label("", 13, UIStyle.MUTED)
	requirements.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	property_group.add_child(requirements)
	actions = VBoxContainer.new()
	actions.add_theme_constant_override("separation", 5)
	card.add_child(actions)
	primary = _button(actions, "", _primary_action)
	second_accessory = _button(actions, "Аксессуар II", func(): equip_requested.emit(selected_item, "accessory_2"))
	quick_assign = _button(actions, "В быстрый слот…", _show_quick_menu)
	drop_button = _button(actions, "Выбросить 1", func(): drop_requested.emit(selected_item))
	message = _label("", 13, UIStyle.TEXT)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.y = 18
	card.add_child(message)
	footer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	box.add_child(footer)
	footer.add_child(_label("БЫСТРЫЕ\nСЛОТЫ", 12, UIStyle.MUTED))
	for index in range(4):
		var slot := Slot.new()
		slot.quick_index = index
		slot.select_on_focus = false
		slot.target_slot = "quick:" + str(index)
		slot.caption = str(index + 1)
		slot.validator = can_drop
		slot.custom_minimum_size = Vector2(46,46)
		slot.chosen.connect(func(_id: String, _source: String): _bind(index))
		slot.activated.connect(func(_id: String, _source: String): _bind(index))
		slot.dropped.connect(_drop)
		slot.context_requested.connect(func(_id: String, _source: String, point: Vector2): _quick_context(index, point))
		footer.add_child(slot)
		quick_slots.append(slot)
	var keyboard := _label("Стрелки · выбор   Enter · действие\nПКМ · меню   1–4 · назначить   Esc · закрыть", 12, UIStyle.MUTED)
	keyboard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keyboard.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	keyboard.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_child(keyboard)
	dev_label = _label("РЕЖИМ\nРАЗРАБОТЧИКА", 11, UIStyle.MUTED)
	footer.add_child(dev_label)
	kit_button = _button(footer, "Тестовый набор", func(): kit_requested.emit())
	kit_button.tooltip_text = "Однократная выдача меча, щита и лечения ×3"
	quick_menu = PopupMenu.new()
	add_child(quick_menu)
	quick_menu.id_pressed.connect(_bind)
	context_menu = PopupMenu.new()
	add_child(context_menu)
	context_menu.id_pressed.connect(_context_action)
	for popup in [quick_menu, context_menu, category_picker.get_popup(), sorter.get_popup()]:
		popup.add_theme_stylebox_override("panel", _style(UIStyle.BACKGROUND, UIStyle.BORDER, 8))
		popup.add_theme_font_size_override("font_size", 14)
		popup.add_theme_color_override("font_color", UIStyle.TEXT)
		popup.add_theme_color_override("font_hover_color", UIStyle.TEXT)
		popup.add_theme_stylebox_override("hover", _style(UIStyle.HOVER, UIStyle.GOLD, 4))
	developer_mode = "--developer" in OS.get_cmdline_user_args()
	get_viewport().size_changed.connect(_layout)
	_layout()
	hide()

func _connect_slot(button: Button) -> void:
	button.chosen.connect(select_item)
	button.activated.connect(_activate)
	button.context_requested.connect(_context)
	button.dropped.connect(_drop)

func _layout() -> void:
	var viewport := get_viewport_rect().size
	var width := minf(1280, viewport.x - 64)
	var height := minf(660, viewport.y - 210)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -width / 2
	offset_right = width / 2
	offset_top = -height / 2 - 20
	offset_bottom = height / 2 - 20
	_layout_grid.call_deferred()
	if card_tabs != null:
		_card_page()

func _layout_grid() -> void:
	if grid == null:
		return
	grid.columns = maxi(1, floori((bag_scroll.size.x - 14 + 7) / 67.0))

func refresh(value: RefCounted) -> void:
	state = value
	character_name.text = state.character_name
	character_name.tooltip_text = state.character_name
	portrait.texture = Icons.portrait(state.character_index)
	var derived: Dictionary = state.rpg.stats(state.catalog)
	stats_label.text = "Здоровье  %.0f / %.0f\nВыносливость  %.0f / %.0f\nАтака  %.0f     ·     Защита  %.0f" % [state.rpg.fighter.hp, derived.max_hp, state.rpg.fighter.stamina, derived.max_stamina, derived.attack, derived.defense]
	purse.text = "●  %d" % state.money
	bag_count.text = "  · %d ст." % state.inventory.items.size()
	for slot in gear_slots:
		var button: Button = gear_slots[slot]
		button.item_id = state.rpg.equipment[slot]
		button.amount = 1 if not button.item_id.is_empty() else 0
		button.tooltip_text = state.rpg.SLOTS[slot] + "\n" + ("Пустой слот" if button.item_id.is_empty() else state.catalog.item_name(button.item_id) + "\nДвойной щелчок / Enter — снять")
		button.selected = selected_slot == slot
		button.refresh()
	for index in range(4):
		var button: Button = quick_slots[index]
		button.item_id = state.rpg.quick[index]
		button.amount = state.inventory.count(button.item_id)
		button.tooltip_text = "%d · %s\nПеренесите сюда предмет или другой быстрый слот" % [index + 1, _name(button.item_id)]
		button.refresh()
	dev_label.visible = developer_mode
	kit_button.visible = developer_mode and not state.rpg.kit_claimed
	kit_button.disabled = state.life.clock.paused or state.rpg.fighter.hp <= 0
	var current := JSON.stringify(state.inventory.items)
	if current != snapshot:
		snapshot = current
		rebuild_bag()
	if not selected_item.is_empty():
		if not selected_slot.is_empty() and state.rpg.equipment.get(selected_slot) != selected_item:
			selected_slot = ""
		if selected_slot.is_empty() and state.inventory.count(selected_item) == 0:
			for slot in state.rpg.equipment:
				if state.rpg.equipment[slot] == selected_item:
					selected_slot = slot
					break
			if selected_slot.is_empty():
				selected_item = ""
	_refresh_card()

func rebuild_bag() -> void:
	if state == null or grid == null:
		return
	var focused_id := ""
	for id in bag_slots:
		if bag_slots[id].has_focus():
			focused_id = id
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	bag_slots.clear()
	var ids := filtered_ids()
	if ids.is_empty():
		empty_label = null
		if not state.inventory.items.is_empty():
			empty_label = _label("Ничего не найдено\n\nИзмените поиск или категорию.", 15, UIStyle.MUTED)
			empty_label.custom_minimum_size = Vector2(270,180)
			empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			grid.add_child(empty_label)
	else:
		empty_label = null
		for id in ids:
			var button := Slot.new()
			button.item_id = id
			button.amount = state.inventory.count(id)
			button.selected = id == selected_item and selected_slot.is_empty()
			button.tooltip_text = "%s × %d\n%s\nДвойной щелчок / Enter — действие · ПКМ — меню" % [state.catalog.item_name(id), button.amount, Icons.category_name(state.catalog.items[id])]
			_connect_slot(button)
			grid.add_child(button)
			bag_slots[id] = button
		if bag_slots.has(focused_id):
			focus_item.call_deferred(focused_id)
	_layout_grid.call_deferred()

func focus_item(id: String) -> void:
	if visible and bag_slots.has(id) and bag_slots[id].is_inside_tree():
		bag_slots[id].grab_focus()

func filtered_ids() -> Array:
	var ids: Array = []
	for id in state.inventory.items:
		var item: Dictionary = state.catalog.items[id]
		if category != "all" and Icons.category(item) != category:
			continue
		if not filter_text.strip_edges().is_empty() and not (str(item.name) + " " + str(item.description)).to_lower().contains(filter_text.strip_edges().to_lower()):
			continue
		ids.append(id)
	ids.sort_custom(func(a: String, b: String):
		if sort_mode == 2 and state.inventory.count(a) != state.inventory.count(b):
			return state.inventory.count(a) > state.inventory.count(b)
		if sort_mode == 3 and Icons.category(state.catalog.items[a]) != Icons.category(state.catalog.items[b]):
			return Icons.category(state.catalog.items[a]) < Icons.category(state.catalog.items[b])
		var order: int = state.catalog.item_name(a).naturalnocasecmp_to(state.catalog.item_name(b))
		return order > 0 if sort_mode == 1 else order < 0)
	return ids

func select_item(id: String, slot: String = "") -> void:
	if id != selected_item:
		description_tab = false
	selected_item = id
	selected_slot = slot
	message.text = ""
	for key in bag_slots:
		bag_slots[key].selected = key == id and slot.is_empty()
		bag_slots[key].refresh()
	for key in gear_slots:
		gear_slots[key].selected = key == slot
		gear_slots[key].refresh()
	_refresh_card()

func _refresh_card() -> void:
	if state == null:
		return
	var exists: bool = state.catalog.items.has(selected_item)
	_card_page()
	detail_icon.texture = Icons.texture(selected_item)
	detail_icon.modulate = Color.WHITE if exists else Color(1,1,1,0.25)
	primary.visible = exists
	quick_assign.visible = exists
	drop_button.visible = exists
	second_accessory.hide()
	properties.text = ""
	comparison.text = ""
	requirements.text = ""
	properties.hide()
	comparison.hide()
	requirements.hide()
	if not exists:
		detail_title.text = "Ваши вещи"
		detail_category.text = "Снаряжение\nи припасы"
		details.text = "Выберите предмет в сумке или слот персонажа.\n\nПеретаскивайте вещи в подходящие слоты. Золотистая рамка подскажет, куда их можно надеть."
		return
	var item: Dictionary = state.catalog.items[selected_item]
	detail_title.text = state.catalog.item_name(selected_item).replace(" (тест)", "")
	detail_category.text = Icons.category_name(item) + "\n" + ("В сумке · ×%d" % state.inventory.count(selected_item) if selected_slot.is_empty() else "Надето · " + state.rpg.SLOTS[selected_slot])
	details.text = item.description
	for key in item.get("modifiers", {}):
		var value: float = item.modifiers[key]
		properties.text += "%s  %+.0f%s\n" % [STAT_NAMES.get(key, key), value * 100.0 if key == "block_reduction" else value, "%" if key == "block_reduction" else ""]
	if item.has("heal"):
		properties.text = "Восстанавливает %.0f HP\nПерерыв 3 секунды" % item.heal
	properties.text = properties.text.trim_suffix("\n")
	properties.visible = not properties.text.is_empty()
	requirements.text = "Требований нет" if not item.has("requirements") else "Требования: " + str(item.requirements)
	requirements.visible = item.has("requirements")
	primary.text = "Снять" if not selected_slot.is_empty() else ("Использовать" if item.has("heal") else "Экипировать")
	var applicable: bool = not selected_slot.is_empty() or item.has("slot") or item.has("heal")
	primary.visible = applicable
	primary.disabled = not _blocked_reason().is_empty()
	primary.tooltip_text = _blocked_reason()
	if item.get("slot") == "accessory_1" and selected_slot.is_empty():
		primary.text = "Надеть · аксессуар I"
		second_accessory.show()
		second_accessory.disabled = primary.disabled
	quick_assign.disabled = not _owned(selected_item)
	drop_button.disabled = not selected_slot.is_empty() or state.life.clock.paused or state.rpg.fighter.hp <= 0 or state.inventory.count(selected_item)==0
	drop_button.tooltip_text = "Сначала снимите вещь в сумку" if not selected_slot.is_empty() else ("Продолжите время" if state.life.clock.paused else "Положить одну вещь на землю в текущей точке")
	if item.has("slot") and selected_slot.is_empty():
		comparison.text = comparison_text(selected_item, item.slot)
		comparison.show()

func _card_page() -> void:
	var compact := get_viewport_rect().size.y < 850
	var exists: bool = state != null and state.catalog.items.has(selected_item)
	card_tabs.visible = compact and exists
	detail_icon.custom_minimum_size = Vector2(40, 40) if compact else Vector2(64,64)
	property_group.visible = exists and (not compact or not description_tab)
	details.visible = not exists or not compact or description_tab
	property_tab_button.set_pressed_no_signal(not description_tab)
	description_tab_button.set_pressed_no_signal(description_tab)

func comparison_text(id: String, slot: String) -> String:
	var item: Dictionary = state.catalog.items[id]
	var old_id: String = state.rpg.equipment[slot]
	var old: Dictionary = state.catalog.items.get(old_id, {})
	var text := "[color=#9aaf99]Вместо: %s[/color]" % ("пустого слота" if old_id.is_empty() else state.catalog.item_name(old_id).replace(" (тест)", ""))
	comparison.tooltip_text = "Сравнение с: " + ("пустым слотом" if old_id.is_empty() else state.catalog.item_name(old_id))
	var compact: bool = get_viewport_rect().size.y < 850
	var changes: Array[String] = []
	var keys: Array = item.get("modifiers", {}).keys()
	for key in old.get("modifiers", {}):
		if key not in keys:
			keys.append(key)
	for key in keys:
		var difference := float(item.get("modifiers", {}).get(key, 0)) - float(old.get("modifiers", {}).get(key, 0))
		if is_zero_approx(difference):
			continue
		var good: bool = difference < 0 if key == "attack_recovery" else difference > 0
		text += "\n[color=%s]%s %+.0f%s[/color]" % ["#9bc48c" if good else "#e79780", STAT_NAMES.get(key, key), difference * 100 if key == "block_reduction" else difference, "%" if key == "block_reduction" else ""]
		var short_names := {"attack": "атака", "defense": "защита", "move_speed": "ход", "max_stamina": "выносл.", "block_reduction": "блок"}
		changes.append("[color=%s]%+.0f%s %s[/color]" % ["#9bc48c" if good else "#e79780", difference * 100 if key == "block_reduction" else difference, "%" if key == "block_reduction" else "", short_names.get(key, STAT_NAMES.get(key, key))])
	return "При замене: " + ", ".join(changes) if compact and not changes.is_empty() else text

func _blocked_reason() -> String:
	if state.life.clock.paused:
		return "Игра на паузе. Продолжите время, чтобы выполнить действие."
	var fighter: Dictionary = state.rpg.fighter
	if fighter.hp <= 0:
		return "После поражения сначала выберите продолжение."
	if not selected_slot.is_empty() or state.catalog.items.get(selected_item, {}).has("slot"):
		if fighter.attack_elapsed >= 0 or fighter.dodge_left > 0:
			return "Дождитесь завершения атаки или уклонения."
	if state.catalog.items.get(selected_item, {}).has("heal"):
		if fighter.hp >= state.rpg.stats(state.catalog).max_hp:
			return "Здоровье уже полностью восстановлено."
		if fighter.heal_cooldown > 0:
			return "Лечение восстанавливается: %.1f с" % fighter.heal_cooldown
	if not _owned(selected_item):
		return "Предмет больше не принадлежит персонажу."
	return ""

func _owned(id: String) -> bool:
	return state != null and state.economy.ledger.count("player", id) + state.economy.ledger.count("equipment", id) > 0

func _primary_action() -> void:
	var reason := _blocked_reason()
	if not reason.is_empty():
		feedback(reason)
		return
	if not selected_slot.is_empty():
		unequip_requested.emit(selected_slot)
	elif state.catalog.items.get(selected_item, {}).has("heal"):
		use_requested.emit(selected_item)
	elif state.catalog.items.get(selected_item, {}).has("slot"):
		equip_requested.emit(selected_item, "")
	else:
		feedback("Этот предмет используется в ремесле или торговле.")

func _activate(id: String, slot: String) -> void:
	select_item(id, slot)
	if not id.is_empty():
		_primary_action()

func _bind(index: int) -> void:
	if selected_item.is_empty():
		feedback("Сначала выберите предмет.")
		return
	bind_requested.emit(index, selected_item)

func _show_quick_menu() -> void:
	quick_menu.clear()
	for index in range(4):
		quick_menu.add_item("%d · %s" % [index + 1, _name(state.rpg.quick[index])], index)
	quick_menu.position = Vector2i(quick_assign.global_position + Vector2(0, quick_assign.size.y))
	quick_menu.popup()

func _context(id: String, slot: String, point: Vector2) -> void:
	context_quick_target = -1
	select_item(id, slot)
	if id.is_empty():
		return
	context_menu.clear()
	if not selected_slot.is_empty() or state.catalog.items[id].has("slot") or state.catalog.items[id].has("heal"):
		context_menu.add_item(primary.text, 0)
		context_menu.set_item_disabled(0, primary.disabled)
		context_menu.set_item_tooltip(0, primary.tooltip_text)
	context_menu.add_separator()
	for index in range(4):
		context_menu.add_item("В быстрый слот %d" % (index + 1), 10 + index)
	context_menu.add_separator()
	context_menu.add_item("Выбросить 1", 99)
	context_menu.set_item_disabled(context_menu.item_count - 1, drop_button.disabled)
	context_menu.position = Vector2i(point)
	context_menu.popup()

func _context_action(id: int) -> void:
	if id >= 100 and id <= 103 and context_quick_target >= 0:
		bind_requested.emit(context_quick_target, ["attack", "block", "dodge", ""][id - 100])
	elif id == 0:
		_primary_action()
	elif id >= 10 and id < 14:
		_bind(id - 10)
	elif id == 99 and not drop_button.disabled:
		drop_requested.emit(selected_item)

func _quick_context(index: int, point: Vector2) -> void:
	context_quick_target = index
	context_menu.clear()
	for option in [["Атака", 100], ["Блок", 101], ["Уклонение", 102], ["Очистить слот", 103]]:
		context_menu.add_item(option[0], option[1])
	context_menu.position = Vector2i(point)
	context_menu.popup()

func can_drop(target: String, data: Dictionary) -> bool:
	if state == null or not data.get("item_id") is String:
		return false
	var id: String = data.item_id
	if target.begins_with("quick:"):
		return id in ["attack", "block", "dodge"] or _owned(id)
	if not state.catalog.items.has(id) or not _owned(id) or data.get("quick_index", -1) >= 0:
		return false
	var natural: String = state.catalog.items[id].get("slot", "")
	return data.get("source_slot", "") != target and (target == natural or (target == "accessory_2" and natural == "accessory_1"))

func _drop(target: String, data: Dictionary) -> void:
	if not can_drop(target, data):
		feedback("Предмет не подходит для этого слота.")
		return
	if target.begins_with("quick:"):
		var index := int(target.trim_prefix("quick:"))
		if data.get("quick_index", -1) >= 0:
			quick_move_requested.emit(int(data.quick_index), index)
		else:
			bind_requested.emit(index, data.item_id)
	elif data.get("source_slot", "") != "":
		equipment_move_requested.emit(data.source_slot, target)
	else:
		equip_requested.emit(data.item_id, target)

func feedback(text: String) -> void:
	message.text = text

func _name(id: String) -> String:
	return {"attack": "Атака", "block": "Блок", "dodge": "Уклонение", "": "Пусто"}.get(id, state.catalog.item_name(id))

func _process(delta: float) -> void:
	if not visible or state == null:
		return
	timer += delta
	if timer >= 0.2:
		timer = 0
		refresh(state)
	var dragging: bool = get_viewport().gui_is_dragging()
	var data: Variant = get_viewport().gui_get_drag_data() if dragging else ({"item_id": selected_item, "source_slot": selected_slot} if selected_slot.is_empty() and not selected_item.is_empty() else {})
	for slot in gear_slots:
		var suitable: bool = data is Dictionary and not data.is_empty() and can_drop(slot, data)
		if gear_slots[slot].suitable != suitable:
			gear_slots[slot].suitable = suitable
			gear_slots[slot].refresh()

func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_D and event.ctrl_pressed and event.alt_pressed:
		developer_mode = not developer_mode
		refresh(state)
		get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.is_pressed() or event.is_echo() or get_viewport().gui_get_focus_owner() is LineEdit:
		return
	for index in range(4):
		if event.is_action_pressed("quick_%d" % (index + 1)):
			_bind(index)
			get_viewport().set_input_as_handled()
			return

func _panel(parent: Control, margin: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(UIStyle.PANEL, UIStyle.BORDER, margin))
	parent.add_child(panel)
	return panel
func _style(color: Color, border: Color, margin: int) -> StyleBoxFlat:
	var style := UIStyle.style()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(margin)
	return style
func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
func _button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", UIStyle.TEXT)
	for state_name in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state_name, _style(UIStyle.PANEL if state_name != "hover" else UIStyle.HOVER, UIStyle.GOLD if state_name == "focus" else UIStyle.BORDER, 6))
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

