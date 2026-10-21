extends SceneTree
const State=preload("res://scripts/simulation/world_state.gd")
const Data=preload("res://scripts/data/adit_location.gd")
const Nav=preload("res://scripts/navigation/town_navigation.gd")
var checks:=0
var failures:=0
func _initialize() -> void:
	call_deferred("run")
func check(ok:bool,text:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(text)
func run() -> void:
	var state:=State.new()
	var original:Dictionary=state.economy.ledger.material_totals()
	check(not state.adventure.initialized and original=={"iron":10,"copper":3},"Unvisited expedition does not change existing economic fixture")
	state.adventure.initialize(state.economy)
	var stock:Dictionary=state.economy.ledger.to_save()
	state.adventure.initialize(state.economy)
	check(state.economy.ledger.to_save()==stock,"Expedition initial stock is issued once")
	state.location_id="adit_entry"
	state.player_position=Data.SPAWN
	var source:String=state.adventure.open_chest("supplies")
	check(state.adventure.take(state,source,"test_sword",1),"Container transfers sword to player")
	check(not state.adventure.take(state,source,"test_sword",1),"Empty chest cannot duplicate sword")
	state.adventure.open_chest("supplies")
	check(state.economy.ledger.count(source,"test_sword")==0,"Reopening does not refill container")
	var pile:String=state.adventure.drop_item(state,"test_sword",1)
	check(not pile.is_empty() and state.inventory.count("test_sword")==0,"Player transfers item to a ground owner")
	check(state.adventure.take(state,pile,"test_sword",1),"Player picks item back up")
	check(not state.adventure.take(state,pile,"test_sword",1),"Same ground item cannot be taken twice")
	check(state.economy.ledger.material_totals()==state.economy.material_budget,"All expedition loot and transfers conserve material")
	check(not state.adventure.open_gate(state,"iron_gate"),"Gate requires key")
	var closed_nav:=Nav.new(Data.solids("adit_entry",state.adventure.gates),Data.SIZE)
	check(closed_nav.path(Data.SPAWN,Vector2(1320,384)).is_empty(),"Locked gate really blocks access to deeper section")
	state.player_position=Vector2(240,240)
	state.adventure.open_chest("key_cache")
	check(state.adventure.take(state,"chest:key_cache","test_adit_key",1),"Key found in branching room")
	check(state.adventure.open_gate(state,"iron_gate"),"Found key opens passage")
	for area in Data.AREAS:
		var nav:=Nav.new(Data.solids(area,state.adventure.gates),Data.SIZE)
		var from:Vector2=Data.SPAWN if area=="adit_entry" else Vector2(240,816)
		var to:=Vector2(1320,384) if area=="adit_entry" else Vector2(1296,240)
		var path:Array=nav.path(from,to)
		check(not path.is_empty() and path.back().distance_to(to)<30,"Full traversable route in "+area)
		var clear:=true
		for point in path:
			clear=clear and nav.clear_segment(from,point)
			from=point
		check(clear,"Route does not cross walls in "+area)
	var scene=load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await physics_frame
	scene.player.position=Data.TOWN_ENTRANCE
	await physics_frame
	scene.interact()
	await physics_frame
	check(scene.world_state.location_id=="adit_entry","E enters expedition from existing town")
	scene.player.position=Data.SPAWN
	scene.interact()
	check(scene.loot_ui.window.visible,"E opens supplies container")
	scene.close_windows()
	scene.player.position=Vector2(1320,384)
	scene.interact()
	check(scene.world_state.location_id=="adit_depths","E transitions to second section")
	scene.player.position=Vector2(144,864)
	scene.interact()
	check(scene.world_state.location_id=="adit_entry","E returns to first section")
	scene.player.position=Vector2(144,912)
	scene.interact()
	check(scene.world_state.location_id=="town","E returns to town")
	scene.queue_free()
	await process_frame
	print("ADVENTURE LOOT TEST: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
