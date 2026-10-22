extends RefCounted
## Единственный источник состояния жителей. Работает и без узлов персонажей.

signal minute_advanced

const Definitions = preload("res://scripts/data/resident_definitions.gd")
const Clock = preload("res://scripts/simulation/game_clock.gd")
const Decisions = preload("res://scripts/simulation/resident_decisions.gd")
const Navigation = preload("res://scripts/navigation/town_navigation.gd")
const Mine = preload("res://scripts/data/mine_location.gd")
const Production = preload("res://scripts/data/production_definitions.gd")
const Crowd = preload("res://scripts/navigation/crowd_navigation.gd")
const Occupations = preload("res://scripts/data/occupation_definitions.gd")
const WALK_PER_MINUTE := 12.0

var clock := Clock.new()
var navigation := Navigation.new()
var mine_navigation := Navigation.new(Mine.solid_rects(), Mine.MAP_SIZE)
var people: Dictionary = {}
var definitions: Dictionary = Definitions.PEOPLE.duplicate(true)
var profile_enabled := false
var profile_usec: Dictionary = {"decisions": 0, "navigation": 0}

func _init() -> void:
	for id in definitions:
		var definition: Dictionary = definitions[id]
		people[id] = {"position": definition["spawn"], "previous": definition["spawn"],
			"id": id,
			"location": "town", "hunger": 20.0, "fatigue": 15.0, "rest_need": 0.0,
			"task": "work", "activity": "work", "goal": definition["work"], "reason": "schedule",
			"next_decision": 480, "path": [], "work_minutes": 0, "sleep_minutes": 0, "meal_minutes": 0}
		if definition["spawn"] != definition["work"]:
			people[id]["activity"] = "walk"
	for id in definitions:
		if definitions[id].get("profession", "") == "miner":
			people[id]["work_mode"] = "mine"
			people[id]["work_site"] = "iron_01"

func register(id: String, definition: Dictionary) -> bool:
	if people.has(id) or not id.begins_with("resident_") or not Occupations.ROLES.has(definition.get("profession", "")):
		return false
	for key in ["spawn", "work", "home", "rest", "food", "errand"]:
		if not definition.get(key) is Vector2 or not navigation.walkable(definition[key]):
			return false
	definitions[id] = definition.duplicate(true)
	people[id] = {"position": definition.spawn, "previous": definition.spawn, "id": id,
		"location": "town", "hunger": 0.0, "fatigue": 15.0, "rest_need": 0.0,
		"task": "work", "activity": "work", "goal": definition.work, "reason": "schedule",
		"next_decision": clock.minute + 5, "path": [], "work_minutes": 0, "sleep_minutes": 0, "meal_minutes": 0}
	if definition.profession == "miner":
		people[id]["work_mode"] = "mine"
		people[id]["work_site"] = "iron_01"
	return true

func advance(real_seconds: float, held: Array[String] = [], blocker := Vector2.INF, blocker_location: String = "town") -> void:
	if clock.paused or real_seconds <= 0:
		return
	clock.fraction += real_seconds * Clock.MINUTES_PER_SECOND * clock.speed
	while clock.fraction >= 1.0 - 0.000000001:
		clock.fraction = maxf(0.0, clock.fraction - 1.0)
		clock.minute += 1
		step(held, blocker, blocker_location)

