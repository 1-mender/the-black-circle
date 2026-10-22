extends CanvasLayer
const UIStyle=preload("res://scripts/ui/dark_theme.gd")
## Торговля и маршрутизация запросов. RPG-инвентарь — отдельное представление тех же данных.
signal sell_requested(item_id: String, amount: int)
signal buy_requested(item_id: String, amount: int)
signal close_requested
signal save_requested
signal load_requested
signal equip_requested(item_id: String, slot: String)
signal unequip_requested(slot: String)
signal use_requested(item_id: String)
signal bind_requested(index: int, item_id: String)
signal equipment_move_requested(from: String, to: String)
signal quick_move_requested(from: int, to: int)
signal kit_requested
signal drop_requested(item_id: String)
const InventoryView = preload("res://scripts/ui/inventory_view.gd")
var inventory_view: PanelContainer
var trade_window: PanelContainer
var trade_rows: VBoxContainer
var window: PanelContainer:
	get: return inventory_view if mode == "inventory" else trade_window
var rows: Container:
	get: return inventory_view.grid if mode == "inventory" else trade_rows
var equipment_box: Control:
	get: return inventory_view.equipment_box
var details: Label:
	get: return inventory_view.details
var actions: Control:
	get: return inventory_view.actions
var kit_button: Button:
	get: return inventory_view.kit_button
var selected_item: String:
	get: return inventory_view.selected_item
	set(value): inventory_view.selected_item = value
var balance: Label
var save_button: Button
var load_button: Button
var route: Label
var notice: Label
var notice_time := 0.0
var title: Label
var summary: Label
var mode := ""
var shop_id := ""
var old_hud: PanelContainer

func _ready() -> void:
	layer = 2
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	old_hud = _panel(root)
	var hud := HBoxContainer.new()
	old_hud.add_child(hud)
	balance = _label("Монеты: 0", 15)
	hud.add_child(balance)
	save_button = _button(hud, "K", func(): save_requested.emit())
	load_button = _button(hud, "L", func(): load_requested.emit())
	route = _label("", 15)
	root.add_child(route)
	route.hide()
	notice = _label("", 15)
	root.add_child(notice)
	notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	notice.offset_left = -180
	notice.offset_right = 180
	notice.offset_top = -116
	notice.offset_bottom = -76
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trade_window = _panel(root)
	trade_window.mouse_filter = Control.MOUSE_FILTER_STOP
	trade_window.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	trade_window.offset_left = -440
	trade_window.offset_right = 440
	trade_window.offset_top = -210
	trade_window.offset_bottom = 220
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	trade_window.add_child(box)
	title = _label("", 23)
	box.add_child(title)
	summary = _label("", 17)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(summary)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(800,140)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	trade_rows = VBoxContainer.new()
	trade_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trade_rows.add_theme_constant_override("separation", 10)
	scroll.add_child(trade_rows)
	_button(box, "Закрыть · E / Esc / I", func(): close_requested.emit())
	trade_window.hide()
	inventory_view = InventoryView.new()
	root.add_child(inventory_view)
	inventory_view.equip_requested.connect(func(id: String, slot: String): equip_requested.emit(id, slot))
	inventory_view.unequip_requested.connect(func(slot: String): unequip_requested.emit(slot))
	inventory_view.use_requested.connect(func(id: String): use_requested.emit(id))
	inventory_view.bind_requested.connect(func(index: int, id: String): bind_requested.emit(index, id))
	inventory_view.equipment_move_requested.connect(func(from: String, to: String): equipment_move_requested.emit(from, to))
	inventory_view.quick_move_requested.connect(func(from: int, to: int): quick_move_requested.emit(from, to))
	inventory_view.kit_requested.connect(func(): kit_requested.emit())
	inventory_view.drop_requested.connect(func(id: String): drop_requested.emit(id))
	inventory_view.close_requested.connect(func(): close_requested.emit())

