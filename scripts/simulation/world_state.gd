extends RefCounted
## Состояние игры: без ссылок на сцены, ввод или интерфейс.

const LocationData = preload("res://scripts/data/test_location.gd")
const MineData = preload("res://scripts/data/mine_location.gd")
const Cartography=preload("res://scripts/simulation/cartography.gd")
var cartography:=Cartography.new()
const Catalog = preload("res://scripts/data/item_catalog.gd")
const Inventory = preload("res://scripts/simulation/inventory.gd")
const ResidentSimulation = preload("res://scripts/simulation/resident_simulation.gd")
const ProductionSimulation = preload("res://scripts/simulation/production_simulation.gd")
const MAX_MONEY := 1000000000
const RPG = preload("res://scripts/simulation/rpg_state.gd")
var rpg := RPG.new()
const Combat = preload("res://scripts/simulation/combat_simulation.gd")
const Arena = preload("res://scripts/data/arena_location.gd")
var arena_combat := Combat.new()
var expedition_combat := Combat.new(Adit.ENEMIES,true)
var combat: RefCounted:
	get: return expedition_combat if Adit.is_area(location_id) else arena_combat
const Adit = preload("res://scripts/data/adit_location.gd")
const Adventure = preload("res://scripts/simulation/adventure_state.gd")
var adventure := Adventure.new()

var catalog := Catalog.new()
var inventory := Inventory.new()
var economy: RefCounted
var money: int:
	get:
		return int(economy.ledger.wallets["player"]) if economy != null else 0
	set(value):
		if economy != null:
			economy.money_budget += value - int(economy.ledger.wallets["player"])
			economy.ledger.wallets["player"] = value
var location_id := "town"
var player_position: Vector2 = LocationData.PLAYER_SPAWN
var character_name := "Авантюрист"
var character_index := 0
var facing_row := 0
var resources: Dictionary = {}
var life := ResidentSimulation.new()
const Social = preload("res://scripts/simulation/social_simulation.gd")
var social := Social.new()

var location_name: String = LocationData.LOCATION_NAME
var npc_records: Dictionary = {
	LocationData.NPC_ID: {"display_name": "Житель · тестовый NPC", "conversations": 0},
}

func _init() -> void:
	for deposit_id in MineData.DEPOSITS:
		resources[deposit_id] = MineData.DEPOSITS[deposit_id]["charges"]
	for id in life.Definitions.PEOPLE:
		if not npc_records.has(id):
			npc_records[id] = {"display_name": life.Definitions.PEOPLE[id]["name"], "conversations": 0}
	economy = ProductionSimulation.new(resources, inventory, catalog)
	rpg.fighter.position = player_position
	life.minute_advanced.connect(_production_tick)

func _production_tick() -> void:
	economy.tick(life, location_id, player_position)
	social.tick(self)

func mine(deposit_id: String) -> int:
	if not MineData.DEPOSITS.has(deposit_id) or int(resources.get(deposit_id, 0)) <= 0:
		return 0
	if life.clock.paused or rpg.fighter.hp<=0 or rpg.fighter.stamina<rpg.mining_cost():
		return 0
	var deposit: Dictionary = MineData.DEPOSITS[deposit_id]
	var amount: int = deposit["yield"]
	if not economy.ledger.transfer("source:" + deposit_id, "player", deposit["item_id"], amount):
		return 0
	economy.mined[deposit["item_id"]] += amount
	economy.revision += 1
	rpg.mining_completed()
	return amount

func sell(shop_id: String, item_id: String, amount: int) -> int:
	var price: int = catalog.buy_price(shop_id, item_id)
	if price <= 0 or amount <= 0 or amount > inventory.count(item_id):
		return 0
	if amount > floori(float(MAX_MONEY - money) / float(price)):
		return 0
	if not economy.ledger.can_add("workshop", item_id, amount):
		return 0
	var earned: int = economy.ledger.trade("player", "shop:" + shop_id, item_id, amount, price)
	if earned > 0:
		economy.ledger.transfer("shop:" + shop_id, "workshop", item_id, amount)
		economy.revision += 1
	return earned

