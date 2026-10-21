extends Node2D
const Data = preload("res://scripts/data/arena_location.gd")
const TILESET = preload("res://asset/tilesets/Dungeon_A5.png")
func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for rect in Data.solid_rects():
		var body := StaticBody2D.new()
		body.position = rect.get_center()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var collider := CollisionShape2D.new()
		collider.shape = shape
		body.add_child(collider)
		add_child(body)
	var label := Label.new()
	label.hide()
	label.position = Vector2(84, 840)
	label.text = "В город · E"
	label.add_theme_font_size_override("font_size", 16)
	add_child(label)
func _draw() -> void:
	for y in range(0, 960, 48):
		for x in range(0, 1440, 48):
			draw_texture_rect_region(TILESET, Rect2(x, y, 48, 48), Rect2(0, 144, 48, 48), Color("8e968c"))
	for rect in Data.solid_rects():
		draw_rect(rect, Color("364743"))
		draw_rect(rect, Color("9a9271"), false, 3)
	draw_circle(Data.EXIT, 28, Color("648b7b"))
	draw_arc(Data.EXIT, 28, 0, TAU, 32, Color("e5c58a"), 3)
