class_name TouchScroll
extends ScrollContainer
## Swipe to scroll with a finger even when the finger starts on a button (Alpha 11's
## touch_map_scroll.gd, Daniele Alpha 16: "map selection isn't scrollable with taps on mobile").
## A tap still presses the button under it; a swipe scrolls and never selects - buttons inside
## check was_drag() before acting.

var finger := -1
var origin := Vector2.ZERO
var origin_scroll := 0
var dragged := false
var released_at := -1000


func was_drag() -> bool:
	return dragged or Time.get_ticks_msec() - released_at < 250


func _inside(p: Vector2) -> bool:
	var local := get_global_transform_with_canvas().affine_inverse() * p
	return Rect2(Vector2.ZERO, size).has_point(local)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed and _inside(st.position):
			finger = st.index
			origin = st.position
			origin_scroll = scroll_vertical
			dragged = false
		elif not st.pressed and st.index == finger:
			if dragged:
				released_at = Time.get_ticks_msec()
				get_viewport().set_input_as_handled()
			finger = -1
			dragged = false
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == finger:
		var sd := event as InputEventScreenDrag
		if sd.position.distance_to(origin) > 12.0:
			dragged = true
		if dragged:
			var k: float = maxf(get_global_transform_with_canvas().get_scale().y, 0.001)   # the menu is scaled to fit
			scroll_vertical = origin_scroll + roundi((origin.y - sd.position.y) / k)
			get_viewport().set_input_as_handled()
