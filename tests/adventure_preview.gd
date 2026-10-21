extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene=load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.change_location("adit_entry",Vector2(864,552))
	scene.world_state.rpg.claim_kit(scene.world_state.economy)
	var enemy:Dictionary=scene.world_state.combat.enemies.adit_archer
	enemy.ai="chase"
	scene.world_state.combat.begin_attack(enemy,scene.world_state.combat.enemy_stats(enemy),scene.player.position,"ranged")
	enemy.attack_elapsed=0.4
	scene.world_state.combat.selected_id="adit_archer"
	scene.world_state.life.clock.paused=true
	scene.time_ui.refresh(scene.world_state.life,"adit_entry",false)
	scene.world_state.combat.request_attack(scene.world_state,enemy.position)
	scene.player.get_node("Camera2D").reset_smoothing()
	for _i in range(4):
		await process_frame
		await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/adventure06_combat.png")
	scene.queue_free()
	await process_frame
	quit()
