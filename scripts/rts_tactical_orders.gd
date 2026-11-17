extends RefCounted
const Rules=preload("res://scripts/rts_tactical_rules.gd")
const FIELD_ORDERS=["move","attack_move","attack","siege","retreat","hold"]

static func initialize(army: Dictionary) -> void:
	army.waypoints=[];army.combat_target="";army.stuck_ticks=0

static func field_enemy(sim: RefCounted, army: Dictionary, id: String) -> bool:
	if not sim.armies.has(id):return false
	var target: Dictionary=sim.armies[id]
	return target.troops>0 and target.faction!=army.faction and target.transport_elapsed==0 and target.get("resident_city","").is_empty()

static func check_queue(sim: RefCounted, command: Dictionary) -> String:
	if command.has("append") and not command.append is bool:return "Queued-order flag is invalid."
	if not command.get("append",false):return ""
	if command.get("type") not in FIELD_ORDERS or command.get("type")=="hold":return "This command cannot be queued."
	for id in command.get("army_ids",[]):
		if not sim.armies.has(id):continue
		var reserved: int=sim.armies[id].get("waypoints",[]).size()
		for earlier in sim.command_queue:
			if id not in earlier.army_ids or earlier.type=="stance":continue
			reserved=reserved+1 if earlier.get("append",false) else 0
		if reserved>=Rules.MAX_WAYPOINTS:return "Order queue is full (16 orders)."
	return ""

static func apply(sim: RefCounted) -> void:
	for command in sim.command_queue:
		var ids: Array=command.army_ids.duplicate();ids.sort()
		for id in ids:
			var army: Dictionary=sim.armies[id]
			if army.troops<=0:continue
			if command.type=="stance":
				army.stance=command.target;sim._emit("stance_changed",{"army":id,"stance":command.target});continue
			var order: Dictionary={"type":command.type,"target":command.target}
			if command.has("gate_node"):order.gate_node=command.gate_node
			if command.get("append",false) and (army.order.type!="hold" or army.transport_elapsed>0):
				army.waypoints.append(order);sim._emit("order_queued",{"army":id,"order":order.type});continue
			army.waypoints.clear();army.combat_target="";army.stuck_ticks=0
			if not sim._set_order(army,order):sim._emit("order_failed",{"army":id,"reason":"No valid route."})
	sim.command_queue.clear()

static func advance(sim: RefCounted, army: Dictionary) -> void:
	if army.troops<=0 or army.routed or army.transport_elapsed>0:return
	while not army.waypoints.is_empty():
		var order: Dictionary=army.waypoints.pop_front()
		if order.type=="attack" and not field_enemy(sim,army,order.target):continue
		if order.type=="siege" and (not sim.cities.has(order.target) or sim.cities[order.target].owner==army.faction):continue
		if sim._set_order(army,order):army.combat_target="";army.stuck_ticks=0;return
	army.combat_target="";sim._hold(army)

static func validate(sim: RefCounted, data: Dictionary) -> String:
	var reserved: Dictionary={}
	for army_id in data.armies:
		var army: Dictionary=data.armies[army_id]
		if not army.get("waypoints") is Array or army.waypoints.size()>Rules.MAX_WAYPOINTS:return "Formation order queue is invalid."
		if not army.get("combat_target") is String or not sim._integer_at_least(army.get("stuck_ticks"),0) or army.stuck_ticks>100:return "Formation engagement state is invalid."
		if not army.combat_target.is_empty() and (not data.armies.has(army.combat_target) or data.armies[army.combat_target].faction==army.faction):return "Formation engagement target is invalid."
		for order in army.waypoints:
			if not order is Dictionary or order.get("type") not in FIELD_ORDERS:return "Queued waypoint type is invalid."
			var error: String=sim._validate_saved_order(order,data.nodes,data.armies,data.cities)
			if not error.is_empty():return error
		reserved[army_id]=army.waypoints.size()
	if not data.get("command_queue") is Array:return "Field command queue is invalid."
	for command in data.command_queue:
		if not command is Dictionary or not command.get("army_ids") is Array or not command.get("append",false) is bool:return "Pending field command is invalid."
		if command.get("type")=="stance":continue
		if command.get("type") not in FIELD_ORDERS:return "Pending field command type is invalid."
		if command.get("append",false) and command.type=="hold":return "Stop cannot be queued."
		for id in command.army_ids:
			if not reserved.has(id):return "Pending field command references an unknown formation."
			reserved[id]=int(reserved[id])+1 if command.get("append",false) else 0
			if reserved[id]>Rules.MAX_WAYPOINTS:return "Pending commands exceed the formation order queue."
	return ""
