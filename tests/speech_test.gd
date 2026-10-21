extends "res://tests/conversation_test.gd"
const Speech=preload("res://scripts/simulation/npc_speech.gd")
const Language=preload("res://scripts/data/conversation_language.gd")
const Art=preload("res://scripts/data/conversation_art.gd")

func ready_reply(world: RefCounted) -> void:
	# Isolate conversational checks from autonomous decisions; the full city is tested below.
	world.life.clock.minute+=1
	world.social.characters.player.cooldown=0

func incident() -> Dictionary:
	var world:=State.new()
	world.location_id="mine"
	world.player_position=Vector2(576,696)
	world.life.people.test_carrier.position=Vector2(816,720)
	world.life.people.test_smith.position=Vector2(864,720)
	world.life.people.test_smith.fatigue=60
	world.life.people.test_merchant.position=Vector2(832,672)
	world.life.people.test_recluse.position=Vector2(1104,720)
	var result: Dictionary=world.social.execute(world,"test_carrier","test_smith","help")
	check(result.ok,"Fixture assistance is a real validated action")
	return {"world":world,"id":int(result.event)}

func memory(world: RefCounted, who: String, id: int) -> Dictionary:
	return world.social._source_topic(who,"player",{"event":id})

func run() -> void:
	contradiction_checks()
	var fixture:=incident()
	var world: RefCounted=fixture.world
	var id: int=fixture.id
	var own: String=Speech.account(world,"test_carrier",memory(world,"test_carrier",id))
	var recipient: String=Speech.account(world,"test_smith",memory(world,"test_smith",id))
	var witness: String=Speech.account(world,"test_merchant",memory(world,"test_merchant",id))
	check(own.begins_with("Я помог кузнецу"),"Own action uses first person and declined recipient")
	check(recipient.begins_with("Тар помог мне"),"Recipient describes help to self")
	check(witness.begins_with("Я видел, как Тар помог кузнецу"),"Eyewitness describes other people's action without becoming participant")
	check(not witness.contains("мы ") and not witness.contains("Мы "),"Witness does not claim joint participation")
	world.life.people.test_carrier.position=Vector2(1056,720)
	world.social.characters.test_carrier.cooldown=0
	check(world.social.execute(world,"test_carrier","test_recluse","inform",{"event":id}).ok,"Rumour travels through actual information transfer")
	var rumour: String=Speech.account(world,"test_recluse",memory(world,"test_recluse",id))
	check(rumour.begins_with("Говорят, Тар") and rumour.contains("Сам я этого не видел"),"Heard story explicitly disclaims eyewitness knowledge")
	# Proper names retain their capitals after the connective; no generic string lowercasing.
	check(Speech.account(world,"test_recluse",memory(world,"test_recluse",id),"source").contains("рассказал Тар"),"Source question names only the actual remembered source")
	check(Language.name_form("test_recluse",1)=="Олу" and Language.name_form("test_apprentice",2)=="Ивой","Supported names have explicit Russian cases")
	world.life.people.test_apprentice.position=Vector2(816,720)
	world.social.characters.test_apprentice.cooldown=0
	var female_help: Dictionary=world.social.execute(world,"test_apprentice","test_smith","help")
	check(female_help.ok and Speech.account(world,"test_apprentice",memory(world,"test_apprentice",int(female_help.event))).begins_with("Я помогла"),"Female actor uses matching past tense")
	approach(world,"test_recluse")
	var session:=Session.new()
	session.start(world,"test_recluse")
	ready_reply(world)
	check(session.choose("news").ok and int(session.current_event.id)==id,"Session selects the source's actual remembered claim")
	check(session.choices.any(func(c: Dictionary):return c.id=="source" and c.text.contains("узнали")),"Hearsay follow-up asks origin rather than presuming eyewitness")
	var counter: int=world.social.next_event
	ready_reply(world)
	check(session.choose("source").ok and int(session.current_event.id)==id and session.line.contains("рассказал Тар"),"Follow-up continues the same event and source")
	check(world.social.next_event==counter,"Source clarification enriches evidence without creating another event")
	var entry: Dictionary=memory(world,"player",id)
	check(entry.accounts.test_recluse.statements.size()==2,"Original report and clarification coexist in one source account")
	var count: int=entry.accounts.test_recluse.statements.size()
	for repeat in range(8):
		ready_reply(world)
		session.choose("source")
	check(world.social.next_event==counter and entry.accounts.test_recluse.statements.size()==count,"Identical retelling neither reapplies events nor duplicates knowledge")
	check(Service.save_game(world,"res://.godot/speech_save.json").is_empty(),"Speech evidence saves outside the user slot")
	var restored:=State.new()
	check(Service.load_game(restored,"res://.godot/speech_save.json").is_empty() and restored.social.to_save()==world.social.to_save(),"Saved statements and all social state restore exactly")
	approach(restored,"test_recluse")
	var reopened:=Session.new()
	reopened.start(restored,"test_recluse")
	reopened.current_event=memory(restored,"test_recluse",id)
	counter=restored.social.next_event
	ready_reply(restored)
	reopened.choose("source")
	check(restored.social.next_event==counter,"Loading does not make old testimony new again")
	var denied:=State.new()
	approach(denied,"test_recluse")
	check(not denied.social.execute(denied,"player","test_recluse","ask_news",{"event":id}).ok,"Unknown facts cannot be fetched from objective history")
	world.social.relationship("test_recluse","player").trust=-20
	ready_reply(world)
	session.choose("source")
	check(session.topic=="declined" and not session.line.contains("Тар"),"Distrust prevents disclosure even of a known fact")
	# Real autonomous disagreement supplies a causal multi-question demonstration.
	var city:=State.new()
	city.location_id="mine"
	city.player_position=Vector2(576,696)
	var conflict: Dictionary={}
	for minute in range(10*1440):
		city.life.advance(0.5)
		for event in city.social.history:
			if event.kind in ["argue","discontent"]:
				conflict=event.duplicate(true)
				break
		if not conflict.is_empty():
			break
	check(not conflict.is_empty(),"Sequence is based on an autonomous conflict, not a scripted conversation")
	var first: String=conflict.actor
	var second: String=conflict.target
	var account_a:=Speech.account(city,first,memory(city,first,int(conflict.id)))
	var account_b:=Speech.account(city,second,memory(city,second,int(conflict.id)))
	check(account_a!=account_b and account_a.begins_with("Я ") and account_b.contains("мне претензии"),"Participants express distinct first-person perspectives")
	check(city.social._conflict_known("player",first,{"event":int(conflict.id)}).is_empty(),"Opinion requires the hero to actually know the selected conflict")
	var scene=load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	stage=scene
	await settle()
	scene.set_physics_process(false)
	scene.player.set_physics_process(false)
	var script_lines: Dictionary={}
	for size in [Vector2i(1152,720),Vector2i(1920,1080)]:
		root.content_scale_size=size
		root.size=size
		# Each fixture starts with the same actual incident and a different source role.
		for speaker_id in ["test_carrier","test_merchant","test_recluse"]:
			var sample:=incident()
			var model: RefCounted=sample.world
			if speaker_id=="test_recluse":
				model.life.people.test_carrier.position=Vector2(1056,720)
				model.social.characters.test_carrier.cooldown=0
				model.social.execute(model,"test_carrier",speaker_id,"inform",{"event":sample.id})
			await install(scene,model,speaker_id)
			ready_reply(model)
			scene.social_ui.dialogue.choose("news")
			await settle()
			var view=scene.social_ui.dialogue
			check(not view.source.visible and not view.speaker.text.contains("тест") and (not view.heading.visible or view.heading.text.contains("Временный силуэт")),"No technical headings or provenance in scene: "+speaker_id+str(size))
			check(view.session.choices.size()>=2 and view.session.choices.size()<=4,"Context replies stay compact: "+speaker_id+str(size))
			check(view.context.get_content_height()<=view.context.size.y+1,"Natural account fits speech frame: "+speaker_id+str(size))
			script_lines[speaker_id]=view.session.line
			await picture("speech_%s_%dx%d"%[speaker_id,size.x,size.y])
		await install(scene,city,first)
		ready_reply(city)
		scene.social_ui.dialogue.choose("news" if scene.social_ui.dialogue.session._known_conflict().is_empty() else "conflict")
		check(not scene.social_ui.dialogue.session.choices.any(func(c:Dictionary):return c.text.contains("видели")),"A participant is not asked whether they saw their own conflict "+str(size))
		for step in ["account","detail","source","stance"]:
			if step!="account":
				ready_reply(city)
				scene.social_ui.dialogue.choose(step)
			await settle()
			check(int(scene.social_ui.dialogue.session.current_event.id)==int(conflict.id),"Conversation retains event context: "+step+str(size))
			await picture("speech_sequence_%s_%dx%d"%[step,size.x,size.y])
			if size.x==1152:
				script_lines[step]=scene.social_ui.dialogue.session.line
	check(Art.portrait_path("test_rival").ends_with("portrait_placeholder.svg") and not Art.portrait_note("test_rival").is_empty(),"Incompatible casting uses a labelled temporary silhouette")
	if capture:
		var output:=FileAccess.open("res://.godot/speech_examples.json",FileAccess.WRITE)
		output.store_string(JSON.stringify(script_lines,"\t",true,true))
		output.close()
	scene.queue_free()
	await settle()
	print("SPEECH TEST: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func contradiction_checks() -> void:
	var world:=State.new()
	world.player_position=Vector2(832,760)
	world.life.people.test_carrier.position=Vector2(816,720)
	world.life.people.test_smith.position=Vector2(864,720)
	world.life.people.test_smith.fatigue=60
	world.life.people.test_rival.position=Vector2(832,768)
	var helped: Dictionary=world.social.execute(world,"test_carrier","test_smith","help")
	var id: int=helped.event
	check(memory(world,"player",id).witnessed,"Verification fixture is personally observed before any report")
	world.life.people.test_rival.position=Vector2(1056,720)
	world.social.characters.test_rival.cooldown=0
	check(world.social.execute(world,"test_rival","test_recluse","inform",{"event":id,"distort":true}).ok,"Low-principle informant can distort a known action through the existing contract")
	var belief: Dictionary=memory(world,"test_recluse",id)
	check(belief.kind=="refuse" and Speech.account(world,"test_recluse",belief).contains("отказал"),"Speech follows perceived refusal without leaking the objective help")
	approach(world,"test_recluse")
	ready_reply(world)
	var stated: Dictionary=world.social.execute(world,"player","test_recluse","ask_news",{"event":id,"statement":Speech.account(world,"test_recluse",belief)})
	var known: Dictionary=memory(world,"player",id)
	check(stated.ok and known.kind=="help" and known.accounts.test_recluse.kind=="refuse" and known.accounts.test_recluse.basis!="verified","Contradictory hearsay is attributed while the personally observed fact remains intact")
	var trust: float=world.social.relation_view("player","test_recluse").trust
	var count: int=world.social.next_event
	ready_reply(world)
	world.social.execute(world,"player","test_recluse","ask_news",{"event":id,"statement":Speech.account(world,"test_recluse",belief)})
	check(world.social.next_event==count and world.social.relation_view("player","test_recluse").trust==trust,"Repeating a disproved story cannot repeatedly penalise trust")
	approach(world,"test_carrier")
	ready_reply(world)
	world.social.execute(world,"player","test_carrier","ask_news",{"event":id,"statement":Speech.account(world,"test_carrier",memory(world,"test_carrier",id))})
	check(known.accounts.test_carrier.basis=="verified" and known.accounts.test_recluse.kind=="refuse","Matching confirmation and contradictory version coexist with distinct certainty")
	check(State.new().apply_save(world.to_save()),"Mixed verified and false testimony survives validation")
	var legacy: Dictionary=world.to_save()
	for who in legacy.social.characters:
		for entry in legacy.social.characters[who].memory+legacy.social.characters[who].summaries:
			for informant in entry.get("accounts",{}):
				entry.accounts[informant].erase("statements")
	check(State.new().apply_save(legacy),"Older accounts without optional statement history remain loadable")
	var bad: Dictionary=world.to_save()
	for entry in bad.social.characters.player.memory:
		if int(entry.id)==id:
			entry.accounts.test_carrier.statements=[42]
	check(not State.new().apply_save(bad),"Malformed optional utterances reject the load atomically")
