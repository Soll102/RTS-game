extends Control
## Local playable move-target review; inherited martial HUD, no route drawing.
const T=preload("res://ui_tokens.gd")
const M=preload("res://martial_tokens.gd")
const Marks=preload("res://martial_marks.gd")
const Geo=preload("res://overlay_geometry.gd")
var app: RefCounted
var map: Node3D
var interface: CanvasLayer
var font: Font=T.font()
var route_metrics: Dictionary={}
var _blockers: Array=[]
const TargetIndicator=preload("res://move_target_indicator.gd")
var indicator_position: Vector3=Vector3.INF
var indicator_destinations: Array=[]
const Routes=preload("res://scripts/rts_route_presentation.gd")
var indicator_until_msec: int=0
var indicator_started_msec: int=0
var indicator_order: String="Move"
var indicator_target: Dictionary={}
var indicator_metrics: Dictionary=TargetIndicator.empty_metrics()
const INDICATOR_DURATION_MSEC=TargetIndicator.DURATION_MSEC
const CITY_BAR_SIZE=Vector2(76,6)
var _city_combat_until: Dictionary={}
var _city_health_tick: int=-1
var _last_skill_event_idx: int=0
var _skill_banners: Array=[]
var _portrait_cache: Dictionary={}
const STANCE_BADGES={"balanced":"Phương Viên","aggressive":"Phong Thỉ ▲","defensive":"Hạc Dực 🛡"}

func city_anchor(id: String) -> Vector3:
	var city: Dictionary=map.simulation.cities[id]
	var point: Vector3=Vector3.INF
	if map.controller.city_positions.has(id):point=map.controller.city_positions[id]
	elif map.controller.node_positions.has(city.node):point=map.controller.node_positions[city.node]
	if not point.is_finite():return point
	return point+Vector3.UP*(5.0 if city.kind=="city" else 1.0)

func city_health(id: String) -> Dictionary:
	var sim=map.simulation;var city: Dictionary=sim.cities[id]
	if sim.tick<_city_health_tick:_city_combat_until.clear()
	_city_health_tick=sim.tick
	var maximum: int=int(city.get("wall_max",0))+int(city.get("city_hp_max",0))
	var current: int=clampi(int(city.get("wall_hp",0))+int(city.get("city_hp",0)),0,maximum)
	var combat: bool=sim._city_under_siege(city)
	var last_siege: int=int(city.get("last_siege_tick",0))
	combat=combat or (last_siege>0 and sim.tick-last_siege<=35)
	for job in sim.get("pending_windups"):
		if job.get("city","")==id:combat=true;break
	if not combat:
		for shot in sim.get("pending_volleys"):
			if shot.kind=="city" and shot.source==id:combat=true;break
	if combat:_city_combat_until[id]=sim.tick+35
	combat=combat or int(_city_combat_until.get(id,-1))>=sim.tick
	return {"visible":maximum>0 and (current<maximum or combat),"current":current,"maximum":maximum,"fraction":float(current)/maximum if maximum>0 else 0.0,"combat":combat}

func clear_move_target() -> void:
	indicator_position=Vector3.INF;indicator_until_msec=0;indicator_started_msec=0
	indicator_target.clear();indicator_destinations.clear();indicator_metrics=TargetIndicator.empty_metrics();queue_redraw()

func _target_position(target: Dictionary) -> Vector3:
	var id: String=str(target.get("id",""));var kind: String=str(target.get("kind","node"))
	if kind=="army" and map.simulation.armies.has(id) and map.simulation.armies[id].troops>0:
		return _actor_point(id)
	if kind in ["city","gate"] and map.simulation.cities.has(id):
		var node: String=str(target.get("gate_node",map.simulation.cities[id].node))
		return map.controller.node_positions[node] if map.controller.node_positions.has(node) else Vector3.INF
	if kind=="node" and map.controller.node_positions.has(id):
		return map.controller.node_positions[id]
	return Vector3.INF

