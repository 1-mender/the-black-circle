extends SceneTree
const State=preload("res://scripts/simulation/world_state.gd")
const Service=preload("res://scripts/simulation/save_service.gd")
var checks:=0
var failures:=0
func _initialize() -> void:
	call_deferred("run")
func check(ok:bool,text:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(text)
func step(state:RefCounted,seconds:float) -> void:
	for _i in range(roundi(seconds*60)):
		state.combat.update_safety(state)
		state.life.advance(1.0/60)
		state.combat.advance(state,1.0/60)
func run() -> void:
	var state:=State.new()
	state.adventure.initialize(state.economy)
	state.location_id="adit_entry"
	state.player_position=Vector2(864,480)
	state.rpg.fighter.position=state.player_position
	state.rpg.claim_kit(state.economy)
	state.combat.sync_context(state)
	state.life.clock.set_speed(60)
	check(state.combat.update_safety(state) and state.life.clock.speed==1,"Expedition threat disables acceleration before tick")
	step(state,0.1)
	check(state.combat.enemies.adit_archer.ai=="alert" and state.rpg.fighter.hp==100,"Detection has a reaction interval before attacks")
	step(state,0.5)
	check(state.combat.enemies.adit_archer.ai=="chase","Detected enemy pursues player")
	state.player_position=Vector2(240,864)
	state.rpg.fighter.position=state.player_position
	step(state,10)
	check(state.combat.enemies.adit_archer.ai in ["return","guard"],"Lost player causes return to ordinary behavior")
	step(state,10)
	check(state.combat.enemies.adit_archer.ai=="guard","Enemy finishes return home")
	state.player_position=Vector2(384,432)
	state.rpg.fighter.position=state.player_position
	for _i in range(4):
		state.combat.request_attack(state,state.combat.enemies.adit_guard.position)
		step(state,0.7)
	check(state.combat.enemies.adit_guard.hp==0,"Existing combat defeats dungeon enemy")
	check(state.economy.ledger.count("enemy:adit_guard","test_iron_ore")==0 and not state.adventure.drops.is_empty(),"Defeated enemy transfers inventory to world")
	var piles:int=state.adventure.drops.size()
	step(state,2)
	check(state.adventure.drops.size()==piles,"Dead enemy does not repeat loot creation")
	var killed_position:Vector2=state.combat.enemies.adit_guard.position
	state.player_position=killed_position
	state.rpg.fighter.position=killed_position
	var source:String=state.adventure.drops.keys()[0]
	check(state.adventure.take(state,source,"test_iron_ore",1),"Enemy loot can be picked up")
	check(state.economy.ledger.material_totals()==state.economy.material_budget,"Enemy-world-player chain conserves all material")
	state.adventure.opened.key_cache=true
	state.economy.ledger.transfer("chest:key_cache","player","test_adit_key",1)
	state.adventure.open_gate(state,"iron_gate")
	state.player_position=Vector2(1080,552)
	state.rpg.fighter.position=state.player_position
	var dropped:String=state.adventure.drop_item(state,"test_heal",1)
	check(not dropped.is_empty() and state.economy.ledger.count(dropped,"test_heal")==1,"Nonempty ground stack exists before saving")
	state.life.clock.paused=true
	check(Service.save_game(state,"res://.godot/adventure_combat_save.json").is_empty(),"Save standing in an opened gate")
	var restored:=State.new()
	check(Service.load_game(restored,"res://.godot/adventure_combat_save.json").is_empty(),"Restore opened gate geometry before position validation")
	check(restored.combat.enemies.adit_guard.hp==0 and restored.adventure.gates.iron_gate,"Defeated enemy and opened passage survive loading")
	check(restored.economy.ledger.to_save()==state.economy.ledger.to_save(),"All inventories and world loot restore")
	check(restored.adventure.drops.has(dropped) and restored.economy.ledger.count(dropped,"test_heal")==1,"Dropped item position and ownership survive loading")
	var pickup:=State.new()
	pickup.apply_save(restored.to_save())
	pickup.life.clock.paused=false
	check(pickup.adventure.take(pickup,dropped,"test_heal",1) and not pickup.adventure.take(pickup,dropped,"test_heal",1),"Saved ground item can be picked exactly once")
	var before:Dictionary=restored.to_save()
	step(restored,1)
	check(restored.to_save()==before,"Full pause freezes traps enemies and world")
	restored.life.clock.paused=false
	restored.location_id="adit_depths"
	restored.player_position=Vector2(240,816)
	restored.rpg.fighter.position=restored.player_position
	restored.combat.update_safety(restored)
	restored.location_id="adit_entry"
	restored.combat.update_safety(restored)
	check(restored.combat.enemies.adit_guard.hp==0,"Reentering does not respawn defeated enemy")
	var trap_state:=State.new()
	trap_state.adventure.initialize(trap_state.economy)
	trap_state.location_id="adit_entry"
	trap_state.player_position=Vector2(528,792)
	trap_state.rpg.fighter.position=trap_state.player_position
	trap_state.life.clock.set_speed(60)
	check(trap_state.combat.update_safety(trap_state) and trap_state.life.clock.speed==1,"Visible trap also locks unsafe speed")
	step(trap_state,0.1)
	check(trap_state.rpg.fighter.hp==100 and trap_state.adventure.traps.spikes.warning>=0,"Trap warns before impact")
	var trap_loaded:=State.new()
	check(trap_loaded.apply_save(trap_state.to_save()),"Save restores active trap warning")
	step(trap_state,0.4)
	step(trap_loaded,0.4)
	check(trap_loaded.rpg.fighter.hp==trap_state.rpg.fighter.hp and not trap_loaded.adventure.traps.spikes.armed,"Loaded trap completes once at the same time")
	check(trap_state.rpg.fighter.hp<100 and not trap_state.adventure.traps.spikes.armed,"One-shot trap affects player and deactivates")
	var hp:float=trap_state.rpg.fighter.hp
	step(trap_state,2)
	check(trap_state.rpg.fighter.hp==hp,"Spent trap does not cause repeated damage")
	var invalid:Dictionary=state.to_save()
	invalid.adventure.drops.clear()
	check(not restored.apply_save(invalid),"Inconsistent ground ownership rejected")
	var corner:=State.new()
	corner.adventure.initialize(corner.economy)
	corner.location_id="adit_entry"
	corner.player_position=Vector2(840,480)
	corner.rpg.fighter.position=corner.player_position
	for id in corner.combat.enemies:
		if id!="adit_archer":
			corner.combat.enemies[id].hp=0
	corner.combat.enemies.adit_archer.position=Vector2(600,288)
	corner.combat.enemies.adit_archer.ai="return"
	corner.combat.sync_context(corner)
	corner.life.clock.set_speed(60)
	check(not corner.combat.threatening(corner),"Enemy returning behind wall is initially out of sight")
	corner.combat.advance(corner,0.2)
	check(corner.life.clock.speed==1 and corner.rpg.fighter.hp==100,"Mid-frame discovery cancels remaining 60x budget before strikes")
	var offarea:=State.new()
	offarea.adventure.initialize(offarea.economy)
	offarea.location_id="adit_depths"
	offarea.rpg.fighter.position=Vector2(240,816)
	offarea.combat.sync_context(offarea)
	offarea.combat.projectiles.append({"position":Vector2(240,816),"direction":Vector2.RIGHT,"left":2.0,"power":20.0,"location":"adit_entry","shooter":"adit_archer"})
	step(offarea,0.5)
	check(offarea.rpg.fighter.hp==100 and offarea.combat.projectiles[0].left==2.0,"Projectiles stay in their own area across scene transitions")
	var wall:=State.new()
	wall.adventure.initialize(wall.economy)
	wall.location_id="adit_entry"
	wall.player_position=Vector2(1116,552)
	wall.rpg.fighter.position=wall.player_position
	wall.combat.sync_context(wall)
	check(not wall.combat.line_clear(Vector2(1040,552),wall.player_position),"Closed dungeon gate blocks attack line")
	wall.combat.projectiles.append({"position":Vector2(1040,552),"direction":Vector2.RIGHT,"left":2.0,"power":20.0,"location":"adit_entry","shooter":"adit_archer"})
	step(wall,0.2)
	check(wall.rpg.fighter.hp==100 and wall.combat.projectiles.is_empty(),"Dungeon projectile cannot pass a closed gate")
	print("ADVENTURE COMBAT TEST: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