func buy(shop_id: String, item_id: String, amount: int) -> int:
	var price: int = catalog.sell_price(shop_id, item_id)
	var paid: int = economy.ledger.trade("shop:" + shop_id, "player", item_id, amount, price)
	if paid > 0:
		economy.revision += 1
	return paid

func to_save() -> Dictionary:
	rpg.fighter.position = player_position
	var dialogues: Dictionary = {}
	for id in npc_records:
		dialogues[id] = npc_records[id]["conversations"]
	return {
		"version": 6,
		"cartography": cartography.to_save(),
		"social": social.to_save(),
		"rpg": rpg.to_save(),
		"combat": arena_combat.to_save(),
		"expedition_combat": expedition_combat.to_save(),
		"adventure": adventure.to_save(),
		"character": {"name": character_name, "sprite": character_index, "facing": facing_row},
		"location": location_id, "position": [player_position.x, player_position.y],
		"money": money, "inventory": inventory.items.duplicate(),
		"resources": resources.duplicate(),
		"conversations": npc_records[LocationData.NPC_ID]["conversations"],
		"life": life.to_save(),
		"dialogues": dialogues,
		"economy": economy.to_save(),
	}

## Проверяем весь документ до изменения текущей игры.
func apply_save(data: Dictionary) -> bool:
	if not _whole(data.get("version"), 1, 6):
		return false
	var restored_map:=Cartography.new()
	if not restored_map.load_data(data.get("cartography",{})):
		return false
	var restored_life := ResidentSimulation.new()
	if int(data["version"]) >= 2 and not restored_life.load_data(data.get("life"),int(data["version"])<=5):
		return false
	if data.get("location") not in ["town", "mine", "arena", "adit_entry", "adit_depths"] or (int(data["version"]) < 4 and data.get("location") == "arena") or (int(data["version"]) < 5 and Adit.is_area(data.get("location"))):
		return false
	var character = data.get("character")
	if not character is Dictionary or not character.get("name") is String:
		return false
	if character["name"].strip_edges().is_empty() or character["name"].length() > 64:
		return false
	if not _whole(character.get("sprite"), 0, 7) or not _whole(character.get("facing"), 0, 3):
		return false
	var point = data.get("position")
	if not point is Array or point.size() != 2:
		return false
	for coordinate in point:
		if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)):
			return false
	var position := Vector2(float(point[0]), float(point[1]))
	var loaded_gates: Dictionary = {}
	if data.get("adventure") is Dictionary and data.adventure.get("gates") is Dictionary:
		loaded_gates=data.adventure.gates
	if not valid_position(data["location"], position, loaded_gates):
		return false
	if not _whole(data.get("money"), 0, MAX_MONEY):
		return false
	var stacks = data.get("inventory")
	if not stacks is Dictionary:
		return false
	for item_id in stacks:
		if not catalog.items.has(item_id) or not _whole(stacks[item_id], 1, Inventory.MAX_COUNT):
			return false
	var saved_resources = data.get("resources")
	if not saved_resources is Dictionary or saved_resources.size() != MineData.DEPOSITS.size():
		return false
	for deposit_id in MineData.DEPOSITS:
		if not _whole(saved_resources.get(deposit_id), 0, MineData.DEPOSITS[deposit_id]["charges"]):
			return false
	if not _whole(data.get("conversations"), 0, 1000000000):
		return false
	var dialogues = data.get("dialogues", {})
	if not dialogues is Dictionary:
		return false
	for id in dialogues:
		if not npc_records.has(id) or not _whole(dialogues[id], 0, 1000000000):
			return false
	var restored_inventory := Inventory.new()
	for id in stacks:
		restored_inventory.items[id] = int(stacks[id])
	var restored_sources: Dictionary = {}
	for id in saved_resources:
		restored_sources[id] = int(saved_resources[id])
	var restored_economy := ProductionSimulation.new(restored_sources, restored_inventory, catalog)
	if int(data["version"]) >= 3:
		if not restored_economy.load_data(data.get("economy"), int(data["version"]) <= 5):
			return false
		if not ProductionSimulation._same_counts(restored_inventory.items, stacks) or int(restored_economy.ledger.wallets["player"]) != int(data["money"]):
			return false
	else:
		restored_economy.ledger.wallets["player"] = int(data["money"])
		restored_economy.money_budget += int(data["money"])
	var restored_rpg := RPG.new()
	if int(data["version"]) >= 4 and not restored_rpg.load_data(data.get("rpg"), restored_economy.ledger, int(data["version"])<=4):
		return false
	var restored_combat := Combat.new()
	if int(data["version"]) >= 4 and not restored_combat.load_data(data.get("combat")):
		return false
	var restored_adventure := Adventure.new()
	if int(data["version"]) >= 5 and not restored_adventure.load_data(data.get("adventure"),restored_economy.ledger):
		return false
	if Adit.is_area(data["location"]) and not restored_adventure.initialized:
		return false
	for pile in restored_adventure.drops.values():
		if not valid_position(pile.area,pile.position,restored_adventure.gates):
			return false
	var restored_expedition := Combat.new(Adit.ENEMIES,true)
	restored_expedition.opened_gates=restored_adventure.gates.duplicate()
	if int(data["version"])>=5 and not restored_expedition.load_data(data.get("expedition_combat")):
		return false
	restored_rpg.fighter.position = position
	var restored_social := Social.new()
	if int(data["version"])>=6 and not restored_social.load_data(data.get("social"),restored_life,restored_economy.ledger):
		return false
	social=restored_social
	rpg = restored_rpg
	arena_combat = restored_combat
	expedition_combat = restored_expedition
	adventure = restored_adventure
	character_name = character["name"]
	character_index = int(character["sprite"])
	facing_row = int(character["facing"])
	location_id = data["location"]
	location_name = LocationData.LOCATION_NAME if location_id == "town" else (MineData.LOCATION_NAME if location_id == "mine" else Arena.LOCATION_NAME)
	if Adit.is_area(location_id):
		location_name = Adit.NAMES[location_id]
	player_position = position
	inventory = restored_inventory
	resources = restored_sources
	economy = restored_economy
	for id in npc_records:
		npc_records[id]["conversations"] = int(dialogues.get(id, data["conversations"] if id == LocationData.NPC_ID else 0))
	cartography=restored_map
	life = restored_life
	life.minute_advanced.connect(_production_tick)
	combat.update_safety(self)
	return true

