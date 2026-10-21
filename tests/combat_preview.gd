extends SceneTree
func _initialize() -> void:
	call_deferred("capture")
func capture() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.world_state.rpg.claim_kit(scene.world_state.economy)
	scene.change_location("arena", Vector2(744, 480))
	scene.world_state.rpg.fighter.hp = 76
	scene.world_state.combat.selected_id = "melee_01"
	var enemy: Dictionary = scene.world_state.combat.enemies.melee_01
	scene.world_state.combat.begin_attack(enemy, scene.world_state.combat.enemy_stats(enemy), scene.player.position, "strong")
	enemy.attack_elapsed = 0.42
	scene.world_state.life.clock.paused = true
	scene.time_ui.refresh(scene.world_state.life, "arena", false)
	scene.world_state.combat.request_attack(scene.world_state, enemy.position)
	scene.player.get_node("Camera2D").reset_smoothing()
	for _i in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/combat_preview.png")
	scene.queue_free()
	await process_frame
	quit()
