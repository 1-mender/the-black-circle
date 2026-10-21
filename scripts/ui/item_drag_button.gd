extends Button
var item_id := ""
func _get_drag_data(_position: Vector2) -> Variant:
	var preview := Label.new()
	preview.text = text
	set_drag_preview(preview)
	return {"item_id": item_id}
