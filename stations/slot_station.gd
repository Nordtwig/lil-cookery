class_name SlotStation
extends Station

## A station with a single item slot: interact takes the item if your hands
## are free, or puts down what you're carrying if the slot is free.
## Subclasses hook the placed/removed events to add behavior (e.g. cooking).
##
## Also handles IngredientBundle — a leftover batch from a yield ingredient's
## split (see CuttingBoard/CookStation's _on_item_removed overrides, which
## call _split_if_yield below). Once a bundle is sitting in a slot, on *any*
## SlotStation — not just wherever it was created — the same tap/hold shape
## applies both ways:
##   - Empty-handed: tap peels off one more piece, hold grabs the whole
##     remaining batch at once.
##   - Carrying a piece that matches the bundle: tap merges it back in
##     (count+1, hands empty), hold absorbs it *and* takes the whole
##     (now-bigger) batch in one motion.
## This is what lets a batch actually be relocated (to free up a board/
## stove, or bring scraps to a counter near the plates), keep offering
## pieces from wherever it's set down next, and take back a piece you'd
## already split off without it being stranded as its own separate object.

const _TAP_GRACE := 0.15

var held_item: Item = null

var _pending_bundle_player: Player = null
var _bundle_press_elapsed := 0.0

@onready var _slot: Marker3D = $Slot


func interact(player: Player) -> void:
	if held_item is IngredientBundle and _matches_bundle(player.held_item):
		# Don't resolve immediately — wait to see if this turns into a hold
		# instead (peel/merge-one vs. take/absorb-everything).
		_pending_bundle_player = player
		_bundle_press_elapsed = 0.0
		return
	var carried := player.held_item
	if carried == null and held_item != null:
		# Take the item off the station.
		var item := held_item
		held_item = null
		player.take_item(_on_item_removed(item))
	elif carried != null and held_item == null:
		# Place the carried item onto the empty slot.
		var item := player.drop_item()
		item.attach_to(_slot)
		held_item = item
		_on_item_placed(item)
	elif carried is Plate and (carried as Plate).can_add(held_item):
		# Carrying a plate, station holds a component: add it to the plate.
		var comp := held_item
		held_item = null
		(carried as Plate).add_component(_on_item_removed(comp))
	elif held_item is Plate and (held_item as Plate).can_add(carried):
		# Station holds a plate, carrying a component: add it to the plate.
		player.drop_item()
		(held_item as Plate).add_component(carried)
	elif carried is Spice and (carried as Spice).can_use() and held_item != null and held_item.can_be_seasoned():
		# Carrying a shaker with charges left: season the item on the
		# station and spend one charge. The shaker itself is never placed
		# down here — bring it back to its rack to refill once it's empty.
		var spice := carried as Spice
		held_item.season(spice.bonus, spice.color)
		spice.consume_use()
	elif carried is Spice and (carried as Spice).can_use() and held_item is Plate:
		# Station holds a plate: season the first seasonable component on it
		# rather than gluing the shaker onto the plate as clutter.
		var spice := carried as Spice
		if (held_item as Plate).season_component(spice.bonus, spice.color):
			spice.consume_use()
	elif carried is OrderTicket and held_item is Plate:
		# Carrying an order ticket, station holds a plate: tag it. The ticket
		# is consumed — its job was just to carry the order over.
		var ticket := carried as OrderTicket
		(held_item as Plate).tag_order(ticket.dish, ticket.table_label())
		player.drop_item()
		carried.queue_free()
	elif held_item is OrderTicket and carried is Plate:
		# Station holds a ticket, carrying a plate: same tag, other direction.
		var ticket := held_item as OrderTicket
		(carried as Plate).tag_order(ticket.dish, ticket.table_label())
		held_item.queue_free()
		held_item = null


func interact_hold(player: Player, delta: float) -> void:
	if held_item is IngredientBundle and _pending_bundle_player == player:
		_bundle_press_elapsed += delta
		if _bundle_press_elapsed >= _TAP_GRACE:
			# Held long enough: a deliberate grab of the whole batch.
			_pending_bundle_player = null
			if player.held_item == null:
				_take_whole_bundle(player)
			else:
				_absorb_and_take_whole_bundle(player)


func _process(_delta: float) -> void:
	if _pending_bundle_player == null:
		return
	var p := _pending_bundle_player
	if not Input.is_action_pressed("p%d_interact" % p.player_id):
		# Released before the grace window elapsed — a genuine quick tap.
		_pending_bundle_player = null
		if p.held_item == null:
			_peel_one(p)
		else:
			_merge_one(p)


func _on_item_placed(_item: Item) -> void:
	pass