func _button(parent: Control, caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func attach_to_hud(slot: Control) -> void:
	var coin:=TextureRect.new()
	coin.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	coin.texture=preload("res://asset/ui/coin.svg")
	coin.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.custom_minimum_size=Vector2(24,24)
	coin.tooltip_text="Монеты"
	slot.add_child(coin)
	for control in [balance, save_button, load_button]:
		control.reparent(slot)
		control.add_theme_font_size_override("font_size", 15)
	save_button.tooltip_text="Сохранить · K"
	load_button.tooltip_text="Загрузить · L"
	save_button.hide()
	load_button.hide()
	old_hud.hide()

func _process(delta: float) -> void:
	if notice_time > 0:
		notice_time -= delta
		notice.visible = notice_time > 0

func show_notice(message: String) -> void:
	notice.text = message
	notice_time = 5.0
	notice.show()

func set_location(_location_id: String) -> void:
	pass

func open_inventory(state: RefCounted) -> void:
	mode = "inventory"
	shop_id = ""
	trade_window.hide()
	inventory_view.show()
	refresh(state)
	if not inventory_view.bag_slots.is_empty():
		inventory_view.focus_item.call_deferred(inventory_view.bag_slots.keys()[0])

func open_trade(state: RefCounted, merchant_id: String) -> void:
	mode = "trade"
	shop_id = merchant_id
	inventory_view.hide()
	trade_window.show()
	refresh(state)

func open_market(state: RefCounted, merchant_id: String = "test_merchant") -> void:
	mode = "market"
	shop_id = merchant_id
	inventory_view.hide()
	trade_window.show()
	refresh(state)

func close_window() -> void:
	inventory_view.hide()
	inventory_view.context_menu.hide()
	inventory_view.quick_menu.hide()
	trade_window.hide()
	mode = ""
	shop_id = ""

func refresh(state: RefCounted) -> void:
	balance.text = str(state.money)
	if mode == "inventory":
		inventory_view.refresh(state)
		return
	if not trade_window.visible:
		return
	for child in trade_rows.get_children():
		trade_rows.remove_child(child)
		child.queue_free()
	if mode == "market":
		_refresh_market(state)
		return
	title.text = state.catalog.shops[shop_id]["name"]
	summary.text = "Баланс: %d монет. Кузнец покупает руду. Касса: %d монет." % [state.money, state.economy.ledger.wallets["shop:" + shop_id]]
	var ids: Array = state.catalog.shops[shop_id]["buy_prices"].keys()
	ids.sort()
	for item_id in ids:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		trade_rows.add_child(row)
		var amount: int = state.inventory.count(item_id)
		var label := _label("%s × %d" % [state.catalog.item_name(item_id), amount], 17)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var price: int = state.catalog.buy_price(shop_id, item_id)
		row.add_child(_label("%d мон./шт." % price, 16))
		_add_sell_button(row, "Продать 1", item_id, 1, amount == 0)
		_add_sell_button(row, "Всё (+%d)" % (price * amount), item_id, amount, amount == 0)

func _refresh_card(state: RefCounted) -> void:
	inventory_view.refresh(state)
func _refresh_market(state: RefCounted) -> void:
	title.text = state.catalog.shops[shop_id]["name"]
	summary.text = "Баланс: %d монет. Только имеющиеся товары; цены тестовые." % state.money
	for id in state.catalog.shops[shop_id]["sell_prices"]:
		var row := HBoxContainer.new()
		rows.add_child(row)
		var count: int = state.economy.ledger.count("shop:" + shop_id, id)
		var price: int = state.catalog.sell_price(shop_id, id)
		var label := _label("%s · в наличии %d" % [state.catalog.item_name(id), count], 17)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		row.add_child(_label("%d мон." % price, 16))
		var button := Button.new()
		button.text = "Купить 1"
		button.focus_mode = Control.FOCUS_NONE
		button.disabled = count == 0 or state.money < price or state.life.clock.paused
		button.tooltip_text = "Нет в наличии" if count == 0 else ("Не хватает монет" if state.money < price else ("Игра на паузе" if state.life.clock.paused else "Купить одну штуку"))
		button.pressed.connect(func(): buy_requested.emit(id, 1))
		row.add_child(button)
	rows.add_child(_label("Пустой магазин пополняется изделиями кузнеца в рабочее время.", 16))

func _add_sell_button(row: HBoxContainer, text: String, item_id: String, amount: int, disabled: bool) -> void:
	var button := Button.new()
	button.text = text
	button.disabled = disabled
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func(): sell_requested.emit(item_id, amount))
	row.add_child(button)

func _panel(parent: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := UIStyle.style()
	style.bg_color = UIStyle.BACKGROUND
	style.border_color = UIStyle.BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel

func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", UIStyle.TEXT)
	label.add_theme_color_override("font_shadow_color", UIStyle.BACKGROUND)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


