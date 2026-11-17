extends RefCounted
const PriorityQueue=preload("res://scripts/rts_priority_queue.gd")
## Integer graph view and distance buckets. Positive costs preserve the original
## (distance, lexical node, lexical source) Dijkstra order without string heaps.
var ids: Array[String]=[]
var index: Dictionary[String,int]={}
var adjacency: Array[PackedInt32Array]=[]
var weights: Array[PackedInt64Array]=[]
var edge_codes: Array[PackedInt32Array]=[]
var code_by_key: Dictionary={}
var edge_count: int=0
var flat_neighbors:=PackedInt32Array()
var flat_weights:=PackedInt64Array()
var flat_codes:=PackedInt32Array()
var offsets:=PackedInt32Array()
var incoming_neighbors: Array[PackedInt32Array]=[]
var incoming_weights: Array[PackedInt64Array]=[]
var passable:=PackedByteArray()
var maximum_weight: int=0

func configure(nodes: Dictionary) -> void:
	ids.assign(nodes.keys());ids.sort();index.clear();adjacency.clear();weights.clear();edge_codes.clear();code_by_key.clear()
	maximum_weight=0;edge_count=0
	flat_neighbors.clear();flat_weights.clear();flat_codes.clear();offsets.resize(ids.size()+1)
	incoming_neighbors.clear();incoming_weights.clear()
	for i in range(ids.size()):incoming_neighbors.append(PackedInt32Array());incoming_weights.append(PackedInt64Array())
	passable.resize(ids.size())
	for i in range(ids.size()):index[ids[i]]=i;passable[i]=1 if nodes[ids[i]].get("passable",true) else 0
	for i in range(ids.size()):
		var neighbors: Array=nodes[ids[i]].edges.keys();neighbors.sort()
		var targets:=PackedInt32Array();var costs:=PackedInt64Array();var codes:=PackedInt32Array()
		for neighbor in neighbors:
			var other: int=index[neighbor]
			var key: String=ids[mini(i,other)]+"|"+ids[maxi(i,other)]
			if not code_by_key.has(key):code_by_key[key]=edge_count;edge_count+=1
			var code: int=code_by_key[key]
			targets.append(other);costs.append(int(nodes[ids[i]].edges[neighbor]));codes.append(code)
			maximum_weight=maxi(maximum_weight,int(nodes[ids[i]].edges[neighbor]))
		adjacency.append(targets);weights.append(costs);edge_codes.append(codes)
		offsets[i]=flat_neighbors.size();flat_neighbors.append_array(targets);flat_weights.append_array(costs);flat_codes.append_array(codes)
	offsets[ids.size()]=flat_neighbors.size()
	for current in range(ids.size()):
		for edge in range(offsets[current],offsets[current+1]):
			var other: int=flat_neighbors[edge]
			var starts: PackedInt32Array=incoming_neighbors[other];var costs: PackedInt64Array=incoming_weights[other]
			starts.append(current);costs.append(flat_weights[edge]);incoming_neighbors[other]=starts;incoming_weights[other]=costs