func _show_target(target: Dictionary, action: String) -> void:
	var position: Vector3=_target_position(target)
	if not position.is_finite() or not map.controller.ground_sampler.is_valid():clear_move_target();return
	position.y=_surface(position.x,position.z)
	if not position.is_finite():clear_move_target();return
	indicator_position=position;indicator_target=target.duplicate();indicator_order=action
	indicator_destinations.clear()
	var assignments: Dictionary=target.get("assignments",{})
	var seen: Dictionary={}
	for id in assignments:
		var destination: String=assignments[id]
		if seen.has(destination):continue
		seen[destination]=true
		if not map.controller.node_positions.has(destination):continue
		var point: Vector3=map.controller.node_positions[destination]
		var route: Dictionary=map.simulation.find_path(map.simulation.armies[id].node,destination)
		var previous: String=route.route[-2] if route.ok and route.route.size()>1 else map.simulation.armies[id].node
		indicator_destinations.append({"point":point,"direction":point-map.controller.node_positions[previous]})
	if indicator_destinations.is_empty():
		var from: Vector3=map.controller.grounded_position(map.controller.selected_armies[0]) if not map.controller.selected_armies.is_empty() else position+Vector3.FORWARD
		indicator_destinations.append({"point":position,"direction":position-from})
	indicator_started_msec=Time.get_ticks_msec();indicator_until_msec=indicator_started_msec+INDICATOR_DURATION_MSEC;queue_redraw()

func show_move_target(target: Dictionary) -> void:
	if not map.controller.accepted_order.is_empty():target=map.controller.accepted_order.duplicate(true)
	var id: String=str(target.get("id",""));var kind: String=str(target.get("kind","node"));var action: String="Move"
	if kind=="army" and map.simulation.armies.has(id) and map.simulation.armies[id].faction!=map.controller.player_faction:action="Attack"
	elif kind in ["city","gate"] and map.simulation.cities.has(id) and map.simulation.cities[id].owner!=map.controller.player_faction:action="Siege"
	if target.get("order")=="attack_move":action="Attack"
	_show_target(target,action)

func show_skill_target(target: Dictionary) -> void:
	_show_target(target,"Skill")

func _refresh_target() -> void:
	if not indicator_position.is_finite():return
	if Time.get_ticks_msec()>=indicator_until_msec:clear_move_target();return
	if indicator_target.get("kind")=="army":
		var point: Vector3=_target_position(indicator_target)
		if not point.is_finite():clear_move_target();return
		indicator_position=point


func army_offset(id: String) -> Vector2:
	var point: Vector3=_actor_point(id);var nearby: Array=[]
	for other in map.simulation._sorted_ids(map.simulation.armies):
		if map.simulation.armies[other].troops<=0 or not map.simulation.armies[other].get("resident_city","").is_empty():continue
		if _actor_point(other).distance_to(point)<10.0:nearby.append(other)
	var y: float=-26.0
	if map.get("source_unit_view")!=null and map.source_unit_view.formations.has(id):
		var head: Vector3=point+Vector3.UP*(map.source_unit_view.display_height(id) if map.source_unit_view.has_method("display_height") else map.source_unit_view.source_height)
		if not map.camera.is_position_behind(head):y=minf(y,map.camera.unproject_position(head).y-map.camera.unproject_position(point).y-20)
	var idx: int=nearby.find(id)
	var stagger_y: float=float(idx)*20.0 if nearby.size()>1 else 0.0
	return Vector2(0.0,y-stagger_y)

