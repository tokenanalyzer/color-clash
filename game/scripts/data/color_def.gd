class_name ColorDef
extends RefCounted
## A single piece color's identity and palette, loaded from data/colors.json.
## `deep` (shaded lower facet) and `rim` (crisp edge highlight) are optional
## in the data and derived from `base` when absent, so older colour files
## and hand-authored entries stay valid.

var id: StringName
var display_name: String
var base_color: Color
var deep_color: Color
var accent_color: Color
var rim_color: Color
var glow_color: Color

static func from_dict(d: Dictionary) -> ColorDef:
	var c := ColorDef.new()
	c.id = StringName(String(d["id"]))
	c.display_name = String(d.get("name", d["id"]))
	c.base_color = Color(String(d.get("base", "#ffffff")))
	c.accent_color = Color(String(d.get("accent", "#ffffff")))
	c.glow_color = Color(String(d.get("glow", "#ffffff")))
	c.deep_color = Color(String(d["deep"])) if d.has("deep") else c.base_color.darkened(0.42)
	c.rim_color = Color(String(d["rim"])) if d.has("rim") else c.accent_color.lightened(0.4)
	return c
