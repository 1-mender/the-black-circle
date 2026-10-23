extends RefCounted
## Выполняется один раз за игровую минуту после решений и перемещения жителей.
## Материалы незавершённого заказа принадлежат escrow-владельцу процесса.

const Ledger = preload("res://scripts/simulation/property_ledger.gd")
const Mine = preload("res://scripts/data/mine_location.gd")
const Settings = preload("res://scripts/data/production_definitions.gd")
const Occupations = preload("res://scripts/data/occupation_definitions.gd")
const Residents = preload("res://scripts/data/resident_definitions.gd")
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
var workers: Dictionary = {}

func _init(charges: Dictionary, player_inventory: RefCounted, definitions: RefCounted) -> void:
	catalog = definitions
	ledger = Ledger.new(charges, player_inventory, catalog)
	material_budget = ledger.material_totals()
	for id in Residents.PEOPLE:
		var definition: Dictionary = Residents.PEOPLE[id]
		if definition.has("legacy_production_role"):
			register_worker(id, definition.profession, true)

func register_worker(id: String, profession: String, legacy: bool = false) -> bool:
	if profession not in ["miner", "smith", "merchant"]:
		return true
	if workers.has(id):
		return false
	var actor_key := "smith" if legacy and profession == "smith" else id
	workers[id] = {"profession": profession, "legacy": legacy, "actor_key": actor_key,
		"mining_progress": 0, "site_cursor": 0, "delivery_progress": 0,
		"status": "Ожидает рабочего времени"}
	if profession == "smith" and not legacy:
		jobs[id] = {}
	return true

func regenerate_deposits(minute: int) -> void:
	if minute <= 0 or minute % Mine.REGEN_MINUTES != 0:
		return
	for site in Mine.DEPOSITS:
		var deposit: Dictionary = Mine.DEPOSITS[site]
		if int(ledger.sources[site]) >= int(deposit.charges):
			continue
		# The source is the Ledger's single stock, not a second ore inventory.
		if not ledger.replenish_source(site):
			continue
		for material in catalog.items[deposit.item_id].material:
			material_budget[material] = int(material_budget[material]) + int(deposit["yield"]) * int(catalog.items[deposit.item_id].material[material])
		revision += 1

func tick(life: RefCounted, player_location: String, player_position: Vector2) -> void:
	# Delivery sees previous work, while rotating the first worker prevents a
	# permanent ID-order monopoly on finite deposits and shared materials.
	for profession in ["miner", "merchant", "smith"]:
		var ids: Array = []
		for id in life.people:
			if workers.has(id) and workers[id].profession == profession:
				ids.append(id)
		ids.sort()
		if ids.is_empty():
			continue
		for offset in range(ids.size()):
			var id: String = ids[(life.clock.minute + offset) % ids.size()]
			var worker: Dictionary = workers[id]
			if worker.legacy and profession == "miner":
				worker.mining_progress = mining_progress
				worker.site_cursor = site_cursor
			if worker.legacy and profession == "merchant":
				worker.delivery_progress = delivery_progress
			match profession:
				"miner": _miner(life, id, worker)
				"merchant": _merchant(life.people[id], id, worker)
				"smith": _smith(life.people[id], worker)
			if worker.legacy:
				status[profession] = worker.status
				if profession == "miner":
					mining_progress = int(worker.mining_progress)
					site_cursor = int(worker.site_cursor)
				elif profession == "merchant":
					delivery_progress = int(worker.delivery_progress)
	if not jobs["player"].is_empty():
		if player_location == "town" and player_position.distance_to(Settings.WORKBENCH) <= 88:
			_process_job("player")
		else:
			status["player"] = "Приостановлено: подойдите к верстаку"
	revision += 1

func _smith(person: Dictionary, worker: Dictionary) -> void:
	var actor: String = worker.actor_key
	if person.activity != "work" or person.location != "town":
		worker.status = "Перерыв, путь или общение с игроком"
		return
	if jobs[actor].is_empty():
		for recipe_id in Occupations.ROLES.smith.recipes:
			if start_job(actor, recipe_id):
				break
	_process_job(actor)
	if not jobs[actor].is_empty() and int(person.get("assist_credit", 0)) > 0:
		person.assist_credit = int(person.assist_credit) - 1
		_process_job(actor)
	worker.status = status.smith if worker.legacy else worker.status

