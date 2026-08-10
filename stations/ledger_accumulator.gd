class_name LedgerAccumulator
extends Station

## One generic script drives all three bookkeeping origin fixtures (Till/
## ReceiptSpike/InvoiceFolder) — same data shape, only which GameState
## category and what it looks like differ, so those live as @export config
## per scene instance (the Ingredients.DEFS / Recipes.DEFS pattern) rather
## than three near-duplicate scripts.
##
## The pile visibly grows through SERVICE off whatever's *unclaimed* —
## GameState.ledger_value(category) minus whatever's already been swept into
## a slip today (_collected) — not the raw day total. Taking a slip sweeps
## the pile to empty immediately; if more of that category happens later the
## same day (a second restock, a late OrderDesk order at night), the pile
## starts growing again from zero and offers a fresh slip for just the new
## amount. This is a rough visual read, not a number, so it can replace the
## hidden HUD total with a felt sense of "busy" without spending the desk's
## actual reveal. NIGHT-only, empty-handed interact hands over a LedgerSlip.
## Refuses if there's nothing UNCLAIMED to report — no document exists for a
## category with zero activity, or one already fully swept, which is what
## makes LedgerDesk's requirement contextual (see LedgerDesk.missing()): no
## orders fulfilled today means no receipt to fetch, full stop. (The slip's
## `amount` is decorative only, not read by the actual bookkeeping math —
## GameState.file_books() always pulls the live day totals directly, so a
## partial pickup never loses money, it's purely what the pile shows.)

## "cash" | "receipts" | "invoices" — GameState.ledger_value() key.
@export var category := ""

## Shown on the slip and in inspect text, e.g. "TILL".
@export var display_name := ""

## Which LedgerSlip scene this fixture hands out — a coin stack for Till, a
## paper stack for ReceiptSpike, a folder stack for InvoiceFolder, set
## per-instance so the carried item actually looks like what it came from
## (a real gap Noah caught: every fixture used to hand out the same generic
## paper slip regardless of source).
@export var slip_scene: PackedScene

## Amount at which the pile visually maxes out — purely a display scale, not
## a cap on the real figure.
@export var pile_cap := 30

@onready var _pile: MeshInstance3D = $Pile
var _pile_bottom_y := 0.0
var _pile_full_height := 0.0

## How much of today's ledger_value(category) has already been swept into a
## slip. Reset to 0 whenever a fresh day's SERVICE begins, in lockstep with
## GameState's own ledger_* reset in start_service() — must stay in sync or
## _unclaimed() could go negative on a new day.
var _collected := 0


func _ready() -> void:
	super._ready()
	# Pin the pile's BASE (not its center) at whatever height it was
	# authored to sit at, so it grows upward off the counter surface as it
	# fills — scaling position proportionally to scale (the original
	# approach) implicitly pins the base at y=0 instead, which put a
	# near-empty pile floating near the counter's own origin rather than
	# resting on top of it.
	_pile_full_height = _pile.mesh.get_aabb().size.y * _pile.scale.y
	_pile_bottom_y = _pile.position.y - _pile_full_height / 2.0
	GameState.phase_changed.connect(_on_phase_changed)


func _on_phase_changed(phase: GameState.Phase) -> void:
	if phase == GameState.Phase.SERVICE:
		_collected = 0


func _unclaimed() -> int:
	return GameState.ledger_value(category) - _collected


func _process(_delta: float) -> void:
	var t := clampf(float(_unclaimed()) / pile_cap, 0.0, 1.0)
	# Never fully flattens to nothing even at 0 — a bare minimum sliver so
	# the fixture reads as "present, just empty right now," not broken.
	var scale_y := lerpf(0.08, 1.0, t)
	_pile.scale.y = scale_y
	_pile.position.y = _pile_bottom_y + (_pile_full_height * scale_y) / 2.0


func interact(player: Player) -> void:
	if player.held_item != null:
		return
	if GameState.phase != GameState.Phase.NIGHT:
		return
	var unclaimed := _unclaimed()
	if unclaimed <= 0:
		return
	var slip: LedgerSlip = slip_scene.instantiate()
	slip.category = category
	slip.display_name = display_name
	slip.amount = unclaimed
	player.take_item(slip)
	_collected += unclaimed


## The per-instance identity a respawned fixture needs back — which category
## it tracks, what it's called, how it's scaled, and what it hands out.
func get_config() -> Dictionary:
	return {
		"category": category,
		"display_name": display_name,
		"pile_cap": pile_cap,
		"slip_scene": slip_scene,
	}


func apply_config(config: Dictionary) -> void:
	category = config.get("category", category)
	display_name = config.get("display_name", display_name)
	pile_cap = config.get("pile_cap", pile_cap)
	slip_scene = config.get("slip_scene", slip_scene)


func get_inspect_text() -> String:
	if _unclaimed() <= 0:
		return "%s\n(nothing to report today)" % display_name
	if GameState.phase != GameState.Phase.NIGHT:
		return "%s\n(check at night)" % display_name
	return "%s\nCarry to the bookkeeping desk to read it" % display_name
