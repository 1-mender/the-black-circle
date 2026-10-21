extends Node2D
## Связывает состояние, персонажей и UI. Никаких правил канона в сцене.

const LocationData = preload("res://scripts/data/test_location.gd")
const WorldState = preload("res://scripts/simulation/world_state.gd")
const RPGState = preload("res://scripts/simulation/rpg_state.gd")
const MineData = preload("res://scripts/data/mine_location.gd")
const SaveService = preload("res://scripts/simulation/save_service.gd")
const TOWN_SCENE = preload("res://scenes/locations/town.tscn")
const MINE_SCENE = preload("res://scenes/locations/mine.tscn")
const ARENA_SCENE = preload("res://scenes/locations/arena.tscn")
const Arena = preload("res://scripts/data/arena_location.gd")
const CombatView = preload("res://scripts/world/combat_view.gd")
const Adit = preload("res://scripts/data/adit_location.gd")
const ADIT_SCENE = preload("res://scenes/locations/adit.tscn")
const LootUI = preload("res://scripts/ui/loot_ui.gd")
const SkillUI = preload("res://scripts/ui/skill_ui.gd")
const Residents = preload("res://scripts/data/resident_definitions.gd")
const Production = preload("res://scripts/data/production_definitions.gd")
const MenuUI=preload("res://scripts/ui/game_menu.gd")
const Preferences=preload("res://scripts/ui/interface_preferences.gd")
var game_menu: CanvasLayer
var preferences:=Preferences.new()
var preferences_path:="user://interface.cfg"
var menu_session:=false
var menu_navigating:=false
var menu_previous_paused:=false
var last_saved_digest:=""
const INTERACTION_DISTANCE := 88.0

var world_state := WorldState.new()
var save_path := SaveService.DEFAULT_PATH
var resident_views: Dictionary = {}
var talking_npc_id := ""
var selected_resident := ""
var debug_labels := false
var hovered_resident := ""
var last_hover_point := Vector2.INF
var ui_interval := 0.0
var inventory_snapshot := ""
var combat_view: Node2D
var loot_ui: CanvasLayer
var skill_ui: CanvasLayer
var social_ui: CanvasLayer
var city_button: Button
const SocialUI = preload("res://scripts/ui/social_ui.gd")
@onready var player = $Actors/Player
@onready var npc = $Actors/NPC
@onready var ui = $GameUI
@onready var economy = $EconomyUI
@onready var smith = $Actors/Blacksmith
@onready var time_ui = $TimeUI
@onready var workshop = $WorkshopUI

func _ready() -> void:
	preferences.path=OS.get_environment("ZLATOGORYE_UI_PREFS") if preferences_path=="user://interface.cfg" and not OS.get_environment("ZLATOGORYE_UI_PREFS").is_empty() else preferences_path
	preferences.load_settings()
	game_menu=MenuUI.new()
	game_menu.show_interaction=preferences.show_interaction
	game_menu.master_volume=preferences.master_volume
	game_menu.fullscreen=preferences.fullscreen
	add_child(game_menu)
	game_menu.action_requested.connect(_menu_action)
	game_menu.interaction_changed.connect(_set_interaction_hint)
	game_menu.volume_changed.connect(_set_master_volume)
	game_menu.fullscreen_changed.connect(_set_fullscreen)
	_apply_master_volume()
	if preferences.fullscreen:
		_apply_fullscreen()
	ui.menu_requested.connect(_open_game_menu)
	ui.map_requested.connect(_toggle_map)
	world_state.cartography.observe(world_state.location_id,world_state.player_position,world_state.adventure.gates)
	social_ui=SocialUI.new()
	add_child(social_ui)
	social_ui.close_requested.connect(close_windows)
	social_ui.action_requested.connect(_social_action)
	social_ui.trade_requested.connect(_social_trade)
	city_button=Button.new()
	city_button.text="O"
	city_button.focus_mode=Control.FOCUS_NONE
	city_button.pressed.connect(_open_social)
	ui.menu_slot.add_child(city_button)
	city_button.hide()
	var dialogue_button:=Button.new()
	dialogue_button.text="Ответить / обсудить события и отношения"
	dialogue_button.pressed.connect(func():_open_social(talking_npc_id))
	ui.dialogue.get_child(0).add_child(dialogue_button)
	loot_ui = LootUI.new()
	add_child(loot_ui)
	loot_ui.close_requested.connect(close_windows)
	loot_ui.take_requested.connect(_take_loot)
	skill_ui=SkillUI.new()
	add_child(skill_ui)
	skill_ui.close_requested.connect(close_windows)
	var skills_button:=Button.new()
	skills_button.text="N"
	skills_button.tooltip_text="Навыки · N"
	skills_button.focus_mode=Control.FOCUS_NONE
	skills_button.pressed.connect(_open_skills)
	ui.menu_slot.add_child(skills_button)
	skills_button.hide()
	ui.location_label.clip_text=true
	ui.location_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	combat_view = CombatView.new()
	combat_view.state = world_state
	combat_view.z_index = 2
	add_child(combat_view)
	player.rpg = world_state.rpg
	player.position = LocationData.PLAYER_SPAWN
	player.reset_physics_interpolation()
	npc.position = LocationData.NPC_SPAWN
	smith.position = MineData.SMITH_POSITION
	ui.location_label.text = world_state.location_name
	player.get_node("Camera2D").reset_smoothing()
	move_child($ResidentDebug, 1)
	economy.sell_requested.connect(_sell)
	economy.buy_requested.connect(_buy)
	workshop.craft_requested.connect(_craft)
	workshop.transfer_requested.connect(_workshop_transfer)
	workshop.close_requested.connect(close_windows)
	economy.close_requested.connect(close_windows)
	economy.save_requested.connect(_request_save)
	economy.load_requested.connect(_request_load)
	time_ui.pause_requested.connect(_toggle_pause)
	time_ui.speed_selected.connect(_set_time_speed)
	time_ui.debug_requested.connect(time_ui.toggle_debug)
	time_ui.attach_to_hud(ui.time_slot)
	economy.attach_to_hud(ui.menu_slot)
	ui.menu_slot.move_child(ui.menu_button,ui.menu_slot.get_child_count()-1)
	ui.quick_bind_requested.connect(_bind_quick)
	economy.bind_requested.connect(_bind_quick)
	economy.equip_requested.connect(_equip)
	economy.unequip_requested.connect(_unequip)
	economy.use_requested.connect(_use_item)
	economy.kit_requested.connect(_claim_kit)
	economy.drop_requested.connect(_drop_item)
	economy.equipment_move_requested.connect(_move_equipment)
	economy.quick_move_requested.connect(_move_quick)
	ui.quick_move_requested.connect(_move_quick)
	ui.quick_requested.connect(_quick_action)
	ui.recovery_requested.connect(_recover)
	ui.defeat_load_requested.connect(_request_load)
	var resident_scene:=preload("res://scenes/actors/npc.tscn")
	var represented: Dictionary={}
	for actor in $Actors.get_children():
		if actor!=player:
			represented[actor.npc_id]=true
	for id in Residents.PEOPLE:
		if not represented.has(id):
			var actor=resident_scene.instantiate()
			actor.npc_id=id
			$Actors.add_child(actor)
	for actor in $Actors.get_children():
		if actor == player:
			continue
		resident_views[actor.npc_id] = actor
		var definition: Dictionary = Residents.PEOPLE[actor.npc_id]
		actor.setup_resident(definition["name"], definition["sprite"])
	_sync_residents(0.0, true)
	economy.refresh(world_state)
	time_ui.refresh(world_state.life, world_state.location_id, false)

