extends Node3D
## PLATFORM SLOT (Slots3, plan sec 2.5). Contract of the root: origin = deck centre, deck top y 0; set_seat(seat, faction);
## `conquest` 0..1 (0 neutral .. 1 fully the owner's). Today the art is the kit platform scaled Rules.R / Slots3.ART_R (no
## pier). Nothing is painted round an owned platform: the owner rim band (Look.rim) went in WP4b (Daniele 2026-11-27: "remove the
## painted halo around a conquered vat ... we'll introduce a less invasive effect more in theme"); `conquest` is the hook that
## effect / the conquest texture will read, set here, read by nothing yet.

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
	conquest = 1.0 if s != "" else 0.0


func _set_conquest(v: float) -> void:
	conquest = clampf(v, 0.0, 1.0)
