extends RefCounted
## Five data-only slots; slot 0 is reserved for autosave.
const Simulation = preload("res://scripts/rts_campaign_simulation.gd")
const OfficerSimulation = preload("res://scripts/rts_officer_campaign.gd")
const CommanderSimulation = preload("res://scripts/battle_campaign.gd")
const MAX_BYTES = 16 * 1024 * 1024
const SLOT_COUNT = 5
const CURRENT_SCHEMA=14
const SCHEMAS=[14,11,12,13]
const LOAD_SLOT_COUNT=SLOT_COUNT*4

static func slot_path(directory: String, slot: int, schema: int=14) -> String:
	return directory.path_join("schema-%d"%schema).path_join("campaign-%d.json" % slot) if slot >= 0 and slot < SLOT_COUNT else ""

static func slot_index(schema: int, slot: int) -> int:
	return SCHEMAS.find(schema)*SLOT_COUNT+slot if schema in SCHEMAS and slot>=0 and slot<SLOT_COUNT else -1

static func _indexed_path(directory: String, slot: int) -> String:
	if slot<0 or slot>=LOAD_SLOT_COUNT:return ""
	var schema: int=SCHEMAS[slot/SLOT_COUNT]
	return directory.path_join("campaign-%d.json"%(slot%SLOT_COUNT)) if schema==11 else slot_path(directory,slot%SLOT_COUNT,schema)

static func load_path(directory: String, slot: int) -> String:
	var path: String=_indexed_path(directory,slot)
	if slot>=0 and slot<SLOT_COUNT and not FileAccess.file_exists(path):
		for schema in [13,12,11]:
			var legacy: String=_indexed_path(directory,slot_index(schema,slot))
			if FileAccess.file_exists(legacy):return legacy
	return path

static func save_slot(sim: RefCounted, directory: String, slot: int) -> String:
	var format: int=int(sim.snapshot().get("format_version",5))
	var path := slot_path(directory, slot,format if format in [12,13,14] else 12)
	if path.is_empty(): return "Invalid save slot."
	var payload: String = sim.save_json()
	if payload.to_utf8_buffer().size() > MAX_BYTES: return "Save exceeds the size limit."
	# Check before touching a previous save. JSON validation also checks the world,
	# route, ferry, siege, queues and match invariants.
	var validator = CommanderSimulation.new() if format in [11,12,13,14] else OfficerSimulation.new() if format==6 else Simulation.new()
	if format in [11,12,13,14]:validator.navigation_warmup=false
	var error: String = validator.load_json(payload)
	if not error.is_empty(): return "Cannot save invalid campaign state: " + error
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK: return "Cannot create save directory."
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return "Cannot write temporary save."
	file.store_string(payload)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK: return "Cannot finish temporary save."
	if FileAccess.get_file_as_string(temporary) != payload: return "Temporary save verification failed."
	if DirAccess.rename_absolute(temporary, path) != OK: return "Cannot replace save slot."
	return ""

static func load_slot(sim: RefCounted, directory: String, slot: int) -> String:
	var path := load_path(directory,slot)
	if path.is_empty(): return "Invalid save slot."
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return "Save slot is empty or unreadable."
	if file.get_length() > MAX_BYTES: file.close(); return "Save exceeds the size limit."
	var payload := file.get_as_text()
	file.close()
	# load_json commits only after validation, including configured world identity.
	return sim.load_json(payload)

static func list_slots(directory: String) -> Array:
	var slots: Array = []
	for slot in range(LOAD_SLOT_COUNT):
		var path: String=_indexed_path(directory,slot)
		if not FileAccess.file_exists(path): continue
		var file := FileAccess.open(path, FileAccess.READ)
		var error: String = "Save is unreadable."
		var candidate = Simulation.new()
		var schema: int=0
		if file != null:
			if file.get_length() > MAX_BYTES: error = "Save exceeds the size limit."
			else:
				var payload: String=file.get_as_text()
				var parsed=JSON.parse_string(payload)
				if parsed is Dictionary:schema=int(parsed.get("format_version",0))
				if parsed is Dictionary and parsed.get("format_version")==6:candidate=OfficerSimulation.new()
				elif parsed is Dictionary and parsed.get("format_version") in [11,12,13,14]:candidate=CommanderSimulation.new();candidate.navigation_warmup=false
				error = candidate.load_json(payload)
				if error.is_empty() and schema not in [11,12,13,14]:error="Earlier schemas remain separate from this gameplay revision."
			file.close()
		var faction: String = ""
		if error.is_empty():
			for id in ["wei", "shu", "wu"]:
				if id not in candidate.ai_factions: faction = id
		slots.append({"slot":slot,"legacy":slot>=SLOT_COUNT,"schema":schema, "valid_metadata":error.is_empty(), "error":error,
			"tick":candidate.tick if error.is_empty() else 0, "faction":faction,
			"world_id":candidate.world_metadata.get("id", "") if error.is_empty() else "",
			"modified_unix":FileAccess.get_modified_time(path)})
	return slots
