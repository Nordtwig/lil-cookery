class_name Crate
extends Station

## Infinite ingredient source: interact with free hands to get a fresh item.
## The lid mesh is tinted with the item color so crates are tellable apart.

const ITEM_SCENE := preload("res://items/item.tscn")

@export var item_type := "tomato"
@export var item_color := Color(0.85, 0.2, 0.15)
@export var item_cookable := false

@onready var _content_mesh: MeshInstance3D = $ContentMesh


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = item_color
	_content_mesh.material_override = mat


func interact(player: Player) -> void:
	if player.held_item != null:
		return
	var item: Item = ITEM_SCENE.instantiate()
	item.item_type = item_type
	item.color = item_color
	item.cookable = item_cookable
	player.take_item(item)
