class_name ColorDef
extends RefCounted
## A single piece color's identity and palette, loaded from data/colors.json.

var id: StringName
var display_name: String
var base_color: Color
var accent_color: Color
var glow_color: Color

static func from_dict(d: Dictionary) -> ColorDef:
	var c := ColorDef.new()
	c.id = StringName(String(d["id"]))
	c.display_name = String(d.get("name", d["id"]))
	c.base_color = Color(String(d.get("base", "#ffffff")))
	c.accent_color = Color(String(d.get("accent", "#ffffff")))
	c.glow_color = Color(String(d.get("glow", "#ffffff")))
	return c
