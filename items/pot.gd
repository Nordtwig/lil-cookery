class_name Pot
extends Item

## A vessel for combined ingredients - it runs the POT recipes (`Ingredients.recipes_for`).
## Fill it with inputs (any order; it only takes things that could still complete some
## recipe - prepped, unless the recipe's entry says "any"), set it on a stove and light
## the burner. It cooks like any
## other item: same gauge, same bands, same pull-to-score. Pull it once it's at least
## Good and the inputs become `yields` portions of the output, which the pot then
## peels out via the ordinary dispenser grammar - a pot of stock is a loaf of bread.
## Pull it too early and it's just a warm pot; put it back. An emptied pot is a pot
## again. Never plated, never trayed, never absorbed (no item_type, like Tray).
##
## Equipment, not an ingredient: finite, orderable, lost only if you lose it. Two pots
## are two things simmering; that's the pressure, not a clock.

const CAPACITY := 4
## Doneness a pot must reach before pulling it converts the inputs. Below this it
## just comes off as it went on. Matches the Good-band boundary.
const CONVERT_MIN := 0.5
const _CONTENT_SCALE := 0.6
const _RING := [Vector3(-0.08, 0.08, -0.08), Vector3(0.08, 0.08, -0.08), Vector3(-0.08, 0.08, 0.08), Vector3(0.08, 0.08, 0.08)]
## Broth before anything's cooked; the liquid tints from here toward the output's own color.
const _RAW_LIQUID := Color(0.80, 0.78, 0.70)

var contents: Array[Item] = []
## Water isn't an item - it's poured in from the sink and counts as the input
## "water" in every recipe check. No cup, nothing to carry or set down.
var has_water := false
var output_type := ""
var portions_left := 0
var _output_quality := -1.0

@onready var _liquid: MeshInstance3D = $Liquid
var _liquid_mat: StandardMaterial3D


func _ready() -> void:
	super._ready()
	_liquid_mat = StandardMaterial3D.new()
	_liquid.material_override = _liquid_mat
	_refresh_liquid()


# --- what the stove sees ---

func is_vessel() -> bool:
	return true


## Cookable exactly while it holds a complete set of inputs and no output yet.
func has_step(verb: int) -> bool:
	return verb == Ingredients.Verb.COOK and output_type == "" and recipe() != ""


func next_verb() -> int:
	return Ingredients.Verb.COOK if has_step(Ingredients.Verb.COOK) else -1


func step_done(_verb: int) -> bool:
	return false


## A cooked pot is "finished" (inert on a stove, like a baked loaf); so is an empty
## or half-filled one - there's nothing to cook.
func is_fully_prepped() -> bool:
	return not has_step(Ingredients.Verb.COOK)


func cook_time() -> float:
	return Ingredients.cook_time_for(recipe())


## The pull. At or past CONVERT_MIN the inputs become the output; below it nothing
## happens and doneness is kept, so the pot resumes when set back on heat. Output
## quality averages the cook's timing with what went in - good bones make good stock.
func lock_in_cook_score(score: float) -> void:
	if output_type != "" or doneness < CONVERT_MIN:
		return
	var out := recipe()
	if out == "":
		return
	var total := 0.0
	for c in contents:
		total += c.quality_value()
		c.queue_free()
	var mean_in := total / contents.size() if not contents.is_empty() else score
	contents.clear()
	has_water = false
	output_type = out
	portions_left = Ingredients.yields_for(out)
	_output_quality = clampf((score + mean_in) / 2.0, 0.0, 1.0)
	doneness = 0.0
	_refresh_liquid()


func quality_value() -> float:
	return _output_quality if _output_quality >= 0.0 else 0.0


# --- filling ---

## The POT recipe whose inputs exactly match what's in here, or "".
func recipe() -> String:
	var have := _counts(_content_types())
	for type in Ingredients.recipes_for(Ingredients.Method.POT):
		if _counts(_input_types(type)) == have and _prep_satisfied(type):
			return type
	return ""


## Only while raw, only if some recipe could still be completed with this added - the
## exact-match rule stated positively. An unprepped input needs a recipe that takes
## that type in any state (a whole potato boils; a whole onion doesn't make sauce).
func can_absorb(item: Item) -> bool:
	if item == null or not can_absorb_type(item.item_type):
		return false
	return item.is_fully_prepped() or _some_recipe_takes_any(item.item_type)


func can_absorb_type(type: String) -> bool:
	if type == "" or output_type != "" or contents.size() >= CAPACITY:
		return false
	var would := _content_types()
	would.append(type)
	var have := _counts(would)
	for candidate in Ingredients.recipes_for(Ingredients.Method.POT):
		var need := _counts(_input_types(candidate))
		var fits := true
		for t in have:
			if have[t] > need.get(t, 0):
				fits = false
				break
		if fits:
			return true
	return false


