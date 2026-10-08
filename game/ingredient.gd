class_name Ingredient
extends Resource

## One ingredient type. The file name is the type - `tomato.tres` defines "tomato" -
## so there is one source of truth and nothing to keep in sync. Ingredients loads and
## indexes every one of these under res://data/ingredients/.

@export var color: Color = Color.WHITE
## Prep steps in order. A station performs a step only if it is the item's next
## unfinished one. Empty for a finished portion or a transform-only type.
@export var steps: Array[Ingredients.Verb] = []
@export var scene: PackedScene
## A dispenser: once prepped, the whole peels `uses` portions of this type.
@export var dispenses: String = ""
@export var uses: int = 0
## A dispenser that can be picked before its prep step - a raw bird gives raw pieces,
## a roasted one gives roasted pieces. A loaf can't be sliced raw; a chicken can be jointed.
@export var dispenses_raw: bool = false
## What a dispenser becomes once picked clean (a chicken leaves bones). Empty: it's gone.
@export var remainder: String = ""
## A transform: `method` turns these inputs into this type. A multiset - repeat a type
## to need two of it. An input must be fully prepped unless the entry is prefixed
## "any " ("any potato": whole or chopped, either boils). Empty for a plain ingredient.
## STOVE takes exactly one input and converts it 1:1 (bread -> toasted_bread); POT
## takes any set and the pot then holds `yields` portions of this (bones + water ->
## stock). Every transform is declared here on its OUTPUT, never on the input.
@export var made_from: Array[String] = []
@export var method: Ingredients.Method = Ingredients.Method.STOVE
@export var yields: int = 0
## Seconds for this type to cook from raw to the top of Perfect. 0 = the stove's
## default. A long cook is also a wide one - every band scales with it - so a stock
## that takes a minute has a generous window before it burns.
@export var cook_time: float = 0.0
