class_name UiSkin
extends RefCounted
const ROOT="res://assets/ui-kit/"
static func faction(k:String)->String:return "viridian" if k=="bloom" else k
static func box(path:String,margin:int=20)->StyleBoxTexture:
 var s=StyleBoxTexture.new();s.texture=load(ROOT+path+".png")
 s.set_texture_margin_all(margin);s.set_content_margin_all(16)
 return s
static func button(b:Button,k:String="vex",primary:bool=false):
 var base="Buttons/"+faction(k)+"/"
 b.add_theme_stylebox_override("normal",box(base+("primary-default" if primary else "secondary")))
 b.add_theme_stylebox_override("hover",box(base+"primary-hover"))
 b.add_theme_stylebox_override("pressed",box(base+"primary-pressed"))
 b.add_theme_stylebox_override("disabled",box(base+"primary-disabled"))
 b.add_theme_color_override("font_color",Color("08141c") if primary else Color("edf7fa"))
 b.add_theme_color_override("font_hover_color",Color("08141c"));b.add_theme_color_override("font_pressed_color",Color("08141c"))
