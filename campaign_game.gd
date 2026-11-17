extends "res://campaign_runtime.gd"
## Pending units-only commander portrait/stat review.
const SourceTest=preload("res://unit-models/source_role_formation_view.gd")
const Backdrop=preload("res://background/exterior_backdrop.gd")
var source_unit_view: Node3D
var exterior_backdrop: Node3D

func _ready() -> void:
	super._ready()
	if not map_ready:return
	exterior_backdrop=Backdrop.new();add_child(exterior_backdrop)
	exterior_backdrop.configure(func(x,z):return Ground.height_at(heights,x,z), -2.0)
	exterior_backdrop.visible=true
	env.background_mode=Environment.BG_COLOR;env.background_color=Color("526357")
	env.fog_enabled=true;env.fog_mode=Environment.FOG_MODE_DEPTH;env.fog_light_color=Color("526357");env.fog_depth_begin=80.0;env.fog_depth_end=420.0
	source_unit_view=SourceTest.new();add_child(source_unit_view)
	var error: String=source_unit_view.configure(simulation,controller)
	if not error.is_empty():push_error(error);get_tree().quit(2);return
	controller.context_order_accepted.connect(interface.overlay.show_move_target)
	interface.skill_order_accepted.connect(interface.overlay.show_skill_target)
	controller.order_result.connect(func(message):
		if not message.is_empty():interface.overlay.clear_move_target())
	controller.entity_visual_pick=source_unit_view.pick
	controller.friendly_visual_pick=func(screen):return source_unit_view.pick(screen,controller.player_faction)
	DisplayServer.window_set_title("Three Kingdoms | Units and Commanders Review v1")

func verify_v8() -> bool:
	if not super.verify_v8():return false
	# Candidate integrity is specific to this isolated review; it grants no approval.
	var integrity=JSON.parse_string(FileAccess.get_file_as_string("res://review-integrity.json"))
	if not integrity is Dictionary or integrity.get("status")!="pending" or integrity.get("scope")!="isolated_playable_review":push_error("An isolated candidate integrity record is required.");return false
	if not integrity.get("files") is Array or integrity.files.is_empty():push_error("Candidate integrity members are missing.");return false
	for record in integrity.files:
		if FileAccess.get_sha256("res://"+record.file)!=record.sha256:push_error("Review dependency changed: "+record.file);return false
	return true

func _process(delta: float) -> void:
	super._process(delta)
	if source_unit_view!=null:source_unit_view.active=app!=null and app.screen=="campaign"

func start(faction: String, challenge: String) -> void:
	if interface!=null:
		interface._cancel_target_mode();interface._status_box.visible=false;interface._message_until=0;interface._skill_feedback_until=0
	if interface!=null:interface.overlay.clear_move_target()
	var error: String=app.start_campaign(faction,challenge)
	if not error.is_empty():interface.message(error,true);return
	_sync_world_view()
	focus_home();interface.refresh_screen()
	if source_unit_view!=null:
		source_unit_view.reset()
		source_unit_view.active=app.screen=="campaign";source_unit_view.sync()
