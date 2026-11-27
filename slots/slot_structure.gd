extends Node3D
## STRUCTURE SLOT (Slots3, plan sec 2.5). Contract of the root: origin = deck centre; Marker3D ScreenMount over the model (the
## count screen mounts there); pivots inside the art keep their names (turret_yaw > head_pivot > spinner for the Googatlings).
## Structures are not scaled in this build. kind / tier / category say which node category the slot serves.

@export var kind := ""
@export var tier := 1
@export var category := ""            # normal | special | relay | relay_special | legacy
var key := ""


func mount(k: String) -> void:
	key = k
	var art := MapBuilder.piece(k)
	art.name = "Art"
	add_child(art)
	var mount_pt := get_node_or_null("ScreenMount") as Marker3D
	if mount_pt != null:                              # over the model's top (the art's own height)
		var top := 0.0
		for mi in art.find_children("*", "MeshInstance3D", true, false):
			var xf := Transform3D.IDENTITY
			var c: Node = mi
			while c != self and c != null:
				xf = (c as Node3D).transform * xf
				c = c.get_parent()
			top = maxf(top, (xf * (mi as MeshInstance3D).get_aabb()).end.y)
		mount_pt.position = Vector3(0, top + 0.4, 0)
