extends SceneTree
const State=preload("res://scripts/simulation/world_state.gd")
const Session=preload("res://scripts/simulation/conversation_session.gd")
const Service=preload("res://scripts/simulation/save_service.gd")
var checks:=0
var failures:=0
var capture:=false
var stage: Node
var demo: Dictionary={}
func _initialize() -> void:
	capture="--capture" in OS.get_cmdline_user_args()
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if ok:
		print("PASS: ",message)
	else:
		failures+=1
		push_error(message)
func settle() -> void:
	for i in range(5):
		await physics_frame
		await process_frame
func tick(state: RefCounted, id: String) -> void:
	var held: Array[String]=[id]
	state.life.advance(0.5/float(state.life.clock.speed),held,state.player_position,state.location_id)
func approach(state: RefCounted, id: String) -> void:
	var p: Dictionary=state.life.people[id]
	state.location_id=p.location
	for offset in [Vector2(0,56),Vector2(56,0),Vector2(-56,0),Vector2(0,-56)]:
		var point: Vector2=p.position+offset
		if state.life.navigation_for(p.location).clear_segment(p.position,point):
			state.player_position=point
			return
func pause_snapshot(session: RefCounted) -> void:
	session.state.life.clock.paused=true
	var before: Dictionary=session.state.to_save()
	check(not session.choose("self").get("ok",true),"Pause blocks a world-changing conversational reply")
	session.choose("topics")
	check(session.state.to_save()==before,"Topic navigation on pause leaves the whole world unchanged")
	session.state.life.clock.paused=false
func install(scene: Node, state: RefCounted, id: String) -> void:
	scene.close_windows()
	scene.world_state=state
	scene.combat_view.state=state
	scene.player.rpg=state.rpg
	approach(state,id)
	scene.player.position=state.player_position
	scene.selected_resident=id
	scene._sync_residents(0.0,true)
	scene.player.get_node("Camera2D").reset_smoothing()
	await settle()
	scene.interact()
	await settle()
func picture(name: String) -> void:
	if not capture:
		return
	if stage!=null and stage.social_ui.direct:
		var session=stage.social_ui.dialogue.session
		tick(session.state,session.npc_id)
		stage.social_ui.refresh()
		stage._sync_residents(0.0,true)
	await create_timer(0.32).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/cinema_"+name+".png")
