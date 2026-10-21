extends CanvasLayer
const UIStyle=preload("res://scripts/ui/dark_theme.gd")
signal take_requested(loot_owner: String, item: String, amount: int)
signal close_requested
var window: PanelContainer
var rows: VBoxContainer
var heading: Label
var loot_owner := ""
var state: RefCounted
var all_button: Button
func _ready() -> void:
	layer = 4
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	window = PanelContainer.new()
	root.add_child(window)
	window.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	window.offset_left=-310
	window.offset_right=310
	window.offset_top=-190
	window.offset_bottom=190
	var style := UIStyle.style()
	style.bg_color=UIStyle.BACKGROUND
	style.border_color=UIStyle.BORDER
	style.set_border_width_all(1)
	style.set_content_margin_all(16)
	window.add_theme_stylebox_override("panel",style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",12)
	window.add_child(box)
	heading=Label.new()
	heading.add_theme_font_size_override("font_size",22)
	heading.add_theme_color_override("font_color",UIStyle.GOLD)
	box.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size=Vector2(580,210)
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	rows=VBoxContainer.new()
	rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var all:=Button.new()
	all_button=all
	all.text="Забрать всё"
	all.focus_mode=Control.FOCUS_NONE
	all.pressed.connect(func():
		for id in state.economy.ledger.owners[loot_owner].items.keys():
			take_requested.emit(loot_owner,id,state.economy.ledger.count(loot_owner,id)))
	box.add_child(all)
	var close_button:=Button.new()
	close_button.text="Закрыть · E / Esc"
	close_button.focus_mode=Control.FOCUS_NONE
	close_button.pressed.connect(func():close_requested.emit())
	box.add_child(close_button)
	window.hide()
func open(value: RefCounted, source: String) -> void:
	state=value
	loot_owner=source
	window.show()
	refresh()
func refresh() -> void:
	if state==null or not window.visible:
		return
	all_button.disabled=state.life.clock.paused
	heading.text=state.adventure.owner_record(loot_owner).get("name","Находки")
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	var items: Dictionary=state.economy.ledger.owners[loot_owner].items
	if items.is_empty():
		var label:=Label.new()
		label.text="Пусто"
		rows.add_child(label)
	for id in items:
		var row:=HBoxContainer.new()
		rows.add_child(row)
		var label:=Label.new()
		label.text="%s × %d" % [state.catalog.item_name(id),int(items[id])]
		label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var button:=Button.new()
		button.text="Взять 1"
		button.disabled=state.life.clock.paused
		button.focus_mode=Control.FOCUS_NONE
		button.pressed.connect(func():take_requested.emit(loot_owner,id,1))
		row.add_child(button)
func close() -> void:
	window.hide()
	loot_owner=""

