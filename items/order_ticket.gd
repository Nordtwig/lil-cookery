class_name OrderTicket
extends Item

## A physical, carryable order slip. Grabbed empty-handed from a
## ServeStation (matches whatever it's currently asking for), then tagged
## onto a plate — carry the ticket to a station holding a plate, or vice
## versa — to attach a live checklist showing the dish and which required
## components are already there. The ticket is consumed the instant it's
## tagged; the tag is purely an aid for the player, never binding — a plate
## still scores against whatever table it's actually delivered to.

@export var dish := ""

@onready var _label: Label3D = $Label


func _ready() -> void:
	super._ready()
	_label.text = dish.to_upper()


func get_inspect_text() -> String:
	return "ORDER TICKET\n%s" % dish.to_upper()