func _physics_process(delta: float) -> void:
	world_state.rpg.fighter.position = player.position
	# Угроза проверяется ПЕРЕД минутными шагами жителей и боевыми таймерами.
	if world_state.combat.update_safety(world_state):
		economy.show_notice("Рядом опасность: ускорение отключено, скорость 1×")
	if menu_session and economy.mode=="inventory" and economy.window.visible and world_state.life.clock.threatened and not world_state.life.clock.paused:
		close_windows()
		economy.show_notice("Опасность рядом — инвентарь закрыт. Продолжите игру, когда будете готовы.")
	_interrupt_conversation()
	var fighter: Dictionary = world_state.rpg.fighter
	var clock = world_state.life.clock
	if not clock.paused:
		fighter.blocking = not _modal_open() and fighter.hp > 0 and fighter.attack_elapsed < 0 and fighter.dodge_left <= 0 and fighter.stamina > 0 and (Input.is_action_pressed("block") or fighter.block_left > 0)
		if fighter.blocking and Input.is_action_pressed("block"):
			fighter.facing = player.position.direction_to(get_global_mouse_position())
	var speed_before_combat:float=clock.speed
	var accepted_seconds: float = world_state.combat.advance(world_state, delta)
	if speed_before_combat>1 and clock.speed==1:
		economy.show_notice("Обнаружена опасность: скорость снижена до 1×")
	_interrupt_conversation()
	player.rpg = world_state.rpg
	player.speed = world_state.rpg.stats(world_state.catalog).move_speed
	player.time_scale = minf(1.0, clock.scale())
	var held: Array[String] = []
	if social_ui.window.visible and social_ui.direct and social_ui.dialogue.session.available and not social_ui.dialogue.session.ended and resident_views.has(social_ui.selected_id):
		var selected: Dictionary = world_state.life.people[social_ui.selected_id]
		if selected.location==world_state.location_id and selected.position.distance_to(player.position)<=140:
			held.append(social_ui.selected_id)
	if ui.dialogue.visible and not talking_npc_id.is_empty():
		held.append(talking_npc_id)
	if economy.mode == "trade":
		held.append("test_smith")
	elif economy.mode == "market":
		held.append("test_merchant")
	world_state.player_position = player.position
	# The same accepted interval reaches residents, production and social decisions.
	world_state.life.advance(accepted_seconds / clock.speed, held, player.position, world_state.location_id)
	_sync_residents(delta)
	player.input_enabled = not clock.paused and not _modal_open() and fighter.hp > 0
	if fighter.hp <= 0:
		if not ui.defeat_panel.visible:
			close_windows()
		ui.defeat_panel.show()
	else:
		ui.defeat_panel.hide()

func _sync_residents(delta: float, snap: bool = false) -> void:
	for id in resident_views:
		var actor = resident_views[id]
		var record: Dictionary = world_state.life.people[id]
		var on_map: bool = record["location"] == world_state.location_id
		var newly_visible: bool = on_map and not actor.visible
		actor.visible = on_map
		actor.collision_layer = 4 if on_map else 0
		# Невидимые представления не анимируются и не двигаются; состояние живёт отдельно.
		if on_map:
			actor.sync_resident(record, world_state.life.clock.fraction, delta, world_state.life.clock.paused, snap or newly_visible)

func _process(delta: float) -> void:
	_conversation_hud()
	if not world_state.life.clock.paused:
		world_state.cartography.observe(world_state.location_id,world_state.player_position,world_state.adventure.gates)
	ui.refresh_map(world_state,_modal_open(),delta)
	if time_ui.clock_panel.visible:
		ui.location_toast.hide()
	ui.refresh_rpg(world_state, world_state.combat.target_text() if world_state.location_id == "arena" or Adit.is_area(world_state.location_id) else "", _modal_open() or time_ui.debug_enabled)
	var target := interaction_target()
	_update_labels(target)
	ui.set_near_npc(false)
	if not target.is_empty() and not _modal_open():
		ui.prompt.text = target["prompt"]
		if target.kind=="dialogue" and nearby_residents().size()>1:
			ui.prompt.text+=" · Tab: сменить собеседника"
		ui.prompt.text=_compact_prompt(target)
		ui.prompt.visible=preferences.show_interaction and not (target.kind=="mine" and int(world_state.resources.get(target.get("id",""),0))<=0)
	ui_interval += delta
	if ui_interval >= 0.2:
		ui_interval = 0.0
		city_button.text="O •" if not world_state.social.characters.player.pending.is_empty() else "O"
		city_button.tooltip_text="Журнал известных событий и разговоры. Полные сведения доступны только при явном включении режима разработчика."
		time_ui.refresh(world_state.life, world_state.location_id, _modal_open())
		workshop.refresh(world_state)
		var snapshot := JSON.stringify(world_state.inventory.items)
		if snapshot != inventory_snapshot:
			inventory_snapshot = snapshot
			if economy.mode == "inventory":
				economy.refresh(world_state)
		if world_state.location_id == "mine":
			get_node("TestMap").queue_redraw()
		$ResidentDebug.life = world_state.life
		$ResidentDebug.selected_id = time_ui.selected_id
		$ResidentDebug.visible = time_ui.debug_panel.visible and world_state.life.people[time_ui.selected_id]["location"] == world_state.location_id
		$ResidentDebug.queue_redraw()