## Every unprepped content is covered by an "any" entry of this recipe.
func _prep_satisfied(recipe_type: String) -> bool:
	for c in contents:
		if not c.is_fully_prepped() and not _recipe_takes_any(recipe_type, c.item_type):
			return false
	return true


func _some_recipe_takes_any(type: String) -> bool:
	for candidate in Ingredients.recipes_for(Ingredients.Method.POT):
		if _recipe_takes_any(candidate, type):
			return true
	return false


static func _recipe_takes_any(recipe_type: String, type: String) -> bool:
	for entry in Ingredients.made_from_for(recipe_type):
		if Ingredients.input_any(entry) and Ingredients.input_type(entry) == type:
			return true
	return false


## A recipe's input types with the "any " prefix stripped.
static func _input_types(recipe_type: String) -> Array:
	return Ingredients.made_from_for(recipe_type).map(Ingredients.input_type)


func absorb(item: Item) -> void:
	item.attach_to(self)
	contents.append(item)
	_arrange()
	_refresh_liquid()


## From the sink's tap. Only while a recipe could still want water.
func can_fill_water() -> bool:
	return can_absorb_type("water")


func fill_water() -> void:
	has_water = true
	_refresh_liquid()


# --- dispensing the output ---

func is_dispenser() -> bool:
	return output_type != ""


func can_dispense() -> bool:
	return output_type != "" and portions_left > 0


func dispensed_portion_type() -> String:
	return output_type


func dispense(host: Node) -> Item:
	var portion: Item = Ingredients.scene_for(output_type).instantiate()
	portion.item_type = output_type
	host.add_child(portion)
	portion.inherited_quality = _output_quality
	portions_left -= 1
	if portions_left == 0:
		output_type = ""
		_output_quality = -1.0
	_refresh_liquid()
	return portion


func frees_when_empty() -> bool:
	return false


func is_unmodified() -> bool:
	return contents.is_empty() and not has_water and output_type == ""


# --- visuals ---

## The body keeps its own color; the liquid is what cooks.
func _update_tint() -> void:
	_mat.albedo_color = color
	_refresh_liquid()


func _refresh_liquid() -> void:
	if _liquid == null:
		return
	if output_type != "":
		_liquid.visible = true
		_liquid_mat.albedo_color = Ingredients.color_for(output_type)
		var fill := float(portions_left) / maxf(1.0, Ingredients.yields_for(output_type))
		_liquid.scale = Vector3(1.0, maxf(fill, 0.05), 1.0)
		return
	# Water shows as soon as it's poured in, so a filled pot reads as filled before
	# anything's cooking; the cook shade then starts from that blue.
	var cooking := has_step(Ingredients.Verb.COOK) and doneness > 0.0
	_liquid.visible = cooking or has_water
	if not cooking:
		if has_water:
			_liquid_mat.albedo_color = Ingredients.color_for("water")
			_liquid.scale = Vector3.ONE
		return
	var start := Ingredients.color_for("water") if has_water else _RAW_LIQUID
	var target := Ingredients.color_for(recipe())
	var shade: Color
	if doneness <= 1.0:
		shade = start.lerp(target, clampf(doneness, 0.0, 1.0))
	else:
		var char_t := clampf((doneness - 1.0) / (BURNT_CAP - 1.0), 0.0, 1.0)
		shade = target.lerp(Color(0.08, 0.07, 0.06), char_t)
	_liquid_mat.albedo_color = shade
	_liquid.scale = Vector3.ONE


func _arrange() -> void:
	for i in contents.size():
		var item := contents[i]
		item.scale = Vector3.ONE * _CONTENT_SCALE
		item.position = _RING[i]
		item.rotation = Vector3.ZERO


func _content_types() -> Array[String]:
	var out: Array[String] = []
	for c in contents:
		out.append(c.item_type)
	if has_water:
		out.append("water")
	return out


static func _counts(types: Array) -> Dictionary:
	var out := {}
	for t in types:
		out[t] = out.get(t, 0) + 1
	return out


func hint_name() -> String:
	return "Pot of %s" % output_type.capitalize() if output_type != "" else "Pot"


func get_inspect_text() -> String:
	if output_type != "":
		return "POT: %s %d/%d (%d%%)" % [output_type.capitalize(), portions_left, Ingredients.yields_for(output_type), int(round(_output_quality * 100))]
	if contents.is_empty():
		return "POT (empty)"
	var names := ", ".join(_content_types().map(func(t): return t.capitalize()))
	var out := recipe()
	if out == "":
		return "POT: %s" % names
	if doneness > 0.0:
		return "POT: %s -> %s (%s)" % [names, out.capitalize(), current_cook_band().capitalize()]
	return "POT: %s -> %s (ready to cook)" % [names, out.capitalize()]