func run() -> void:
	var stranger:=State.new()
	approach(stranger,"test_recluse")
	var conversation:=Session.new()
	conversation.start(stranger,"test_recluse")
	check(conversation.line.contains("не знакомы"),"A first meeting uses unfamiliar cautious greeting")
	check(conversation.choices.size()<=5 and not conversation.choices.any(func(c:Dictionary):return c.id=="help"),"Opening offers topics rather than every social function")
	tick(stranger,"test_recluse")
	check(conversation.choose("self").ok and conversation.line.contains("переписчик"),"Identity question answers the actual profession")
	check(conversation.line.contains("О личном"),"A reserved personality limits personal disclosure")
	tick(stranger,"test_recluse")
	conversation.choose("topics")
	check(conversation.choose("self").ok and conversation.line.contains("уже спрашивали"),"Repeated questions are recognised")
	var reopened:=Session.new()
	reopened.start(stranger,"test_recluse")
	check(reopened._already("self"),"Previously discussed topics survive ending the encounter")
	pause_snapshot(conversation)
	var trusted:=State.new()
	approach(trusted,"test_carrier")
	trusted.life.people.test_carrier.fatigue=60
	for i in range(3):
		check(trusted.social.execute(trusted,"player","test_carrier","help").ok,"Trust earned by meaningful labour help %d"%i)
		tick(trusted,"test_carrier")
	var friend:=Session.new()
	friend.start(trusted,"test_carrier")
	check(friend.line.contains("помню вашу поддержку"),"Trusted greeting refers to actual remembered help")
	check(trusted.social.relation_view("test_carrier","player").trust>=30 and trusted.rpg.fighter.stamina<100,"Trust uses real relations and assistance costs stamina")
	evidence_checks()
	tick(trusted,"test_carrier")
	friend.choose("work")
	tick(trusted,"test_carrier")
	check(friend.choose("request_help").ok,"A conversational request creates the existing real pending request")
	for minute in range(90):
		tick(trusted,"test_carrier")
		friend.refresh_state()
		if friend.shown_reply>0:
			break
	check(friend.shown_reply>0 and friend.line.contains("помог") and trusted.social.characters.test_carrier.pending.is_empty(),"The dialogue follows an NPC's actual delayed decision without inventing an answer")
	# Seek an autonomous conflict; do not inject an argument or a fixed day.
	var city:=State.new()
	city.location_id="mine"
	city.player_position=Vector2(576,696)
	var conflict: Dictionary={}
	for minute in range(10*1440):
		city.life.advance(0.5)
		for event in city.social.history:
			if event.kind in ["argue","discontent"] and "player" not in [event.actor,event.target]:
				conflict=event.duplicate(true)
				break
		if not conflict.is_empty():
			break
	check(not conflict.is_empty(),"A real conflict emerges autonomously within ten days")
	if conflict.is_empty():
		quit(1)
		return
	var actor: String=conflict.actor
	var target: String=conflict.target
	# Read each participant's actual source memory; force no new story into the city.
	approach(city,actor)
	var a:=Session.new()
	a.start(city,actor)
	tick(city,actor)
	check(a.choose("news").ok and not a.current_event.is_empty(),"Participant discusses an event in personal memory")
	var event_id: int=a.current_event.id
	var first_version: String=a.line
	demo={"seed":city.social.seed,"conflict":conflict,"first_source":actor,"first_version":first_version,"trust":trusted.social.relation_view("test_carrier","player").trust}
	var source_target: String=str(a.current_event.target if a.current_event.actor==actor else a.current_event.actor)
	approach(city,source_target)
	var b:=Session.new()
	b.start(city,source_target)
	tick(city,source_target)
	# This is an event the other participant actually remembers, not a global-history read.
	var fact: Dictionary=city.social._source_topic(source_target,"player",{"event":event_id})
	check(not fact.is_empty(),"The second source really knows the same event")
	b.choose("conflict")
	tick(city,source_target)
	check(b.choose("detail").ok and b.line!=first_version and first_version.contains("Я поспорила") and b.line.contains("отказал"),"Two participants give different perspectives on the same conflict")
	var remembered: Dictionary={}
	for memory in city.social.characters.player.memory+city.social.characters.player.summaries:
		if int(memory.id)==event_id:
			remembered=memory
	check(remembered.get("accounts",{}).has(actor) and remembered.accounts.has(source_target),"One memory keeps two distinct attributed accounts")
	check(not remembered.witnessed and remembered.accounts[actor].basis=="account","An eyewitness report is not promoted to the player's own observation")
	check(not b.line.contains("агрессия") and not b.line.contains("Долгая цель"),"Spoken dialogue does not reveal private numerical motives")
	check(Service.save_game(city,"res://.godot/conversation_save.json").is_empty(),"Reports and dialogue topics save to a separate test slot")
	var restored:=State.new()
	check(Service.load_game(restored,"res://.godot/conversation_save.json").is_empty() and restored.social.to_save()==city.social.to_save(),"All sources, certainty, relationships and memory restore without replay")
	var bad: Dictionary=city.to_save()
	bad.social.characters.player.memory[-1]["accounts"]={"unknown":{"source":"unknown"}}
	check(not State.new().apply_save(bad),"Malformed testimony is rejected atomically")
	var unaware:=State.new()
	approach(unaware,"test_recluse")
	check(not unaware.social.execute(unaware,"player","test_recluse","ask_news",{"event":event_id}).ok,"A globally existing event ID cannot give an unaware NPC knowledge")
	var scene=load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	stage=scene
	await settle()
	scene.set_physics_process(false)
	scene.player.set_physics_process(false)
	var first_demo:=State.new()
	await install(scene,first_demo,"test_recluse")
	check(scene.social_ui.direct and scene.social_ui.window.visible and not scene.ui.visible,"Actual E opens a separate cinematic layer and hides the ordinary HUD")
	check(scene.social_ui.portrait.texture.get_height()>=300,"Dialogue uses the existing large bust instead of a magnified walking sprite")
	await picture("first_meeting")
	for size in [Vector2i(1152,720),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.content_scale_size=size
		root.size=size
		scene.social_ui._layout()
		await settle()
		var view=scene.social_ui.dialogue
		var bounds:=Rect2(Vector2.ZERO,Vector2(size))
		check(bounds.encloses(view.speech.get_global_rect()) and bounds.encloses(view.portrait.get_global_rect()),"Portrait and speech fit "+str(size))
		var safe:=true
		for button in view.buttons:
			safe=safe and bounds.encloses(button.get_global_rect()) and not button.get_global_rect().intersects(view.speech.get_global_rect())
		check(safe,"All replies fit without covering the spoken line "+str(size))
		await picture("layout_%dx%d"%[size.x,size.y])
	root.content_scale_size=Vector2i(1152,720)
	root.size=Vector2i(1152,720)
	await install(scene,trusted,"test_carrier")
	await picture("trusted")
	await install(scene,city,actor)
	# Discuss the same known event again explicitly as a follow-up.
	tick(city,actor)
	var real_memory: Dictionary=city.social._source_topic(actor,"player",{"event":event_id})
	scene.social_ui.dialogue.choose("conflict")
	tick(city,actor)
	scene.social_ui.dialogue.choose("detail")
	await picture("conflict_first")
	await settle()
	scene.social_ui.dialogue._layout()
	await settle()
	check(scene.social_ui.context.get_content_height()<=scene.social_ui.context.size.y+1,"A full conflict account is readable without clipped lines")
	await install(scene,city,source_target)
	tick(city,source_target)
	scene.social_ui.dialogue.choose("conflict")
	tick(city,source_target)
	scene.social_ui.dialogue.choose("detail")
	demo["second_source"]=source_target
	demo["second_version"]=scene.social_ui.dialogue.session.line
	if capture:
		var file:=FileAccess.open("res://.godot/cinema_demo.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(demo,"\t",true,true))
		file.close()
	await picture("conflict_other")
	await settle()
	scene.social_ui.dialogue._layout()
	await settle()
	check(scene.social_ui.context.get_content_height()<=scene.social_ui.context.size.y+1,"The other participant account also fits the spoken frame")
	if capture:
		scene.close_windows()
		scene._open_social()
		scene.social_ui.tabs.current_tab=1
		await picture("knowledge")
	# Actual ordinary pause, all other residents, safety and keyboard routing.
	scene.close_windows()
	await install(scene,State.new(),"test_smith")
	var model=scene.social_ui.dialogue.session
	var before_time: int=scene.world_state.life.clock.minute
	var before_npc: Vector2=scene.world_state.life.people.test_smith.position
	for i in range(20):
		scene._physics_process(0.1)
	check(scene.world_state.life.clock.minute>before_time and scene.world_state.life.people.test_smith.position==before_npc,"Participants stop while the rest of world time continues")
	scene.social_ui.dialogue.refresh()
	var first_button: Button=scene.social_ui.dialogue.buttons[0]
	var automatic_focus: bool=scene.get_viewport().gui_get_focus_owner()==first_button
	var arrow:=InputEventAction.new()
	arrow.action="ui_down"
	arrow.pressed=true
	Input.parse_input_event(arrow)
	await settle()
	var arrow_moved: bool=scene.get_viewport().gui_get_focus_owner()!=first_button
	arrow=InputEventAction.new()
	arrow.action="ui_up"
	arrow.pressed=true
	Input.parse_input_event(arrow)
	await settle()
	var arrow_returned: bool=scene.get_viewport().gui_get_focus_owner()==first_button
	var quick:=InputEventAction.new()
	quick.action="quick_1"
	quick.pressed=true
	scene._unhandled_input(quick)
	check(automatic_focus and arrow_moved and arrow_returned and model.topic=="self" and model.line.contains("кузнице"),"Arrow navigation and numbered answers select dialogue topics instead of combat quick slots")
	scene.social_ui.dialogue.buttons[0].grab_focus()
	var current_topic: String=model.topic
	var pause_event:=InputEventAction.new()
	pause_event.action="pause_game"
	pause_event.pressed=true
	Input.parse_input_event(pause_event)
	await settle()
	check(scene.world_state.life.clock.paused and model.topic==current_topic,"Space pauses the common clock even while a dialogue button has focus")
	var before_pause: Dictionary=scene.world_state.to_save()
	scene._physics_process(0.3)
	check(scene.world_state.to_save()==before_pause,"Tactical pause also freezes an open conversation's world")
	scene.world_state.life.clock.paused=false
	scene.world_state.life.clock.threatened=true
	scene._interrupt_conversation()
	check(not scene.social_ui.window.visible and scene.ui.visible and scene.player.input_enabled,"Threat safely interrupts the cinematic view and restores world input")
	await install(scene,State.new(),"test_smith")
	tick(scene.world_state,"test_smith")
	scene.social_ui.dialogue.choose("self")
	check(scene.save_game("res://.godot/cinema_input.json"),"Saving inside a cinematic conversation succeeds")
	check(scene.load_game("res://.godot/cinema_input.json") and not scene.social_ui.window.visible and scene.ui.visible,"Loading exits the ephemeral conversation and restores ordinary input")
	check(scene.world_state.social.characters.player.memory.any(func(m:Dictionary):return m.get("subject","")=="self"),"NPC conversation knowledge survives real scene save/load")
	check(model.state.economy.ledger.material_totals()=={"iron":10,"copper":3},"Conversations do not manufacture resources")
	scene.queue_free()
	await settle()
	print("CONVERSATION TEST: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func evidence_checks() -> void:
	var world:=State.new()
	world.location_id="mine"
	world.player_position=Vector2(576,696)
	world.life.people.test_carrier.position=Vector2(816,720)
	world.life.people.test_smith.position=Vector2(864,720)
	world.life.people.test_smith.fatigue=60
	var event: Dictionary=world.social.execute(world,"test_carrier","test_smith","help")
	world.life.people.test_carrier.position=Vector2(1056,720)
	world.social.characters.test_carrier.cooldown=0
	world.social.execute(world,"test_carrier","test_recluse","inform",{"event":event.event})
	approach(world,"test_recluse")
	var hearsay:=Session.new()
	hearsay.start(world,"test_recluse")
	tick(world,"test_recluse")
	hearsay.choose("news")
	var memory: Dictionary={}
	for entry in world.social.characters.player.memory:
		if int(entry.id)==int(event.event):
			memory=entry
	check(not memory.is_empty() and memory.accounts.test_recluse.basis=="rumour" and hearsay.provenance.contains("слух"),"A retold story retains its hearsay origin instead of becoming eyewitness evidence")
	var observed:=State.new()
	observed.player_position=Vector2(832,760)
	observed.life.people.test_carrier.position=Vector2(816,720)
	observed.life.people.test_smith.position=Vector2(864,720)
	observed.life.people.test_smith.fatigue=60
	var seen: Dictionary=observed.social.execute(observed,"test_carrier","test_smith","help")
	approach(observed,"test_carrier")
	var checked:=Session.new()
	checked.start(observed,"test_carrier")
	tick(observed,"test_carrier")
	checked.choose("news")
	var fact: Dictionary={}
	for entry in observed.social.characters.player.memory:
		if int(entry.id)==int(seen.event):
			fact=entry
	check(fact.witnessed and fact.accounts.test_carrier.basis=="verified" and checked.provenance.contains("личным наблюдением"),"Confirmation requires an actual matching personal observation")
	var unwelcoming:=State.new()
	approach(unwelcoming,"test_recluse")
	unwelcoming.social.relationship("test_recluse","player").trust=-20
	var reserved:=Session.new()
	reserved.start(unwelcoming,"test_recluse")
	tick(unwelcoming,"test_recluse")
	var knowledge: Dictionary=unwelcoming.social.characters.player.knowledge.duplicate(true)
	reserved.choose("news")
	check(reserved.line.contains("не хочу") and unwelcoming.social.characters.player.memory.all(func(m:Dictionary):return m.kind=="talk"),"An unwilling source refuses without exposing hidden facts")

	var bounded:=State.new()
	bounded.location_id="mine"
	bounded.player_position=Vector2(576,696)
	bounded.life.people.test_carrier.position=Vector2(816,720)
	bounded.life.people.test_smith.position=Vector2(864,720)
	bounded.life.people.test_smith.fatigue=60
	var speakers: Array[String]=["test_npc","test_merchant","test_guard","test_recluse"]
	for i in range(speakers.size()):
		bounded.life.people[speakers[i]].position=Vector2(832+(i%2)*40,672+floori(float(i)/2)*96)
	var incident: Dictionary=bounded.social.execute(bounded,"test_carrier","test_smith","help")
	bounded.location_id="town"
	bounded.player_position=Vector2(1112,720)
	var informed:=true
	for informant in speakers:
		bounded.life.people[informant].position=Vector2(1056,720)
		informed=informed and bounded.social.execute(bounded,informant,"player","inform",{"event":incident.event}).ok
	var reports: Dictionary={}
	for entry in bounded.social.characters.player.memory:
		if int(entry.id)==int(incident.event):
			reports=entry.get("accounts",{})
	check(informed and reports.size()==3 and reports.has(speakers[-1]),"Attributed accounts are bounded and retain the most recent source even within one minute")
	check(State.new().apply_save(bounded.to_save()),"Bounded multi-source evidence passes save validation")