func can_interact() -> bool:
	if world_state.location_id != "town":
		return false
	if player.global_position.distance_to(npc.global_position) > INTERACTION_DISTANCE:
		return false
	var query := PhysicsRayQueryParameters2D.create(
		player.global_position - Vector2(0, 4), npc.global_position - Vector2(0, 4), 1)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func _reachable(point: Vector2, shorten: float = 0.0) -> bool:
	var origin: Vector2 = player.global_position - Vector2(0, 4)
	if player.global_position.distance_to(point) > INTERACTION_DISTANCE:
		return false
	var end := point - Vector2(0, 4)
	end -= origin.direction_to(end) * minf(shorten, origin.distance_to(end))
	var query := PhysicsRayQueryParameters2D.create(origin, end, 1)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func interaction_target() -> Dictionary:
	var targets: Array[Dictionary] = []
	for drop_owner in world_state.adventure.drops:
		var record: Dictionary = world_state.adventure.drops[drop_owner]
		if record.area == world_state.location_id and not world_state.economy.ledger.owners[drop_owner].items.is_empty():
			targets.append({"kind":"loot","owner":drop_owner,"position":record.position,"prompt":"[ E ]  Подобрать находки"})
	if world_state.location_id == "town":
		targets.append({"kind":"adit","position":Adit.TOWN_ENTRANCE,"prompt":"[ E ]  Заброшенная штольня · тестовая экспедиция"})
		targets.append({"kind": "arena", "position": Arena.TOWN_ENTRANCE, "prompt": "[ E ]  Боевой полигон · тестовые противники"})
		targets.append({"kind": "enter", "position": MineData.TOWN_ENTRANCE, "prompt": "[ E ]  Войти в тестовую шахту"})
		targets.append({"kind": "workshop", "position": Production.WORKBENCH, "prompt": "[ E ]  Общий склад и ремесло"})
	elif world_state.location_id == "mine":
		targets.append({"kind": "exit", "position": MineData.EXIT, "prompt": "[ E ]  Вернуться в Златогорье"})
		for deposit_id in MineData.DEPOSITS:
			var deposit: Dictionary = MineData.DEPOSITS[deposit_id]
			var remaining: int = world_state.resources[deposit_id]
			var hint := "[ E ]  %s · осталось подходов: %d" % [world_state.catalog.item_name(deposit["item_id"]), remaining]
			if remaining == 0:
				hint = "Месторождение истощено"
			targets.append({"kind": "mine", "id": deposit_id, "position": deposit["position"], "prompt": hint})
	elif world_state.location_id == "arena":
		targets.append({"kind": "arena_exit", "position": Arena.EXIT, "prompt": "[ E ]  Вернуться в Златогорье"})
	elif Adit.is_area(world_state.location_id):
		targets.append({"kind":"adit_exit","position":Vector2(144,912) if world_state.location_id=="adit_entry" else Vector2(144,864),"prompt":"[ E ]  В город" if world_state.location_id=="adit_entry" else "[ E ]  К входу штольни"})
		if world_state.location_id=="adit_entry":
			targets.append({"kind":"adit_deeper","position":Vector2(1320,384),"prompt":"[ E ]  Спуститься в глубины"})
		else:
			targets.append({"kind":"lever","position":Adit.LEVER,"prompt":"[ E ]  Повернуть ворот · расчистить проход"})
		for id in Adit.CONTAINERS:
			var record: Dictionary=Adit.CONTAINERS[id]
			if record.area==world_state.location_id:
				targets.append({"kind":"chest","id":id,"position":record.point,"prompt":"[ E ]  "+record.name})
		for id in Adit.VEINS:
			var record: Dictionary=Adit.VEINS[id]
			if record.area==world_state.location_id:
				targets.append({"kind":"adit_ore","id":id,"position":record.point,"prompt":"[ E ]  Добыть руду · запас %d" % world_state.economy.ledger.count("vein:"+id,record.item)})
		for id in Adit.GATES:
			var record: Dictionary=Adit.GATES[id]
			if record.area==world_state.location_id and not world_state.adventure.gates[id]:
				targets.append({"kind":"gate","id":id,"position":record.point,"prompt":"[ E ]  "+record.name})
		for id in Adit.TRAPS:
			var record: Dictionary=Adit.TRAPS[id]
			if record.area==world_state.location_id and world_state.adventure.traps[id].armed:
				targets.append({"kind":"trap","id":id,"position":record.point,"prompt":"[ E ]  Обезвредить ловушку"})
	for id in resident_views:
		if world_state.life.people[id]["location"] != world_state.location_id:
			continue
		var actor = resident_views[id]
		var kind := "dialogue"
		targets.append({"kind": kind, "id": id, "position": actor.position, "prompt": "[ E ]  %s%s" % [Residents.PEOPLE[id]["name"], " · продать руду" if kind == "trade" else (" · купить изделия" if kind == "market" else " · поговорить")]})
	if not selected_resident.is_empty():
		for candidate in targets:
			if candidate.get("id","")==selected_resident and candidate.kind=="dialogue" and _reachable(candidate.position):
				return candidate
		selected_resident=""
	var nearest: Dictionary = {}
	var distance := INF
	for target in targets:
		var candidate: float = player.position.distance_to(target["position"])
		if target.kind=="workshop" and candidate<=64:
			candidate-=24
		if candidate < distance and _reachable(target["position"], 30.0 if target["kind"] == "mine" else 0.0):
			nearest = target
			distance = candidate
	return nearest

