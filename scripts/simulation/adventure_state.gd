extends RefCounted
## Конечные запасы экспедиции и записи мира, без спрайтов.
const Data = preload("res://scripts/data/adit_location.gd")
const Navigation = preload("res://scripts/navigation/town_navigation.gd")
const Town = preload("res://scripts/data/test_location.gd")
const Mine = preload("res://scripts/data/mine_location.gd")
const Arena = preload("res://scripts/data/arena_location.gd")
var initialized := false
var opened: Dictionary = {}
var gates := {"iron_gate":false,"rubble":false}
var traps: Dictionary = {}
var drops: Dictionary = {}
var next_drop := 1
var revision := 0
func _init() -> void:
	for id in Data.CONTAINERS:
		opened[id] = false
	for id in Data.TRAPS:
		traps[id] = {"armed":true,"warning":-1.0}

func initialize(economy: RefCounted) -> void:
	if initialized:
		return
	# Единственный контролируемый стартовый запас области, не награда за вход.
	for id in Data.CONTAINERS:
		_seed(economy,"chest:"+id,Data.CONTAINERS[id].items)
	for id in Data.VEINS:
		_seed(economy,"vein:"+id,{Data.VEINS[id].item:Data.VEINS[id].count})
	for id in Data.ENEMIES:
		_seed(economy,"enemy:"+id,Data.ENEMIES[id].items)
	initialized = true
	revision += 1
func _seed(economy: RefCounted, owner: String, items: Dictionary) -> void:
	for id in items:
		economy.ledger.owners[owner].add(id,int(items[id]))
		for material in economy.catalog.items[id].material:
			economy.material_budget[material] += int(items[id])*int(economy.catalog.items[id].material[material])

func open_chest(id: String) -> String:
	if not initialized or not Data.CONTAINERS.has(id):
		return ""
	opened[id] = true
	revision += 1
	return "chest:"+id
func take(state: RefCounted, owner: String, item: String, amount: int) -> bool:
	if state.life.clock.paused or state.rpg.fighter.hp <= 0 or not accessible(state, owner):
		return false
	if not state.economy.ledger.transfer(owner,"player",item,amount):
		return false
	revision += 1
	return true

