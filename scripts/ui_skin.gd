class_name UiSkin
extends RefCounted
const ROOT="res://assets/ui-kit/"
static func faction(k:String)->String:return "viridian" if k=="bloom" else k
static func box(path:String,margin:int=20)->StyleBoxTexture:
 var s=StyleBoxTexture.new();s.texture=load(ROOT+path+".png")
 s.set_texture_margin_all(margin);s.set_content_margin_all(16)
 return s
static func button(b:Button,k:String="vex",primary:bool=false):
 MenuSkin.style_ivory(b,"primary" if primary else "secondary")   # 0.24.5: the 40B2 ivory keys (the old kit buttons are retired)
