extends Node3D
## PLATFORM SLOT (Slots3, plan sec 2.5). Contract of the root: origin = deck centre, deck top y 0; set_seat(seat, faction);
## `conquest` 0..1 (0 neutral .. 1 fully the owner's). Today the art is the kit platform scaled Rules.R / Slots3.ART_R (no
## pier) and conquest drives the owner rim (Look.rim); the conquest texture (next round) swaps this shader, not the callers.

var key := ""
var seat := ""
var faction := ""
var conquest := 0.0: set = _set_conquest


func mount(k: String) -> void:
	key = k
	var art := MapBuilder.piece(k)
	art.name = "Art"
	art.scale = Vector3.ONE * Slots3.k()
	add_child(art)


func set_seat(s: String, f := "") -> void:
	seat = s
	faction = f
	Look.rim(self, s)
	conquest = 1.0 if s != "" else 0.0


func _set_conquest(v: float) -> void:
	conquest = clampf(v, 0.0, 1.0)
	var rim := get_node_or_null("LookRim") as MeshInstance3D
	if rim != null:
		rim.visible = seat != "" and conquest > 0.01
