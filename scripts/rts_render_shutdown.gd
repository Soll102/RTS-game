extends RefCounted
## Stop submissions and finish the last draw while its resources are still alive.
static func finish(tree: SceneTree, game: Node, code: int=0) -> void:
	if tree.has_meta("rts_shutting_down"):return
	tree.set_meta("rts_shutting_down",true)
	if is_instance_valid(game):
		game.propagate_call("set_process",[false]);game.propagate_call("set_physics_process",[false])
		if game is Node3D:game.visible=false
	if DisplayServer.get_name()=="headless":tree.quit(code);return
	await tree.process_frame
	await RenderingServer.frame_post_draw
	RenderingServer.force_sync()
	await tree.process_frame
	await RenderingServer.frame_post_draw
	RenderingServer.force_sync()
	tree.quit(code)
