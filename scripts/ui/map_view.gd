extends Control
const Geometry=preload("res://scripts/data/map_geometry.gd")
const UIStyle=preload("res://scripts/ui/dark_theme.gd")
var world: RefCounted
var large:=false
var area:=""
var gate_key:=""
var solids: Array[Rect2]=[]
var last_signature:=""
func _ready() -> void:
	clip_contents=true
	mouse_filter=Control.MOUSE_FILTER_IGNORE
func refresh(state: RefCounted) -> void:
	world=state
	var key:=JSON.stringify(state.adventure.gates)
	if area!=state.location_id or key!=gate_key:
		area=state.location_id
		gate_key=key
		solids=Geometry.walls(area,state.adventure.gates)
	var signature:=str([state.cartography.get_instance_id(),area,key,state.player_position,state.rpg.fighter.facing,state.cartography.known.get(area,{}).size(),size])
	if last_signature!=signature:
		last_signature=signature
		queue_redraw()
func world_rect() -> Rect2:
	if large:
		return Rect2(Vector2.ZERO,Geometry.bounds(area))
	return Rect2(world.player_position-Vector2(336,264),Vector2(672,528))
func map_point(point: Vector2) -> Vector2:
	var view:=world_rect()
	var scale_factor:=minf((size.x-12)/view.size.x,(size.y-12)/view.size.y)
	return (size-view.size*scale_factor)/2+(point-view.position)*scale_factor
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),UIStyle.BACKGROUND)
	if world==null or area.is_empty():
		return
	var view:=world_rect()
	var scale_factor:=minf((size.x-12)/view.size.x,(size.y-12)/view.size.y)
	var cols:=Geometry.columns(area)
	for index in world.cartography.known.get(area,{}):
		var cell:=Rect2((int(index)%cols)*48,floori(float(index)/cols)*48,48,48)
		if not cell.intersects(view):
			continue
		draw_rect(Rect2(map_point(cell.position),cell.size*scale_factor+Vector2(0.5,0.5)),Color("30363c"))
		if area=="town":
			for road in Geometry.Town.ROADS:
				_draw_part(cell,road,scale_factor,Color("5e5c52"))
		for wall in solids:
			_draw_part(cell,wall,scale_factor,Color("888b8e"))
	var exits:=Geometry.exits(area)
	for index in range(exits.size()):
		var exit_point: Vector2=exits[index]
		if world.cartography.knows(area,exit_point):
			draw_circle(map_point(exit_point),4,UIStyle.GOLD)
			if large:
				draw_string(ThemeDB.fallback_font,map_point(exit_point)+Vector2(10,5),Geometry.exit_name(area,index),HORIZONTAL_ALIGNMENT_LEFT,-1,14,UIStyle.MUTED)
	var point:=map_point(world.player_position)
	var facing: Vector2=world.rpg.fighter.facing.normalized()
	if facing.is_zero_approx():
		facing=Vector2.DOWN
	var side:=facing.orthogonal()
	draw_circle(point,7,UIStyle.BACKGROUND)
	draw_colored_polygon(PackedVector2Array([point+facing*8,point-facing*5+side*4,point-facing*5-side*4]),UIStyle.TEXT)
func _draw_part(cell: Rect2, shape: Rect2, scale_factor: float, color: Color) -> void:
	if cell.intersects(shape):
		var part:=cell.intersection(shape)
		draw_rect(Rect2(map_point(part.position),part.size*scale_factor),color)
