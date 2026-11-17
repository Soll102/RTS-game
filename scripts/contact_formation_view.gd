extends "res://scripts/source_animated_review_view.gd"
## Contact is composed once across all roles by melee_contact_motion.gd.
## This adapter retains the original Infantry source rig and attack dependency.
func display_position(id: String) -> Vector3:
	if formations.has(id) and is_instance_valid(formations[id].root):return formations[id].root.global_position
	return controller.grounded_position(id)

func sync() -> void:
	super.sync()
	if controller!=null:controller.display_position=display_position
