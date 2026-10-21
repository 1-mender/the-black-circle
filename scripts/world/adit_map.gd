extends Node2D
const Data = preload("res://scripts/data/adit_location.gd")
const TILES = preload("res://asset/tilesets/Dungeon_A5.png")
const DECOR = preload("res://asset/tilesets/Dungeon_B.png")
const CHEST = preload("res://asset/characters/!Chest.png")
const TRAP_TEXTURE = preload("res://asset/characters/!Other1.png")
const SWITCH_TEXTURE = preload("res://asset/characters/!Switch1.png")
const Icons = preload("res://scripts/ui/item_icons.gd")
var world_state: RefCounted
var area := "adit_entry"
var gate_shapes: Dictionary = {}
func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for rect in Data.solids(area,{"iron_gate":true,"rubble":true}):
		_body(rect)
	for id in Data.GATES:
		if Data.GATES[id].area == area:
			gate_shapes[id] = _body(Data.GATES[id].rect)
	var labels := [[Vector2(144,920),"В город · E"],[Vector2(1200,420),"В глубины · E"]] if area == "adit_entry" else [[Vector2(100,920),"К выходу · E"],[Vector2(160,144),"Боковой склад"],[Vector2(1140,120),"Дальний участок"]]
	for entry in labels:
		var label := Label.new()
		label.hide()
		label.position = entry[0]
		label.text = entry[1]
		label.add_theme_font_size_override("font_size",16)
		label.add_theme_color_override("font_color",Color("e8d4a3"))
		add_child(label)
func _body(rect: Rect2) -> CollisionShape2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = rect.get_center()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	return shape
func _process(_delta: float) -> void:
	for id in gate_shapes:
		gate_shapes[id].set_deferred("disabled",world_state.adventure.gates[id])
	queue_redraw()
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,Data.SIZE),Color("121c19"))
	for y in range(22):
		for x in range(32):
			var rect := Rect2(x*48,y*48,48,48)
			if Data.floor_at(area,rect.get_center()):
				var color := Color("8f9681")
				if x < 10 and y < 10:
					color = Color("799b9e")
				elif x > 22:
					color = Color("b39b7a")
				draw_texture_rect_region(TILES,rect,Rect2(0,144,48,48),color)
	for wall in Data.solids(area,{"iron_gate":true,"rubble":true}):
		for y in range(int(wall.position.y),int(wall.end.y),48):
			for x in range(int(wall.position.x),int(wall.end.x),48):
				draw_texture_rect_region(TILES,Rect2(x,y,48,48),Rect2(288,96,48,48),Color("788575"))
	if world_state == null:
		return
	for id in Data.GATES:
		var record: Dictionary = Data.GATES[id]
		if record.area == area and not world_state.adventure.gates[id]:
			for y in range(int(record.rect.position.y),int(record.rect.end.y),48):
				draw_texture_rect_region(DECOR,Rect2(record.rect.position.x,y,48,48),Rect2(576,720,48,48) if id=="iron_gate" else Rect2(48,144,48,48))
	for id in Data.CONTAINERS:
		var record: Dictionary = Data.CONTAINERS[id]
		if record.area == area:
			draw_texture_rect_region(CHEST,Rect2(record.point-Vector2(24,42),Vector2(48,48)),Rect2(48,144 if world_state.adventure.opened[id] else 0,48,48))
	for id in Data.VEINS:
		var record: Dictionary = Data.VEINS[id]
		if record.area == area:
			var count: int = world_state.economy.ledger.count("vein:"+id,record.item)
			draw_texture_rect_region(DECOR,Rect2(record.point-Vector2(24,40),Vector2(48,48)),Rect2(96,192,48,48),Color.WHITE if count>0 else Color("505950"))
	for id in Data.TRAPS:
		var record: Dictionary = Data.TRAPS[id]
		if record.area == area:
			var trap: Dictionary = world_state.adventure.traps[id]
			var texture:Texture2D=TRAP_TEXTURE if record.kind=="spikes" else SWITCH_TEXTURE
			var source:=Rect2(0,288 if trap.warning>=0 else 192,48,48) if record.kind=="spikes" else Rect2(0,192,48,48)
			draw_texture_rect_region(texture,Rect2(record.point-Vector2(24,24),Vector2(48,48)),source,Color.WHITE if trap.armed else Color("526052"))
			if trap.armed:
				draw_arc(record.point,52 if trap.warning>=0 else 22,0,TAU,32,Color("ed9971") if trap.warning>=0 else Color("ad8062"),3)
	for drop_owner in world_state.adventure.drops:
		var record: Dictionary = world_state.adventure.drops[drop_owner]
		var items: Dictionary = world_state.economy.ledger.owners[drop_owner].items
		if record.area == area and not items.is_empty():
			draw_circle(record.position,18,Color("433e2a"))
			draw_texture_rect(Icons.texture(items.keys()[0]),Rect2(record.position-Vector2(16,24),Vector2(32,32)),false)
	var exit := Vector2(144,912) if area=="adit_entry" else Vector2(144,864)
	draw_arc(exit,24,0,TAU,24,Color("e6c78d"),3)
	if area=="adit_entry":
		draw_arc(Vector2(1320,384),24,0,TAU,24,Color("e6c78d"),3)
	else:
		draw_texture_rect_region(SWITCH_TEXTURE,Rect2(Data.LEVER-Vector2(24,24),Vector2(48,48)),Rect2(0,48 if world_state.adventure.gates.rubble else 0,48,48))
