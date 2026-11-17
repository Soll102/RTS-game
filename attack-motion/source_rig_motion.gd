extends Node
## Pending authored motion on exact retained ROTK XIV source rigs.
## The outer actor/mount controls simulation position; this changes real bone poses.
## Source geometry, Skin, materials, texture and bone rest resources stay immutable.

signal finished(state: String)

var actor: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var model: Dictionary = {}
var catalog: Dictionary = {}
var current_state := ""
var configured := false
var bind_report: Dictionary = {}
var _resource_root := "res://"
var _last_seek_stamp: int = -1

func configure(source_actor: Node3D, model_id: String, catalog_path := "res://attack-motion/animation-catalog.json") -> bool:
	if configured or not is_instance_valid(source_actor):
		return false
	actor = source_actor
	if not FileAccess.file_exists(catalog_path):
		return _fail("Missing authored motion catalog: " + catalog_path)
	catalog = JSON.parse_string(FileAccess.get_file_as_string(catalog_path))
	if catalog.get("schema", -1) != 1 or catalog.get("approved", true):
		return _fail("Expected pending schema-1 authored motion review")
	_resource_root = catalog_path.get_base_dir().get_base_dir().trim_suffix("/") + "/"
	for candidate in catalog.get("models", []):
		if candidate.id == model_id:
			model = candidate
			break
	if model.is_empty():
		return _fail("Unsupported exact source rig: " + model_id)
	var model_path := _resource_root + String(model.file)
	if FileAccess.get_sha256(model_path) != String(model.sha256):
		return _fail("Exact source model dependency hash mismatch: " + model_id)
	var skeletons := actor.find_children("*", "Skeleton3D", true, false)
	if skeletons.size() != 1:
		return _fail("Expected one actual source Skeleton3D: " + model_id)
	skeleton = skeletons[0] as Skeleton3D
	# Godot's import_as_skeleton_bones retains every source node, plus one
	# unweighted bone per source mesh node. All original rig nodes are checked below.
	for original in model.rest_bones:
		var bone := skeleton.find_bone(String(original.name))
		if bone < 0:
			return _fail("Missing original source bone: " + String(original.name))
		var expected_parent := int(original.parent)
		var actual_parent := skeleton.get_bone_parent(bone)
		if expected_parent < 0:
			if actual_parent != -1:
				return _fail("Source root parent changed")
		else:
			var parent_name := "source_joint_%04d" % expected_parent
			if actual_parent < 0 or String(skeleton.get_bone_name(actual_parent)) != parent_name:
				return _fail("Source hierarchy changed at " + String(original.name))
		var rest := skeleton.get_bone_rest(bone)
		var t: Array = original.translation
		if rest.origin.distance_to(Vector3(t[0], t[1], t[2])) > 0.005:
			return _fail("Source rest position changed at " + String(original.name))
		var r: Array = original.rotation
		var source_rotation := Quaternion(r[0], r[1], r[2], r[3]).normalized()
		if absf(source_rotation.dot(rest.basis.get_rotation_quaternion().normalized())) < 0.99999:
			return _fail("Source rest rotation changed at " + String(original.name))
	var mesh_count := 0
	var triangles := 0
	for item in actor.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := item as MeshInstance3D
		mesh_count += 1
		if mesh_node.get_skin() == null or mesh_node.get_node_or_null(mesh_node.skeleton) != skeleton:
			return _fail("Source mesh lacks its actual Skin/Skeleton binding")
		for surface in range(mesh_node.mesh.get_surface_count()):
			var arrays := mesh_node.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += indices.size() / 3
	if triangles != int(model.triangles):
		return _fail("Original exported source triangle set changed")
	if skeleton.get_bone_count() != int(model.rig_node_count) + mesh_count:
		return _fail("Complete source nodes/mesh-node import differs: " + model_id)
	bind_report = {"model_id": model.id, "model_sha256": model.sha256, "skeleton_bones": skeleton.get_bone_count(), "visible_source_meshes": mesh_count, "triangles": triangles, "actual_skin_binding": true, "original_rest_hierarchy": true}
	skeleton.reset_bone_poses()
	player = AnimationPlayer.new()
	player.name = "AuthoredSourceMotionPlayer"
	add_child(player)
	player.root_node = player.get_path_to(actor)
	var library := AnimationLibrary.new()
	var skeleton_path := String(actor.get_path_to(skeleton))
	for clip_name in model.clips:
		var entry: Dictionary = model.clips[clip_name]
		var clip_path := _resource_root + String(entry.file)
		if FileAccess.get_sha256(clip_path) != String(entry.sha256):
			return _fail("Authored clip bytes changed: " + String(entry.id))
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(clip_path))
		if data.get("model_sha256", "") != model.sha256 or data.get("rig_node_transform_sha256", "") != model.node_transform_sha256 or data.get("skin_sha256", "") != model.skin_sha256 or data.get("approved", true):
			return _fail("Clip has incompatible exact source dependency: " + String(entry.id))
		var animation := Animation.new()
		animation.resource_name = String(entry.id) + " v1"
		animation.length = float(data.duration)
		animation.loop_mode = Animation.LOOP_LINEAR if bool(data.loop) else Animation.LOOP_NONE
		for channel in data.channels:
			var bone_name := String(channel.bone)
			if skeleton.find_bone(bone_name) < 0:
				return _fail("Authored track refers to missing source bone")
			var path := NodePath(skeleton_path + ":" + bone_name)
			var position_track := animation.add_track(Animation.TYPE_POSITION_3D)
			animation.track_set_path(position_track, path)
			animation.track_set_interpolation_type(position_track, Animation.INTERPOLATION_LINEAR)
			var rotation_track := animation.add_track(Animation.TYPE_ROTATION_3D)
			animation.track_set_path(rotation_track, path)
			animation.track_set_interpolation_type(rotation_track, Animation.INTERPOLATION_LINEAR)
			for key in channel.keys:
				var p: Array = key.position
				var q: Array = key.rotation
				animation.position_track_insert_key(position_track, float(key.time), Vector3(p[0], p[1], p[2]))
				animation.rotation_track_insert_key(rotation_track, float(key.time), Quaternion(q[0], q[1], q[2], q[3]).normalized())
		library.add_animation(StringName(clip_name), animation)
	player.add_animation_library("authored", library)
	player.animation_finished.connect(_on_animation_finished)
	configured = true
	return reset_to_rest()

