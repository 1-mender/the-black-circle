extends SceneTree
var checks:=0
var failures:=0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, description: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(description)
func run() -> void:
	var scene=load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await physics_frame
	await process_frame
	scene.set_physics_process(false)
	scene.player.set_physics_process(false)
	var player=scene.player
	var camera: Camera2D=player.get_node("Camera2D")
	check(is_physics_interpolation_enabled(),"Render interpolation is enabled")
	check(camera.process_callback==Camera2D.CAMERA2D_PROCESS_PHYSICS and not camera.position_smoothing_enabled,"Camera follows the same physical trajectory without a second chase filter")
	# Same distance at different step sizes must produce the same gait, including slowdown.
	var poses: Array=[]
	for steps in [15,30,60,144]:
		player.update_sprite(Vector2.ZERO,0)
		for step in range(steps):
			player.update_sprite(Vector2.RIGHT,1.0/steps,Vector2.RIGHT,60.0/steps)
		poses.append(player.sprite.region_rect)
		check(is_equal_approx(player.animation_distance,60.0),"Gait follows distance at %d steps"%steps)
	check(poses.all(func(p:Rect2):return p==poses[0]),"Different update rates yield the same foot phase")
	player.position=Vector2(180,400)
	player.reset_physics_interpolation()
	Input.action_press("move_right")
	for i in range(60):
		await physics_frame
		player._physics_process(1.0/60)
	check(player.position.x<=228.1 and player.position.x>200,"Interpolated presentation preserves building collision")
	check(player.animation_distance==0.0 and player.sprite.region_rect.position.x==48,"Pushing a wall stops the feet on the idle pose")
	Input.action_release("move_right")
	player.position=Vector2(864,900)
	player.reset_physics_interpolation()
	player.time_scale=0.25
	Input.action_press("move_right")
	var start: Vector2=player.position
	for i in range(12):
		await physics_frame
		player._physics_process(1.0/60)
	check(is_equal_approx(player.animation_distance,player.position.distance_to(start)),"Slow movement advances gait only by actual travelled distance")
	Input.action_release("move_right")
	scene.change_location("mine",Vector2(576,696))
	check(player.position==Vector2(576,696) and player.velocity==Vector2.ZERO,"Area change teleports immediately and clears motion")
	if "--capture" in OS.get_cmdline_user_args():
		scene.change_location("town",Vector2(864,720))
		player.time_scale=1.0
		player.set_physics_process(true)
		Input.action_press("move_right")
		for i in range(20):
			await physics_frame
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/movement_running.png")
		Input.action_release("move_right")
	scene.queue_free()
	await process_frame
	print("MOVEMENT VISUAL TEST: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
