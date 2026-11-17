extends "res://commander_review_game.gd"
const Arrows=preload("res://scripts/arrow_volley_view.gd")
const SelectionView=preload("res://scripts/rts_selection_view.gd")
const RenderShutdown=preload("res://scripts/rts_render_shutdown.gd")
var arrow_effects: Node3D
var selection_view: Node3D

func _ready() -> void:
	super._ready()
	if not map_ready:return
	arrow_effects=Arrows.new();add_child(arrow_effects)
	arrow_effects.set_process(false)
	var error: String=arrow_effects.configure(simulation,controller)
	if not error.is_empty():push_error(error);get_tree().quit(2);return
	selection_view=SelectionView.new();add_child(selection_view);selection_view.configure(simulation,controller,source_unit_view)
	get_tree().auto_accept_quit=false;get_tree().root.close_requested.connect(request_exit)
	DisplayServer.window_set_title("Three Kingdoms | Unification")

func request_exit() -> void:
	await RenderShutdown.finish(get_tree(),self)

func _process(delta: float) -> void:
	super._process(delta)
	if arrow_effects!=null:
		arrow_effects.active=app!=null and app.screen=="campaign";arrow_effects.sync()

func start(faction: String, challenge: String) -> void:
	super.start(faction,challenge)
	if arrow_effects!=null:arrow_effects.reset()
