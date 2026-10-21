extends SceneTree
const State = preload("res://scripts/simulation/world_state.gd")
const Service = preload("res://scripts/simulation/save_service.gd")
const Definitions = preload("res://scripts/data/resident_definitions.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
	else:
		print("PASS: ",message)

func pair(state: RefCounted, a: String, b: String) -> void:
	state.life.people[a].position=Vector2(816,720)
	state.life.people[b].position=Vector2(864,720)
	state.life.people[a].previous=state.life.people[a].position
	state.life.people[b].previous=state.life.people[b].position
	state.social.characters[a].cooldown=0
	state.social.characters[b].cooldown=0

func run() -> void:
	var state:=State.new()
	check(state.life.people.size()==11 and state.social.characters.size()==12,"Eleven data-defined residents plus player identity")
	var ids: Dictionary={}
	for id in state.life.people:
		ids[state.life.people[id].id]=true
	check(ids.size()==11,"Stable unique IDs retain all four legacy residents")
	var zero_seed: Dictionary=State.new().to_save()
	zero_seed.social.seed=0
	check(State.new().apply_save(zero_seed),"Zero is a valid reproducible LCG state and survives loading")
	check(state.social.relationship("test_rival","test_apprentice")!=state.social.relationship("test_apprentice","test_rival"),"Relationships are directed, not one friendship score")
	for id in ["test_carrier","test_recluse"]:
		state.social.characters[id].pending={"from":"test_smith","kind":"request_help","minute":480,"event":1}
	check(state.social.choose("test_carrier","test_smith",35).action!=state.social.choose("test_recluse","test_smith",35).action,"Different personalities decide differently in the same situation")
	state.social.characters.test_carrier.emotion.anger=95
	check(state.social.choose("test_carrier","test_smith",35).action=="refuse","Strong anger can outweigh a normally helpful character's principles")
	state.social.characters.test_carrier.emotion.anger=0
	state.social.characters.test_carrier.pending={}
	state.social.characters.test_recluse.pending={}
	pair(state,"test_carrier","test_smith")
	state.life.people.test_smith.fatigue=60
	state.life.people.test_recluse.position=Vector2(1440,1104)
	state.location_id="mine"
	state.player_position=Vector2(576,696)
	var before: Dictionary=state.economy.ledger.material_totals()
	var helper_fatigue: float=state.life.people.test_carrier.fatigue
	state.social.characters.test_carrier.reason="PRIVATE_HELP_INTENT"
	var helped: Dictionary=state.social.execute(state,"test_carrier","test_smith","help",{"command":"help-once"})
	check(helped.ok and state.life.people.test_smith.fatigue==48 and state.life.people.test_carrier.fatigue>helper_fatigue,"Help spends labour and changes actual fatigue")
	check(state.life.people.test_smith.assist_credit==2 and state.economy.ledger.material_totals()==before,"Help reserves a bounded labour credit without inventing material")
	check(state.social.characters.test_smith.memory[-1].witnessed and state.social.characters.test_smith.memory[-1].effects.has("delta"),"Witness memory records interpretation and actual relationship consequence")
	check(not str(state.social.characters.test_smith.memory[-1].reason).contains("PRIVATE_HELP_INTENT") and str(state.social.history[-1].reason).contains("PRIVATE_HELP_INTENT"),"Observing an act does not reveal another character's private motive")
	check(state.social.characters.test_recluse.memory.is_empty() and state.social.characters.player.memory.is_empty(),"Distant NPC and player in another area do not learn hidden events")
	var wall:=State.new()
	wall.life.people.test_carrier.position=Vector2(600,648)
	wall.life.people.test_smith.position=Vector2(600,696)
	wall.life.people.test_recluse.position=Vector2(744,648)
	wall.social.execute(wall,"test_carrier","test_smith","talk")
	check(wall.social.characters.test_recluse.memory.is_empty(),"An opaque obstacle blocks nearby observation")
	pair(state,"test_carrier","test_recluse")
	var informed: Dictionary=state.social.execute(state,"test_carrier","test_recluse","inform")
	check(informed.ok and state.social.characters.test_recluse.memory[-1].source=="test_carrier" and not state.social.characters.test_recluse.memory[-1].witnessed,"Information has a speaker and does not become a direct observation")
	state.life.clock.paused=true
	var snapshot: Dictionary=state.social.to_save()
	state.life.advance(300)
	check(state.social.to_save()==snapshot and not state.social.execute(state,"test_carrier","test_recluse","talk").ok,"Pause stops social time and rejects consequences")
	state.life.clock.paused=false
	pair(state,"test_carrier","test_smith")
	check(not state.social.execute(state,"test_carrier","test_smith","help",{"command":"help-once"}).ok,"Command receipt prevents duplicate consequence")
	var restored:=State.new()
	check(restored.apply_save(state.to_save()),"Social world loads atomically")
	check(restored.social.to_save()==state.social.to_save(),"Personality, asymmetric relations, observations and receipts restore exactly")
	pair(restored,"test_carrier","test_smith")
	check(not restored.social.execute(restored,"test_carrier","test_smith","help",{"command":"help-once"}).ok,"Receipt survives load; the event is not applied twice")
	var bad: Dictionary=state.to_save()
	bad.social.characters.test_smith.emotion.anger="bad"
	var prior: Dictionary=restored.to_save()
	check(not restored.apply_save(bad) and restored.to_save()==prior,"Bad social save leaves every current subsystem untouched")
	var old: Dictionary=State.new().to_save()
	old.version=5
	old.erase("social")
	for id in Definitions.PEOPLE:
		if id not in ["test_npc","test_smith","test_miner","test_merchant"]:
			old.life.people.erase(id)
			old.dialogues.erase(id)
			old.economy.ledger.owners.erase("npc:"+id)
			old.economy.ledger.wallets.erase("npc:"+id)
		old.economy.ledger.owners.erase("process:social:"+id)
		old.economy.ledger.wallets.erase("process:social:"+id)
	for record in old.life.people.values():
		record.erase("id")
	for battle in [old.combat,old.expedition_combat]:
		for fighter in battle.enemies.values():
			for key in ["fear","courage","motivation","seen_defeats","pursuit_refused"]:
				fighter.erase(key)
	check(State.new().apply_save(old),"Actual v5 shape with four residents and no new owners migrates")
	_drops_and_size()
	_rumours()
	_player_branch()
	var outputs: Array=[]
	for setup in [[7307,0],[187,4],[9301,8]]:
		var first: Dictionary=_ten_days(int(setup[0]),int(setup[1]))
		var second: Dictionary=_ten_days(int(setup[0]),int(setup[1]))
		check(first.snapshot==second.snapshot,"Ten days reproducible: seed %d, warehouse %d" % [setup[0],setup[1]])
		check(int(first.events)>30 and first.kinds.has("accept") and (first.kinds.has("argue") or first.kinds.has("discontent") or first.kinds.has("refuse")),"Autonomous cooperation and conflict arise from real circumstances: %d" % setup[0])
		check(first.bounded,"History, memory, summaries and knowledge remain bounded over ten days")
		check(first.conserved,"Ten days preserve iron, copper and money including social projects")
		check(first.loaded,"World restores after ten days and continues without replay")
		check(first.changed_route,"Remembered social preferences cause real travel beyond a habitual errand point")
		outputs.append({"seed":setup[0],"warehouse":setup[1],"events":first.events,"kinds":first.kinds,"chains":first.chains,"produced":first.produced})
	var file:=FileAccess.open("res://.godot/social07_stories.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(outputs,"\t"))
	file.close()
	print("SOCIAL TEST: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _ten_days(initial_seed: int, stock: int) -> Dictionary:
	var state:=State.new()
	state.social.seed=initial_seed
	state.location_id="mine"
	state.player_position=Vector2(576,696)
	var ore:=0
	while ore<stock:
		var source: String="iron_01" if state.resources.iron_01>0 else "iron_02"
		ore+=state.mine(source)
	if ore>0:
		state.economy.ledger.transfer("player","workshop","test_iron_ore",ore)
	var materials: Dictionary=state.economy.ledger.material_totals()
	var money:=0
	for cash in state.economy.ledger.wallets.values():
		money+=int(cash)
	var kinds: Dictionary={}
	var chains: Array=[]
	var sample_counts: Dictionary={}
	var last:=0
	var conserved:=true
	var changed_route:=false
	for minute in range(10*1440):
		state.life.advance(0.5)
		for id in state.life.people:
			var resident: Dictionary=state.life.people[id]
			if resident.has("social_goal") and resident.task=="errand" and resident.position!=resident.previous and resident.goal!=Definitions.PEOPLE[id].errand:
				changed_route=true
		for event in state.social.history:
			if int(event.id)>last:
				kinds[event.kind]=int(kinds.get(event.kind,0))+1
				if event.kind in ["request_help","accept","refuse","help","argue","reconcile","shortage","project","completed","deception","misinformation","inform"] and int(sample_counts.get(event.kind,0))<8:
					var sample: Dictionary=event.duplicate(true)
					for cause in state.social.history:
						if int(cause.id)==int(event.topic):
							sample["causal_event"]={"id":cause.id,"minute":cause.minute,"actor":cause.actor,"target":cause.target,"kind":cause.kind,"consequence":cause.consequence}
					chains.append(sample)
					sample_counts[event.kind]=int(sample_counts.get(event.kind,0))+1
				last=maxi(last,int(event.id))
		if minute%240==0:
			var cash:=0
			for amount in state.economy.ledger.wallets.values():
				cash+=int(amount)
			conserved=conserved and state.economy.ledger.material_totals()==materials and cash==money
	var bounded: bool=state.social.history.size()<=128
	for person in state.social.characters.values():
		bounded=bounded and person.memory.size()<=24 and person.summaries.size()<=8 and person.knowledge.size()<=12
	var loaded:=State.new()
	var slot: String="res://.godot/social_ten_days_%d.json" % initial_seed
	var valid: bool=Service.save_game(state,slot).is_empty() and Service.load_game(loaded,slot).is_empty()
	if valid:
		state.life.advance(0.5)
		loaded.life.advance(0.5)
		valid=state.social.to_save()==loaded.social.to_save() and state.economy.to_save()==loaded.economy.to_save()
	return {"snapshot":state.to_save(),"events":state.social.next_event-1,"kinds":kinds,"bounded":bounded,"conserved":conserved,"loaded":valid,"chains":chains,"changed_route":changed_route,"produced":state.economy.produced.duplicate()}

func _player_branch() -> void:
	var state:=State.new()
	pair(state,"test_rival","test_apprentice")
	state.player_position=Vector2(840,760)
	state.social.execute(state,"test_apprentice","test_rival","request_help")
	pair(state,"test_rival","test_apprentice")
	state.social.execute(state,"test_rival","test_apprentice","refuse")
	pair(state,"test_rival","test_apprentice")
	state.social.characters.test_rival.grievances.test_apprentice={"event":1,"until":660}
	var argued: Dictionary=state.social.execute(state,"test_rival","test_apprentice","argue")
	check(argued.ok and not state.social._conflict_known("player","test_rival").is_empty(),"Player can witness an actual argument")
	state.social.characters.player.cooldown=0
	var before: Dictionary=state.social.choose("test_rival","test_apprentice",20)
	state.social.characters.test_rival.emotion.anger=40
	var supported: Dictionary=state.social.execute(state,"player","test_rival","support")
	check(supported.ok and state.social.characters.test_rival.emotion.anger==24,"Player intervention changes an existing conflict emotion")
	check(state.social.characters.test_rival.memory[-1].actor=="player","Intervention is remembered by its recipient")
	state.social.characters.player.cooldown=0
	state.social.characters.test_rival.pending={}
	state.social.execute(state,"player","test_rival","request_help")
	state.social.characters.test_rival.emotion.anger=19
	state.social.relationship("test_rival","player").trust=10
	state.social.relationship("test_rival","player").dislike=0
	var without_support: String=state.social.choose("test_rival","player",0).action
	state.social.characters.player.cooldown=0
	state.social.execute(state,"player","test_rival","support")
	check(without_support=="refuse" and state.social.choose("test_rival","player",0).action=="accept","Player support changes the subsequent decision from refusal to acceptance")
	state.social.characters.test_rival.pending={}
	state.social.relationship("test_rival","player").dislike=0
	state.social.characters.player.cooldown=0
	state.social.characters.test_rival.cooldown=0
	state.social.execute(state,"test_rival","player","request_help")
	state.social.characters.player.cooldown=0
	check(state.social.execute(state,"player","test_rival","accept").ok,"Player accepts an actual pending request and contributes labour")
	check(state.social.characters.player.pending.is_empty(),"A request resolves exactly once")

func _drops_and_size() -> void:
	var state:=State.new()
	state.mine("iron_01")
	var safe:=true
	for i in range(600):
		var owner: String=state.adventure.drop_item(state,"test_iron_ore",1)
		if owner.is_empty() or not state.adventure.take(state,owner,"test_iron_ore",1):
			safe=false
	check(safe and state.adventure.drops.size()==1,"600 drop/pick cycles recycle IDs without losing or duplicating stock")
	state.adventure.initialize(state.economy)
	state.adventure.next_drop=513
	for i in range(1,513):
		var owner: String="drop:"+str(i)
		if not state.economy.ledger.owners.has(owner):
			state.economy.ledger.add_drop_owner(owner)
		state.adventure.drops[owner]={"area":"town","position":state.player_position}
		# Explicit fixture only: populate the finite slots, adjust conservation budget.
		state.economy.ledger.owners[owner].add("test_food",1)
	var carried: int=state.inventory.count("test_iron_ore")
	check(state.adventure.drop_item(state,"test_iron_ore",1).is_empty() and state.inventory.count("test_iron_ore")==carried,"512 occupied piles reject dropping without teleporting or losing the item")
	var enemy: Dictionary=state.expedition_combat.enemies.adit_guard
	enemy.hp=0
	state.adventure.enemy_died(state,"adit_guard",enemy)
	state.location_id="adit_entry"
	state.player_position=enemy.position
	check(state.adventure.drops.has("enemy:adit_guard") and state.adventure.take(state,"enemy:adit_guard","test_iron_ore",1),"512 full piles cannot hide a newly defeated enemy's loot")
	check(State.new().apply_save(state.to_save()),"Saturated legacy pile set and corpse fallback save/load correctly")
	var slot:="res://.godot/social_size_test.json"
	var clean:=State.new()
	check(Service.save_game(clean,slot).is_empty(),"Dedicated save-size fixture writes normally")
	var text:=FileAccess.get_file_as_string(slot)
	clean.social.characters.player.reason="x".repeat(Service.MAX_BYTES)
	check(not Service.save_game(clean,slot).is_empty() and FileAccess.get_file_as_string(slot)==text,"Oversized save is rejected before replacing the prior slot")

func _rumours() -> void:
	var state:=State.new()
	pair(state,"test_carrier","test_smith")
	state.life.people.test_smith.fatigue=50
	state.life.people.test_rival.position=Vector2(840,760)
	state.life.people.test_mediator.position=Vector2(1440,1104)
	var help: Dictionary=state.social.execute(state,"test_carrier","test_smith","help")
	var fact: int=help.event
	check(not state.social._shareable("test_rival","test_smith").is_empty(),"Speaker does not inspect a recipient's private memory to choose news")
	pair(state,"test_rival","test_mediator")
	check(state.social.execute(state,"test_rival","test_mediator","inform",{"event":fact,"distort":true}).ok,"A low-principle actor can deliberately misrepresent a known event")
	var perceived: Dictionary={}
	for memory in state.social.characters.test_mediator.memory:
		if int(memory.id)==fact:
			perceived=memory
	check(perceived.get("kind")=="refuse" and not perceived.witnessed and state.social.history[0].kind=="help","Rumour belief is separate from objective truth and labelled hearsay")
	pair(state,"test_rival","test_smith")
	var trust: float=state.social.relationship("test_smith","test_rival").trust
	state.social.execute(state,"test_rival","test_smith","inform",{"event":fact,"distort":true})
	check(state.social.characters.test_smith.memory[-1].kind=="deception" and state.social.relationship("test_smith","test_rival").trust<trust,"An eyewitness detects deception, remembers it and distrusts the speaker")
	check(State.new().apply_save(state.to_save()),"Reported beliefs, private transmission history and exposed deception save correctly")
