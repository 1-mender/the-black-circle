extends SceneTree
const State=preload("res://scripts/simulation/world_state.gd")
const Life=preload("res://scripts/simulation/resident_simulation.gd")
const Nav=preload("res://scripts/navigation/town_navigation.gd")
const Crowd=preload("res://scripts/navigation/crowd_navigation.gd")
var checks:=0
var failures:=0
var capture:=false
func _initialize() -> void:
	capture="--capture" in OS.get_cmdline_user_args()
	call_deferred("run")
func check(value: bool, message: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(message)
	else:
		print("PASS: ",message)
func settle() -> void:
	for i in range(4):
		await process_frame
		await physics_frame
func fixture(count: int, nav: RefCounted) -> RefCounted:
	var life:=Life.new()
	var original: Dictionary=life.people.test_npc.duplicate(true)
	life.people.clear()
	life.navigation=nav
	for i in range(count):
		var id: String="fixture_%02d"%i
		var person: Dictionary=original.duplicate(true)
		person.id=id
		person.position=Vector2(120+(i%4)*36,120+floori(float(i)/4)*36)
		person.previous=person.position
		if count==20 and i>=10:
			person.position.x+=480
			person.previous=person.position
		person.goal=person.position+Vector2(-480 if count==20 and i>=10 else 480,0)
		person.path=[person.goal]
		life.people[id]=person
	return life
func walk(life: RefCounted, minutes: int) -> Dictionary:
	var safe:=true
	var separated:=true
	for minute in range(minutes):
		life.clock.minute+=1
		for id in life.people:
			life.people[id].previous=life.people[id].position
		for id in life.people:
			life._move(life.people[id],Vector2.INF)
			var person: Dictionary=life.people[id]
			safe=safe and life.navigation.clear_segment(person.previous,person.position)
			for other in life.people:
				if id!=other:
					separated=separated and person.position.distance_to(life.people[other].position)>=Crowd.SPACING-0.02
	return {"safe":safe,"separated":separated}
func run() -> void:
	var obstacles: Array[Rect2]=[]
	for count in [11,20]:
		var life=fixture(count,Nav.new(obstacles,Vector2(1000,600)))
		var result:=walk(life,180)
		check(result.safe and result.separated,"%d bodies stay separated throughout movement"%count)
		var arrived:=true
		var stable: Dictionary={}
		for id in life.people:
			arrived=arrived and life.people[id].position.distance_to(life.people[id].goal)<48
			stable[id]=life.people[id].position
		check(arrived,"%d residents complete crowded crossing"%count)
		walk(life,30)
		var still:=true
		for id in life.people:
			still=still and life.people[id].position==stable[id]
		check(still,"%d residents stand still without jitter after arrival"%count)

	var old_crowd=fixture(11,Nav.new(obstacles,Vector2(1000,600)))
	for id in old_crowd.people:
		old_crowd.people[id].position=Vector2(400,300)
		old_crowd.people[id].previous=Vector2(400,300)
		old_crowd.people[id].goal=Vector2(400,300)
		old_crowd.people[id].path=[]
	walk(old_crowd,120)
	var recovered:=true
	for id in old_crowd.people:
		for other in old_crowd.people:
			if id!=other:
				recovered=recovered and old_crowd.people[id].position.distance_to(old_crowd.people[other].position)>=Crowd.SPACING-0.02
	check(recovered,"Eleven coincident legacy residents gradually separate without teleporting")
	var settled: Dictionary={}
	for id in old_crowd.people:
		settled[id]=old_crowd.people[id].position
	walk(old_crowd,30)
	var quiet:=true
	for id in old_crowd.people:
		quiet=quiet and old_crowd.people[id].position.distance_to(settled[id])<0.1
	check(quiet,"Recovered group settles without repeated attempts to occupy a neighbour")
	# A 96px corridor: after wall clearance there is room for two 32px bodies.
	obstacles=[Rect2(0,0,1000,200),Rect2(0,296,1000,200)]
	var opposing=fixture(2,Nav.new(obstacles,Vector2(1000,500)))
	var ids: Array=opposing.people.keys()
	for i in range(2):
		var person: Dictionary=opposing.people[ids[i]]
		person.position=Vector2(180 if i==0 else 780,252)
		person.previous=person.position
		person.goal=Vector2(780 if i==0 else 180,252)
		person.path=[person.goal]
	var passing:=walk(opposing,180)
	check(passing.safe and passing.separated,"Head-on passing respects walls and body spacing")
	check(opposing.people[ids[0]].position.x>740 and opposing.people[ids[1]].position.x<220,"Head-on residents yield and pass through a wide enough corridor")
	var world:=State.new()
	world.life.advance(600)
	var all_separated:=true
	for id in world.life.people:
		for other in world.life.people:
			if id!=other and world.life.people[id].location==world.life.people[other].location:
				all_separated=all_separated and world.life.people[id].position.distance_to(world.life.people[other].position)>=Crowd.SPACING-0.02
	check(all_separated,"Actual eleven inhabitants do not share standing positions")
	var saved: Dictionary=world.to_save()
	var loaded:=State.new()
	check(loaded.apply_save(saved),"Crowd routes save and load")
	var legacy: Dictionary=saved.duplicate(true)
	for record in legacy.life.people.values():
		record.erase("route")
		record.erase("crowd_recovery")
	check(State.new().apply_save(legacy),"Version 0.7 saves without crowd routes remain compatible")
	var malformed: Dictionary=saved.duplicate(true)
	malformed.life.people.test_npc.route=[[300,400]]
	check(not State.new().apply_save(malformed),"A saved crowd route through a wall is rejected")
	world.life.advance(60)
	loaded.life.advance(60)
	check(world.life.to_save()==loaded.life.to_save(),"Saved routes continue deterministically")
	var scene=load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await settle()
	scene.set_physics_process(false)
	scene.player.set_physics_process(false)
	check(not scene.debug_labels,"All-name debug mode is disabled by default")
	scene.player.position=Vector2(1056,720)
	scene.world_state.player_position=scene.player.position
	var nearby: Array=scene.nearby_residents()
	check(nearby.size()>=2,"Several nearby residents can be selected")
	var first: Dictionary=scene.interaction_target()
	var cycle:=InputEventKey.new()
	cycle.physical_keycode=KEY_TAB
	cycle.pressed=true
	check(cycle.is_action_pressed("cycle_resident"),"Physical Tab is registered in project Input Map")
	scene._unhandled_input(cycle)
	var second: Dictionary=scene.interaction_target()
	check(first.get("id","")!=second.get("id","") and second.kind=="dialogue","Tab switches the unambiguous E target")
	scene.interact()
	check(scene.social_ui.window.visible and scene.social_ui.direct and scene.social_ui.selected_id==second.id,"E opens direct dialogue with exactly the selected person")
	check(scene.social_ui.portrait.texture!=null and not scene.social_ui.context.text.is_empty(),"Dialogue provides a portrait and observable context")
	scene.world_state.social.characters.player.cooldown=0
	var count_before: int=scene.world_state.social.characters[second.id].memory.size()
	scene.social_ui.actions.talk.pressed.emit()
	check(scene.world_state.social.characters[second.id].memory.size()>count_before,"Dialogue changes real social memory")
	scene.world_state.life.clock.paused=true
	var paused: Dictionary=scene.world_state.to_save()
	scene.social_ui.refresh()
	check(scene.social_ui.actions.topics.disabled==false and scene.social_ui.actions.leave.disabled==false and scene.social_ui.feedback.text.contains("Пауза"),"Paused dialogue explicitly explains unavailable actions")
	scene.social_ui.tabs.current_tab=1
	scene.social_ui.refresh()
	check(scene.world_state.to_save()==paused,"UI navigation while paused does not mutate world")
	scene.close_windows()
	scene._open_social()
	check(scene.social_ui.tabs.visible and scene.social_ui.tabs.tab_count==3,"O separates acquaintances, events and explicit developer mode")
	check(not scene.social_ui.card.text.contains("Принципы:") and not scene.social_ui.card.text.contains("привязанность"),"Ordinary card hides private psychology and numerical metrics")
	scene.social_ui.tabs.current_tab=2
	check(scene.social_ui.developer and scene.social_ui.card.text.contains("Принципы:"),"Developer tab explicitly exposes complete NPC diagnostics")
	scene.close_windows()
	scene.world_state.life.clock.paused=false
	for id in ["test_smith","test_merchant"]:
		scene.selected_resident=id
		scene.player.position=scene.resident_views[id].position+Vector2(0,60)
		scene.world_state.player_position=scene.player.position
		scene.interact()
		check(scene.social_ui.window.visible and scene.social_ui.trade_button.visible,"Shopkeeper retains direct social dialogue: "+id)
		scene.social_ui.trade_button.pressed.emit()
		check(scene.economy.window.visible and scene.economy.mode==("trade" if id=="test_smith" else "market"),"Dialogue reaches existing finite shop: "+id)
		scene.close_windows()
	scene.world_state.social.characters.player.memory.clear()
	scene.world_state.social.characters.player.summaries.clear()
	check(second.id in scene.social_ui.known_people(),"Established acquaintances survive bounded memory forgetting")
	# Unknown inhabitants in another area never appear in the player's picker.
	scene.world_state=State.new()
	scene.world_state.location_id="mine"
	scene.world_state.player_position=Vector2(576,696)
	scene.social_ui.open(scene.world_state)
	check(scene.social_ui.picker.item_count==0 and not scene.social_ui.card.text.contains("Лин"),"Unseen people and their thoughts are absent from acquaintances")
	scene.close_windows()
	scene.world_state.location_id="town"
	scene.world_state.player_position=Vector2(864,816)
	scene.player.position=Vector2(864,816)
	scene.selected_resident="test_npc"
	scene.player.position=scene.resident_views.test_npc.position+Vector2(0,60)
	scene.world_state.player_position=scene.player.position
	scene.interact()
	for size in [Vector2i(1152,720),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.content_scale_size=size
		root.size=size
		scene.social_ui._layout()
		await settle()
		var bounds: Rect2=scene.social_ui.window.get_global_rect()
		check(Rect2(Vector2.ZERO,Vector2(size)).encloses(bounds),"Dialogue fits "+str(size))
		check(not scene.ui.visible and not scene.time_ui.visible,"Cinematic dialogue replaces ordinary HUD "+str(size))
		var inside:=true
		for action in scene.social_ui.actions.values():
			if action.visible:
				inside=inside and bounds.encloses(action.get_global_rect())
		check(inside,"All social actions fit "+str(size))
		if capture:
			scene.world_state.social.characters.player.cooldown=0
			scene.social_ui.refresh()
			await settle()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/dialogue071_%dx%d.png"%[size.x,size.y])

	scene.close_windows()
	if capture:
		# Capture real observed town activity, not an empty first-minute history.
		scene.world_state.life.advance(1440)
		scene._sync_residents(0.0,true)
	scene.social_ui.open(scene.world_state)
	for size in [Vector2i(1152,720),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.content_scale_size=size
		root.size=size
		scene.social_ui._layout()
		for tab in range(3):
			scene.social_ui.tabs.current_tab=tab
			await settle()
			var bounds: Rect2=scene.social_ui.window.get_global_rect()
			check(bounds.encloses(scene.social_ui.tabs.get_global_rect()) and Rect2(Vector2.ZERO,Vector2(size)).encloses(bounds),"Journal tab %d fits %s"%[tab,str(size)])
			if capture:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://.godot/journal071_%dx%d_%d.png"%[size.x,size.y,tab])
	scene.close_windows()
	scene.set_process(false)
	for actor in scene.resident_views.values():
		actor.hide()
	var fixture_views: Dictionary={}
	for i in range(20):
		var actor=load("res://scenes/actors/npc.tscn").instantiate()
		scene.get_node("Actors").add_child(actor)
		actor.position=Vector2(720+(i%5)*38,720+floori(float(i)/5)*48)
		actor.setup_resident("Проверка %02d · только тест"%i,i%8)
		fixture_views["fixture_%02d"%i]=actor
	scene.resident_views=fixture_views
	await settle()
	scene._update_labels({"kind":"dialogue","id":"fixture_00"})
	var visible_labels:=0
	for actor in fixture_views.values():
		visible_labels+=int(actor.caption.visible)
	check(visible_labels==1,"Twenty-person fixture shows one ordinary label")
	scene.debug_labels=true
	scene._update_labels({})
	var labels_safe:=true
	var rects: Array[Rect2]=[]
	for actor in fixture_views.values():
		var rect:=Rect2(actor.position+actor.caption.position,actor.caption.size)
		for previous in rects:
			labels_safe=labels_safe and not rect.intersects(previous)
		rects.append(rect)
	check(labels_safe,"Twenty debug labels are laid out without overlapping")
	scene.debug_labels=false
	scene._update_labels({"kind":"dialogue","id":"fixture_00"})
	if capture:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/crowd071_twenty.png")
	check(scene.world_state.life.people.size()==11,"Twenty-person fixture never changes persistent population")
	scene.queue_free()
	await settle()
	print("CROWD INTERACTION TEST: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
