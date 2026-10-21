extends ScrollContainer
const UIStyle=preload("res://scripts/ui/dark_theme.gd")
signal item_returned(data: Dictionary)
func _ready() -> void:
	resized.connect(queue_redraw)
	get_v_scroll_bar().value_changed.connect(func(_value: float): queue_redraw())
func _draw() -> void:
	var columns := maxi(1, floori((size.x - 14 + 7) / 67.0))
	var rows := maxi(1, ceili((size.y + 7) / 67.0)) + 1
	for y in range(rows):
		for x in range(columns):
			var cell := Rect2(x * 67, y * 67 - scroll_vertical % 67, 60, 60)
			draw_rect(cell, UIStyle.BACKGROUND)
			draw_rect(cell.grow(-0.5), UIStyle.BORDER, false, 1)
func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("source_slot", "") != ""
func _drop_data(_position: Vector2, data: Variant) -> void:
	item_returned.emit(data)