func _fail(message: String) -> bool:
	push_error(message)
	return false

func set_state(state: String, restart := false, blend := 0.10) -> bool:
	if not configured:return false
	if state=="rest":
		if current_state!="rest":reset_to_rest()
		return true
	if state!="attack" or not model.clips.has("attack"):return false
	if current_state=="attack" and not restart:return true
	current_state="attack"
	player.play("authored/attack",maxf(0.0,blend))
	if restart:player.seek(0.0,true)
	player.advance(0.0)
	return true

func seek(seconds: float) -> void:
	if not configured or not model.clips.has(current_state):
		return
	var stamp: int = int(seconds * 30.0)
	if stamp == _last_seek_stamp:
		return
	_last_seek_stamp = stamp
	player.seek(clampf(seconds, 0.0, float(model.clips[current_state].duration)), true)
	player.advance(0.0)
	skeleton.force_update_all_bone_transforms()

func set_speed(multiplier: float) -> void:
	if configured:
		player.speed_scale = maxf(0.0, multiplier)

func reset_to_rest() -> bool:
	if not configured:return false
	_last_seek_stamp = -1
	player.stop();skeleton.reset_bone_poses();skeleton.force_update_all_bone_transforms()
	current_state="rest"
	return true

func clip_duration(state: String) -> float:
	var requested := String(catalog.get("state_aliases", {}).get(state, state))
	return float(model.clips.get(requested, {}).get("duration", 0.0))

func pause() -> void:
	if configured:
		player.pause()

func resume() -> void:
	if configured:
		player.play()

func _on_animation_finished(animation_name: StringName) -> void:
	finished.emit(String(animation_name).get_slice("/",1))
