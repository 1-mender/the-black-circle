extends RefCounted
## Выполняется один раз за игровую минуту после решений и перемещения жителей.
## Материалы незавершённого заказа принадлежат escrow-владельцу процесса.

const Ledger = preload("res://scripts/simulation/property_ledger.gd")
const Mine = preload("res://scripts/data/mine_location.gd")
const Settings = preload("res://scripts/data/production_definitions.gd")
var ledger: RefCounted
var catalog: RefCounted
var jobs: Dictionary = {"smith": {}, "player": {}}
var status: Dictionary = {"miner": "Ожидает рабочего времени", "smith": "Нет материалов", "merchant": "Нет готовых изделий", "player": "Нет заказа"}
var mined: Dictionary = {"test_iron_ore": 0, "test_copper_ore": 0}
var produced: Dictionary = {}
var mining_progress := 0
var site_cursor := 0
var delivery_progress := 0
var revision := 0
var material_budget: Dictionary = {}
var money_budget := 700

func _init(charges: Dictionary, player_inventory: RefCounted, definitions: RefCounted) -> void:
	catalog = definitions
	ledger = Ledger.new(charges, player_inventory, catalog)
	material_budget = ledger.material_totals()

func tick(life: RefCounted, player_location: String, player_position: Vector2) -> void:
	_miner(life)
	# Приёмка видит продукцию предыдущего шага: готовое изделие существует
	# на складе до передачи торговцу и не может быть выдано повторно.
	_merchant(life.people["test_merchant"])
	var smith: Dictionary = life.people["test_smith"]
	if smith["activity"] == "work" and smith["location"] == "town":
		if jobs["smith"].is_empty():
			for recipe_id in ["iron_tool", "copper_trinket", "iron_ingot", "copper_ingot"]:
				if start_job("smith", recipe_id):
					break
		_process_job("smith")
		if not jobs.smith.is_empty() and int(smith.get("assist_credit",0))>0:
			smith.assist_credit=int(smith.assist_credit)-1
			_process_job("smith")
	else:
		status["smith"] = "Перерыв, путь или общение с игроком"
	if not jobs["player"].is_empty():
		if player_location == "town" and player_position.distance_to(Settings.WORKBENCH) <= 88:
			_process_job("player")
		else:
			status["player"] = "Приостановлено: подойдите к верстаку"
	revision += 1

func _miner(life: RefCounted) -> void:
	var person: Dictionary = life.people["test_miner"]
	var bag = ledger.owners["npc:test_miner"]
	if person["task"] != "work" or person["activity"] != "work":
		status["miner"] = "Путь, доставка или перерыв"
		return
	if person["location"] == "town" and person["position"].distance_to(Settings.WORKBENCH) < 1:
		for id in bag.items.keys():
			ledger.transfer("npc:test_miner", "workshop", id, bag.count(id))
		if not bag.items.is_empty():
			status["miner"] = "Склад заполнен"
			return
		person["work_mode"] = "mine" if _has_ore() else "idle"
		life.refresh_assignment("test_miner")
		status["miner"] = "Руда передана на склад" if _has_ore() else "Месторождения истощены"
		return
	if person["location"] != "mine":
		status["miner"] = "Идёт в шахту"
		return
	var site: String = person["work_site"]
	if int(ledger.sources[site]) == 0:
		_select_site(person, life)
		return
	var deposit: Dictionary = Mine.DEPOSITS[site]
	var carried_amount := 0
	for amount in bag.items.values():
		carried_amount += int(amount)
	if carried_amount + int(deposit["yield"]) > Settings.CARRY_LIMIT:
		person["work_mode"] = "deliver"
		life.refresh_assignment("test_miner")
		status["miner"] = "Несёт руду на склад"
		return
	if person["position"].distance_to(deposit["position"] + Vector2(0, 64)) > 1:
		return
	mining_progress += 1
	status["miner"] = "Добыча %s: %d/%d мин." % [site, mining_progress, Settings.MINE_MINUTES]
	if mining_progress < Settings.MINE_MINUTES:
		return
	mining_progress = 0
	var amount: int = deposit["yield"]
	if ledger.transfer("source:" + site, "npc:test_miner", deposit["item_id"], amount):
		mined[deposit["item_id"]] += amount
	_select_site(person, life)

func _has_ore() -> bool:
	for amount in ledger.sources.values():
		if int(amount) > 0:
			return true
	return false

func _select_site(person: Dictionary, life: RefCounted) -> void:
	mining_progress = 0
	var sites := ["iron_01", "copper_01", "iron_02"]
	for offset in range(1, sites.size() + 1):
		var index: int = (site_cursor + offset) % sites.size()
		if int(ledger.sources[sites[index]]) > 0:
			site_cursor = index
			person["work_site"] = sites[index]
			life.refresh_assignment("test_miner")
			return
	person["work_mode"] = "deliver" if not ledger.owners["npc:test_miner"].items.is_empty() else "idle"
	life.refresh_assignment("test_miner")
	status["miner"] = "Все жилы истощены"

func start_job(actor: String, recipe_id: String) -> bool:
	if actor not in jobs or not jobs[actor].is_empty() or not catalog.recipes.has(recipe_id):
		return false
	var recipe: Dictionary = catalog.recipes[recipe_id]
	var source := "workshop" if actor == "smith" else "player"
	if not ledger.reserve(source, "process:" + actor, recipe["inputs"]):
		status[actor] = "Не хватает материалов"
		return false
	jobs[actor] = {"recipe": recipe_id, "progress": 0}
	status[actor] = "Заказ начат"
	revision += 1
	return true

