extends RefCounted
## Единственный реестр имущества. Источники — представление общих запасов жил,
## а не вторая копия руды. Все передачи и преобразования проверяются до изменения.

const Inventory = preload("res://scripts/simulation/inventory.gd")
const Mine = preload("res://scripts/data/mine_location.gd")
const Definitions = preload("res://scripts/data/production_definitions.gd")
const Adit = preload("res://scripts/data/adit_location.gd")
const Residents = preload("res://scripts/data/resident_definitions.gd")
const MAX_MONEY := 1000000000
var owners: Dictionary = {}
var wallets: Dictionary = {}
var sources: Dictionary
var catalog: RefCounted

func _init(charges: Dictionary, player_inventory: RefCounted, definitions: RefCounted) -> void:
	sources = charges
	catalog = definitions
	for id in Definitions.OWNERS:
		owners[id] = Inventory.new()
		wallets[id] = 0
	for id in Adit.fixed_owners():
		owners[id] = Inventory.new()
		wallets[id] = 0
	for id in Residents.PEOPLE:
		for owner in ["npc:"+id,"process:social:"+id]:
			if not owners.has(owner):
				owners[owner]=Inventory.new()
				wallets[owner]=0
	owners["player"] = player_inventory
	wallets["shop:test_smith"] = 500
	wallets["shop:test_merchant"] = 200

func count(owner: String, item_id: String) -> int:
	if owner.begins_with("source:"):
		var id := owner.trim_prefix("source:")
		if Mine.DEPOSITS.has(id) and Mine.DEPOSITS[id]["item_id"] == item_id:
			return int(sources.get(id, 0)) * int(Mine.DEPOSITS[id]["yield"])
		return 0
	return owners[owner].count(item_id) if owners.has(owner) else 0

func can_add(owner: String, item_id: String, amount: int) -> bool:
	return owners.has(owner) and catalog.items.has(item_id) and amount > 0 and amount <= Inventory.MAX_COUNT - count(owner, item_id)

func transfer(from: String, to: String, item_id: String, amount: int) -> bool:
	if from == to or not can_add(to, item_id, amount) or count(from, item_id) < amount:
		return false
	if from.begins_with("source:"):
		var id := from.trim_prefix("source:")
		var batch: int = Mine.DEPOSITS[id]["yield"]
		if amount % batch != 0:
			return false
		sources[id] -= floori(float(amount) / float(batch))
	else:
		if not owners.has(from) or not owners[from].remove(item_id, amount):
			return false
	owners[to].add(item_id, amount)
	return true

func has_inputs(owner: String, inputs: Dictionary) -> bool:
	for id in inputs:
		if count(owner, id) < int(inputs[id]):
			return false
	return true

func reserve(from: String, escrow: String, inputs: Dictionary) -> bool:
	if from == escrow or not owners.has(from) or not owners.has(escrow) or not owners[escrow].items.is_empty() or not has_inputs(from, inputs):
		return false
	for id in inputs:
		if not can_add(escrow, id, int(inputs[id])):
			return false
	for id in inputs:
		transfer(from, escrow, id, int(inputs[id]))
	return true

func transform(escrow: String, destination: String, inputs: Dictionary, outputs: Dictionary) -> bool:
	if escrow == destination or not owners.has(escrow) or not has_inputs(escrow, inputs):
		return false
	for id in outputs:
		if not can_add(destination, id, int(outputs[id])):
			return false
	for id in inputs:
		owners[escrow].remove(id, int(inputs[id]))
	for id in outputs:
		owners[destination].add(id, int(outputs[id]))
	return true

func trade(seller: String, buyer: String, item_id: String, amount: int, price: int) -> int:
	if seller == buyer or not wallets.has(seller) or not wallets.has(buyer) or price <= 0 or price > MAX_MONEY or amount <= 0 or amount > Inventory.MAX_COUNT:
		return 0
	var cost := amount * price
	if cost > int(wallets[buyer]) or cost > MAX_MONEY - int(wallets[seller]):
		return 0
	if not transfer(seller, buyer, item_id, amount):
		return 0
	wallets[buyer] -= cost
	wallets[seller] += cost
	return cost

func to_save() -> Dictionary:
	var saved: Dictionary = {}
	for id in owners:
		saved[id] = owners[id].items.duplicate()
	return {"owners": saved, "wallets": wallets.duplicate()}

func load_data(data: Variant, legacy: bool = false) -> bool:
	if not data is Dictionary or not data.get("owners") is Dictionary or not data.get("wallets") is Dictionary:
		return false
	data = data.duplicate(true)
	if legacy:
		for id in owners:
			if not data["owners"].has(id):
				data["owners"][id] = {}
			if not data["wallets"].has(id):
				data["wallets"][id] = 0
	for id in data["owners"]:
		if not owners.has(id):
			if not id is String or not id.begins_with("drop:") or not id.trim_prefix("drop:").is_valid_int() or int(id.trim_prefix("drop:")) < 1 or int(id.trim_prefix("drop:")) > 512:
				return false
			owners[id] = Inventory.new()
			wallets[id] = 0
	if data["owners"].size() != owners.size() or data["wallets"].size() != wallets.size():
		return false
	for owner in owners:
		var items = data["owners"].get(owner)
		if not items is Dictionary or not whole(data["wallets"].get(owner), MAX_MONEY):
			return false
		for id in items:
			if not catalog.items.has(id) or not whole(items[id], Inventory.MAX_COUNT) or items[id] <= 0:
				return false
	for owner in owners:
		owners[owner].items.clear()
		for id in data["owners"][owner]:
			owners[owner].items[id] = int(data["owners"][owner][id])
		wallets[owner] = int(data["wallets"][owner])
	return true

func add_drop_owner(id: String) -> bool:
	if owners.has(id) or not id.begins_with("drop:"):
		return false
	owners[id] = Inventory.new()
	wallets[id] = 0
	return true

func add_resident(id: String) -> bool:
	if not id.begins_with("resident_") or owners.has("npc:" + id):
		return false
	for prefix in ["npc:", "process:social:"]:
		var owner_id: String = prefix + id
		owners[owner_id] = Inventory.new()
		wallets[owner_id] = 0
	return true

func material_totals() -> Dictionary:
	var totals := {"iron": 0, "copper": 0}
	for owner in owners:
		for id in owners[owner].items:
			for material in catalog.items[id]["material"]:
				totals[material] += count(owner, id) * int(catalog.items[id]["material"][material])
	for id in Mine.DEPOSITS:
		var item_id: String = Mine.DEPOSITS[id]["item_id"]
		for material in catalog.items[item_id]["material"]:
			totals[material] += count("source:" + id, item_id) * int(catalog.items[item_id]["material"][material])
	return totals

static func whole(value: Variant, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= maximum and float(value) == floor(float(value))