func _draw() -> void:
	if app==null or app.screen!="campaign":return
	var control=map.controller;var sim=map.simulation
	var clip:=Rect2(Vector2(8,8),get_viewport().get_visible_rect().size-Vector2(16,16))
	_blockers=interface.overlay_blockers()
	route_metrics={"ground_runs":0,"ferry_runs":0,"chevrons":0,"deduplicated_legs":0,"banners":0,"flags":0,"supply_runs":0,"city_health_bars":0}
	_refresh_target()
	_draw_gates(clip)
	if sim.get("tactical_rts")==true:_draw_defense_range(clip)
	indicator_metrics=TargetIndicator.empty_metrics()
	for id in sim._sorted_ids(sim.cities):
		var city: Dictionary=sim.cities[id];var world: Vector3=city_anchor(id)
		if map.camera.is_position_behind(world):continue
		var point: Vector2=map.camera.unproject_position(world)
		if app.show_labels and (control.selected_city==id or point.distance_to(get_local_mouse_position())<40):
			var text: String=app.settlement_name(id);var width: float=font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x+22
			var box:=Rect2(point-Vector2(width*.5,12),Vector2(width,24))
			if Geo.visible_box(box,clip,_blockers):
				draw_style_box(T.box(Color("14100b",0.88),T.ACCENT if control.selected_city==id else Color("8a7344",0.65)),box)
				draw_rect(Rect2(box.position+Vector2(1,1),Vector2(3,22)),T.FACTION[city.owner])
				_world_text(box.position+Vector2(11,17),text,14,T.WORLD_ACCENT if control.selected_city==id else T.INK)
		var health: Dictionary=city_health(id)
		if not health.visible and control.selected_city!=id:continue
		var health_box:=Rect2(point+Vector2(-CITY_BAR_SIZE.x*.5,16),CITY_BAR_SIZE)
		if not Geo.visible_box(health_box.grow(1),clip,_blockers):continue
		draw_rect(health_box.grow(2),Color(0.05,0.06,0.08,0.92))
		draw_rect(Rect2(health_box.position,Vector2(CITY_BAR_SIZE.x*health.fraction,CITY_BAR_SIZE.y)),M.CINNABAR if health.fraction<.3 else T.FACTION[city.owner])
		draw_rect(health_box.grow(1),T.ACCENT if control.selected_city==id else M.EDGE,false,1)
		route_metrics.city_health_bars+=1
		if sim.get("tactical_rts")==true and city.capture_ticks>0:
			var progress:=Rect2(health_box.position+Vector2(0,9),Vector2(CITY_BAR_SIZE.x*float(city.capture_ticks)/sim.Tactical.capture_duration(city),4))
			draw_rect(Rect2(progress.position,Vector2(CITY_BAR_SIZE.x,4)),T.WORLD_BASE);draw_rect(progress,T.ACCENT)
			_world_text(progress.position+Vector2(0,17),sim.Tactical.city_phase(city),12,T.INK)
		if health_box.grow(5).has_point(get_local_mouse_position()):
			_world_text(health_box.position+Vector2(0,20),"Walls + HP: %d / %d"%[health.current,health.maximum],12,M.TEXT)
	var m_pos: Vector2=get_local_mouse_position()
	var closest_army_id: String="";var closest_dist_sq: float=36.0*36.0
	for army_id in sim._sorted_ids(sim.armies):
		var a: Dictionary=sim.armies[army_id]
		if a.troops<=0 or not a.get("resident_city","").is_empty():continue
		var w: Vector3=_actor_point(army_id)
		if map.camera.is_position_behind(w):continue
		var d_sq: float=map.camera.unproject_position(w).distance_squared_to(m_pos)
		if d_sq<closest_dist_sq:closest_dist_sq=d_sq;closest_army_id=army_id
	for id in sim._sorted_ids(sim.armies):
		var army: Dictionary=sim.armies[id]
		if army.troops<=0 or not army.get("resident_city","").is_empty():continue
		var world: Vector3=_actor_point(id)
		if map.camera.is_position_behind(world):continue
		var ground: Vector2=map.camera.unproject_position(world)
		var selected: bool=id in control.selected_armies
		var hovered: bool=(id==closest_army_id)
		var is_friendly: bool=army.faction==control.player_faction
		var in_combat: bool=not army.engaged_ids.is_empty()
		if not selected and not hovered:
			if is_friendly:
				if army.troops>=army.original_troops and not in_combat:continue
			else:
				if not in_combat and army.troops>=army.original_troops and ground.distance_to(get_local_mouse_position())>=44:continue
		var center: Vector2=ground+army_offset(id)
		var box:=Rect2(center-Vector2(24,2.5),Vector2(48,5))
		if not Geo.visible_box(box.grow(2),clip,_blockers):continue
		draw_rect(box.grow(1.5),Color(0.05,0.06,0.08,0.92))
		var hp_frac: float=clampf(float(army.troops)/maxi(1,army.original_troops),0.0,1.0)
		draw_rect(Rect2(box.position,Vector2(48*hp_frac,5)),T.FACTION[army.faction])
		draw_rect(box.grow(1),T.ACCENT if selected else Color(1,1,1,0.28),false,1.0)
		var hero_id: String=sim.officer_for(id)
		var hero_name: String=sim.Officers.DEFINITIONS[hero_id].name if not hero_id.is_empty() and sim.Officers.DEFINITIONS.has(hero_id) else army.faction.to_upper()
		var show_label: bool=selected or hovered or in_combat
		if show_label:
			var multi_select: bool=control.selected_armies.size()>1 and selected and not hovered
			var title: String
			if multi_select:
				title="%s (%d)"%[hero_name,army.troops]
			elif not is_friendly:
				title="%s · %s (%d)"%[army.faction.capitalize(),army.unit_type.capitalize(),army.troops]
			else:
				var stance_tag: String=str(STANCE_BADGES.get(str(army.get("stance","balanced")),"Phương Viên"))
				title="%s · %s (%d) [%s]"%[hero_name,army.unit_type.capitalize(),army.troops,stance_tag]
			var width: float=font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x
			var tag_rect:=Rect2(center+Vector2(-width*.5-5,-20),Vector2(width+10,16))
			draw_rect(tag_rect,Color("120e0a",0.88))
			draw_rect(Rect2(tag_rect.position,Vector2(2.5,16)),T.FACTION[army.faction])
			_world_text(center+Vector2(-width*.5+1,-8),title,11,T.WORLD_ACCENT if selected else T.INK)
	if control._dragging:
		var selection:=Rect2(control._drag_start,get_viewport().get_mouse_position()-control._drag_start).abs()
		draw_rect(selection,Color(M.TEXT,.06));draw_rect(selection,Color(M.TEXT,.7),false,1)

	_draw_combat_clashes(clip)
	_draw_routes(clip)
	_draw_waypoints(clip)
	_draw_skill_effects(clip)
	_draw_battle_ticker(clip)
	# Transient target feedback stays visible above over-map army standards.
	if indicator_position.is_finite():
		for destination in indicator_destinations:
			var metrics: Dictionary=TargetIndicator.draw(self,map.camera,_surface,indicator_position if indicator_target.get("kind")=="army" else destination.point,indicator_started_msec,Time.get_ticks_msec(),indicator_order,clip,_blockers,destination.direction)
			indicator_metrics=metrics

