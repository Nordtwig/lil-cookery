class_name SlotStation
extends Station

## A station with a single item slot: interact takes the item if your hands
## are free, or puts down what you're carrying if the slot is free.
## Subclasses hook the placed/removed events to add behavior (e.g. cooking).
##
## Also handles dispensers — anything speaking Item's dispenser grammar
## (can_dispense/can_absorb/dispense/absorb): a baked loaf, a chopped head,
## a player-filled Tray. Once one is sitting in a slot, on *any* SlotStation
## (not just its own prep station), the same tap/hold shape applies both ways:
##   - Empty-handed: tap peels off one portion, hold takes the whole batch.
##   - Carrying something it can absorb: tap merges it in, hold merges it
##     and takes the whole batch in one motion.
## The reverse direction works too: carrying a container that can absorb the
## slot's item (a tray in hand, a finished patty on the stove) scoops it up
## on a plain tap — mirroring the carry-plate/station-component symmetry.
## The whole is a normal carryable Item, so relocating it is just picking it
## up and setting it down somewhere else, where it keeps offering portions.
## A vessel (Pot, Pan) is a dispenser too: tap acts on what's inside, hold lifts
## it. Carrying a plate to one plates a portion straight out of it.
##
## Subclasses gate what may be set down with accepts() (a stove takes only
## vessels) and hear about a held dispenser's contents changing while it stays
## in the slot (_on_portion_dispensed / _on_held_contents_changed - a stove
## scores a patty the moment it leaves the pan, not only when the pan lifts).
##
## Also handles untagging: empty-handed, holding interact on a tagged Plate
## sitting in the slot strips its order tag and hands the player back a real
## OrderTicket for it (reconstructed from Plate.tagged_dish/tagged_table_number)
## — same tap/hold shape as the dispenser (a quick tap still just takes the
## plate, tag untouched). The plate has to be set down for this on purpose —
## you'll want to relocate the ticket somewhere anyway, so it's never a dead end.

const _TAP_GRACE := 0.15
const _ORDER_TICKET_SCENE := preload("res://items/order_ticket.tscn")

## If set, this station spawns one instance of this scene into its slot at
## game start — how a one-time world seed (the kitchen's starting spice
## shaker, 2026-08-14) gets placed without a bespoke pre-placement mechanism,
## same "config lives as @export, per-instance" convention Crate's
## contained_type / CrateStack's starting_crate_type already use. Empty for
## every station that should just start bare (nearly all of them).
@export var start_item_scene: PackedScene

## What's "in the slot" — a plain var for every ordinary single-slot station
## (Counter, CookStation, CuttingBoard), but routed through two overridable
## methods so a subclass can redirect it elsewhere entirely (TrayFridge points
## this at whichever of several stacked slots is currently active) without
## touching a single line of the dispensing/combine/season/tag logic below.
var held_item: Item:
	get:
		return _get_held()
	set(value):
		_set_held(value)

var _held_backing: Item = null

var _pending_dispense_player: Player = null
var _dispense_press_elapsed := 0.0

## Empty-handed hold on a tagged plate strips the tag instead of taking it —
## see interact()/interact_hold() below. Separate pending state from the
## dispenser's, since a plate is never a dispenser (no conflict, but keeping
## them distinct avoids one hold accidentally resolving the other's timer).
var _pending_untag_player: Player = null
var _untag_press_elapsed := 0.0

## get_node_or_null, not $Slot: a station with no single fixed slot (again,
## TrayFridge) has no "Slot" node at all and overrides _slot_marker() instead,
## so this is simply never read in that case.
@onready var _slot: Marker3D = get_node_or_null("Slot")


func _ready() -> void:
	super._ready()
	if start_item_scene != null:
		var item: Item = start_item_scene.instantiate()
		item.attach_to(_slot_marker())
		held_item = item


func _get_held() -> Item:
	return _held_backing


func _set_held(value: Item) -> void:
	_held_backing = value


## Where a placed item physically attaches. Base: the one fixed Slot marker;
## TrayFridge overrides this to whichever stacked slot is currently active.
func _slot_marker() -> Marker3D:
	return _slot