func _miner(life: RefCounted, id: String, worker: Dictionary) -> void:
	var person: Dictionary = life.people[id]
	var bag = ledger.owners["npc:" + id]
	if person["task"] != "work" or person["activity"] != "work":
		worker.status = "Путь, доставка или перерыв"
		return
	if person["location"] == "town" and person["position"].distance_to(Settings.WORKBENCH) <= 48:
		for item_id in bag.items.keys():
			ledger.transfer("npc:" + id, "workshop", item_id, bag.count(item_id))
		if not bag.items.is_empty():
			worker.status = "Склад заполнен"
			return
		person["work_mode"] = "mine" if _has_ore() else "idle"
		life.refresh_assignment(id)
		worker.status = "Руда передана на склад" if _has_ore() else "Месторождения истощены"
		return
	if person["location"] != "mine":
		worker.status = "Идёт в шахту"
		return
	var site: String = person["work_site"]
	if int(ledger.sources[site]) == 0:
		_select_site(person, life, id, worker)
		return
	var deposit: Dictionary = Mine.DEPOSITS[site]
	var carried_amount := 0
	for amount in bag.items.values():
		carried_amount += int(amount)
	if carried_amount + int(deposit["yield"]) > Settings.CARRY_LIMIT:
		person["work_mode"] = "deliver"
		life.refresh_assignment(id)
		worker.status = "Несёт руду на склад"
		return
	if person["position"].distance_to(deposit["position"] + Vector2(0, 64)) > 1:
		return
	worker.mining_progress = int(worker.mining_progress) + 1
	worker.status = "Добыча %s: %d/%d мин." % [site, worker.mining_progress, Settings.MINE_MINUTES]
	if worker.mining_progress < Settings.MINE_MINUTES:
		return
	worker.mining_progress = 0
	var amount: int = deposit["yield"]
	if ledger.transfer("source:" + site, "npc:" + id, deposit["item_id"], amount):
		mined[deposit["item_id"]] += amount
	_select_site(person, life, id, worker)

func _has_ore() -> bool:
	for amount in ledger.sources.values():
		if int(amount) > 0:
			return true
	return false

func _select_site(person: Dictionary, life: RefCounted, id: String, worker: Dictionary) -> void:
	worker.mining_progress = 0
	var sites: Array = Occupations.ROLES.miner.sites
	for offset in range(1, sites.size() + 1):
		var index: int = (int(worker.site_cursor) + offset) % sites.size()
		if int(ledger.sources[sites[index]]) > 0:
			worker.site_cursor = index
			person["work_site"] = sites[index]
			life.refresh_assignment(id)
			return
	person["work_mode"] = "deliver" if not ledger.owners["npc:" + id].items.is_empty() else "idle"
	life.refresh_assignment(id)
	worker.status = "Все жилы истощены"

func start_job(actor: String, recipe_id: String) -> bool:
	if actor not in jobs or not jobs[actor].is_empty() or not catalog.recipes.has(recipe_id):
		return false
	var recipe: Dictionary = catalog.recipes[recipe_id]
	var source := "player" if actor == "player" else "workshop"
	if not ledger.reserve(source, _process_owner(actor), recipe["inputs"]):
		_set_status(actor, "Не хватает материалов")
		return false
	jobs[actor] = {"recipe": recipe_id, "progress": 0}
	_set_status(actor, "Заказ начат")
	revision += 1
	return true

func _process_owner(actor: String) -> String:
	return "process:" + actor if actor in ["smith", "player"] else "process:worker:" + actor

func _set_status(actor: String, message: String) -> void:
	if status.has(actor):
		status[actor] = message
	elif workers.has(actor):
		workers[actor].status = message

