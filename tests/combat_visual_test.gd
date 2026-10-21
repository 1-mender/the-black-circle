extends SceneTree
## Visual state contract: guard and swing use distinct poses and existing combat timing.
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/combat_visual_" + name + ".png")

func settle() -> void:
	for _i in range(4):
		await process_frame

func run() -> void:
	root.size = Vector2i(1152, 720)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await settle()
	scene.change_location("arena", Vector2(720, 480))
	scene.world_state.rpg.claim_kit(scene.world_state.economy)
	scene.economy.refresh(scene.world_state)
	scene.set_physics_process(false)
	scene.player.set_physics_process(false)
	scene.world_state.life.clock.paused = true
	var fighter: Dictionary = scene.world_state.rpg.fighter
	fighter.position = scene.player.position
	fighter.facing = Vector2.RIGHT
	fighter.attack_elapsed = -1.0
	fighter.blocking = true
	scene.player._update_combat_pose(fighter)
	scene.economy.inventory_view.refresh(scene.world_state)
	check(scene.player.sprite.region_rect.position.x == (scene.player.character_index % 4) * 144 + 48, "Block uses a braced pose, not the strike frame")
	check(scene.ui.quick_buttons[1].icon == scene.economy.inventory_view.quick_slots[1].image.texture, "HUD and inventory use the same block action icon")
	await settle()
	await capture("block")
	fighter.blocking = false
	fighter.attack_elapsed = 0.08
	scene.player._update_combat_pose(fighter)
	check(scene.player.sprite.region_rect.position.x == (scene.player.character_index % 4) * 144, "Windup draws the backswing pose")
	await settle()
	await capture("windup")
	fighter.attack_elapsed = 0.22
	scene.player._update_combat_pose(fighter)
	check(scene.player.sprite.region_rect.position.x == (scene.player.character_index % 4) * 144 + 96, "Active hit draws the forward swing pose")
	await settle()
	await capture("swing")
	scene.queue_free()
	await process_frame
	print("COMBAT VISUAL TEST: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