func interact() -> void:
	if world_state.rpg.fighter.hp <= 0:
		return
	var target := interaction_target()
	if target.is_empty():
		return
	if world_state.life.clock.paused and target.kind!="dialogue":
		economy.show_notice("Пауза: продолжите время для взаимодействия")
		return
	if target.kind=="dialogue" and world_state.life.clock.threatened:
		economy.show_notice("Рядом опасность — сначала отойдите в безопасное место.")
		return
	match target["kind"]:
		"adit":
			change_location("adit_entry",Adit.SPAWN)
		"adit_exit":
			if world_state.location_id=="adit_entry":
				change_location("town",Adit.TOWN_RETURN)
			else:
				change_location("adit_entry",Vector2(1320,384))
		"adit_deeper":
			change_location("adit_depths",Vector2(240,816))
		"chest":
			loot_ui.open(world_state,world_state.adventure.open_chest(target.id))
		"loot":
			loot_ui.open(world_state,target.owner)
		"gate":
			var opened: bool=target.id=="iron_gate" and world_state.adventure.open_gate(world_state,target.id)
			economy.show_notice("Проход открыт" if opened else "Найдите ключ или механизм в боковом помещении")
		"lever":
			world_state.adventure.open_gate(world_state,"rubble")
			economy.show_notice("Ворот убрал завал в южном проходе")
		"trap":
			world_state.adventure.disarm(target.id)
			economy.show_notice("Ловушка обезврежена")
		"adit_ore":
			var amount: int=world_state.adventure.mine(world_state,target.id)
			economy.show_notice("Руда получена" if amount>0 else "Жила истощена или добыча недоступна")
		"arena":
			change_location("arena", Arena.SPAWN)
			economy.show_notice("Полигон: ЛКМ атака · ПКМ блок · Shift уклонение · Space пауза · Q замедление")
		"arena_exit":
			change_location("town", Arena.TOWN_RETURN)
		"dialogue":
			talking_npc_id = target["id"]
			selected_resident=talking_npc_id
			social_ui.open(world_state,talking_npc_id)
			if not world_state.life.clock.paused and social_ui.dialogue.session.available and not social_ui.dialogue.session.ended:
				_hold_resident(talking_npc_id)
			_conversation_hud()
			player.input_enabled = false
		"trade":
			_hold_resident("test_smith")
			economy.open_trade(world_state, "test_smith")
			player.input_enabled = false
		"market":
			_hold_resident("test_merchant")
			economy.open_market(world_state)
			player.input_enabled = false
		"workshop":
			workshop.open(world_state)
			player.input_enabled = false
		"enter":
			change_location("mine", MineData.SPAWN)
		"exit":
			change_location("town", MineData.TOWN_RETURN)
		"mine":
			var amount: int = world_state.mine(target["id"])
			var item_id: String = MineData.DEPOSITS[target["id"]]["item_id"]
			economy.show_notice("Получено: %s × %d" % [world_state.catalog.item_name(item_id), amount] if amount > 0 else "Добыча недоступна: жила истощена или стек заполнен.")
			get_node("TestMap").queue_redraw()
			economy.refresh(world_state)

func _hold_resident(id: String) -> void:
	# Останавливаем в видимой позиции, чтобы собеседник не прыгал вперёд на шаг.
	var record: Dictionary = world_state.life.people[id]
	var point: Vector2 = resident_views[id].position
	if world_state.life.navigation_for(record["location"]).walkable(point):
		record["position"] = point
		record["previous"] = point
	record["path"].clear()
	record["activity"] = "wait"
	record["reason"] = "conversation"
	record["next_decision"] = world_state.life.clock.minute + 1

func change_location(id: String, spawn: Vector2) -> void:
	hovered_resident=""
	selected_resident=""
	close_windows()
	if id!=world_state.location_id:
		world_state.combat.selected_id=""
		world_state.combat.queued.clear()
	var previous := get_node("TestMap")
	remove_child(previous)
	previous.queue_free()
	if Adit.is_area(id):
		world_state.adventure.initialize(world_state.economy)
	var map: Node2D = TOWN_SCENE.instantiate() if id == "town" else (MINE_SCENE.instantiate() if id == "mine" else (ADIT_SCENE.instantiate() if Adit.is_area(id) else ARENA_SCENE.instantiate()))
	map.name = "TestMap"
	if id == "mine":
		map.world_state = world_state
	elif Adit.is_area(id):
		map.world_state = world_state
		map.area = id
	add_child(map)
	move_child(map, 0)
	world_state.location_id = id
	world_state.location_name = LocationData.LOCATION_NAME if id == "town" else (MineData.LOCATION_NAME if id == "mine" else Arena.LOCATION_NAME)
	if Adit.is_area(id):
		world_state.location_name=Adit.NAMES[id]
	world_state.player_position = spawn
	player.position = spawn
	player.reset_physics_interpolation()
	world_state.rpg.fighter.position = spawn
	world_state.combat.update_safety(world_state)
	player.velocity = Vector2.ZERO
	_sync_residents(0.0, true)
	$TreeCanopies.visible = id == "town"
	$TownMarkers.visible = id == "town"
	ui.location_label.text = world_state.location_name
	ui.location_label.tooltip_text = world_state.location_name
	var camera: Camera2D = player.get_node("Camera2D")
	ui.announce_location(id)
	economy.set_location(id)
	var size: Vector2 = LocationData.MAP_SIZE if id == "town" else (MineData.MAP_SIZE if id == "mine" else Arena.MAP_SIZE)
	if Adit.is_area(id):
		size=Adit.SIZE
	camera.limit_right = int(size.x)
	camera.limit_bottom = int(size.y)
	camera.reset_smoothing()
	camera.reset_physics_interpolation()
	economy.refresh(world_state)
	time_ui.refresh(world_state.life, id, false)

