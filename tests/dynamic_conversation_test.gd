extends SceneTree
const State = preload("res://scripts/simulation/world_state.gd")
const Session = preload("res://scripts/simulation/conversation_session.gd")
const View = preload("res://scripts/ui/conversation_view.gd")
const Journal = preload("res://scripts/ui/social_ui.gd")
const Art = preload("res://scripts/data/conversation_art.gd")
const Language = preload("res://scripts/data/conversation_language.gd")
const Speech = preload("res://scripts/simulation/npc_speech.gd")
const Service = preload("res://scripts/simulation/save_service.gd")
const SLOT := "res://.godot/dynamic_conversation_test.json"
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error(label)

func near(world: RefCounted, id: String) -> void:
	var position: Vector2 = world.life.people[id].position
	for offset in [Vector2(0, 56), Vector2(56, 0), Vector2(-56, 0), Vector2(0, -56)]:
		if world.life.navigation_for("town").clear_segment(position, position + offset):
			world.player_position = position + offset
			return

func reply(world: RefCounted) -> void:
	world.life.clock.minute += 1
	world.social.characters.player.cooldown = 0

func run() -> void:
	var world := State.new()
	var first: String = world.spawn_resident(Vector2(768, 864), "metalworker")
	var second: String = world.spawn_resident(Vector2(768, 864), "miner")
	check(first == "resident_000001" and not second.is_empty(), "Fixture creates the exact dynamic ID from the reported crash")
	if first.is_empty() or second.is_empty():
		quit(1)
		return
	var visible_name: String = Language.display_name(first, world)
	check(visible_name.contains("Житель 1") and not visible_name.contains(first), "Current resident definition supplies the visible name")
	Language.extra_names.clear()
	check(Language.display_name(first, world) == visible_name, "Dialogue reads the live world rather than a process-global name cache")
	check(Art.public_introduction(first, world).contains(visible_name) and Art.public_introduction(first, world).contains("обработкой металла"), "Introduction uses the generated resident's name and actual profession")
	check(Art.portrait_path(first, world).ends_with("Actor1_%d.png" % (int(world.life.definitions[first].sprite) + 1)), "Conversation art uses the generated resident's sprite")
	near(world, first)
	var view := View.new()
	root.add_child(view)
	view.open(world, first)
	check(view.speaker.text == visible_name and view.portrait.texture != null, "Opening the real dialogue view presents the generated resident")
	var conversation: RefCounted = view.session
	reply(world)
	var introduction: Dictionary = conversation.choose("self")
	check(introduction.get("ok", false) and conversation.line.contains(visible_name) and not conversation.line.contains(first), "Reported conversation_art.gd crash: first acquaintance and self-description work")
	reply(world)
	var work_reply: Dictionary = conversation.choose("work")
	check(work_reply.get("ok", false) and conversation.line.to_lower().contains("работ"), "Work question uses the resident's current world state")
	view.close()
	view.queue_free()
	# An actual social action between two generated residents becomes a remembered story.
	world.life.people[second].fatigue = 60
	world.social.characters[first].cooldown = 0
	world.social.characters[second].cooldown = 0
	var action: Dictionary = world.social.execute(world, first, second, "help")
	check(action.get("ok", false), "Two dynamically created residents interact through SocialSimulation")
	if action.get("ok", false):
		var memory: Dictionary = world.social._source_topic(first, "player", {"event": int(action.event)})
		var account: String = Speech.account(world, first, memory)
		check(account.contains(Language.name_form(second, 1, world)) and not account.contains(second), "Resident tells a story about another generated resident by name")
		near(world, first)
		var news := Session.new()
		news.start(world, first)
		reply(world)
		check(news.choose("news").get("ok", false) and news.line.contains(Language.name_form(second, 1, world)) and not news.line.contains(second), "Player hears the generated residents' real interaction")
	world.life.definitions[second]["speech_female"] = true
	world.life.people[first].fatigue = 60
	world.social.characters[first].cooldown = 0
	world.social.characters[second].cooldown = 0
	var reverse: Dictionary = world.social.execute(world, second, first, "help")
	check(reverse.get("ok", false) and Speech.account(world, second, world.social._source_topic(second, "player", {"event": int(reverse.get("event", 0))})).begins_with("Я помогла"), "NPC speech uses the generated resident's live grammatical metadata")
	var journal := Journal.new()
	root.add_child(journal)
	journal.open(world)
	var found := false
	for index in range(journal.picker.item_count):
		if journal.picker.get_item_metadata(index) == first and journal.picker.get_item_text(index) == world.social.name_of(first):
			found = true
	check(found and not journal.journal.text.contains(first), "Known dynamic residents appear by name in the ordinary journal")
	journal.close()
	journal.queue_free()
	check(Service.save_game(world, SLOT).is_empty(), "Dialogue fixture saves to a dedicated test slot")
	var loaded := State.new()
	check(Service.load_game(loaded, SLOT).is_empty(), "Dialogue fixture loads through SaveService")
	if loaded.life.people.has(first):
		near(loaded, first)
		var again := Session.new()
		again.start(loaded, first)
		check(again._already("self"), "Generated resident remembers the previous introduction after loading")
		reply(loaded)
		check(again.choose("self").get("ok", false) and again.line.contains("уже спрашивали") and again.line.contains(visible_name), "Repeated conversation after loading uses the saved identity")
		check(loaded.life.definitions[first].profession == "metalworker" and Language.display_name(first, loaded) == visible_name, "Saved profession and visible name remain available to dialogue")
		check(Language.female(second, loaded) and Language.past(second, "помог", "помогла", loaded) == "помогла", "Saved speech characteristics remain available after loading")
		check(Art.public_introduction("test_smith", loaded).contains("кузнице") and Language.name_form("test_recluse", 1, loaded) == "Олу", "Legacy residents retain their dialogue and name forms")
	print("DYNAMIC CONVERSATION TEST: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