func interact(player: Player) -> void:
	var carried := player.held_item
	if held_item != null and (
		(carried == null and held_item.can_dispense())
		or (carried != null and held_item.can_absorb(carried))
	):
		# Don't resolve immediately — wait to see if this turns into a hold
		# instead (peel/merge-one vs. take/absorb-everything). Note an empty
		# tray with empty hands falls straight through to a plain take — no
		# grace-window delay when there's nothing to peel.
		_pending_dispense_player = player
		_dispense_press_elapsed = 0.0
		return
	if carried == null and held_item is Plate and (held_item as Plate).is_tagged():
		# Don't resolve immediately — wait to see if this turns into a hold
		# instead (strip the tag rather than taking the plate).
		_pending_untag_player = player
		_untag_press_elapsed = 0.0
		return
	if carried == null and held_item != null:
		# Take the item off the station.
		var item := held_item
		held_item = null
		player.take_item(_on_item_removed(item))
	elif carried != null and held_item == null:
		# Place the carried item onto the empty slot, if this station takes it.
		if not accepts(carried):
			return
		var item := player.drop_item()
		item.attach_to(_slot_marker())
		held_item = item
		_on_item_placed(item)
	elif carried != null and held_item != null and carried.can_absorb(held_item):
		# Carrying a container that can take the slot's item (a tray in hand,
		# a finished patty on the stove): scoop it up — the mirror of the
		# carry-plate + station-component branch below. Runs through
		# _on_item_removed so a board/stove still locks in the score.
		var item := held_item
		held_item = null
		carried.absorb(_on_item_removed(item))
	elif carried != null and held_item != null and carried.can_dispense() and held_item.can_absorb_type(carried.dispensed_portion_type()):
		# Carrying a ready dispenser (a baked loaf, a chopped head), station
		# holds a container that takes its portions: peel one straight onto
		# it, skipping the hand — repeated taps empty the whole dispenser
		# into the tray (four taps deposits a chopped head's four scraps).
		held_item.absorb(carried.dispense(self))
		_on_held_contents_changed()
		if carried.spent():
			player.drop_item()
			carried.queue_free()
	elif carried != null and held_item != null and held_item.can_dispense() and carried.can_absorb_type(held_item.dispensed_portion_type()):
		# The mirror direction (2026-08-14 fix — this was missing entirely
		# since Crate stopped being a Station 2026-08-11, silently dropping its
		# old bespoke swipe-onto-a-carried-tray code): station holds a
		# dispenser (a Crate on a shelf, a baked loaf set down mid-prep),
		# carrying a container that takes its portions — peel one straight
		# onto it, skipping the hand. Repeated taps swipe a Tray full of an
		# ingredient straight off a shelf's Crate without a crate-to-hand-to-
		# tray round trip.
		var d := held_item
		carried.absorb(_dispense_from_held())
		if d.spent():
			held_item = null
			d.queue_free()
	elif carried is Plate and held_item != null and held_item.can_dispense() and (carried as Plate).can_add_type(held_item.dispensed_portion_type()):
		# Carrying a plate, station holds a vessel or dispenser with a plateable
		# portion inside: plate one straight out of it - a patty out of the pan
		# on the stove, a ladle of sauce from the pot, a slice off a loaf.
		var d := held_item
		(carried as Plate).add_component(_dispense_from_held())
		if d.spent():
			held_item = null
			d.queue_free()
	elif carried is Plate and (carried as Plate).can_add(held_item):
		# Carrying a plate, station holds a component: add it to the plate.
		var comp := held_item
		held_item = null
		(carried as Plate).add_component(_on_item_removed(comp))
	elif held_item is Plate and (held_item as Plate).can_add(carried):
		# Station holds a plate, carrying a component: add it to the plate.
		player.drop_item()
		(held_item as Plate).add_component(carried)
	elif carried is Spice and held_item != null and held_item.can_be_seasoned():
		# Carrying a shaker: season the item on the station. Infinite
		# uses — the shaker itself is never placed down here.
		var spice := carried as Spice
		held_item.season(spice.bonus, spice.color)
	elif carried is Spice and held_item is Plate:
		# Station holds a plate: season the first seasonable component on it
		# rather than gluing the shaker onto the plate as clutter.
		var spice := carried as Spice
		(held_item as Plate).season_component(spice.bonus, spice.color)
	elif carried is OrderTicket and held_item is Plate:
		# Carrying an order ticket, station holds a plate: tag it. If the
		# plate already carried a different tag, that one comes back as a real
		# ticket in the player's hand (the same ticket object, repurposed)
		# instead of silently vanishing — a straight swap, never a destroy.
		# Only a genuinely untagged plate consumes the carried ticket outright.
		var ticket := carried as OrderTicket
		var plate := held_item as Plate
		if plate.is_tagged():
			var old_dish := plate.tagged_dish()
			var old_table := plate.tagged_table_number()
			plate.tag_order(ticket.dish, ticket.table_number)
			ticket.dish = old_dish
			ticket.table_number = old_table
		else:
			plate.tag_order(ticket.dish, ticket.table_number)
			player.drop_item()
			carried.queue_free()
	elif held_item is OrderTicket and carried is Plate:
		# Station holds a ticket, carrying a plate: same tag, other direction
		# — same swap-not-destroy rule if the carried plate already had a
		# different tag.
		var ticket := held_item as OrderTicket
		var plate := carried as Plate
		if plate.is_tagged():
			var old_dish := plate.tagged_dish()
			var old_table := plate.tagged_table_number()
			plate.tag_order(ticket.dish, ticket.table_number)
			ticket.dish = old_dish
			ticket.table_number = old_table
		else:
			plate.tag_order(ticket.dish, ticket.table_number)
			held_item.queue_free()
			held_item = null


