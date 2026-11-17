extends SceneTree

const OrderInput=preload("res://scripts/rts_order_input.gd")
const RenderShutdown=preload("res://scripts/rts_render_shutdown.gd")

var passed: int=0
var failed: int=0

func _initialize() -> void:
	call_deferred("run")

func check(label: String, ok: bool) -> void:
	if ok:
		passed+=1
		print("PASS ",label)
	else:
		failed+=1
		push_error("FAIL "+label)

func run() -> void:
	var game=load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	check("installed scene initializes",game.map_ready and game.app!=null)
	if not game.map_ready:
		await RenderShutdown.finish(self,game,1)
		return
	game.start("wei","standard")
	game.controller.set_process(false)
	check("campaign starts",game.app.screen=="campaign" and not game.simulation.paused)
	var minimap=game.interface.minimap
	minimap.backdrop=null
	minimap._backdrop_world_id=""
	minimap.queue_redraw()
	await process_frame
	check("minimap recreates a missing backdrop",minimap.backdrop!=null)
	var gates: Array=game.simulation.gate_nodes("C1")
	var removed_position: Variant=null
	if not gates.is_empty() and game.controller.node_positions.has(gates[0]):
		removed_position=game.controller.node_positions[gates[0]]
		game.controller.node_positions.erase(gates[0])
	var picked: Dictionary=OrderInput.pick(game.controller,root.get_visible_rect().size*.5,true)
	check("picking tolerates a missing gate node",picked is Dictionary)
	if removed_position!=null:game.controller.node_positions[gates[0]]=removed_position
	game.overview_maximum=40.0
	game._zoom_goal=400.0
	game._process(1.0/60.0)
	check("zoom goal reclamps after fit changes",game.camera.transform.is_finite() and game.distance<=game.overview_maximum+.001)
	game.controller.select_city("C1")
	var commanders: Array=game.simulation.available_commanders("wei")
	var before_food: int=game.simulation.cities.C1.food
	var recruit_error: String="missing commander"
	if not commanders.is_empty():recruit_error=game.app.session.recruit_for_commander("infantry",str(commanders[0]),500)
	var expected_cost: int=500*int(game.simulation.PROFILES.infantry.cost)*int(game.simulation.SCALE)
	check("recruitment uses commander and current food cost",recruit_error.is_empty() and game.simulation.cities.C1.food==before_food-expected_cost)
	game.simulation.configure_ai([])
	for city in game.simulation.cities.values():
		city.owner="wei"
		for index in range(city.production_queue.size()-1,-1,-1):
			if city.production_queue[index].faction!="wei":city.production_queue.remove_at(index)
	for army in game.simulation.armies.values():
		if army.faction!="wei":army.troops=0
	game.simulation.step()
	game.app.poll()
	check("current victory rules reach result",game.simulation.match_state=="finished" and game.app.result=="victory" and game.app.screen=="result")
	var reached_victory: bool=game.app.result=="victory"
	game.app.continue_campaign()
	check("victory can continue",reached_victory and game.simulation.match_state=="running" and game.simulation.continued and game.app.screen=="campaign")
	print("REVIEW_SMOKE: %d passed, %d failed"%[passed,failed])
	await RenderShutdown.finish(self,game,1 if failed>0 else 0)
