extends SceneTree
const State = preload("res://scripts/simulation/world_state.gd")
const Service = preload("res://scripts/simulation/save_service.gd")
var checks := 0
var failures := 0
var capture := false
func _initialize() -> void:
	capture="--capture" in OS.get_cmdline_user_args()
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
	else:
		print("PASS: ",message)
func settle() -> void:
	for i in range(4):
		await physics_frame
		await process_frame

func run() -> void:
	var baseline: Dictionary={}
	for speed in [1.0,4.0,12.0,60.0]:
		var timed:=State.new()
		timed.social.seed=131
		timed.location_id="mine"
		timed.player_position=Vector2(576,696)
		timed.life.clock.speed=speed
		for frame in range(roundi(1440/speed)):
			timed.life.advance(0.5)
		var snapshot: Dictionary={"social":timed.social.to_save(),"people":timed.life.to_save().people,"economy":timed.economy.to_save()}
		if baseline.is_empty():
			baseline=snapshot
		check(snapshot==baseline,"Same social world after one day at %s×" % str(speed))
	var working:=State.new()
	working.location_id="mine"
	working.player_position=Vector2(576,696)
	working.mine("iron_01")
	working.economy.ledger.transfer("player","workshop","test_iron_ore",2)
	working.life.clock.minute=509
	working.life.advance(0.5)
	# Move two real workers together; material remains escrow-owned.
	working.life.people.test_carrier.position=working.life.people.test_smith.position+Vector2(-48,0)
	working.social.characters.test_carrier.cooldown=0
	working.life.people.test_smith.fatigue=40
	var progress: int=working.economy.jobs.smith.get("progress",0)
	var helped: Dictionary=working.social.execute(working,"test_carrier","test_smith","help")
	working.life.clock.minute+=4
	working.life.people.test_smith.social_hold_until=0
	working.life.people.test_smith.activity="work"
	working.life.people.test_smith.position=working.life.Definitions.PEOPLE.test_smith.work
	working.life.people.test_smith.goal=working.life.people.test_smith.position
	working.life.people.test_smith.next_decision=working.life.clock.minute+5
	working.economy.tick(working.life,working.location_id,working.player_position)
	check(helped.ok and int(working.economy.jobs.smith.get("progress",0))==progress+2,"Real help credit advances reserved production by an extra work minute")
	check(working.economy.ledger.material_totals()=={"iron":10,"copper":3},"Assisted production conserves all materials")
	check(Service.save_game(working,"res://.godot/social_disk07.json").is_empty(),"Social/economic state saved to dedicated disk slot")
	var disk:=State.new()
	check(Service.load_game(disk,"res://.godot/social_disk07.json").is_empty(),"Real JSON disk load restores new state")
	check(working.social.to_save()==disk.social.to_save(),"JSON numeric types cannot change remembered social state")
	working.life.advance(30)
	disk.life.advance(30)
	if working.social.to_save()!=disk.social.to_save() or working.economy.to_save()!=disk.economy.to_save():
		for pair in [["res://.godot/social_expected.json",working],["res://.godot/social_actual.json",disk]]:
			var diagnostic:=FileAccess.open(pair[0],FileAccess.WRITE)
			diagnostic.store_string(JSON.stringify(pair[1].to_save(),"\t",true,true))
			diagnostic.close()
	check(working.social.to_save()==disk.social.to_save() and working.economy.to_save()==disk.economy.to_save(),"After disk load, same decisions and work resume without replay")
	_psychology()
	var scene=load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await settle()
	check(scene.resident_views.size()==11,"Data definitions create all eleven visual NPCs")
	scene.world_state.life.clock.paused=true
	var paused_social: Dictionary=scene.world_state.social.to_save()
	scene._open_social("test_recluse")
	scene.social_ui.refresh()
	check(scene.world_state.social.to_save()==paused_social,"Inspecting a previously unopened card on pause cannot mutate social state")
	scene.close_windows()
	scene.world_state.life.clock.paused=false
	# Returning archer leaves a wall during this accelerated physics frame.
	scene.change_location("adit_entry",Vector2(840,480))
	for id in scene.world_state.combat.enemies:
		if id!="adit_archer":
			scene.world_state.combat.enemies[id].hp=0
	scene.world_state.combat.enemies.adit_archer.position=Vector2(600,288)
	scene.world_state.combat.enemies.adit_archer.ai="return"
	scene.world_state.combat.sync_context(scene.world_state)
	scene.world_state.life.clock.set_speed(60)
	var clock_before: float=scene.world_state.life.clock.minute+scene.world_state.life.clock.fraction
	var combat_before: float=scene.world_state.combat.elapsed+scene.world_state.combat.fraction
	scene._physics_process(0.2)
	var clock_after: float=scene.world_state.life.clock.minute+scene.world_state.life.clock.fraction
	var combat_after: float=scene.world_state.combat.elapsed+scene.world_state.combat.fraction
	check(scene.world_state.life.clock.speed==1 and scene.world_state.rpg.fighter.hp==100,"Mid-frame threat discards accelerated attack budget safely")
	check(absf((clock_after-clock_before)/2-(combat_after-combat_before))<0.000001,"Residents, social world and combat receive the same accepted time")
	scene.change_location("town",Vector2(864,816))
	scene.set_physics_process(false)
	scene.player.set_physics_process(false)
	# Read actual emergent events instead of injecting a screenplay for the UI.
	scene.world_state.life.advance(1440)
	scene._sync_residents(0.0,true)
	scene._open_social()
	check(scene.social_ui.window.visible and not scene.social_ui.developer,"Journal opens in player knowledge mode")
	check(not scene.social_ui.card.text.contains("Личная память:"),"Ordinary card cannot disclose NPC thoughts")
	if capture:
		await settle()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/social07_player.png")
	var toggle:=InputEventAction.new()
	toggle.action="social_journal"
	toggle.pressed=true
	scene._unhandled_input(toggle)
	var closed: bool=not scene.social_ui.window.visible
	scene._unhandled_input(toggle)
	check(closed and scene.social_ui.window.visible,"Mapped O action toggles the responsive journal")
	scene.player.position=scene.world_state.life.people.test_rival.position+Vector2(0,40)
	scene.world_state.player_position=scene.player.position
	scene.world_state.social.characters.player.cooldown=0
	scene.social_ui.open(scene.world_state,"test_rival")
	scene.social_ui.refresh()
	scene.social_ui.actions.talk.pressed.emit()
	check(scene.world_state.social.characters.player.last_action=="talk" and scene.world_state.social.characters.test_rival.memory[-1].actor=="player","Real dialogue button applies the validated action and persists its consequence")
	scene.close_windows()
	scene.social_ui.open(scene.world_state)
	scene.social_ui.tabs.current_tab=2
	scene.social_ui.selected_id="test_rival"
	scene.social_ui.refresh()
	check(scene.social_ui.card.text.contains("Принципы:") and scene.social_ui.card.text.contains("Причина:"),"Explicit developer card explains personality and current choice")
	for size in [Vector2i(1152,720),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.content_scale_size=size
		root.size=size
		scene.social_ui._layout()
		await settle()
		var bounds: Rect2=scene.social_ui.window.get_global_rect()
		check(Rect2(Vector2.ZERO,Vector2(size)).encloses(bounds),"Social window stays inside "+str(size))
		check(not bounds.intersects(scene.ui.header.get_global_rect()) and not bounds.intersects(scene.ui.quick_panel.get_global_rect()),"Journal avoids HUD and quick actions "+str(size))
		if capture:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/social07_%dx%d.png" % [size.x,size.y])
	scene.close_windows()
	check(not scene.social_ui.window.visible,"Escape/close path releases social modal")
	scene.queue_free()
	await settle()
	print("SOCIAL INTEGRATION TEST: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _psychology() -> void:
	var state:=State.new()
	state.adventure.initialize(state.economy)
	state.location_id="adit_entry"
	state.player_position=Vector2(912,528)
	state.rpg.fighter.position=state.player_position
	state.combat.sync_context(state)
	var archer: Dictionary=state.combat.enemies.adit_archer
	var ally: Dictionary=state.combat.enemies.adit_guard
	ally.position=Vector2(864,480)
	ally.hp=0
	archer.courage=10.0
	archer.motivation=10.0
	state.combat.advance(state,1.0/60)
	check(ally.id in archer.seen_defeats and archer.fear>0,"Visible ally defeat changes fear without omniscience")
	check(archer.ai=="flee" and archer.pursuit_refused and archer.attack_elapsed<0,"Fear cancels an attack and allows abandoning pursuit")
	var saved:=State.new()
	check(saved.apply_save(state.to_save()) and saved.combat.enemies.adit_archer.ai=="flee","Fear, retreat and observed allied losses persist")
	archer.fear=55.0
	archer.courage=50.0
	archer.motivation=100.0
	archer.ai="chase"
	archer.pursuit_refused=false
	state.combat.advance(state,1.0/60)
	check(archer.ai!="flee","Strong motivation can outweigh the same fear")
	var hidden:=State.new()
	hidden.adventure.initialize(hidden.economy)
	hidden.location_id="adit_entry"
	hidden.rpg.fighter.position=Vector2(240,864)
	hidden.combat.sync_context(hidden)
	hidden.combat.enemies.adit_guard.hp=0
	hidden.combat.advance(hidden,1.0/60)
	check(hidden.combat.enemies.adit_archer.seen_defeats.is_empty(),"A distant unseen defeat does not inform another fighter")