## The same ladder as interact(), naming each rung instead of doing it. Keep the
## two in the same order - a hint that names a verb a tap wouldn't do is worse
## than no hint.
func hints(player: Player) -> Array[Dictionary]:
	var carried := player.held_item
	var out: Array[Dictionary] = []
	if held_item != null and carried == null and held_item.can_dispense():
		out.append(hint("interact", "Take one %s" % held_item.dispensed_portion_type().capitalize()))
		out.append(hint("interact_hold", "Take %s" % held_item.hint_name()))
	elif held_item != null and carried != null and held_item.can_absorb(carried):
		out.append(hint("interact", "Put %s in %s" % [carried.hint_name(), held_item.hint_name()]))
		out.append(hint("interact_hold", "Take all"))
	elif carried == null and held_item is Plate and (held_item as Plate).is_tagged():
		out.append(hint("interact", "Pick up Plate"))
		out.append(hint("interact_hold", "Take the ticket off"))
	elif carried == null and held_item != null:
		out.append(hint("interact", "Pick up %s" % held_item.hint_name()))
	elif carried != null and held_item == null:
		if accepts(carried):
			out.append(hint("interact", "Put down %s" % carried.hint_name()))
	elif carried != null and held_item != null and carried.can_absorb(held_item):
		out.append(hint("interact", "Scoop %s" % held_item.hint_name()))
	elif carried != null and held_item != null and carried.can_dispense() and held_item.can_absorb_type(carried.dispensed_portion_type()):
		out.append(hint("interact", "Add %s to %s" % [carried.dispensed_portion_type().capitalize(), held_item.hint_name()]))
	elif carried != null and held_item != null and held_item.can_dispense() and carried.can_absorb_type(held_item.dispensed_portion_type()):
		out.append(hint("interact", "Take one %s into %s" % [held_item.dispensed_portion_type().capitalize(), carried.hint_name()]))
	elif carried is Plate and held_item != null and held_item.can_dispense() and (carried as Plate).can_add_type(held_item.dispensed_portion_type()):
		out.append(hint("interact", "Plate %s" % held_item.dispensed_portion_type().capitalize()))
	elif carried is Plate and (carried as Plate).can_add(held_item):
		out.append(hint("interact", "Plate %s" % held_item.hint_name()))
	elif held_item is Plate and (held_item as Plate).can_add(carried):
		out.append(hint("interact", "Plate %s" % carried.hint_name()))
	elif carried is Spice and held_item != null and held_item.can_be_seasoned():
		out.append(hint("interact", "Season %s" % held_item.hint_name()))
	elif carried is Spice and held_item is Plate:
		out.append(hint("interact", "Season the plate"))
	elif carried is OrderTicket and held_item is Plate:
		out.append(hint("interact", "Tag the plate"))
	elif held_item is OrderTicket and carried is Plate:
		out.append(hint("interact", "Tag the plate"))
	return out


func interact_hold(player: Player, delta: float) -> void:
	if held_item is Item and _pending_dispense_player == player:
		_dispense_press_elapsed += delta
		if _dispense_press_elapsed >= _TAP_GRACE:
			# Held long enough: a deliberate grab of the whole batch.
			_pending_dispense_player = null
			if player.held_item == null:
				_take_whole_dispenser(player)
			else:
				_absorb_and_take_whole(player)
	elif held_item is Plate and _pending_untag_player == player:
		_untag_press_elapsed += delta
		if _untag_press_elapsed >= _TAP_GRACE:
			# Held long enough: strip the tag and hand back a real ticket for
			# it. The plate stays put — this is never a take.
			_pending_untag_player = null
			_strip_tag_to_ticket(held_item as Plate, player)