func _modal_open() -> bool:
	return menu_session or ui.map_window.visible or ui.dialogue.visible or economy.window.visible or workshop.window.visible or ui.defeat_panel.visible or ui.help_panel.visible or loot_ui.window.visible or skill_ui.window.visible or social_ui.window.visible

func _open_social(target: String = "") -> void:
	var was_open: bool=social_ui.window.visible
	close_windows()
	if not was_open:
		social_ui.open(world_state,target)
		_conversation_hud()
		player.input_enabled=false

func _social_action(target: String, action: String) -> void:
	world_state.player_position=player.position
	var result: Dictionary=world_state.social.execute(world_state,"player",target,action)
	social_ui.response=result.reason
	social_ui.refresh()

func _open_skills() -> void:
	var was_open:bool=skill_ui.window.visible
	close_windows()
	if not was_open:
		skill_ui.open(world_state)
		player.input_enabled=false

func _take_loot(loot_owner: String, item: String, amount: int) -> void:
	world_state.player_position=player.position
	var record: Dictionary=world_state.adventure.owner_record(loot_owner)
	if not record.is_empty() and _reachable(record.point) and world_state.adventure.take(world_state,loot_owner,item,amount):
		economy.show_notice("Получено: %s × %d" % [world_state.catalog.item_name(item),amount])
	else:
		economy.show_notice("Подбор недоступен: проверьте паузу, расстояние и наличие вещи")
	loot_ui.refresh()

func _drop_item(id: String) -> void:
	world_state.player_position=player.position
	var result: String=world_state.adventure.drop_item(world_state,id,1)
	economy.refresh(world_state)
	economy.inventory_view.feedback("Предмет лежит рядом. Закройте окно и нажмите E, чтобы подобрать." if not result.is_empty() else "Нельзя выбросить: проверьте запас, паузу и состояние. Если заняты все 512 находок, подберите часть вещей.")

func _recover() -> void:
	var stats: Dictionary = world_state.rpg.stats(world_state.catalog)
	world_state.rpg.fighter = RPGState.new_fighter(LocationData.PLAYER_SPAWN)
	world_state.rpg.fighter.hp = stats.max_hp
	world_state.rpg.fighter.stamina = stats.max_stamina
	world_state.combat.queued.clear()
	ui.defeat_panel.hide()
	change_location("town", LocationData.PLAYER_SPAWN)
	economy.show_notice("Вы восстановились в безопасной тестовой точке")

func _quick_action(index: int) -> void:
	if _modal_open():
		return
	ui.reveal_quick.call_deferred(index)
	var action: String = world_state.rpg.quick[index]
	var applied := false
	var visual_action := action
	match action:
		"attack":
			applied = world_state.combat.request_attack(world_state, _keyboard_aim())
		"block":
			if not world_state.life.clock.paused:
				world_state.rpg.fighter.block_left = 0.8
				applied = true
		"dodge":
			applied = world_state.combat.dodge(world_state, Input.get_vector("move_left", "move_right", "move_up", "move_down"))
		_:
			if world_state.catalog.items.has(action):
				if world_state.catalog.items[action].has("heal"):
					visual_action = "heal"
					applied = _use_item(action)
				elif world_state.catalog.items[action].has("slot"):
					visual_action = "equip"
					applied = _equip(action, "")
	ui.animate_quick(index, visual_action, applied)

func _attack_aim() -> Vector2:
	var combat = world_state.combat
	if combat.enemies.has(combat.selected_id) and (world_state.location_id == "arena" or Adit.is_area(world_state.location_id)):
		return combat.enemies[combat.selected_id].position
	return get_global_mouse_position()

func _open_inventory() -> void:
	if _modal_open():
		close_windows()
	else:
		economy.open_inventory(world_state)
		player.input_enabled = false

func _bind_quick(index: int, id: String) -> void:
	var bound: bool = world_state.rpg.bind_quick(index, id, world_state.economy.ledger)
	economy.refresh(world_state)
	economy.inventory_view.feedback("Назначено в слот %d" % (index + 1) if bound else "Нельзя назначить: предмет отсутствует.")

func _move_quick(from: int, to: int) -> void:
	world_state.rpg.move_quick(from, to)
	economy.refresh(world_state)
	economy.inventory_view.feedback("Быстрые слоты переставлены")

func _move_equipment(from: String, to: String) -> void:
	var moved: bool = not world_state.life.clock.paused and world_state.rpg.move_equipment(world_state.economy.ledger, from, to)
	economy.refresh(world_state)
	economy.inventory_view.feedback("Снаряжение переставлено" if moved else "Нельзя переставить: проверьте слот, паузу и состояние персонажа.")

func _equip(id: String, slot: String) -> bool:
	var equipped: bool = not world_state.life.clock.paused and world_state.rpg.equip(world_state.economy.ledger, id, slot)
	economy.refresh(world_state)
	economy.inventory_view.feedback("Предмет экипирован" if equipped else "Нельзя надеть: неподходящий слот, нет предмета, пауза или действие ещё не завершено.")
	return equipped

func _unequip(slot: String) -> void:
	var removed: bool = not world_state.life.clock.paused and world_state.rpg.unequip(world_state.economy.ledger, slot)
	economy.refresh(world_state)
	economy.inventory_view.feedback("Предмет возвращён в сумку" if removed else "Нельзя снять: пауза, слот пуст или действие ещё не завершено.")

func _use_item(id: String) -> bool:
	var used: bool = not world_state.life.clock.paused and world_state.rpg.heal(world_state.economy.ledger, id)
	economy.refresh(world_state)
	economy.inventory_view.feedback("Здоровье восстановлено" if used else "Лечение недоступно: полное HP, перерыв, пауза или нет предмета.")
	return used

