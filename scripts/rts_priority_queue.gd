extends RefCounted
## Stable binary min-heap. Duplicate entries are discarded by the pathfinder.
var entries: Array = []

func _less(a: Array, b: Array) -> bool:
	if a[0] != b[0]: return a[0] < b[0]
	if a[1] != b[1]: return str(a[1]) < str(b[1])
	return str(a[2]) < str(b[2])

func push(distance: int, node: String, source: String = "") -> void:
	var item: Array = [distance,node,source]
	entries.append(item)
	var i: int = entries.size()-1
	while i > 0:
		var parent: int = (i-1)/2
		if not _less(item,entries[parent]): break
		entries[i] = entries[parent]
		i = parent
	entries[i] = item

func pop() -> Array:
	var result: Array = entries[0]
	var last: Array = entries.pop_back()
	if entries.is_empty(): return result
	var i: int = 0
	while i*2+1 < entries.size():
		var child: int = i*2+1
		if child+1 < entries.size() and _less(entries[child+1],entries[child]): child += 1
		if not _less(entries[child],last): break
		entries[i] = entries[child]
		i = child
	entries[i] = last
	return result

func is_empty() -> bool:
	return entries.is_empty()
