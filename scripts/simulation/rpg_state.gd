extends RefCounted
## Характеристики и привязки предметов; физическое имущество остаётся в Ledger.

const SLOTS: Dictionary = {"main_hand": "Основная рука", "off_hand": "Вторая рука", "head": "Голова", "body": "Тело", "feet": "Обувь", "accessory_1": "Аксессуар 1", "accessory_2": "Аксессуар 2"}
const BASE: Dictionary = {"max_hp": 100.0, "max_stamina": 100.0, "attack": 8.0, "defense": 1.0, "move_speed": 210.0, "attack_speed": 1.0, "attack_recovery": 0.38, "stamina_regen": 16.0, "block_reduction": 0.5}
var base: Dictionary = BASE.duplicate()
var equipment: Dictionary = {}
var quick: Array = ["attack", "block", "dodge", "test_heal"]
var kit_claimed := false
var fighter: Dictionary = new_fighter(Vector2.ZERO)
const Skills = preload("res://scripts/simulation/skill_state.gd")
var skills := Skills.new()

func _init() -> void:
	for slot in SLOTS:
		equipment[slot] = ""

static func new_fighter(position: Vector2) -> Dictionary:
	return {"position": position, "hp": 100.0, "stamina": 100.0, "facing": Vector2.RIGHT,
		"attack_elapsed": -1.0, "attack_scale": 1.0, "attack_kind": "normal", "hit_ids": [], "shot": false,
		"cooldown": 0.0, "dodge_left": 0.0, "dodge_cooldown": 0.0, "heal_cooldown": 0.0,
		"hurt": 0.0, "blocking": false, "block_left": 0.0, "dodge_direction": Vector2.RIGHT,
		"attack_count": 0, "nav_wait": 0.0, "path": []}

func stats(catalog: RefCounted) -> Dictionary:
	var result := base.duplicate()
	for id in equipment.values():
		if id.is_empty():
			continue
		for key in catalog.items[id].get("modifiers", {}):
			result[key] = float(result.get(key, 0)) + float(catalog.items[id]["modifiers"][key])
	result["block_reduction"] = clampf(result["block_reduction"], 0, 0.9)
	for key in ["max_hp", "max_stamina", "move_speed"]:
		result[key] = maxf(1, result[key])
	result["attack_speed"] = maxf(0.1, result["attack_speed"])
	result["attack_recovery"] = maxf(0.05, result["attack_recovery"])
	if not equipment.main_hand.is_empty():
		result.attack += skills.rank("melee")*0.35
	result.defense += skills.rank("defense")*0.2
	return result

func mining_cost() -> float:
	return 6.0/(1.0+float(skills.rank("mining"))*0.03)

func mining_completed() -> void:
	fighter.stamina=maxf(0,fighter.stamina-mining_cost())
	skills.practice("mining",true)

func equip(ledger: RefCounted, item_id: String, requested_slot: String = "") -> bool:
	if fighter["attack_elapsed"] >= 0 or fighter["dodge_left"] > 0 or fighter["hp"] <= 0:
		return false
	if not ledger.catalog.items.has(item_id):
		return false
	var slot: String = ledger.catalog.items[item_id].get("slot", "") if requested_slot.is_empty() else requested_slot
	var natural: String = ledger.catalog.items[item_id].get("slot", "")
	if not equipment.has(slot) or (slot != natural and not (slot == "accessory_2" and natural == "accessory_1")) or ledger.count("player", item_id) < 1:
		return false
	var old: String = equipment[slot]
	if not old.is_empty() and not ledger.can_add("player", old, 1):
		return false
	if not ledger.transfer("player", "equipment", item_id, 1):
		return false
	if not old.is_empty():
		ledger.transfer("equipment", "player", old, 1)
	equipment[slot] = item_id
	clamp_vitals(ledger.catalog)
	return true

func unequip(ledger: RefCounted, slot: String) -> bool:
	if fighter["hp"] <= 0 or not equipment.has(slot) or equipment[slot].is_empty() or fighter["attack_elapsed"] >= 0 or fighter["dodge_left"] > 0:
		return false
	if not ledger.transfer("equipment", "player", equipment[slot], 1):
		return false
	equipment[slot] = ""
	clamp_vitals(ledger.catalog)
	return true

func clamp_vitals(catalog: RefCounted) -> void:
	var derived := stats(catalog)
	fighter["hp"] = minf(fighter["hp"], derived["max_hp"])
	fighter["stamina"] = minf(fighter["stamina"], derived["max_stamina"])

func bind_quick(index: int, id: String, ledger: RefCounted) -> bool:
	if index < 0 or index >= quick.size():
		return false
	if id not in ["attack", "block", "dodge", ""] and (not ledger.catalog.items.has(id) or ledger.count("player", id) + ledger.count("equipment", id) == 0):
		return false
	quick[index] = id
	return true

func move_quick(from: int, to: int) -> bool:
	if from < 0 or to < 0 or from >= quick.size() or to >= quick.size():
		return false
	var old: String = quick[to]
	quick[to] = quick[from]
	quick[from] = old
	return true