func _claim_kit() -> void:
	if not world_state.life.clock.paused:
		world_state.rpg.claim_kit(world_state.economy)
	economy.refresh(world_state)

func _at_bench() -> bool:
	return world_state.location_id == "town" and _reachable(Production.WORKBENCH) and not world_state.life.clock.paused

func _craft(recipe_id: String) -> void:
	if not workshop.window.visible or not _at_bench():
		return
	var started: bool = world_state.economy.start_job("player", recipe_id)
	economy.show_notice("Заказ начат; оставайтесь у верстака" if started else "Заказ уже идёт или не хватает материалов")
	workshop.refresh(world_state)

func _workshop_transfer(item_id: String, to_workshop: bool) -> void:
	if not workshop.window.visible or not _at_bench():
		return
	var amount: int = world_state.inventory.count(item_id) if to_workshop else 1
	var moved: bool = world_state.economy.ledger.transfer("player" if to_workshop else "workshop", "workshop" if to_workshop else "player", item_id, amount)
	if not moved:
		economy.show_notice("Передача недоступна: проверьте запас и вместимость")
	workshop.refresh(world_state)

func _buy(item_id: String, amount: int) -> void:
	if world_state.life.clock.paused or economy.mode != "market" or world_state.location_id != "town" or not _reachable(resident_views["test_merchant"].position):
		return
	var paid: int = world_state.buy(economy.shop_id, item_id, amount)
	economy.show_notice("Покупка: −%d монет" % paid if paid > 0 else "Недостаточно денег, товара или места")
	economy.refresh(world_state)

func _sell(item_id: String, amount: int) -> void:
	if world_state.life.clock.paused:
		return
	if economy.mode != "trade" or world_state.location_id != "town" or not _reachable(smith.position):
		return
	var earned: int = world_state.sell(economy.shop_id, item_id, amount)
	economy.show_notice("Продано: +%d монет" % earned if earned > 0 else "Продажа недоступна. Проверьте количество предметов и баланс.")
	economy.refresh(world_state)

func save_game(path: String = SaveService.DEFAULT_PATH) -> bool:
	world_state.player_position = player.position
	world_state.character_index = player.character_index
	world_state.facing_row = player.facing_row
	var actual_pause: bool=world_state.life.clock.paused
	if menu_session:
		world_state.life.clock.paused=menu_previous_paused
	var error: String = SaveService.save_game(world_state, path)
	if error.is_empty():
		last_saved_digest=_game_digest()
	if menu_session:
		world_state.life.clock.paused=actual_pause
	economy.show_notice("Игра сохранена · L для загрузки" if error.is_empty() else error)
	return error.is_empty()

func load_game(path: String = SaveService.DEFAULT_PATH) -> bool:
	var error: String = SaveService.load_game(world_state, path)
	if not error.is_empty():
		economy.show_notice(error)
		if menu_session and game_menu.window.visible:
			game_menu.notice(error)
		return false
	menu_session=false
	game_menu.window.hide()
	change_location(world_state.location_id, world_state.player_position)
	player.rpg = world_state.rpg
	ui.defeat_panel.visible = world_state.rpg.fighter.hp <= 0
	player.character_index = world_state.character_index
	player.facing_row = world_state.facing_row
	player.update_sprite(Vector2.ZERO, 0.0)
	last_saved_digest=_game_digest()
	economy.show_notice("Игра загружена")
	return true

func _request_save() -> void:
	save_game(save_path)

func _request_load() -> void:
	# Перестраиваем карту после завершения обработки клавиши/клика.
	load_game.call_deferred(save_path)

func _toggle_pause() -> void:
	if menu_session:
		return
	world_state.life.clock.paused = not world_state.life.clock.paused
	player.input_enabled = not world_state.life.clock.paused and not _modal_open()
	# Не используем SceneTree.paused: кнопки, загрузка и снятие паузы должны работать.
	time_ui.refresh(world_state.life, world_state.location_id, _modal_open())
	economy.refresh(world_state)
	workshop.refresh(world_state)
	loot_ui.refresh()

func _cycle_speed() -> void:
	world_state.life.clock.cycle_speed()
	time_ui.refresh(world_state.life, world_state.location_id, _modal_open())

func _set_time_speed(value: float) -> void:
	if world_state.life.clock.set_speed(value):
		time_ui.refresh(world_state.life, world_state.location_id, _modal_open())

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if menu_session:
		return
	if social_ui.direct and social_ui.window.visible:
		for index in range(5):
			if event.is_action_pressed("quick_%d"%(index+1) if index<4 else "dialogue_choice_5"):
				social_ui.dialogue.choose_number(index)
				get_viewport().set_input_as_handled()
				return
	if event.is_action_pressed("world_map"):
		_toggle_map()
	elif event.is_action_pressed("attack") and not _modal_open():
		if world_state.location_id == "arena" or Adit.is_area(world_state.location_id):
			world_state.combat.select_at(get_global_mouse_position())
		world_state.combat.request_attack(world_state, _attack_aim())
	elif event.is_action_pressed("dodge") and not _modal_open():
		world_state.combat.dodge(world_state, Input.get_vector("move_left", "move_right", "move_up", "move_down"))
	elif event.is_action_pressed("combat_speed"):
		_set_time_speed(0.25 if world_state.life.clock.speed != 0.25 else 1.0)
	elif event.is_action_pressed("quick_1"):
		_quick_action(0)
	elif event.is_action_pressed("quick_2"):
		_quick_action(1)
	elif event.is_action_pressed("quick_3"):
		_quick_action(2)
	elif event.is_action_pressed("quick_4"):
		_quick_action(3)
	elif event.is_action_pressed("save_game"):
		_request_save()
	elif event.is_action_pressed("load_game"):
		_request_load()
	elif event.is_action_pressed("pause_game"):
		_toggle_pause()
	elif event.is_action_pressed("time_speed"):
		_cycle_speed()
	elif event.is_action_pressed("npc_debug"):
		time_ui.toggle_debug()
	elif event.is_action_pressed("inventory"):
		if _modal_open():
			close_windows()
		else:
			economy.open_inventory(world_state)
			player.input_enabled = false
	elif event.is_action_pressed("skills"):
		_open_skills()
	elif event.is_action_pressed("debug_labels"):
		debug_labels=not debug_labels
	elif event.is_action_pressed("cycle_resident") and not _modal_open():
		cycle_resident()
	elif event.is_action_pressed("social_journal"):
		_open_social()
	elif event.is_action_pressed("interact"):
		if _modal_open():
			close_windows()
		else:
			interact()
	elif event.is_action_pressed("ui_cancel"):
		close_windows()
	else:
		return
	get_viewport().set_input_as_handled()