func _process_job(actor: String) -> void:
	if jobs[actor].is_empty():
		status[actor] = "Нет материалов" if actor == "smith" else "Нет заказа"
		return
	var job: Dictionary = jobs[actor]
	var recipe: Dictionary = catalog.recipes[job["recipe"]]
	job["progress"] = mini(int(job["progress"]) + 1, int(recipe["minutes"]))
	status[actor] = "%s: %d/%d мин." % [recipe["name"], job["progress"], recipe["minutes"]]
	if int(job["progress"]) < int(recipe["minutes"]):
		return
	var destination: String = recipe["destination"] if actor == "smith" else "player"
	if not ledger.transform("process:" + actor, destination, recipe["inputs"], recipe["outputs"]):
		status[actor] = "Нет места для результата; материалы в заказе"
		return
	for id in recipe["outputs"]:
		produced[id] = int(produced.get(id, 0)) + int(recipe["outputs"][id])
	jobs[actor] = {}
	status[actor] = "Готово: " + recipe["name"]

func _merchant(person: Dictionary) -> void:
	if person["activity"] != "work" or person["location"] != "town":
		status["merchant"] = "Путь, общение или перерыв"
		return
	var bag = ledger.owners["npc:test_merchant"]
	if bag.items.is_empty():
		for id in catalog.shops["test_merchant"]["sell_prices"]:
			if ledger.transfer("finished", "npc:test_merchant", id, 1):
				delivery_progress = 0
				break
	if bag.items.is_empty():
		status["merchant"] = "Нет готовых изделий"
		return
	delivery_progress += 1
	status["merchant"] = "Приёмка товара: %d/%d мин." % [delivery_progress, Settings.DELIVERY_MINUTES]
	if delivery_progress >= Settings.DELIVERY_MINUTES:
		for id in bag.items.keys():
			ledger.transfer("npc:test_merchant", "shop:test_merchant", id, bag.count(id))
		delivery_progress = 0
		if not bag.items.is_empty():
			status["merchant"] = "Нет места в магазине; товар остаётся у торговца"

func to_save() -> Dictionary:
	return {"ledger": ledger.to_save(), "jobs": jobs.duplicate(true), "mined": mined.duplicate(),
		"produced": produced.duplicate(), "mining_progress": mining_progress, "site_cursor": site_cursor,
		"delivery_progress": delivery_progress, "status": status.duplicate(),
		"material_budget": material_budget.duplicate(), "money_budget": money_budget}

func load_data(data: Variant, legacy: bool = false) -> bool:
	if not data is Dictionary or not data.get("jobs") is Dictionary or not data.get("status") is Dictionary:
		return false
	if not ledger.load_data(data.get("ledger"), legacy):
		return false
	if not data.get("material_budget") is Dictionary or not Ledger.whole(data.get("money_budget"), 10000000000):
		return false
	for material in data["material_budget"]:
		if not Ledger.whole(data["material_budget"][material], 10000000000):
			return false
	var total_money := 0
	for cash in ledger.wallets.values():
		total_money += int(cash)
	if total_money != int(data["money_budget"]) or not _same_counts(ledger.material_totals(), data["material_budget"]):
		return false
	if data["jobs"].size() != 2 or data["status"].size() != 4:
		return false
	for actor in jobs:
		var job = data["jobs"].get(actor)
		if not job is Dictionary:
			return false
		var escrow: Dictionary = ledger.owners["process:" + actor].items
		if job.is_empty():
			if not escrow.is_empty():
				return false
		else:
			if job.size() != 2 or not catalog.recipes.has(job.get("recipe")):
				return false
			var recipe: Dictionary = catalog.recipes[job["recipe"]]
			if not Ledger.whole(job.get("progress"), int(recipe["minutes"])) or not _same_counts(escrow, recipe["inputs"]):
				return false
			job["progress"] = int(job["progress"])
	for key in status:
		if not data["status"].get(key) is String or data["status"][key].length() > 250:
			return false
	for entry in [["mining_progress", Settings.MINE_MINUTES - 1], ["site_cursor", 2], ["delivery_progress", Settings.DELIVERY_MINUTES - 1]]:
		if not Ledger.whole(data.get(entry[0]), entry[1]):
			return false
	for key in ["mined", "produced"]:
		if not data.get(key) is Dictionary:
			return false
		for id in data[key]:
			if not catalog.items.has(id) or not Ledger.whole(data[key][id], 1000000000):
				return false
	jobs = data["jobs"].duplicate(true)
	status = data["status"].duplicate()
	mined = data["mined"].duplicate()
	for id in ["test_iron_ore", "test_copper_ore"]:
		if not mined.has(id):
			return false
	produced = data["produced"].duplicate()
	for dictionary in [mined, produced]:
		for id in dictionary:
			dictionary[id] = int(dictionary[id])
	mining_progress = int(data["mining_progress"])
	site_cursor = int(data["site_cursor"])
	delivery_progress = int(data["delivery_progress"])
	material_budget = ledger.material_totals()
	money_budget = total_money
	return true

static func _same_counts(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for id in left:
		if not right.has(id) or int(left[id]) != int(right[id]):
			return false
	return true