## Called whenever an item is about to leave the slot — taken by hand, or
## combined straight onto a carried plate — and returns whatever should
## actually go to that destination. The default just passes `item` through
## unchanged; CuttingBoard/CookStation override this to substitute a single
## freshly-prepped piece (and stash the rest of a yield ingredient's batch
## back in the slot, via _split_if_yield below) so the split happens the
## same way regardless of which path took the item.
func _on_item_removed(item: Item) -> Item:
	return item


## True if `carried` is either nothing (empty-handed — peel/take-all) or a
## single real piece matching this station's bundle (merge/absorb-take-all).
func _matches_bundle(carried: Item) -> bool:
	if carried == null:
		return true
	return carried.item_type == (held_item as IngredientBundle).contained_type


## Call from a subclass's _on_item_removed once it's determined this was the
## item's first-ever completion (not a resumed re-chop/re-cook) and locked
## in `score`. Splits into a single returned piece plus a leftover bundle/
## piece in the slot if the ingredient yields more than one; otherwise
## returns `item` unchanged.
func _split_if_yield(item: Item, score: float) -> Item:
	var n := Ingredients.yield_for(item.item_type)
	if n <= 1:
		return item

	var item_type := item.item_type
	var doneness := item.doneness
	item.queue_free()

	var remaining := n - 1
	if remaining >= 2:
		var bundle: IngredientBundle = preload("res://items/ingredient_bundle.tscn").instantiate()
		bundle.contained_type = item_type
		bundle.count = remaining
		bundle.piece_doneness = doneness
		bundle.piece_score = score
		bundle.attach_to(_slot)
		held_item = bundle
	elif remaining == 1:
		held_item = _spawn_piece(item_type, doneness, score)
		held_item.attach_to(_slot)
	# remaining == 0: nothing left; held_item stays null (already cleared by
	# the caller before this was invoked).

	return _spawn_piece(item_type, doneness, score)


## A quick tap on a leftover batch: hand over one piece, keep the rest.
func _peel_one(player: Player) -> void:
	var bundle := held_item as IngredientBundle
	if bundle == null:
		return
	var piece := _spawn_piece(bundle.contained_type, bundle.piece_doneness, bundle.piece_score)
	player.take_item(piece)
	bundle.count -= 1
	if bundle.count <= 0:
		held_item = null
		bundle.queue_free()


## A sustained hold on a leftover batch, empty-handed: take the whole thing.
## If only one piece is actually left, hand over a real ingredient instead
## of a bundle wrapping a single piece — a "batch of one" isn't platable.
func _take_whole_bundle(player: Player) -> void:
	var bundle := held_item as IngredientBundle
	if bundle == null:
		return
	held_item = null
	if bundle.count <= 1:
		var piece := _spawn_piece(bundle.contained_type, bundle.piece_doneness, bundle.piece_score)
		player.take_item(piece)
		bundle.queue_free()
	else:
		player.take_item(bundle)


## A quick tap while carrying a piece that matches the batch: put it back.
func _merge_one(player: Player) -> void:
	var bundle := held_item as IngredientBundle
	if bundle == null:
		return
	var carried := player.drop_item()
	carried.queue_free()
	bundle.count += 1


## A sustained hold while carrying a matching piece: absorb it into the
## batch and take the whole (now one bigger) thing in the same motion.
func _absorb_and_take_whole_bundle(player: Player) -> void:
	var bundle := held_item as IngredientBundle
	if bundle == null:
		return
	var carried := player.drop_item()
	carried.queue_free()
	bundle.count += 1  # always >= 2 after absorbing — never the "batch of one" case
	held_item = null
	player.take_item(bundle)


## A freshly split-off piece has never itself been cooked, even though its
## doneness (hence tint) matches how well the source ended up — see
## Item._cook_started for why a later cook pass (e.g. toasting) still plays
## out fresh rather than picking up wherever the source left off. The
## recorded score/completeness is separate and always carried over exactly.
func _spawn_piece(item_type: String, doneness: float, score: float) -> Item:
	var piece: Item = Ingredients.scene_for(item_type).instantiate()
	piece.item_type = item_type
	add_child(piece)  # scratch-parented so _ready() fires; caller reparents it next
	# A split piece always shows its "piece" look (the CHOP_PIECES_AT gate is
	# purely visual here — the ingredient may have no CHOP step at all, e.g.
	# a baked bread slice), regardless of which verb actually produced it.
	piece.chop_progress = Item.CHOP_PIECES_AT
	piece.doneness = doneness
	piece.complete_step(score)
	return piece


## A plate on a counter, an ingredient on the cutting board, a patty on the
## stove — whatever's sitting in the slot is what's worth inspecting here,
## not the station itself. Empty slot -> nothing to add.
func get_inspect_text() -> String:
	if held_item != null:
		return held_item.get_inspect_text()
	return ""
