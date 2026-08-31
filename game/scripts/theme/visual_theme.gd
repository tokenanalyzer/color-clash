class_name VisualTheme
extends RefCounted
## Single source of truth for Color Clash's premium visual identity — the
## deep-navy, high-contrast, glossy-gem look. Pure static helpers + colour
## constants (no autoload, no scene) so any renderer can pull the same
## palette, panel styleboxes and easing without a node dependency.
##
## Art direction: vibrant saturated gems on a dark cosmic board, soft glows,
## crisp rim light, generous rounding, restrained UI chrome. Everything is
## code-drawn — no external art assets — so it scales cleanly to any Android
## resolution and stays cheap on the gl_compatibility renderer.

# ---------------------------------------------------------------- surfaces --
const BG_TOP := Color(0.055, 0.07, 0.14)
const BG_BOTTOM := Color(0.02, 0.03, 0.07)
const BG_VIGNETTE := Color(0.0, 0.0, 0.0, 0.45)

const PANEL := Color(0.08, 0.10, 0.18, 0.92)
const PANEL_SOLID := Color(0.10, 0.12, 0.20, 1.0)
const PANEL_RAISED := Color(0.13, 0.16, 0.26, 0.96)
const PANEL_BORDER := Color(1, 1, 1, 0.10)
const PANEL_BORDER_BRIGHT := Color(0.55, 0.75, 1.0, 0.35)
const WELL := Color(0.03, 0.04, 0.09, 0.85)

# ------------------------------------------------------------------- text --
const TEXT := Color(0.95, 0.97, 1.0)
const TEXT_DIM := Color(0.66, 0.72, 0.86)
const TEXT_GOLD := Color(1.0, 0.83, 0.32)
const OUTLINE := Color(0.0, 0.0, 0.02, 0.65)

# ---------------------------------------------------------------- accents --
const ACCENT := Color(0.36, 0.62, 1.0)
const ACCENT_HOT := Color(1.0, 0.42, 0.62)
const FEVER := Color(1.0, 0.55, 0.15)
const FEVER_HOT := Color(1.0, 0.24, 0.52)
const STAR := Color(1.0, 0.84, 0.22)
const COIN := Color(1.0, 0.78, 0.20)
const GEM := Color(0.62, 0.40, 0.95)
const GOOD := Color(0.45, 0.92, 0.62)

## Praise word + colour for a resolved move, keyed by how big the moment was
## (chain depth, or raw cleared-cell count for a single big blast).
static func praise(chain_depth: int, cleared_count: int) -> Dictionary:
	var score := maxi(chain_depth * 3, cleared_count)
	if score >= 22:
		return {"text": "UNREAL!", "color": Color(1.0, 0.35, 0.75)}
	if score >= 16:
		return {"text": "AMAZING!", "color": Color(1.0, 0.5, 0.25)}
	if score >= 11:
		return {"text": "GREAT!", "color": Color(1.0, 0.8, 0.25)}
	if score >= 7:
		return {"text": "GOOD!", "color": Color(0.5, 0.9, 0.6)}
	return {"text": "NICE", "color": Color(0.7, 0.85, 1.0)}

# ------------------------------------------------------------- styleboxes --

## Rounded filled panel with an optional hairline border. Used for every
## HUD pill / dialog so chrome stays consistent.
static func panel(bg: Color = PANEL, radius: int = 20, border: Color = PANEL_BORDER, border_w: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 4)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	return sb

## Filled "capsule" button face in an accent colour, with a lighter top edge.
static func button_face(tint: Color, radius: int = 18) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = tint
	sb.set_corner_radius_all(radius)
	sb.border_color = tint.lightened(0.35)
	sb.border_width_top = 3
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 5)
	return sb

## Applies the shared "flat, no chrome" look to a Button (used where we draw
## the button face ourselves).
static func strip_button(b: Button) -> void:
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(s, empty)
	b.focus_mode = Control.FOCUS_NONE

static func label(text: String, size: int, color: Color = TEXT, outline: int = 5) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", OUTLINE)
	return l

# ------------------------------------------------------------- primitives --

## Soft filled glow disc: `layers` concentric circles fading out, cheap
## substitute for a real blur on the gl_compatibility renderer.
static func draw_glow(ci: CanvasItem, center: Vector2, radius: float, color: Color, layers: int = 5) -> void:
	for i in range(layers, 0, -1):
		var t := float(i) / float(layers)
		var c := color
		c.a = color.a * (1.0 - t) * 0.6
		ci.draw_circle(center, radius * t, c)

## Vertical linear gradient fill over `rect` (top→bottom), approximated with
## horizontal bands — no Gradient/texture allocation.
static func draw_v_gradient(ci: CanvasItem, rect: Rect2, top: Color, bottom: Color, bands: int = 24) -> void:
	var bh := rect.size.y / float(bands)
	for i in bands:
		var t := float(i) / float(bands - 1)
		ci.draw_rect(Rect2(rect.position + Vector2(0, bh * i), Vector2(rect.size.x, bh + 1.0)), top.lerp(bottom, t))

const WORDMARK := "COLOR CLASH"
const _WORDMARK_TINTS := [
	Color(1.0, 0.36, 0.42), Color(1.0, 0.66, 0.24), Color(1.0, 0.86, 0.28),
	Color(0.42, 0.82, 0.5), Color(0.36, 0.66, 1.0), Color(1, 1, 1),
	Color(0.62, 0.44, 0.95), Color(1.0, 0.42, 0.6), Color(0.36, 0.8, 0.86),
	Color(1.0, 0.72, 0.3), Color(0.5, 0.84, 0.56),
]

## The "COLOR CLASH" wordmark — each letter individually tinted — drawn
## horizontally centred on `center` with the given cap height. `alpha`
## fades the whole mark for reveal animations.
static func draw_wordmark(ci: CanvasItem, center: Vector2, font_size: float, alpha: float = 1.0) -> void:
	var font := ThemeDB.fallback_font
	var fs := int(font_size)
	var total := font.get_string_size(WORDMARK, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := center.x - total * 0.5
	for i in WORDMARK.length():
		var ch := WORDMARK[i]
		var col: Color = _WORDMARK_TINTS[i] if i < _WORDMARK_TINTS.size() else Color.WHITE
		col.a = alpha
		ci.draw_string_outline(font, Vector2(x, center.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.6 * alpha))
		ci.draw_string(font, Vector2(x, center.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