func _process(_delta: float) -> void:
	if _pending_dispense_player != null:
		var p := _pending_dispense_player
		if not Input.is_action_pressed("p%d_interact" % p.player_id):
			# Released before the grace window elapsed — a genuine quick tap.
			_pending_dispense_player = null
			if p.held_item == null:
				_peel_one(p)
			else:
				_merge_one(p)
		return
	if _pending_untag_player != null:
		var p := _pending_untag_player
		if not Input.is_action_pressed("p%d_interact" % p.player_id):
			# Released before the grace window elapsed — a genuine quick tap:
			# take the plate normally, tag untouched.
			_pending_untag_player = null
			var item := held_item
			held_item = null
			p.take_item(_on_item_removed(item))


## A quick tap on a dispenser: hand over one portion, keep the rest. A whole
## that frees when empty (a loaf peeled to its last slice) is consumed; a
## container (Tray) just sits there empty, ready to refill.
func _peel_one(player: Player) -> void:
	var d := held_item
	if d == null or not d.can_dispense():
		return
	player.take_item(_dispense_from_held())
	if d.spent():
		held_item = null
		d.queue_free()


## A sustained empty-handed hold: take the whole batch to relocate it.
func _take_whole_dispenser(player: Player) -> void:
	var d := held_item
	if d == null:
		return
	held_item = null
	# Through the removal hook, like every other way an item leaves a slot - a
	# bird lifted whole off a stove mid-roast still gets its cook score locked.
	player.take_item(_on_item_removed(d))


## A quick tap while carrying something the batch can absorb: put it in.
func _merge_one(player: Player) -> void:
	var d := held_item
	if d == null or not d.can_absorb(player.held_item):
		return
	d.absorb(player.drop_item())
	_on_held_contents_changed()


## A sustained hold while carrying something the batch can absorb: put it in
## and take the whole (now one bigger) batch in the same motion.
func _absorb_and_take_whole(player: Player) -> void:
	var d := held_item
	if d == null:
		return
	if d.can_absorb(player.held_item):
		d.absorb(player.drop_item())
	held_item = null
	player.take_item(_on_item_removed(d))


## Hand out one portion from the held dispenser, telling the station about it
## first: a stove scores a patty as it leaves the pan, the way it would score it
## leaving the burner. Every dispense out of the slot goes through here.
func _dispense_from_held() -> Item:
	var portion := _on_portion_dispensed(held_item.dispense(self))
	_on_held_contents_changed()
	return portion


## Whether a carried item may be set down here. Base: anything. A stove takes
## only vessels.
func accepts(_item: Item) -> bool:
	return true


## A portion just left the held dispenser while the dispenser itself stays in
## the slot. Base: nothing to do.
func _on_portion_dispensed(portion: Item) -> Item:
	return portion


## The held item is still here but what's inside it changed (a pan filled or
## emptied by a tap). Base: nothing to do.
func _on_held_contents_changed() -> void:
	pass


## Reads the tag off before clearing it, so nothing is lost — the player gets
## a real OrderTicket back, not just a discarded tag.
func _strip_tag_to_ticket(plate: Plate, player: Player) -> void:
	var ticket: OrderTicket = _ORDER_TICKET_SCENE.instantiate()
	ticket.dish = plate.tagged_dish()
	ticket.table_number = plate.tagged_table_number()
	plate.clear_tag()
	player.take_item(ticket)


func _on_item_placed(_item: Item) -> void:
	pass


## Called whenever an item is about to leave the slot — taken by hand, or
## combined straight onto a carried plate — and returns whatever should
## actually go to that destination. The default just passes `item` through;
## CuttingBoard/CookStation override this to lock in a freshly-earned prep
## score before the item leaves.
func _on_item_removed(item: Item) -> Item:
	return item


## A plate on a counter, an ingredient on the cutting board, a patty on the
## stove — whatever's sitting in the slot is what's worth inspecting here,
## not the station itself. Empty slot -> nothing to add.
func get_inspect_text() -> String:
	if held_item != null:
		return held_item.get_inspect_text()
	return ""


func is_empty() -> bool:
	return held_item == null


func clear_contents() -> void:
	if held_item != null:
		held_item.queue_free()
		held_item = null