static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	if not (value is int or value is float):
		return false
	return is_finite(float(value)) and value >= minimum and value <= maximum and float(value) == floor(float(value))

static func valid_position(location: String, position: Vector2, opened_gates: Dictionary = {}) -> bool:
	var size: Vector2 = LocationData.MAP_SIZE if location == "town" else (MineData.MAP_SIZE if location == "mine" else Arena.MAP_SIZE)
	if Adit.is_area(location):
		size=Adit.SIZE
	if not Rect2(Vector2.ZERO, size).has_point(position):
		return false
	var solids: Array[Rect2] = LocationData.solid_rects() if location == "town" else (MineData.solid_rects() if location == "mine" else Arena.solid_rects())
	if Adit.is_area(location):
		solids=Adit.solids(location,opened_gates)
	for rect in solids:
		# Та же окружность ступней, что в player.tscn; допускаем контакт со стеной.
		var feet := position - Vector2(0, 4)
		var closest := feet.clamp(rect.position, rect.end)
		if feet.distance_squared_to(closest) < 11.9 * 11.9:
			return false
	return true

func talk_to(npc_id: String) -> String:
	if not npc_records.has(npc_id):
		return ""
	var record: Dictionary = npc_records[npc_id]
	record["conversations"] += 1
	social.execute(self,"player",npc_id,"talk")
	return "Можем поговорить о работе и о том, что случилось в районе.\nЕсли нужна помощь или вы хотите обсудить спор — скажите.\nВыберите ответ ниже."