func move_equipment(ledger: RefCounted, from: String, to: String) -> bool:
	if from == to or from not in ["accessory_1", "accessory_2"] or to not in ["accessory_1", "accessory_2"] or equipment[from].is_empty():
		return false
	if fighter.hp <= 0 or fighter.attack_elapsed >= 0 or fighter.dodge_left > 0:
		return false
	# Один и тот же владелец equipment; меняются места, не количество имущества.
	var old: String = equipment[to]
	equipment[to] = equipment[from]
	equipment[from] = old
	clamp_vitals(ledger.catalog)
	return true

func claim_kit(economy: RefCounted) -> bool:
	if kit_claimed:
		return false
	var kit := {"test_sword": 1, "test_shield": 1, "test_heal": 3}
	for id in kit:
		if not economy.ledger.can_add("player", id, kit[id]):
			return false
	for id in kit:
		economy.ledger.owners["player"].add(id, kit[id])
		for material in economy.catalog.items[id]["material"]:
			economy.material_budget[material] += kit[id] * int(economy.catalog.items[id]["material"][material])
	kit_claimed = true
	equip(economy.ledger, "test_sword")
	equip(economy.ledger, "test_shield")
	return true

func heal(ledger: RefCounted, id: String = "test_heal") -> bool:
	if fighter["hp"] <= 0 or fighter["heal_cooldown"] > 0 or not ledger.catalog.items.has(id):
		return false
	var amount: float = ledger.catalog.items[id].get("heal", 0)
	var maximum: float = stats(ledger.catalog)["max_hp"]
	if amount <= 0 or fighter["hp"] >= maximum or not ledger.transfer("player", "consumed", id, 1):
		return false
	fighter["hp"] = minf(maximum, fighter["hp"] + amount)
	fighter["heal_cooldown"] = 3.0
	return true

static func encode_fighter(record: Dictionary) -> Dictionary:
	var result := record.duplicate(true)
	result.erase("path")
	for key in ["position", "facing", "dodge_direction"]:
		result[key] = [record[key].x, record[key].y]
	return result

static func decode_fighter(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {}
	var result: Dictionary = data.duplicate(true)
	for key in ["position", "facing", "dodge_direction"]:
		var point = result.get(key)
		if not point is Array or point.size() != 2 or not number(point[0], -10000, 10000) or not number(point[1], -10000, 10000):
			return {}
		result[key] = Vector2(point[0], point[1])
	for key in ["hp", "stamina", "cooldown", "dodge_left", "dodge_cooldown", "heal_cooldown", "hurt", "block_left", "nav_wait"]:
		if not number(result.get(key), 0, 10000):
			return {}
		result[key] = float(result[key])
	if not number(result.get("attack_elapsed"), -1, 100) or not number(result.get("attack_scale"), 0.1, 10):
		return {}
	if result.get("attack_kind") not in ["normal", "strong", "ranged"] or not result.get("blocking") is bool or not result.get("shot") is bool:
		return {}
	if not result.get("hit_ids") is Array or result["hit_ids"].size() > 10 or not number(result.get("attack_count"), 0, 1000000000):
		return {}
	for id in result["hit_ids"]:
		if not id is String:
			return {}
	result["attack_count"] = int(result["attack_count"])
	result["path"] = []
	return result

func to_save() -> Dictionary:
	return {"base": base.duplicate(), "equipment": equipment.duplicate(), "quick": quick.duplicate(), "kit_claimed": kit_claimed, "fighter": encode_fighter(fighter), "skills": skills.to_save()}

func load_data(data: Variant, ledger: RefCounted, legacy: bool = false) -> bool:
	if not data is Dictionary or not data.get("base") is Dictionary or not data.get("equipment") is Dictionary or not data.get("quick") is Array or not data.get("kit_claimed") is bool:
		return false
	if data["base"].size() != BASE.size() or data["equipment"].size() != SLOTS.size() or data["quick"].size() != 4:
		return false
	for key in BASE:
		if not number(data["base"].get(key), 0.1 if key != "defense" else 0.0, 1000):
			return false
	var counts: Dictionary = {}
	for slot in SLOTS:
		var id = data["equipment"].get(slot)
		if not id is String:
			return false
		if not id.is_empty():
			if not ledger.catalog.items.has(id):
				return false
			var natural: String = ledger.catalog.items[id].get("slot", "")
			if slot != natural and not (slot == "accessory_2" and natural == "accessory_1"):
				return false
			counts[id] = int(counts.get(id, 0)) + 1
	if counts != ledger.owners["equipment"].items:
		return false
	for id in data["quick"]:
		if not id is String or (id not in ["attack", "block", "dodge", ""] and not ledger.catalog.items.has(id)):
			return false
	var restored := decode_fighter(data.get("fighter"))
	if restored.is_empty():
		return false
	base = data["base"].duplicate()
	equipment = data["equipment"].duplicate()
	quick = data["quick"].duplicate()
	kit_claimed = data["kit_claimed"]
	fighter = restored
	if data.has("skills"):
		if not skills.load_data(data.skills):
			return false
	elif not legacy:
		return false
	var derived := stats(ledger.catalog)
	return fighter["hp"] <= derived["max_hp"] and fighter["stamina"] <= derived["max_stamina"]

static func number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum


