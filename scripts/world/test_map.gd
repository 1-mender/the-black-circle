extends Node2D
## Временный ландшафт: рисунок и коллизии построены из одной геометрии.

const Data = preload("res://scripts/data/test_location.gd")

func _ready() -> void:
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

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Data.MAP_SIZE), Color("465b49"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1300
	for i in range(1100):
		var point := Vector2(rng.randf_range(48, 1776), rng.randf_range(192, 1200))
		draw_line(point, point + Vector2(3, -4), Color("53694e"), 1)
	for road in Data.ROADS:
		_draw_paving(road)
	# Гора и условный вход: только техническая декорация, не карта замка.
	draw_rect(Data.MOUNTAIN, Color("56616a"))
	for x in range(48, 1776, 96):
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, 192), Vector2(x + 40, 62), Vector2(x + 96, 192),
		]), Color("68717a"))
	draw_rect(Rect2(816, 48, 240, 144), Color("828680"))
	draw_rect(Rect2(864, 72, 144, 120), Color("283339"))
	for rect in Data.BUILDINGS:
		_draw_building(rect)
	for rect in Data.ROCKS:
		draw_rect(Rect2(rect.position + Vector2(6, 8), rect.size), Color(0, 0, 0, 0.2))
		draw_style_box(_stone_style(), rect)
	for tree in Data.TREES:
		draw_circle(tree + Vector2(9, 3), 34, Color(0, 0, 0, 0.16))
		draw_rect(Rect2(tree - Vector2(12, 12), Vector2(24, 24)), Color("796047"))
	for rect in [Rect2(0, 0, 1824, 48), Rect2(0, 1200, 1824, 48),
		Rect2(0, 0, 48, 1248), Rect2(1776, 0, 48, 1248)]:
		draw_rect(rect, Color("747b75"))
		draw_rect(rect.grow(-5), Color("555f5b"), false, 2)

func _draw_paving(rect: Rect2) -> void:
	draw_rect(rect, Color("898977"))
	for y in range(int(rect.position.y), int(rect.end.y), Data.CELL_SIZE):
		for x in range(int(rect.position.x), int(rect.end.x), Data.CELL_SIZE):
			var tile := Rect2(x + 2, y + 2, 44, 44).intersection(rect)
			draw_rect(tile, Color("999985") if (x + y) % 96 == 0 else Color("929381"))
	draw_rect(rect, Color("b0aa8e"), false, 3)

func _draw_building(rect: Rect2) -> void:
	draw_rect(Rect2(rect.position + Vector2(10, 14), rect.size), Color(0, 0, 0, 0.24))
	draw_rect(rect, Color("a19880"))
	draw_rect(Rect2(rect.position + Vector2(5, rect.size.y - 56), Vector2(rect.size.x - 10, 51)), Color("b9ad8b"))
	var roof := Rect2(rect.position, Vector2(rect.size.x, rect.size.y - 56))
	draw_rect(roof, Color("555f69"))
	draw_rect(roof.grow(-8), Color("64717a"))
	for y in range(int(roof.position.y + 18), int(roof.end.y), 22):
		draw_line(Vector2(roof.position.x + 8, y), Vector2(roof.end.x - 8, y), Color("505c65"), 2)
	draw_rect(Rect2(rect.get_center().x - 19, rect.end.y - 48, 38, 48), Color("3d3830"))
	for x in [rect.position.x + 38, rect.end.x - 66]:
		draw_rect(Rect2(x, rect.end.y - 42, 28, 24), Color("3d5051"))
		draw_line(Vector2(x + 14, rect.end.y - 42), Vector2(x + 14, rect.end.y - 18), Color("d0b975"), 2)

func _stone_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("7d8278")
	style.border_color = Color("a1a293")
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	return style