func _draw_combat_clashes(clip: Rect2) -> void:
	if map.distance>140:return
	var sim=map.simulation
	var drawn_pairs: Dictionary={}
	var clock: float=(float(sim.tick)+clampf(float(sim.accumulator_us)/100000.0,0.0,1.0))*.1
	for id in sim._sorted_ids(sim.armies):
		var a: Dictionary=sim.armies[id]
		if a.troops<=0 or a.routed or a.engaged_ids.is_empty():continue
		for enemy_id in a.engaged_ids:
			if not sim.armies.has(enemy_id):continue
			var b: Dictionary=sim.armies[enemy_id]
			if b.troops<=0 or b.faction==a.faction:continue
			var pair_key: String=id+"|"+enemy_id if id<enemy_id else enemy_id+"|"+id
			if drawn_pairs.has(pair_key):continue
			drawn_pairs[pair_key]=true
			var pa: Vector3=_actor_point(id);var pb: Vector3=_actor_point(enemy_id)
			var mid: Vector3=(pa+pb)*.5+Vector3.UP*1.25
			if map.camera.is_position_behind(mid):continue
			var screen: Vector2=map.camera.unproject_position(mid)
			if not Geo.visible_box(Rect2(screen-Vector2.ONE*16,Vector2.ONE*32),clip,_blockers):continue
			var phase: float=fposmod(clock*1.35+float(pair_key.hash()%17)*.07,1.0)
			var pulse: float=sin(phase*PI)
			# Expanding shockwave ring + warm weapon clash glow
			draw_circle(screen,6.5+3.0*pulse,Color(0.08,0.05,0.03,0.55))
			draw_arc(screen,6.0+6.5*phase,0,TAU,20,Color(1.0,.76,.28,(1.0-phase)*.75),1.8,true)
			var d: float=5.5+1.5*pulse
			draw_line(screen+Vector2(-d,-d),screen+Vector2(d,d),Color(1.0,.94,.76,.92),2.2,true)
			draw_line(screen+Vector2(-d,d),screen+Vector2(d,-d),Color(1.0,.94,.76,.92),2.2,true)
			# Flying directional sparks on weapon impact
			for s_idx in range(4):
				var ang: float=s_idx*PI*.5+phase*2.4
				var r0: float=3.5+phase*5.0
				var r1: float=r0+3.5*(1.0-phase)
				var dir:=Vector2(cos(ang),sin(ang))
				draw_line(screen+dir*r0,screen+dir*r1,Color(1.0,.84,.38,(1.0-phase)*.85),1.4,true)
	# Draw active volley impact dust / target ring when arrows land
	var volleys=sim.get("pending_volleys")
	if volleys is Array:
		for shot in volleys:
			var rem: float=float(shot.impact_tick)*.1-clock
			if rem>-.22 and rem<.12 and shot.get("goal") is Array:
				var gx: float=float(shot.goal[0])/10.0;var gz: float=float(shot.goal[1])/10.0
				var gpos:=Vector3(gx,_surface(gx,gz)+.2,gz)
				if map.camera.is_position_behind(gpos):continue
				var sp: Vector2=map.camera.unproject_position(gpos)
				if not Geo.visible_box(Rect2(sp-Vector2.ONE*14,Vector2.ONE*28),clip,_blockers):continue
				var impact_u: float=clampf(1.0-absf(rem)/.22,0.0,1.0)
				draw_arc(sp,4.0+9.0*(1.0-impact_u),0,TAU,16,Color(1.0,.82,.45,impact_u*.65),1.6,true)

