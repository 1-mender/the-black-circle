extends RefCounted
## Общая для экранной и фоновой симуляции навигация; сцены ей не нужны.
## Сетка 24px, запас под радиус ступней, без диагонального срезания углов.

const Data = preload("res://scripts/data/test_location.gd")
const CELL := 24.0
var grid := AStarGrid2D.new()
var solids: Array[Rect2] = Data.solid_rects()
var map_size: Vector2 = Data.MAP_SIZE

func _init(obstacles: Array[Rect2] = Data.solid_rects(), size: Vector2 = Data.MAP_SIZE) -> void:
	solids = obstacles
	map_size = size
	grid.region = Rect2i(0, 0, ceili(size.x / CELL), ceili(size.y / CELL))
	grid.cell_size = Vector2(CELL, CELL)
	grid.offset = Vector2(CELL * 0.5, CELL * 0.5)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for y in range(grid.region.size.y):
		for x in range(grid.region.size.x):
			var id := Vector2i(x, y)
			grid.set_point_solid(id, not walkable(grid.get_point_position(id)))

func walkable(point: Vector2) -> bool:
	if not Rect2(Vector2.ZERO, map_size).has_point(point):
		return false
	for rect in solids:
		if rect.grow(15).has_point(point - Vector2(0, 4)):
			return false
	return true

func clear_segment(from: Vector2, to: Vector2) -> bool:
	var count := maxi(1, ceili(from.distance_to(to) / 6.0))
	for i in range(count + 1):
		if not walkable(from.lerp(to, float(i) / float(count))):
			return false
	return true

func _cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CELL), floori(point.y / CELL))

func _anchor(point: Vector2) -> Vector2i:
	var center := _cell(point)
	var best := Vector2i(-1, -1)
	var distance := INF
	for y in range(center.y - 3, center.y + 4):
		for x in range(center.x - 3, center.x + 4):
			var id := Vector2i(x, y)
			if not grid.is_in_boundsv(id) or grid.is_point_solid(id):
				continue
			var candidate := grid.get_point_position(id)
			var length := point.distance_squared_to(candidate)
			if length < distance and clear_segment(point, candidate):
				best = id
				distance = length
	return best

func path(from: Vector2, to: Vector2, avoid := Vector2.INF) -> Array[Vector2]:
	var changed: Array[Vector2i] = []
	if avoid.is_finite():
		var center := _cell(avoid)
		for y in range(center.y - 2, center.y + 3):
			for x in range(center.x - 2, center.x + 3):
				var id := Vector2i(x, y)
				if grid.is_in_boundsv(id) and not grid.is_point_solid(id) and grid.get_point_position(id).distance_to(avoid) < 42:
					grid.set_point_solid(id, true)
					changed.append(id)
	var result := _build_path(from, to, avoid)
	for id in changed:
		grid.set_point_solid(id, false)
	return result

func _build_path(from: Vector2, to: Vector2, avoid: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if not walkable(from) or not walkable(to):
		return result
	var avoiding: bool = avoid.is_finite() and Geometry2D.get_closest_point_to_segment(avoid, from, to).distance_to(avoid) < 42
	if not avoiding and clear_segment(from, to):
		result.append(to)
		return result
	var start := _anchor(from)
	var finish := _anchor(to)
	if start.x < 0 or finish.x < 0:
		return result
	var points := grid.get_point_path(start, finish)
	if points.is_empty():
		return result
	for point in points:
		result.append(point)
	result.append(to)
	return result

func around_people(from: Vector2, to: Vector2, id: String, people: Dictionary, location: String, blocker: Vector2) -> Array[Vector2]:
	var points: Array[Vector2]=[]
	for other in people:
		if other!=id and people[other].location==location:
			var occupied_point: Vector2 = people[other].position
			if Geometry2D.get_closest_point_to_segment(occupied_point, from, to).distance_to(occupied_point) < 72:
				points.append(occupied_point)
	if blocker.is_finite():
		points.append(blocker)
	var changed: Array[Vector2i]=[]
	for point in points:
		var cell:=_cell(point)
		for y in range(cell.y-2,cell.y+3):
			for x in range(cell.x-2,cell.x+3):
				var key:=Vector2i(x,y)
				if grid.is_in_boundsv(key) and not grid.is_point_solid(key) and grid.get_point_position(key).distance_to(point)<34:
					grid.set_point_solid(key,true)
					changed.append(key)
	# A finite blocker at the origin forces AStar rather than the straight shortcut.
	var result:=_build_path(from,to,from)
	for key in changed:
		grid.set_point_solid(key,false)
	return result