func solve(seeds: Array, blocked: Dictionary={}, blocked_edges: Dictionary={}, limit: int=-1, target: int=-1, respect_passable: bool=true) -> Dictionary:
	# Sparse heap fallback keeps the generic API safe for large positive costs;
	# campaign distances use the faster bounded integer buckets.
	if maximum_weight>4096 and limit<0:return _solve_heap(seeds,blocked,blocked_edges,limit,target,respect_passable)
	var n: int=ids.size()
	var distance:=PackedInt64Array();distance.resize(n);distance.fill(-1)
	var source:=PackedInt32Array();source.resize(n);source.fill(-1)
	var previous:=PackedInt32Array();previous.resize(n);previous.fill(-1)
	var settled:=PackedByteArray();settled.resize(n)
	var allowed_nodes:=passable.duplicate() if respect_passable else PackedByteArray()
	if not respect_passable:allowed_nodes.resize(n);allowed_nodes.fill(1)
	for id in blocked:
		var i: int=int(index.get(id,-1))
		if i>=0:allowed_nodes[i]=0
	var blocked_codes:=PackedByteArray();blocked_codes.resize(edge_count)
	var has_blocked_edges: bool=false
	for key in blocked_edges:
		var code: int=int(code_by_key.get(key,-1))
		if code>=0:blocked_codes[code]=1;has_blocked_edges=true
	var layers: Array=[];layers.resize(limit+1 if limit>=0 else 1024)
	var capacity: int=layers.size()
	var neighbors: PackedInt32Array=flat_neighbors;var costs: PackedInt64Array=flat_weights;var codes: PackedInt32Array=flat_codes;var edge_offsets: PackedInt32Array=offsets
	var discovered:=PackedInt32Array();var queued: int=0
	for seed in seeds:
		var i: int=seed[0]
		if distance[i]<0:discovered.append(i)
		distance[i]=0;source[i]=seed[1];previous[i]=-1
		if layers[0]==null:layers[0]=[]
		layers[0].append(i);queued+=1
	var cost: int=0;var visits: int=0
	while queued>0 and cost<capacity:
		if layers[cost]==null:cost+=1;continue
		var layer: Array=layers[cost];layer.sort();queued-=layer.size();layers[cost]=null
		for layer_index in range(layer.size()):
			var current: int=layer[layer_index]
			if settled[current]!=0 or distance[current]!=cost:continue
			settled[current]=1;visits+=1
			if current==target:return {"distance":distance,"source":source,"previous":previous,"discovered":discovered,"visits":visits}
			var current_source: int=source[current]
			for edge in range(edge_offsets[current],edge_offsets[current+1]):
				var other: int=neighbors[edge]
				if allowed_nodes[other]==0 or (has_blocked_edges and blocked_codes[codes[edge]]!=0):continue
				var next_cost: int=cost+costs[edge]
				if next_cost>65536 and limit<0:return _solve_heap(seeds,blocked,blocked_edges,limit,target,respect_passable)
				if limit>=0 and next_cost>limit:continue
				var known: int=distance[other]
				if known<0 or next_cost<known or (next_cost==known and current_source<source[other]):
					if known<0:discovered.append(other)
					distance[other]=next_cost;source[other]=current_source;previous[other]=current
					if next_cost>=capacity:capacity=next_cost+1024;layers.resize(capacity)
					if layers[next_cost]==null:layers[next_cost]=[]
					layers[next_cost].append(other);queued+=1
		cost+=1
	return {"distance":distance,"source":source,"previous":previous,"discovered":discovered,"visits":visits}

func _solve_heap(seeds: Array,blocked: Dictionary,blocked_edges: Dictionary,limit: int,target: int,respect_passable: bool) -> Dictionary:
	var n: int=ids.size()
	var distance:=PackedInt64Array();distance.resize(n);distance.fill(-1)
	var source:=PackedInt32Array();source.resize(n);source.fill(-1)
	var previous:=PackedInt32Array();previous.resize(n);previous.fill(-1)
	var settled:=PackedByteArray();settled.resize(n)
	var discovered:=PackedInt32Array();var visits: int=0
	var queue:=PriorityQueue.new()
	for seed in seeds:
		var i: int=seed[0]
		if distance[i]<0:discovered.append(i)
		distance[i]=0;source[i]=seed[1]
		queue.push(0,ids[i],str(seed[1]).pad_zeros(12))
	while not queue.is_empty():
		var item: Array=queue.pop();var current: int=index[item[1]];var cost: int=item[0]
		if settled[current]!=0 or distance[current]!=cost or source[current]!=int(item[2]):continue
		settled[current]=1;visits+=1
		if current==target:break
		for edge in range(adjacency[current].size()):
			var other: int=adjacency[current][edge]
			var a: int=mini(current,other);var b: int=maxi(current,other)
			if blocked.has(ids[other]) or blocked_edges.has(ids[a]+"|"+ids[b]) or (respect_passable and passable[other]==0):continue
			var next_cost: int=cost+weights[current][edge]
			if limit>=0 and next_cost>limit:continue
			if distance[other]<0 or next_cost<distance[other] or (next_cost==distance[other] and source[current]<source[other]):
				if distance[other]<0:discovered.append(other)
				distance[other]=next_cost;source[other]=source[current];previous[other]=current
				queue.push(next_cost,ids[other],str(source[other]).pad_zeros(12))
	return {"distance":distance,"source":source,"previous":previous,"discovered":discovered,"visits":visits}