func close_windows() -> void:
	ui.map_window.hide()
	social_ui.close()
	_conversation_hud()
	skill_ui.close()
	loot_ui.close()
	ui.help_panel.hide()
	economy.close_window()
	workshop.close()
	close_dialogue()
	if menu_session and not menu_navigating and not game_menu.window.visible:
		world_state.life.clock.paused=true
		game_menu.show_page("pause")

func close_dialogue() -> void:
	ui.close_dialogue()
	talking_npc_id = ""
	player.input_enabled = not world_state.life.clock.paused

func nearby_residents() -> Array[String]:
	var result: Array[String]=[]
	for id in resident_views:
		if resident_views[id].visible and _reachable(resident_views[id].position):
			result.append(id)
	result.sort_custom(func(a:String,b:String):
		var da: float=player.position.distance_squared_to(resident_views[a].position)
		var db: float=player.position.distance_squared_to(resident_views[b].position)
		return a<b if is_equal_approx(da,db) else da<db)
	return result

func cycle_resident() -> void:
	hovered_resident=""
	var ids:=nearby_residents()
	if ids.is_empty():
		selected_resident=""
		return
	var current:=interaction_target()
	var id: String=selected_resident if not selected_resident.is_empty() else str(current.get("id",""))
	selected_resident=ids[(ids.find(id)+1)%ids.size()]

func _update_labels(target: Dictionary) -> void:
	var highlighted: String=str(target.get("id","")) if target.get("kind","")=="dialogue" else ""
	if social_ui.window.visible and social_ui.direct:
		highlighted=social_ui.selected_id
	elif not _modal_open():
		var mouse:=get_global_mouse_position()
		var moved: bool=mouse.distance_to(last_hover_point)>1
		last_hover_point=mouse
		var closest:=INF
		var under_mouse:=""
		for id in resident_views:
			var actor=resident_views[id]
			var distance: float=(actor.position-Vector2(0,24)).distance_to(mouse)
			if actor.visible and distance<24 and distance<closest:
				closest=distance
				under_mouse=id
		if moved:
			hovered_resident=under_mouse
			if not under_mouse.is_empty() and _reachable(resident_views[under_mouse].position):
				selected_resident=under_mouse
		if hovered_resident==under_mouse and not hovered_resident.is_empty():
			highlighted=hovered_resident
	var rectangles: Array[Rect2]=[]
	for id in resident_views:
		var actor=resident_views[id]
		var label: Label=actor.caption
		var display_name: String=str(Residents.PEOPLE.get(id,{}).get("name",label.text))
		label.text=display_name if debug_labels else display_name.get_slice(" · ",0).replace(" (тест)","")
		label.visible=actor.visible and (debug_labels or id==highlighted)
		if not label.visible:
			continue
		label.position=Vector2(-label.size.x/2,-70)
		var bounds:=Rect2(actor.position+label.position,label.size+Vector2(8,4))
		var searching:=true
		while searching:
			searching=false
			for previous in rectangles:
				if bounds.intersects(previous):
					bounds.position.y-=bounds.size.y+2
					searching=true
					break
		label.position=bounds.position-actor.position
		rectangles.append(bounds)

func _social_trade(target: String) -> void:
	if world_state.life.clock.paused or not _reachable(resident_views[target].position):
		social_ui.feedback.text="Торговля требует близости и продолжающегося времени."
		return
	close_windows()
	_hold_resident(target)
	if target=="test_smith":
		economy.open_trade(world_state,target)
	elif target=="test_merchant":
		economy.open_market(world_state)
	player.input_enabled=false

func _conversation_hud() -> void:
	var cinematic: bool=(social_ui.direct and social_ui.window.visible) or (game_menu!=null and game_menu.window.visible and game_menu.page=="title")
	ui.visible=not cinematic
	time_ui.visible=not cinematic
	economy.visible=not cinematic

func _interrupt_conversation() -> void:
	if social_ui.direct and social_ui.window.visible and (world_state.life.clock.threatened or world_state.rpg.fighter.hp<=0):
		close_windows()
		economy.show_notice("Опасность рядом — разговор прерван.")