func _draw_gates(clip: Rect2) -> void:
	if map.controller.selected_armies.is_empty() or map.distance>150:return
	var sim=map.simulation
	for city_id in sim._sorted_ids(sim.cities):
		if sim.cities[city_id].owner==map.controller.player_faction:continue
		var gates: Array=sim.gate_nodes(city_id)
		for i in range(gates.size()):
			if not map.controller.node_positions.has(gates[i]):continue
			var world: Vector3=map.controller.node_positions[gates[i]]+Vector3.UP*.2
			if map.camera.is_position_behind(world):continue
			var point: Vector2=map.camera.unproject_position(world)
			if not Geo.visible_box(Rect2(point-Vector2.ONE*8,Vector2.ONE*16),clip,_blockers):continue
			if point.distance_to(get_local_mouse_position())<16:_world_text(point+Vector2(9,-8),"Gate %d"%(i+1),12,T.WORLD_ERROR)

func _unit_ring(world: Vector3, radius: float, color: Color, width: float, clip: Rect2) -> void:
	var previous:=Vector2.INF
	for i in range(33):
		var point:=world+Vector3(cos(TAU*i/32.0),0,sin(TAU*i/32.0))*radius
		point.y=_surface(point.x,point.z)+.14
		if map.camera.is_position_behind(point):previous=Vector2.INF;continue
		var screen: Vector2=map.camera.unproject_position(point)
		if previous.is_finite():
			_draw_visible(previous,screen,T.WORLD_BASE,width+2.0,clip);_draw_visible(previous,screen,color,width,clip)
		previous=screen

