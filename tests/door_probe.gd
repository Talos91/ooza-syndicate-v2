extends SceneTree
## PROTO: TWO DOORS probe.  Godot --headless --path . --script res://tests/door_probe.gd -- --doors=0|1 [--dump]
## Per half-turn map: seat A's and seat B's walk (path metres / BRAWL_SPEED = seconds) home -> enemy home, and the mean over
## every target (A -> X against B -> the half-turn image of X). --dump prints every route's path length (baseline compare).

const MAPS := ["N-11-round", "N-14-hooks", "N-20-s-bends", "N-22-hex-gates", "N-24-k-crossing", "N-28-l-loops"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dump := "--dump" in args
	for a in args:
		if a.begins_with("--doors="):
			Rules.PROTO_TWO_DOORS = a.ends_with("1")   #DOORSET
		if a == "--exits=1":
			Rules.PROTO_TWO_DOORS_EXITS = true   #DOORSET
	for code in MAPS:
		var m := MapBuilder.load_map("res://maps4/%s.json" % code)
		var seats := {}
		var home := {}
		for st in m["seats"]["1v1"]:
			seats[int(st["node"])] = str(st["seat"])
			home[str(st["seat"])] = int(st["node"])
		var s := Sim.new()
		s.setup(m, MapBuilder.layout(m), seats, {"A": "null", "B": "null"}, 1)
		var c := Vector3.ZERO
		var ids := []
		for n in s.nodes:
			if n["node_kind"] != "junction":
				c += n["pos"]
				ids.append(n["id"])
		c /= float(ids.size())
		var image := func(id: int) -> int:                # the half-turn image of a node (nearest to its rotation)
			var p: Vector3 = s.nodes[id]["pos"]
			var q := Vector3(2.0 * c.x - p.x, p.y, 2.0 * c.z - p.z)
			var best := -1
			var bd := INF
			for j in ids:
				var d: float = (s.nodes[j]["pos"] as Vector3).distance_to(q)
				if d < bd:
					bd = d
					best = j
			return best
		var walk := func(a: int, b: int) -> float:
			var r: Array = s.find_route(a, b)
			if r.size() < 2:
				return -1.0
			var path: Dictionary = s.build_path(r)
			return (path["cum"] as PackedFloat32Array)[-1] / Rules.BRAWL_SPEED
		var ha: int = home["A"]
		var hb: int = home["B"]
		var hh_a: float = walk.call(ha, hb)
		var hh_b: float = walk.call(hb, ha)
		var sum := 0.0
		var sum_abs := 0.0
		var worst := 0.0
		var k := 0
		for x in ids:
			if x == ha:
				continue
			var y: int = image.call(x)
			if y == hb:
				continue
			var ta: float = walk.call(ha, x)
			var tb: float = walk.call(hb, y)
			if ta < 0.0 or tb < 0.0:
				continue
			sum += ta - tb
			sum_abs += absf(ta - tb)
			worst = maxf(worst, absf(ta - tb))
			k += 1
		print("FAIR %s doors=%d homeA->B %.2f s homeB->A %.2f s diff %+.2f s | targets %d mean A-B %+.2f s mean|A-B| %.2f s worst %.2f s" % [
				code, (1 if not Rules.PROTO_TWO_DOORS else 2) + (10 if Rules.PROTO_TWO_DOORS_EXITS else 0), hh_a, hh_b, hh_a - hh_b, k, sum / maxf(k, 1), sum_abs / maxf(k, 1), worst])
		if dump:
			for a in ids:
				for b in ids:
					if a != b:
						print("DUMP %s %d>%d %.4f" % [code, a, b, walk.call(a, b)])
	quit(0)