# Handle cinematic shortcuts before focused buttons consume Space as ui_accept.
# The same clock and handlers are used by the rest of the game.
func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("ui_cancel"):
		if menu_session:
			if game_menu.window.visible:
				game_menu.back()
			else:
				close_windows()
				game_menu.show_page("pause")
		elif _modal_open():
			close_windows()
		else:
			_open_game_menu()
		get_viewport().set_input_as_handled()
		return
	if menu_session and (get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit):
		return
	if menu_session:
		# Mouse buttons also belong to combat actions. Let Control receive clicks first;
		# the menu modal guard below prevents any unhandled click from fighting.
		if event is InputEventMouseButton:
			return
		var shortcuts: Dictionary={"inventory":"inventory","social_journal":"journal","skills":"skills","save_game":"save","load_game":"load","world_map":"map"}
		for action in shortcuts:
			if event.is_action_pressed(action):
				_menu_action(shortcuts[action])
				get_viewport().set_input_as_handled()
				return
		if economy.inventory_view.visible:
			for index in range(4):
				if event.is_action_pressed("quick_%d"%(index+1)):
					# InventoryView handles 1–4 as bindings before _unhandled_input.
					return
		for action in ["pause_game","combat_speed","time_speed","interact","attack","block","dodge","quick_1","quick_2","quick_3","quick_4"]:
			if event.is_action_pressed(action):
				get_viewport().set_input_as_handled()
				return
	if ui!=null and ui.map_window!=null and ui.map_window.visible and not event.is_echo() and event.is_action_pressed("pause_game"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if social_ui==null or not social_ui.direct or not social_ui.window.visible or event.is_echo():
		return
	if event.is_action_pressed("pause_game"):
		_toggle_pause()
	elif event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
		close_windows()
	else:
		for index in range(5):
			if event.is_action_pressed("quick_%d"%(index+1) if index<4 else "dialogue_choice_5"):
				social_ui.dialogue.choose_number(index)
				get_viewport().set_input_as_handled()
				return
		return
	get_viewport().set_input_as_handled()

func _toggle_map() -> void:
	var opening: bool=not ui.map_window.visible
	close_windows()
	ui.map_window.visible=opening
	if opening:
		ui.full_map.refresh(world_state)
		player.input_enabled=false

func _keyboard_aim() -> Vector2:
	var combat=world_state.combat
	if combat.enemies.has(combat.selected_id) and (world_state.location_id=="arena" or Adit.is_area(world_state.location_id)):
		return combat.enemies[combat.selected_id].position
	return player.position+world_state.rpg.fighter.facing.normalized()*160.0

func _compact_prompt(target: Dictionary) -> String:
	match str(target.get("kind","")):
		"dialogue": return "E · "+preload("res://scripts/data/conversation_language.gd").display_name(str(target.get("id",target.get("npc_id","test_npc"))))
		"enter": return "E · В шахту"
		"adit": return "E · В штольню"
		"arena": return "E · На полигон"
		"workshop": return "E · Верстак"
		"mine","vein": return "E · Добывать"
		"loot": return "E · Подобрать"
		"chest": return "E · Открыть"
		"gate": return "E · Проход"
	return "E · "+str(target.get("prompt","")).replace("[ E ]","").replace("(тест)","").strip_edges().left(38)

func _open_game_menu() -> void:
	if menu_session:
		if game_menu.window.visible:
			_resume_menu()
		else:
			close_windows()
		return
	menu_previous_paused=world_state.life.clock.paused
	close_windows()
	menu_session=true
	world_state.life.clock.paused=true
	player.input_enabled=false
	time_ui.clock_panel.hide()
	game_menu.show_page("pause")

func _resume_menu() -> void:
	menu_navigating=true
	close_windows()
	game_menu.window.hide()
	menu_session=false
	world_state.life.clock.paused=menu_previous_paused
	player.input_enabled=not world_state.life.clock.paused and world_state.rpg.fighter.hp>0
	menu_navigating=false

func _menu_action(action: String) -> void:
	menu_navigating=true
	if action=="inventory" and world_state.life.clock.threatened and not menu_previous_paused:
		game_menu.notice("Опасность рядом. Сначала завершите бой или откройте инвентарь на тактической паузе для просмотра.")
		menu_navigating=false
		return
	match action:
		"resume": _resume_menu()
		"back": game_menu.back()
		"settings":
			game_menu.settings_origin=game_menu.page
			game_menu.show_page("settings")
		"controls": game_menu.show_page("controls")
		"save":
			var saved:=save_game(save_path)
			if game_menu.window.visible:
				game_menu.notice("Игра сохранена" if saved else "Не удалось сохранить. Игра остаётся открыта.")
		"load": _request_load()
		"main": game_menu.show_page("title" if not last_saved_digest.is_empty() and last_saved_digest==_game_digest() else "confirm")
		"title":
			close_windows()
			game_menu.show_page("title")
		"save_title":
			if save_game(save_path):
				game_menu.show_page("title")
			else:
				game_menu.notice("Не удалось сохранить. Данные игры остаются открыты.")
		"inventory","journal","skills","map":
			var already: bool=economy.window.visible if action=="inventory" else social_ui.window.visible if action=="journal" else skill_ui.window.visible if action=="skills" else ui.map_window.visible
			game_menu.window.hide()
			close_windows()
			if already:
				world_state.life.clock.paused=true
				game_menu.show_page("pause")
			elif action=="inventory":
				# The existing inventory uses live-time equipment and item actions.
				# Keep player input locked; restore menu pause when the window closes.
				world_state.life.clock.paused=menu_previous_paused
				economy.open_inventory(world_state)
			elif action=="journal":
				world_state.life.clock.paused=true
				_open_social()
			elif action=="skills":
				world_state.life.clock.paused=true
				_open_skills()
			else:
				world_state.life.clock.paused=true
				_toggle_map()
			player.input_enabled=false
	menu_navigating=false

func _game_digest() -> String:
	world_state.player_position=player.position
	var data: Dictionary=world_state.to_save()
	data.character.facing=player.facing_row
	data.character.sprite=player.character_index
	if menu_session:
		data.life.clock.paused=menu_previous_paused
	return JSON.stringify(data,"",true,true).sha256_text()

func _set_interaction_hint(value: bool) -> void:
	if preferences.set_interaction(value)!=OK:
		game_menu.notice("Настройка действует до выхода: файл настроек недоступен.")

func _set_master_volume(value: float) -> void:
	if preferences.set_volume(value)!=OK:
		game_menu.notice("Настройка звука действует до выхода: файл настроек недоступен.")
	_apply_master_volume()

func _apply_master_volume() -> void:
	AudioServer.set_bus_mute(0,preferences.master_volume<=0.0)
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(0.001,preferences.master_volume)))

func _set_fullscreen(value: bool) -> void:
	if preferences.set_fullscreen(value)!=OK:
		game_menu.notice("Режим экрана действует до выхода: файл настроек недоступен.")
	_apply_fullscreen()

func _apply_fullscreen() -> void:
	if DisplayServer.get_name()!="headless":
		get_window().mode=Window.MODE_FULLSCREEN if preferences.fullscreen else Window.MODE_WINDOWED
