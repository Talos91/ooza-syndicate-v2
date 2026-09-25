class_name NeonPanel
extends Control
var accent=Color("18dae8")
var fill=Color("030d13eF")
var glowing=false
var cut=14.0
func _ready():
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 resized.connect(queue_redraw)
func _draw():
 var w=size.x;var h=size.y;var c=minf(cut,minf(w,h)*.15)
 var points=PackedVector2Array([Vector2(c,0),Vector2(w-c,0),Vector2(w,c),Vector2(w,h-c),Vector2(w-c,h),Vector2(c,h),Vector2(0,h-c),Vector2(0,c)])
 draw_colored_polygon(points,fill)
 points.append(points[0])
 if glowing:
  for width in [16,10,6]:draw_polyline(points,Color(accent,.045),width,true)
 draw_polyline(points,Color(accent,.9 if glowing else .72),2.5 if glowing else 1.0,true)
