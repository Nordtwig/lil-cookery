class_name DataDir

## Loads every .tres in a folder into {file stem: resource}. The folder is the table
## and the file name is the key - what a table editor edits and what the game reads.

static func load_all(dir_path: String, type: Script) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("DataDir: cannot open %s" % dir_path)
		return out
	var files := dir.get_files()
	files.sort()
	for file in files:
		# An exported build may list "x.tres.remap"; load() follows the remap itself.
		var name := file.trim_suffix(".remap")
		if not name.ends_with(".tres"):
			continue
		var res := load(dir_path.path_join(name))
		if res == null or not is_instance_of(res, type):
			push_error("DataDir: %s/%s is not a %s" % [dir_path, name, type.get_global_name()])
			continue
		out[name.get_basename()] = res
	return out


## Reports every cycle-forming node in a directed graph {node: [nodes it points to]}.
## Nodes named but absent from the graph are ignored - existence is checked elsewhere.
static func find_cycles(edges: Dictionary) -> Array[String]:
	var bad: Array[String] = []
	var done := {}
	for start in edges:
		var stack := [start]
		var path := {}
		while not stack.is_empty():
			var node = stack.back()
			if node in done:
				stack.pop_back()
				continue
			if node in path:
				path.erase(node)
				done[node] = true
				stack.pop_back()
				continue
			path[node] = true
			for next in edges.get(node, []):
				if next in path:
					if next not in bad:
						bad.append(next)
				elif next not in done and next in edges:
					stack.append(next)
	return bad