func step(held: Array[String] = [], blocker := Vector2.INF, blocker_location: String = "town") -> void:
	for id in people:
		people[id]["previous"] = people[id]["position"]
	for id in people:
		var resident: Dictionary = people[id]
		var occupied: bool = id in held or clock.minute < int(resident.get("social_hold_until",0))
		if occupied:
			resident["activity"] = "wait"
		_update_needs(resident)
		if occupied:
			resident["reason"] = "conversation"
			resident["next_decision"] = clock.minute + 1
			continue
		if clock.minute >= resident["next_decision"]:
			var decision_start := Time.get_ticks_usec() if profile_enabled else 0
			var decision := Decisions.choose(resident, clock.minute)
			var goal := goal_for(id, decision["task"], resident)
			var changed: bool = decision["task"] != resident["task"] or goal != resident["goal"]
			resident["task"] = decision["task"]
			resident["reason"] = decision["reason"]
			resident["goal"] = goal
			resident["next_decision"] = clock.minute + 5
			if profile_enabled:
				profile_usec.decisions += Time.get_ticks_usec() - decision_start
			if changed or resident["path"].is_empty() or resident["activity"] == "wait":
				var path_start := Time.get_ticks_usec() if profile_enabled else 0
				resident["path"] = navigation_for(resident["location"]).path(resident["position"], goal, blocker if resident["location"] == blocker_location else Vector2.INF)
				if profile_enabled:
					profile_usec.navigation += Time.get_ticks_usec() - path_start
		var move_start := Time.get_ticks_usec() if profile_enabled else 0
		_move(resident, blocker if resident["location"] == blocker_location else Vector2.INF)
		if definitions[id].get("profession", "") == "miner":
			_transition_miner(id, resident)
		if profile_enabled:
			profile_usec.navigation += Time.get_ticks_usec() - move_start
	minute_advanced.emit()

func navigation_for(location: String) -> RefCounted:
	return navigation if location == "town" else mine_navigation

func refresh_assignment(id: String) -> void:
	var person: Dictionary = people[id]
	person["goal"] = goal_for(id, person["task"], person)
	person["path"] = navigation_for(person["location"]).path(person["position"], person["goal"])
	person["next_decision"] = clock.minute
	person["activity"] = person["task"] if person["position"].distance_to(person["goal"]) < 0.1 else "walk"

func goal_for(id: String, task: String, resident: Dictionary) -> Vector2:
	if task == "errand" and resident.get("social_goal") is Array:
		return Vector2(resident.social_goal[0],resident.social_goal[1])
	if definitions[id].get("profession", "") == "miner":
		if resident["location"] == "mine":
			if task == "work" and resident["work_mode"] == "mine":
				return Mine.DEPOSITS[resident["work_site"]]["position"] + Vector2(0, 64)
			return Mine.EXIT - Vector2(0, 64)
		if task == "work" and resident["work_mode"] in ["deliver", "idle"]:
			return Production.WORKBENCH
	return definitions[id][Definitions.TASK_POINT[task]]

func _transition_miner(id: String, resident: Dictionary) -> void:
	if resident["position"].distance_to(resident["goal"]) > 0.1:
		return
	var location: String = resident["location"]
	if location == "town" and resident["task"] == "work" and resident["work_mode"] == "mine":
		resident["location"] = "mine"
		resident["position"] = Mine.SPAWN
	elif location == "mine" and (resident["task"] != "work" or resident["work_mode"] != "mine"):
		resident["location"] = "town"
		resident["position"] = Mine.TOWN_RETURN
	else:
		return
	resident["previous"] = resident["position"]
	resident["path"].clear()
	resident["goal"] = goal_for(id, resident["task"], resident)
	resident["activity"] = "walk"
	resident["next_decision"] = clock.minute

func _update_needs(resident: Dictionary) -> void:
	var activity: String = resident["activity"]
	# Legacy field retained for slots 1–5. Food is optional, never a survival timer.
	resident["hunger"] = 0.0
	var fatigue_rate := 0.06 if activity == "work" else 0.04
	if activity == "sleep":
		fatigue_rate = -0.25
		resident["sleep_minutes"] += 1
	elif activity == "rest":
		fatigue_rate = -0.12
	if activity=="work" and int(resident.get("support_until",0))>clock.minute:
		fatigue_rate*=0.7
	resident["fatigue"] = clampf(resident["fatigue"] + fatigue_rate, 0, 100)
	var rest_rate := 0.16 if activity == "work" else 0.015
	if activity in ["rest", "sleep", "eat"]:
		rest_rate = -0.55
	resident["rest_need"] = clampf(resident["rest_need"] + rest_rate, 0, 100)
	if activity == "work":
		resident["work_minutes"] += 1
	if activity == "eat":
		resident["meal_minutes"] += 1