func _draw_defense_range(clip: Rect2) -> void:
	var id: String=map.controller.selected_city
	if id.is_empty() or not map.simulation.cities.has(id):return
	var city: Dictionary=map.simulation.cities[id]
	if city.garrison<=0:return
	for gate in map.simulation.gate_nodes(id):
		if not map.controller.node_positions.has(gate):continue
		var point: Vector3=map.controller.node_positions[gate]
		_unit_ring(point,map.simulation.Tactical.GUARD_RANGE/10.0,Color(T.FACTION[city.owner],.35),1.0,clip)

func _draw_waypoints(clip: Rect2) -> void:
	for id in map.controller.selected_armies:
		if not map.simulation.armies.has(id):continue
		var army: Dictionary=map.simulation.armies[id]
		var queue: Array=army.get("waypoints",[])
		if queue.is_empty():continue
		var prev_point: Vector3=Vector3.ZERO
		if not army.get("route",[]).is_empty():
			var last_node: String=str(army.route[-1])
			if map.controller.node_positions.has(last_node):prev_point=map.controller.node_positions[last_node]+Vector3.UP*.14
		if prev_point==Vector3.ZERO:
			prev_point=map.controller.interpolated_position(id)+Vector3.UP*.14
		for index in range(queue.size()):
			var node: String=map.simulation._target_node(queue[index])
			if not map.controller.node_positions.has(node):continue
			var point: Vector3=map.controller.node_positions[node]+Vector3.UP*.14
			_route_line(prev_point,point,false,clip)
			prev_point=point
			if map.camera.is_position_behind(point):continue
			var screen: Vector2=map.camera.unproject_position(point)
			if not Geo.visible_box(Rect2(screen-Vector2(8,8),Vector2(16,16)),clip,_blockers):continue
			var marker:=Rect2(screen-Vector2.ONE*6,Vector2.ONE*12)
			draw_rect(marker,T.WORLD_BASE);draw_rect(marker,T.ACCENT,false,1.2)
			_world_text(screen+Vector2(-4,4),str(index+1),12,T.ACCENT)

func _surface(x: float,z: float) -> float:
	var ground: float=float(map.controller.ground_sampler.call(x,z))
	if map.simulation.get("river_navigation")!=null and map.simulation.river_navigation.contains(Vector2(x,z)*10):return maxf(.30,ground)
	return ground

var _dash_phase: float=0.0

func _route_line(a: Vector3,b: Vector3,ferry: bool,clip: Rect2) -> void:
	if map.camera.is_position_behind(a) or map.camera.is_position_behind(b):return
	var start: Vector2=map.camera.unproject_position(a);var finish: Vector2=map.camera.unproject_position(b)
	var length: float=start.distance_to(finish)
	# Guidance routes are drawn as dashed lines. The dash phase continues across
	# sampled segments and slowly marches toward the destination.
	var color:=Color("91c7ee",.78) if ferry else Color("e6f2dc",.78)
	var shadow:=Color(0.05,0.07,0.06,.42)
	var pattern:=Vector2(6,5) if ferry else Vector2(9,6)
	var march: float=-float(Time.get_ticks_msec()%100000)*.018
	for run in Geo.pattern_runs(length,_dash_phase+march,pattern):
		var p0: Vector2=start.lerp(finish,run.x/maxf(.001,length));var p1: Vector2=start.lerp(finish,run.y/maxf(.001,length))
		_draw_visible(p0,p1,shadow,3.2,clip)
		_draw_visible(p0,p1,color,1.7,clip)
	_dash_phase+=length

