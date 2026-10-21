extends SceneTree
## Полный маршрут проверяется по реальным коллизиям; бой отдельно продвигается фиксированными шагами.
const Data=preload("res://scripts/data/adit_location.gd")
const Nav=preload("res://scripts/navigation/town_navigation.gd")
const SLOT:="res://.godot/adventure_journey_save.json"
var checks:=0
var failures:=0
var scene:Node
var capture:=false
func _initialize() -> void:
	capture="--capture" in OS.get_cmdline_user_args()
	call_deferred("run")
func check(ok:bool,text:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(text)
func settle() -> void:
	for _i in range(3):
		await physics_frame
		await process_frame
func sync_position() -> void:
	scene.world_state.player_position=scene.player.position
	scene.world_state.rpg.fighter.position=scene.player.position
func walk(to:Vector2) -> void:
	var state=scene.world_state
	var navigation:=Nav.new(Data.solids(state.location_id,state.adventure.gates),Data.SIZE)
	var path:Array=navigation.path(scene.player.position,to)
	var clear:=not path.is_empty()
	for point in path:
		while scene.player.position.distance_to(point)>0.01:
			var next:Vector2=scene.player.position.move_toward(point,12)
			if scene.player.test_move(scene.player.global_transform,next-scene.player.position):
				clear=false
				break
			scene.player.position=next
		if not clear:
			break
	sync_position()
	check(clear and scene.player.position.distance_to(to)<30,"Real collider route: "+state.location_id+" -> "+str(to))
func take_all() -> void:
	var state=scene.world_state
	var source:String=scene.loot_ui.loot_owner
	for id in state.economy.ledger.owners[source].items.keys():
		scene._take_loot(source,id,state.economy.ledger.count(source,id))
	scene.close_windows()
func fight(id:String) -> void:
	var state=scene.world_state
	for _i in range(6):
		if state.combat.enemies[id].hp<=0:
			break
		state.combat.request_attack(state,state.combat.enemies[id].position)
		for _step in range(48):
			state.combat.advance(state,1.0/60)
	check(state.combat.enemies[id].hp==0 and state.rpg.fighter.hp>0,"Live encounter completed: "+id)
func shot(name:String) -> void:
	if not capture:
		return
	scene.player.get_node("Camera2D").reset_smoothing()
	await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/adventure06_"+name+".png")
func run() -> void:
	scene=load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.save_path=SLOT
	await settle()
	# Route/loot tests freeze automatic simulation; encounters explicitly advance the same combat model.
	scene.set_physics_process(false)
	scene.player.set_physics_process(false)
	scene.player.position=Data.TOWN_ENTRANCE
	sync_position()
	scene.interact()
	await settle()
	check(scene.world_state.location_id=="adit_entry","Start expedition from town without developer grant")
	walk(Data.SPAWN)
	scene.interact()
	take_all()
	scene._equip("test_sword","")
	scene._equip("test_shield","")
	check(scene.world_state.rpg.equipment.main_hand=="test_sword","Preparation uses finite found supplies")
	await shot("entry")
	walk(Vector2(384,432))
	fight("adit_guard")
	check(scene.world_state.rpg.skills.experience.melee>0,"Weapon practice earned during encounter")
	walk(Vector2(240,240))
	scene.interact()
	take_all()
	check(scene.world_state.inventory.count("test_adit_key")==1,"Branching side room provides gate key")
	walk(Vector2(1032,552))
	scene.interact()
	await settle()
	check(scene.world_state.adventure.gates.iron_gate,"Gate opens through actual E interaction")
	walk(Vector2(1320,384))
	scene.interact()
	await settle()
	check(scene.world_state.location_id=="adit_depths","Route reaches second area")
	walk(Data.LEVER)
	scene.interact()
	await settle()
	check(scene.world_state.adventure.gates.rubble,"Side lever opens alternate passage")
	walk(Vector2(240,240))
	scene.interact()
	take_all()
	check(scene.world_state.inventory.count("test_iron_ingot")==1,"Crafting material found in depth cache")
	walk(Vector2(816,816))
	fight("deep_guard")
	walk(Vector2(1296,816))
	for _i in range(3):
		scene.interact()
	check(scene.world_state.rpg.skills.rank("mining")>0,"Finite dungeon resource grants mining practice")
	walk(Vector2(1296,240))
	scene.interact()
	take_all()
	scene._equip("test_adit_ring","")
	scene._equip("test_armor","")
	check(scene.world_state.rpg.equipment.accessory_1=="test_adit_ring" and scene.world_state.rpg.stats(scene.world_state.catalog).stamina_regen==18,"Rare fixed reward provides a modest useful property")
	var heal_before:int=scene.world_state.inventory.count("test_heal")
	scene.world_state.rpg.fighter.heal_cooldown=0
	scene._use_item("test_heal")
	check(scene.world_state.rpg.fighter.hp>0 and scene.world_state.inventory.count("test_heal")==heal_before-1,"Expedition consumable used through existing item system")
	await shot("reward")
	scene._open_skills()
	await shot("skills")
	check(scene.skill_ui.window.visible,"Skills window opens from existing interface")
	for resolution in [Vector2i(1152,720),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.content_scale_size=Vector2i.ZERO
		root.size=resolution
		await settle()
		check(root.get_visible_rect().encloses(scene.skill_ui.window.get_global_rect()),"Skills UI fits "+str(resolution))
	scene.close_windows()
	root.size=Vector2i(1152,720)
	walk(Vector2(144,864))
	scene.interact()
	await settle()
	walk(Vector2(144,912))
	scene.interact()
	await settle()
	check(scene.world_state.location_id=="town","Full expedition returns to town")
	var state=scene.world_state
	var sold:int=state.sell("test_smith","test_copper_ore",1)
	check(sold==3 and state.money==3,"Found ore feeds existing trade and workshop")
	scene.player.position=scene.Production.WORKBENCH+Vector2(0,48)
	sync_position()
	scene.interact()
	scene._craft("test_sword")
	for _i in range(35):
		state.life.advance(0.5)
	check(state.inventory.count("test_sword")==1,"Found ingot becomes equipment through real timed recipe")
	check(state.economy.ledger.material_totals()==state.economy.material_budget,"Entire expedition and town cycle conserves material")
	scene.close_windows()
	var source:String=state.adventure.drop_item(state,"test_sword",1)
	check(not source.is_empty(),"Crafted item can be dropped in town")
	scene.interact()
	check(scene.loot_ui.window.visible,"Ground item can be opened in town")
	take_all()
	check(state.inventory.count("test_sword")==1,"Town ground pickup restores exactly one sword")
	check(scene.save_game(SLOT),"Complete expedition saved to isolated test slot")
	var ledger:Dictionary=state.economy.ledger.to_save()
	for _i in range(3):
		check(scene.load_game(SLOT) and state.economy.ledger.to_save()==ledger,"Repeated load preserves loot without duplication")
	check(state.expedition_combat.enemies.adit_guard.hp==0 and state.expedition_combat.enemies.deep_guard.hp==0 and state.adventure.opened.reward,"Enemy and cache completion persist after returning to town")
	check(state.rpg.skills.rank("mining")>0 and state.rpg.skills.experience.melee>0,"Expedition practice persists after loading")
	await shot("return")
	scene.queue_free()
	await process_frame
	print("ADVENTURE JOURNEY TEST: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