func clear_line(area: String, from: Vector2, to: Vector2) -> bool:
	var walls: Array[Rect2] = Data.solids(area,gates) if Data.is_area(area) else (Town.solid_rects() if area=="town" else (Mine.solid_rects() if area=="mine" else Arena.solid_rects()))
	from-=Vector2(0,4)
	to-=Vector2(0,4)
	for rect in walls:
		if rect.has_point(from) or rect.has_point(to):
			return false
		var corners: Array[Vector2]=[rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
		for i in range(4):
			if Geometry2D.segment_intersects_segment(from,to,corners[i],corners[(i+1)%4])!=null:
				return false
	return true
func accessible(state: RefCounted, owner: String) -> bool:
	var record := owner_record(owner)
	if record.is_empty() or record.area != state.location_id or state.player_position.distance_to(record.point) > 88:
		return false
	if owner.begins_with("chest:") and not opened.get(owner.trim_prefix("chest:"),false):
		return false
	return clear_line(state.location_id,state.player_position,record.point)
func owner_record(owner: String) -> Dictionary:
	if owner.begins_with("chest:"):
		return Data.CONTAINERS.get(owner.trim_prefix("chest:"),{})
	if drops.has(owner):
		return {"area":drops[owner].area,"point":drops[owner].position,"name":"На земле"}
	return {}
func drop_item(state: RefCounted, item: String, amount: int) -> String:
	if state.life.clock.paused or state.rpg.fighter.hp <= 0 or state.inventory.count(item) < amount or amount <= 0:
		return ""
	var point: Vector2 = state.player_position
	var owner := _allocate_drop(state,point,state.location_id)
	if owner.is_empty():
		return ""
	if not state.economy.ledger.transfer("player",owner,item,amount):
		return ""
	revision += 1
	return owner
func _allocate_drop(state: RefCounted, point: Vector2, area: String) -> String:
	# Preserve legacy sequential IDs, recycle empty owners instead of leaking slots.
	var owners: Array=drops.keys()
	owners.sort()
	for owner in owners:
		if owner.begins_with("drop:") and state.economy.ledger.owners[owner].items.is_empty():
			drops[owner]={"area":area,"position":point}
			return owner
	if next_drop<=512:
		var owner := "drop:"+str(next_drop)
		if not state.economy.ledger.add_drop_owner(owner):
			return ""
		drops[owner]={"area":area,"position":point}
		next_drop+=1
		return owner
	# Do not teleport a new item into a distant pile. A failed drop keeps ownership.
	return ""
func enemy_died(state: RefCounted, id: String, enemy: Dictionary) -> void:
	var source := "enemy:"+id
	if drops.has(source):
		return
	if not state.economy.ledger.owners.has(source) or state.economy.ledger.owners[source].items.is_empty():
		return
	var owner := _allocate_drop(state,enemy.position,enemy.location)
	if owner.is_empty():
		# No pile in this area: keep an accessible corpse inventory, never lose loot.
		drops[source]={"area":enemy.location,"position":enemy.position}
		revision+=1
		return
	for item in state.economy.ledger.owners[source].items.keys():
		state.economy.ledger.transfer(source,owner,item,state.economy.ledger.count(source,item))
	revision += 1
func open_gate(state: RefCounted, id: String) -> bool:
	if not gates.has(id) or gates[id] or state.life.clock.paused:
		return false
	if id == "iron_gate" and state.economy.ledger.count("player","test_adit_key") == 0:
		return false
	gates[id] = true
	revision += 1
	return true
func disarm(id: String) -> bool:
	if not traps.has(id) or not traps[id].armed:
		return false
	traps[id].armed = false
	traps[id].warning = -1.0
	revision += 1
	return true
func threatening(state: RefCounted) -> bool:
	for id in traps:
		var record: Dictionary = Data.TRAPS[id]
		if record.area == state.location_id and traps[id].armed and state.rpg.fighter.position.distance_to(record.point) < 110:
			return true
	return false
func tick(state: RefCounted, delta: float) -> void:
	if not Data.is_area(state.location_id) or state.rpg.fighter.hp <= 0:
		return
	for id in traps:
		var record: Dictionary = Data.TRAPS[id]
		var trap: Dictionary = traps[id]
		if record.area != state.location_id or not trap.armed:
			continue
		var distance: float = state.rpg.fighter.position.distance_to(record.point)
		if trap.warning < 0 and distance < 25:
			trap.warning = 0.65 if record.kind == "falling" else 0.3
		if trap.warning >= 0:
			trap.warning -= delta
			if trap.warning <= 0:
				if distance < 52:
					state.combat.damage(state.rpg.fighter,state.rpg.stats(state.catalog),14,record.point)
				disarm(id)
func mine(state: RefCounted, id: String) -> int:
	if not Data.VEINS.has(id) or state.life.clock.paused:
		return 0
	if state.rpg.fighter.hp<=0 or state.rpg.fighter.stamina<state.rpg.mining_cost():
		return 0
	var record: Dictionary = Data.VEINS[id]
	if state.location_id != record.area or state.player_position.distance_to(record.point) > 88:
		return 0
	if not state.economy.ledger.transfer("vein:"+id,"player",record.item,1):
		return 0
	revision += 1
	state.rpg.mining_completed()
	return 1
func to_save() -> Dictionary:
	var piles: Dictionary = {}
	for id in drops:
		piles[id] = {"area":drops[id].area,"position":[drops[id].position.x,drops[id].position.y]}
	return {"initialized":initialized,"opened":opened.duplicate(),"gates":gates.duplicate(),"traps":traps.duplicate(true),"drops":piles,"next_drop":next_drop}
func load_data(data: Variant, ledger: RefCounted) -> bool:
	if not data is Dictionary or not data.get("initialized") is bool or not data.get("opened") is Dictionary or not data.get("gates") is Dictionary or not data.get("traps") is Dictionary or not data.get("drops") is Dictionary:
		return false
	for pair in [[opened,data.opened],[gates,data.gates]]:
		if pair[0].size() != pair[1].size():
			return false
		for id in pair[0]:
			if not pair[1].get(id) is bool:
				return false
	if data.traps.size() != traps.size() or not _integer(data.get("next_drop"),1,513) or data.drops.size() < int(data.next_drop)-1 or data.drops.size()>512+Data.ENEMIES.size():
		return false
	for id in traps:
		if not data.traps.get(id) is Dictionary or not data.traps[id].get("armed") is bool or not _number(data.traps[id].get("warning"),-1,0.65):
			return false
	var piles: Dictionary = {}
	for n in range(1,int(data.next_drop)):
		var id := "drop:"+str(n)
		if not data.drops.get(id) is Dictionary or not ledger.owners.has(id):
			return false
		var record: Dictionary = data.drops[id]
		if record.get("area") not in ["town","mine","arena","adit_entry","adit_depths"] or not record.get("position") is Array or record.position.size()!=2 or not _number(record.position[0],0,1824) or not _number(record.position[1],0,1248):
			return false
		piles[id] = {"area":record.area,"position":Vector2(record.position[0],record.position[1])}
	for owner in data.drops:
		if piles.has(owner):
			continue
		var id: String = str(owner).trim_prefix("enemy:")
		var record = data.drops[owner]
		if not str(owner).begins_with("enemy:") or not Data.ENEMIES.has(id) or not record is Dictionary or record.get("area")!=Data.ENEMIES[id].location or not record.get("position") is Array or record.position.size()!=2 or not _number(record.position[0],0,1824) or not _number(record.position[1],0,1248):
			return false
		piles[owner]={"area":record.area,"position":Vector2(record.position[0],record.position[1])}
	for id in ledger.owners:
		if id.begins_with("drop:") and not piles.has(id):
			return false
	if not data.initialized:
		for id in Data.fixed_owners():
			if not ledger.owners[id].items.is_empty():
				return false
		for value in data.opened.values()+data.gates.values():
			if value:
				return false
	initialized = data.initialized
	opened = data.opened.duplicate()
	gates = data.gates.duplicate()
	traps = data.traps.duplicate(true)
	drops = piles
	next_drop = int(data.next_drop)
	return true
static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value>=low and value<=high
static func _integer(value: Variant, low: int, high: int) -> bool:
	return _number(value,low,high) and float(value)==floorf(float(value))