func _draw_routes(clip: Rect2) -> void:
	var sim=map.simulation;var control=map.controller;var seen: Dictionary={}
	for id in control.selected_armies:
		if not sim.armies.has(id):continue
		var army: Dictionary=sim.armies[id];var current: Vector3=control.interpolated_position(id)
		_dash_phase=0.0
		if army.transport_elapsed>0:
			for boat in sim.vessels.values():
				if boat.request!="army:"+id or boat.phase!="occupied":continue
				var path: Array=boat.path;var best: int=0;var distance: float=INF
				for i in range(path.size()-1):
					var a: Vector3=sim.river_navigation.position(path[i])/10;var b: Vector3=sim.river_navigation.position(path[i+1])/10
					var nearest: Vector3=Geometry3D.get_closest_point_to_segment(current,a,b)
					if nearest.distance_squared_to(current)<distance:distance=nearest.distance_squared_to(current);best=i+1
				var previous: Vector3=current
				for i in range(best,path.size()):
					var next: Vector3=sim.river_navigation.position(path[i])/10;next.y=.44
					_route_line(previous,next,true,clip);previous=next
				_route_line(previous,control.node_positions[army.route[0]]+Vector3.UP*.14,true,clip)
			var proxy: Dictionary=army.duplicate(true);proxy.node=proxy.route.pop_front();army=proxy;current=control.node_positions[proxy.node]
		for leg in Routes.movement_legs(army,current,control.node_positions,sim.world_metadata.crossings):
			var identity: String=str(leg.key)
			if seen.has(identity):route_metrics.deduplicated_legs+=1;continue
			seen[identity]=true
			var points: PackedVector3Array=Routes.sample_leg(leg,_surface,2)
			if leg.kind=="ferry" and identity.contains("|"):
				var ends: PackedStringArray=identity.split("|")
				var crossing: Dictionary=sim._crossing_by_edge.get(sim._edge_key(ends[0],ends[1]),{})
				if not crossing.is_empty():
					var index: int=crossing.nodes.find(ends[0]);var trip: Dictionary=sim.river_navigation.route(crossing.docks[index],crossing.docks[1-index])
					if trip.ok:
						points=PackedVector3Array([leg["from"]+Vector3.UP*.14])
						for node in trip.route:
							var p: Vector3=sim.river_navigation.position(node)/10;p.y=.44;points.append(p)
						points.append(leg["to"]+Vector3.UP*.14)
			for i in range(points.size()-1):_route_line(points[i],points[i+1],leg.kind=="ferry",clip)
			if leg.kind=="ferry":route_metrics.ferry_runs+=1
			else:route_metrics.ground_runs+=1

func _draw_visible(a: Vector2, b: Vector2, color: Color, width: float, clip: Rect2) -> void:
	for part in Geo.visible_line(a,b,clip,_blockers):draw_line(part[0],part[1],color,width,true)

