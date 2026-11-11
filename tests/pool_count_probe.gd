extends SceneTree
## Counts what the player is offered (release line, not demo/proto): MapPool.battlefield() with the demo flags off.
func _init() -> void:
	Rules.demo = false
	Rules.proto_debug = false
	var b := MapPool.battlefield()
	var codes := b.map(func(p): return str(p).get_file().substr(0, 4))
	print("POOL_COUNT %d" % b.size())
	print("POOL_CODES " + " ".join(codes))
	var modes := {}
	for p in b:
		for m in MapPool._offered_modes(p):
			modes[m] = int(modes.get(m, 0)) + 1
	print("POOL_MODES " + str(modes))
	print("ALL_COUNT %d" % MapPool.all().size())
	quit()
