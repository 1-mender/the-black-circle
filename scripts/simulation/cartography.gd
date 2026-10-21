extends RefCounted
## Bounded player map knowledge. Grid visibility is conservative around obstacles.
const Geometry=preload("res://scripts/data/map_geometry.gd")
var known: Dictionary={}
var last_area:=""
var last_cell:=Vector2i(-999,-999)
var last_gates:=""
var opaque: Dictionary={}
func observe(area: String, position: Vector2, gates: Dictionary) -> void:
	var cell:=Vector2i((position/Geometry.CELL).floor())
	var gate_key:=JSON.stringify(gates)
	if area==last_area and cell==last_cell and gate_key==last_gates:
		return
	if area!=last_area or gate_key!=last_gates:
		opaque.clear()
		for wall in Geometry.walls(area,gates):
			for y in range(floori(wall.position.y/48),ceili(wall.end.y/48)):
				for x in range(floori(wall.position.x/48),ceili(wall.end.x/48)):
					if wall.intersects(Rect2(x*48+6,y*48+6,36,36)):
						opaque[Vector2i(x,y)]=true
	last_area=area
	last_cell=cell
	last_gates=gate_key
	if not known.has(area):
		known[area]={}
	var cols:=Geometry.columns(area)
	var rows:=ceili(Geometry.bounds(area).y/48)
	for y in range(maxi(0,cell.y-7),mini(rows,cell.y+8)):
		for x in range(maxi(0,cell.x-7),mini(cols,cell.x+8)):
			var target:=Vector2i(x,y)
			if cell.distance_squared_to(target)<=49 and _visible(cell,target):
				known[area][y*cols+x]=true
func _visible(from: Vector2i, target: Vector2i) -> bool:
	var point:=from
	var dx:=absi(target.x-from.x)
	var dy:=-absi(target.y-from.y)
	var sx:=1 if from.x<target.x else -1
	var sy:=1 if from.y<target.y else -1
	var error:=dx+dy
	while point!=target:
		if point!=from and opaque.has(point):
			return false
		var twice:=2*error
		if twice>=dy and twice<=dx and (opaque.has(point+Vector2i(sx,0)) or opaque.has(point+Vector2i(0,sy))):
			return false
		if twice>=dy:
			error+=dy
			point.x+=sx
		if twice<=dx:
			error+=dx
			point.y+=sy
	return true
func knows(area: String, position: Vector2) -> bool:
	var cell:=Vector2i((position/48).floor())
	return known.get(area,{}).has(cell.y*Geometry.columns(area)+cell.x)
func to_save() -> Dictionary:
	var result: Dictionary={}
	for area in known:
		var cells: Array=known[area].keys()
		cells.sort()
		result[area]=cells
	return result
func load_data(value: Variant) -> bool:
	if not value is Dictionary or value.size()>Geometry.AREAS.size():
		return false
	var restored: Dictionary={}
	for area in value:
		if area not in Geometry.AREAS or not value[area] is Array or value[area].size()>Geometry.count(area):
			return false
		restored[area]={}
		for cell in value[area]:
			if not (cell is int or cell is float) or not is_finite(float(cell)) or cell!=floorf(cell) or cell<0 or cell>=Geometry.count(area) or restored[area].has(int(cell)):
				return false
			restored[area][int(cell)]=true
	known=restored
	last_area=""
	return true
