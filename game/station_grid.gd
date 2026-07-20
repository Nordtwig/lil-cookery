extends Node

## Source of truth for which station occupies which floor cell. Cells are
## just rounded (x, z) world coordinates, since every station already sits
## on integer coordinates. Every Station self-registers here in _ready() and
## unregisters in _exit_tree(), so this is a passive record of the scene as
## laid out today — nothing reads it yet. It's the foundation grid-based
## placement (moving a station at runtime) will build on.

var _occupied: Dictionary = {}  # Vector2i -> Station


func world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(roundi(pos.x), roundi(pos.z))


func cell_to_world(cell: Vector2i, y: float) -> Vector3:
	return Vector3(cell.x, y, cell.y)


func is_occupied(cell: Vector2i) -> bool:
	return _occupied.has(cell)


func get_station(cell: Vector2i) -> Station:
	return _occupied.get(cell)


## Registers a station at its own current position. Returns false (and warns)
## if another station already holds that cell — a real layout conflict, not
## something to silently paper over.
func register(station: Station) -> bool:
	var cell := world_to_cell(station.global_position)
	if _occupied.has(cell) and _occupied[cell] != station:
		push_warning("StationGrid: cell %s already held by %s, cannot register %s" % [cell, _occupied[cell].name, station.name])
		return false
	_occupied[cell] = station
	station.grid_cell = cell
	return true


func unregister(station: Station) -> void:
	if _occupied.get(station.grid_cell) == station:
		_occupied.erase(station.grid_cell)