func _world_text(point: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string_outline(font,point,text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,3,M.INK)
	draw_string(font,point,text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _actor_point(id: String) -> Vector3:
	if map.get("source_unit_view")!=null and map.source_unit_view.has_method("hud_position"):
		return map.source_unit_view.hud_position(id)
	if map.get("source_unit_view")!=null and map.source_unit_view.has_method("display_position"):
		return map.source_unit_view.display_position(id)
	return map.controller.grounded_position(id)

func _draw_skill_effects(clip: Rect2) -> void:
	var sim=map.simulation
	var now: int=Time.get_ticks_msec()
	if sim.events.size()<_last_skill_event_idx:_last_skill_event_idx=0;_skill_banners.clear()
	while _last_skill_event_idx<sim.events.size():
		var ev: Dictionary=sim.events[_last_skill_event_idx];_last_skill_event_idx+=1
		if str(ev.get("type",ev.get("kind","")))=="commander_skill":
			var officer_id: String=str(ev.get("officer",""))
			var army_id: String=str(ev.get("army",""))
			var def: Dictionary=sim.Officers.DEFINITIONS.get(officer_id,{})
			var pos: Vector3=_actor_point(army_id) if sim.armies.has(army_id) else Vector3.ZERO
			var targets: Array=ev.get("targets",[])
			if not targets.is_empty() and sim.armies.has(str(targets[0])):pos=_actor_point(str(targets[0]))
			_skill_banners.append({
				"officer":officer_id,"name":str(def.get("name","Commander")),
				"skill":str(ev.get("skill",def.get("skill","Skill"))),
				"faction":str(def.get("faction","wei")),
				"portrait":str(def.get("portrait","")),
				"point":pos,"started":now,"until":now+3200
			})
	var active: Array=[]
	for item in _skill_banners:
		if now<int(item.until):active.append(item)
	_skill_banners=active
	if _skill_banners.is_empty():return
	for item in _skill_banners:
		var u: float=clampf(float(now-int(item.started))/1800.0,0.0,1.0)
		if u<1.0 and Vector3(item.point).is_finite() and not map.camera.is_position_behind(item.point):
			var sp: Vector2=map.camera.unproject_position(item.point+Vector3.UP*.35)
			if clip.has_point(sp):
				var radius: float=12.0+46.0*u
				var col: Color=T.FACTION.get(item.faction,T.ACCENT)
				draw_arc(sp,radius,0,TAU,28,Color(col.r,col.g,col.b,(1.0-u)*.82),2.6,true)
				draw_arc(sp,radius*.65,0,TAU,24,Color(1.0,.88,.48,(1.0-u)*.75),1.8,true)
	var banner: Dictionary=_skill_banners[-1]
	var age: float=float(now-int(banner.started))/3200.0
	var alpha: float=clampf(minf(age*6.0,(1.0-age)*4.0),0.0,1.0)
	var vp: Vector2=get_viewport().get_visible_rect().size
	var box:=Rect2(Vector2(vp.x*.5-156,14),Vector2(312,54))
	if not Geo.visible_box(box,clip,_blockers):return
	draw_rect(box.grow(2),Color(0.05,0.04,0.03,0.92*alpha))
	draw_rect(box,Color("18120c",0.94*alpha))
	var fcol: Color=T.FACTION.get(banner.faction,T.ACCENT)
	draw_rect(Rect2(box.position,Vector2(4,box.size.y)),Color(fcol.r,fcol.g,fcol.b,alpha))
	draw_rect(box,Color(T.ACCENT.r,T.ACCENT.g,T.ACCENT.b,0.85*alpha),false,1.5)
	var p_path: String="res://"+str(banner.portrait)
	if not str(banner.portrait).is_empty():
		if not _portrait_cache.has(p_path):_portrait_cache[p_path]=load(p_path) as Texture2D
		var tex: Texture2D=_portrait_cache[p_path]
		if tex!=null:draw_texture_rect(tex,Rect2(box.position+Vector2(8,5),Vector2(38,44)),false,Color(1,1,1,alpha))
	_world_text(box.position+Vector2(54,23),str(banner.name).to_upper()+" · CHIẾN KỸ",12,Color(T.ACCENT.r,T.ACCENT.g,T.ACCENT.b,alpha))
	_world_text(box.position+Vector2(54,43),"「 "+str(banner.skill)+" 」",15,Color(1.0,.95,.82,alpha))

func _draw_battle_ticker(clip: Rect2) -> void:
	if app==null:return
	var recent: Array=app.recent_events(3)
	if recent.is_empty():return
	var x0: float=14.0;var y0: float=14.0
	for i in range(recent.size()):
		var ev: Dictionary=recent[i]
		var line: String="%02d:%02d  %s"%[int(ev.tick)/600,(int(ev.tick)/10)%60,str(ev.text)]
		var w: float=font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x+16
		var row_box:=Rect2(Vector2(x0,y0+i*20),Vector2(w,18))
		if not Geo.visible_box(row_box,clip,_blockers):continue
		var fade: float=1.0-float(i)*.22
		draw_rect(row_box,Color(0.07,0.06,0.05,0.76*fade))
		draw_rect(Rect2(row_box.position,Vector2(2.5,row_box.size.y)),Color(T.ACCENT.r,T.ACCENT.g,T.ACCENT.b,0.85*fade))
		_world_text(row_box.position+Vector2(8,13),line,12,Color(T.INK.r,T.INK.g,T.INK.b,fade))
