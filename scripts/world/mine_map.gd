extends Node2D
## Самостоятельная сцена шахты. Визуализация читает остатки жил из WorldState.

const Data = preload("res://scripts/data/mine_location.gd")
const TILESET = preload("res://asset/tilesets/Dungeon_A5.png")
var world_state: RefCounted

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
	label.position = Data.EXIT + Vector2(-90, 20)
	label.text = "Выход в Златогорье"
	label.add_theme_font_size_override("font_size", 17)
	add_child(label)

func _draw() -> void:
	for y in range(0, int(Data.MAP_SIZE.y), 48):
		for x in range(0, int(Data.MAP_SIZE.x), 48):
			draw_texture_rect_region(TILESET, Rect2(x, y, 48, 48), Rect2(0, 144, 48, 48), Color("858a8d"))
	var walls: Array[Rect2] = Data.solid_rects()
	for i in range(6):
		var rect := walls[i]
		for y in range(int(rect.position.y), int(rect.end.y), 48):
			for x in range(int(rect.position.x), int(rect.end.x), 48):
				draw_texture_rect_region(TILESET, Rect2(x, y, 48, 48), Rect2(288, 96, 48, 48), Color("697783"))
	for deposit_id in Data.DEPOSITS:
		var deposit: Dictionary = Data.DEPOSITS[deposit_id]
		var point: Vector2 = deposit["position"]
		var remaining := int(world_state.resources[deposit_id]) if world_state != null else int(deposit["charges"])
		var tint := Color("d6d8ed") if deposit["item_id"] == "test_iron_ore" else Color("efb67a")
		if remaining == 0:
			tint = Color("54575b")
		draw_texture_rect_region(TILESET, Rect2(point - Vector2(24, 32), Vector2(48, 48)), Rect2(48, 192, 48, 48), tint)
		draw_arc(point, 28, 0, TAU, 24, tint, 2, true)
		for charge in range(remaining):
			draw_circle(point + Vector2(-10 + charge * 10, 27), 3, Color("f5d895"))
	draw_circle(Data.EXIT, 28, Color("487b72"))
	draw_line(Data.EXIT + Vector2(0, -16), Data.EXIT + Vector2(0, 16), Color("e7dfbf"), 4)
	draw_line(Data.EXIT + Vector2(0, 16), Data.EXIT + Vector2(-10, 6), Color("e7dfbf"), 4)
	draw_line(Data.EXIT + Vector2(0, 16), Data.EXIT + Vector2(10, 6), Color("e7dfbf"), 4)