func _move(resident: Dictionary, blocker: Vector2) -> void:
	# Gradually repair coincident positions from older saves; never teleport or push.
	if Crowd.occupied(resident.position,resident.id,people,resident.location):
		resident["crowd_recovery"]=true
	if resident.get("crowd_recovery",false) and Crowd.occupied(resident.position,resident.id,people,resident.location,48):
		var separated: Vector2=Crowd.escape(resident.position,resident.id,people,resident.location,navigation_for(resident.location))
		if blocker.is_finite() and Geometry2D.get_closest_point_to_segment(blocker,resident.position,separated).distance_to(blocker)<28:
			separated=resident.position
		resident.activity="walk" if separated!=resident.position else "wait"
		resident.position=separated
		return
	resident.erase("crowd_recovery")
	var nearby: bool = resident.position.distance_to(resident.goal)<48 and Crowd.occupied(resident.goal,resident.id,people,resident.location)
	if nearby or resident["position"].distance_to(resident["goal"]) < 0.1:
		resident["path"].clear()
		resident["activity"] = resident["task"]
		return
	if resident["path"].is_empty():
		resident["activity"] = "wait"
		resident["reason"] = "blocked"
		return
	var distance := WALK_PER_MINUTE
	var replanned := false
	while distance > 0.001 and not resident["path"].is_empty():
		var destination: Vector2 = resident["path"][0]
		var origin: Vector2 = resident["position"]
		var next := origin.move_toward(destination, distance)
		if blocker.is_finite() and Geometry2D.get_closest_point_to_segment(blocker, origin, next).distance_to(blocker) < 28.0:
			resident["activity"] = "wait"
			resident["reason"] = "player"
			return
		if not Crowd.free_segment(origin,next,resident.id,people,resident.location,navigation_for(resident.location)) and clock.minute%3==0 and not replanned:
			replanned=true
			var alternate: Array[Vector2]=navigation_for(resident.location).around_people(origin,resident.goal,resident.id,people,resident.location,blocker)
			if not alternate.is_empty():
				resident.path=alternate
				destination=resident.path[0]
				next=origin.move_toward(destination,distance)
		var steered: Vector2 = Crowd.steer(origin,next,resident.id,people,resident.location,navigation_for(resident.location))
		if steered != next:
			if blocker.is_finite() and Geometry2D.get_closest_point_to_segment(blocker,origin,steered).distance_to(blocker)<28:
				steered=origin
			resident.position=steered
			resident.activity="walk" if steered!=origin else "wait"
			resident.reason="blocked"
			resident.next_decision=mini(resident.next_decision,clock.minute+3)
			return
		distance -= origin.distance_to(next)
		resident["position"] = next
		if next.distance_to(destination) < 0.001:
			resident["path"].pop_front()
	resident["activity"] = resident["task"] if resident["position"].distance_to(resident["goal"]) < 0.1 else "walk"

func to_save() -> Dictionary:
	var saved: Dictionary = {}
	for id in people:
		var resident: Dictionary = people[id].duplicate(true)
		resident["route"] = []
		for point in resident.path:
			resident.route.append([point.x,point.y])
		resident.erase("path")
		resident.erase("previous")
		for key in ["position", "goal"]:
			var point: Vector2 = resident[key]
			resident[key] = [point.x, point.y]
		saved[id] = resident
	var extra: Dictionary = {}
	for id in definitions:
		if not Definitions.PEOPLE.has(id):
			var definition: Dictionary = definitions[id].duplicate(true)
			for key in ["spawn", "work", "home", "rest", "food", "errand"]:
				definition[key] = [definition[key].x, definition[key].y]
			extra[id] = definition
	return {"clock": clock.to_save(), "people": saved, "definitions": extra}