func _process_job(actor: String) -> void:
	if jobs[actor].is_empty():
		_set_status(actor, "Нет заказа" if actor == "player" else "Нет материалов")
		return
	var job: Dictionary = jobs[actor]
	var recipe: Dictionary = catalog.recipes[job["recipe"]]
	job["progress"] = mini(int(job["progress"]) + 1, int(recipe["minutes"]))
	_set_status(actor, "%s: %d/%d мин." % [recipe["name"], job["progress"], recipe["minutes"]])
	if int(job["progress"]) < int(recipe["minutes"]):
		return
	var destination: String = "player" if actor == "player" else recipe["destination"]
	if not ledger.transform(_process_owner(actor), destination, recipe["inputs"], recipe["outputs"]):
		_set_status(actor, "Нет места для результата; материалы в заказе")
		return
	for id in recipe["outputs"]:
		produced[id] = int(produced.get(id, 0)) + int(recipe["outputs"][id])
	jobs[actor] = {}
	_set_status(actor, "Готово: " + recipe["name"])

func _merchant(person: Dictionary, id: String, worker: Dictionary) -> void:
	if person["activity"] != "work" or person["location"] != "town":
		worker.status = "Путь, общение или перерыв"
		return
	var bag = ledger.owners["npc:" + id]
	if bag.items.is_empty():
		for item_id in catalog.shops[id]["sell_prices"]:
			if ledger.transfer("finished", "npc:" + id, item_id, 1):
				worker.delivery_progress = 0
				break
	if bag.items.is_empty():
		worker.status = "Нет готовых изделий"
		return
	worker.delivery_progress = int(worker.delivery_progress) + 1
	worker.status = "Приёмка товара: %d/%d мин." % [worker.delivery_progress, Settings.DELIVERY_MINUTES]
	if worker.delivery_progress >= Settings.DELIVERY_MINUTES:
		for item_id in bag.items.keys():
			ledger.transfer("npc:" + id, "shop:" + id, item_id, bag.count(item_id))
		worker.delivery_progress = 0
		if not bag.items.is_empty():
			worker.status = "Нет места в магазине; товар остаётся у торговца"

func to_save() -> Dictionary:
	var saved_workers: Dictionary = {}
	for id in workers:
		if workers[id].legacy:
			continue
		var worker: Dictionary = workers[id]
		saved_workers[id] = {"profession": worker.profession, "mining_progress": worker.mining_progress,
			"site_cursor": worker.site_cursor, "delivery_progress": worker.delivery_progress,
			"status": worker.status}
	return {"ledger": ledger.to_save(), "jobs": jobs.duplicate(true), "mined": mined.duplicate(),
		"produced": produced.duplicate(), "mining_progress": mining_progress, "site_cursor": site_cursor,
		"delivery_progress": delivery_progress, "status": status.duplicate(),
		"material_budget": material_budget.duplicate(), "money_budget": money_budget,
		"workers": saved_workers}

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
	if data["jobs"].size() != jobs.size() or data["status"].size() != 4:
		return false
	for actor in jobs:
		var job = data["jobs"].get(actor)
		if not job is Dictionary:
			return false
		var escrow: Dictionary = ledger.owners[_process_owner(actor)].items
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
	var saved_workers = data.get("workers", {})
	if not saved_workers is Dictionary:
		return false
	var dynamic_count := 0
	for id in workers:
		if workers[id].legacy:
			continue
		dynamic_count += 1
		var worker = saved_workers.get(id)
		if not worker is Dictionary or worker.size() != 5 or worker.get("profession") != workers[id].profession:
			return false
		if not Ledger.whole(worker.get("mining_progress"), Settings.MINE_MINUTES - 1) or not Ledger.whole(worker.get("site_cursor"), 2) or not Ledger.whole(worker.get("delivery_progress"), Settings.DELIVERY_MINUTES - 1):
			return false
		if not worker.get("status") is String or worker.status.length() > 250:
			return false
	if saved_workers.size() != dynamic_count:
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
	for id in workers:
		var worker: Dictionary = workers[id]
		if worker.legacy:
			worker.status = status[worker.profession]
			if worker.profession == "miner":
				worker.mining_progress = mining_progress
				worker.site_cursor = site_cursor
			elif worker.profession == "merchant":
				worker.delivery_progress = delivery_progress
		else:
			worker.mining_progress = int(saved_workers[id].mining_progress)
			worker.site_cursor = int(saved_workers[id].site_cursor)
			worker.delivery_progress = int(saved_workers[id].delivery_progress)
			worker.status = saved_workers[id].status
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
