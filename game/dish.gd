class_name Dish
extends Resource

## One servable dish. The file name is the dish name. Components are ingredient
## types and may repeat (a burger's two slices); scoring matches by count.

@export var components: Array[String] = []
## Should be plated before the others - a small penalty if not. Optional.
@export var base: String = ""
## How a tagged plate arranges the components. Display only, never scored.
@export_enum("stack", "fan") var layout: String = "stack"