## Вызывается на новом экземпляре, до замены текущей симуляции.
func load_data(data: Variant, legacy: bool = false) -> bool:
	if not data is Dictionary or not data.get("clock") is Dictionary or not data.get("people") is Dictionary:
		return false
	var time: Dictionary = data["clock"]
	if not _whole(time.get("minute"), 0, 1000000000) or not _number(time.get("fraction"), 0, 1) or time["fraction"] >= 1:
		return false
	if not _number(time.get("speed"), 0.25, 60) or float(time["speed"]) not in Clock.SPEEDS or not time.get("paused") is bool:
		return false
	var saved: Dictionary = data["people"]
	var extra = data.get("definitions", {})
	if not extra is Dictionary or extra.size() > 200:
		return false
	for id in extra:
		if not id is String or not id.begins_with("resident_") or id.length() > 40 or not extra[id] is Dictionary:
			return false
		var definition: Dictionary = extra[id].duplicate(true)
		if not definition.get("name") is String or definition.name.length() > 64 or not _whole(definition.get("sprite"), 0, 7):
			return false
		definition.sprite = int(definition.sprite)
		for key in ["spawn", "work", "home", "rest", "food", "errand"]:
			var point = definition.get(key)
			if not point is Array or point.size() != 2 or not _number(point[0], 0, 1824) or not _number(point[1], 0, 1248):
				return false
			definition[key] = Vector2(point[0], point[1])
		if not register(id, definition):
			return false
	if saved.size() > definitions.size():
		return false
	for id in saved:
		if not definitions.has(id):
			return false
	for id in definitions:
		if legacy and not saved.has(id):
			continue
		if not saved.get(id) is Dictionary:
			return false
		var resident: Dictionary = saved[id].duplicate(true)
		if resident.has("crowd_recovery") and not resident.crowd_recovery is bool:
			return false
		if resident.get("id",id) != id:
			return false
		resident["id"] = id
		for key in ["social_hold_until","support_until","social_goal_until","assist_credit"]:
			if not _whole(resident.get(key,0),0,1000000010):
				return false
			if resident.has(key):
				resident[key]=int(resident[key])
		if resident.has("social_goal"):
			var meeting = resident.social_goal
			if not meeting is Array or meeting.size()!=2 or not _number(meeting[0],0,1824) or not _number(meeting[1],0,1248) or not navigation.walkable(Vector2(meeting[0],meeting[1])):
				return false
		if resident.get("location") not in ["town", "mine"] or resident.get("task") not in Definitions.TASK_POINT:
			return false
		if definitions[id].get("profession", "") != "miner" and resident["location"] != "town":
			return false
		if definitions[id].get("profession", "") == "miner":
			resident["work_mode"] = resident.get("work_mode", "mine")
			resident["work_site"] = resident.get("work_site", "iron_01")
			if resident["work_mode"] not in ["mine", "deliver", "idle"] or not Mine.DEPOSITS.has(resident["work_site"]):
				return false
		if resident.get("activity") not in Definitions.TASK_NAMES or resident.get("reason") not in Definitions.REASONS:
			return false
		for key in ["hunger", "fatigue", "rest_need"]:
			if not _number(resident.get(key), 0, 100):
				return false
			resident[key] = float(resident[key])
		for key in ["next_decision", "work_minutes", "sleep_minutes", "meal_minutes"]:
			if not _whole(resident.get(key), 0, 1000000010):
				return false
			resident[key] = int(resident[key])
		for key in ["position", "goal"]:
			var point = resident.get(key)
			if not point is Array or point.size() != 2 or not _number(point[0], 0, 1824) or not _number(point[1], 0, 1248):
				return false
			resident[key] = Vector2(float(point[0]), float(point[1]))
			if not navigation_for(resident["location"]).walkable(resident[key]):
				return false
		var expected := goal_for(id, resident["task"], resident)
		if resident["goal"].distance_to(expected) > 0.1:
			return false
		resident["previous"] = resident["position"]
		resident["path"] = navigation_for(resident["location"]).path(resident["position"], resident["goal"])
		if resident.has("route"):
			if not resident.route is Array or resident.route.size()>512:
				return false
			resident.path=[]
			var origin: Vector2=resident.position
			for point in resident.route:
				if not point is Array or point.size()!=2 or not _number(point[0],0,1824) or not _number(point[1],0,1248):
					return false
				var target:=Vector2(point[0],point[1])
				if not navigation_for(resident.location).clear_segment(origin,target):
					return false
				resident.path.append(target)
				origin=target
			resident.erase("route")
		people[id] = resident
	clock.minute = int(time["minute"])
	clock.fraction = float(time["fraction"])
	clock.speed = float(time["speed"])
	clock.paused = time["paused"]
	return true

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum

static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value, minimum, maximum) and float(value) == floor(float(value))
