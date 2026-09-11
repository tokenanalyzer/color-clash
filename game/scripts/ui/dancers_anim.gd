class_name DancersAnim
extends Control
## The Home Screen's dancing couple (Jamie + Jasmine), 2026-09-06 asset pass.
##
## Source: the user-supplied `assets/home/dancers_source.mp4` — a 560x752,
## 24fps, ~4s green-screen clip. Godot 4's video player has no alpha and
## can't chroma-key at runtime, so the clip was keyed offline (ramp key +
## hard de-spill + largest-blob isolation, the same pipeline the repo uses
## for its other keyed sheets) into a 36-frame RGBA sprite sheet
## (`assets/home/dancers_sheet.png`, 6x6 grid). This node flips through the
## frames on a timer and loops; the source mp4 stays in the repo untouched.
##
## Placement is driven by the Home Screen reference: the couple is centred
## horizontally and stands on the stone dais in the empty lower-middle band,
## with generous transparent padding baked into each frame so the head /
## feet / cape / hair can never clip.

const SHEET_PATH := "res://assets/home/dancers_sheet.png"
const FRAMES := 36
const COLS := 6
const ROWS := 6
const CELL_W := 394
const CELL_H := 372
const FPS := 9.0

var _sprite: TextureRect
var _sheet: Texture2D
var _regions: Array[Rect2] = []
var _frame := 0
var _t := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	_sheet = load(SHEET_PATH) if ResourceLoader.exists(SHEET_PATH) else null
	if _sheet == null:
		return
	for i in FRAMES:
		_regions.append(Rect2((i % COLS) * CELL_W, (i / COLS) * CELL_H, CELL_W, CELL_H))
	_sprite = TextureRect.new()
	_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sprite)
	_apply_frame(0)
	set_process(false)

func has_art() -> bool:
	return _sheet != null

## Cell aspect (w / h) so the caller can size the node without distortion.
func cell_aspect() -> float:
	return float(CELL_W) / float(CELL_H)

func _apply_frame(i: int) -> void:
	if _sprite == null or _regions.is_empty():
		return
	var at := AtlasTexture.new()
	at.atlas = _sheet
	at.region = _regions[clampi(i, 0, FRAMES - 1)]
	at.filter_clip = true
	_sprite.texture = at

## Start the loop (call when the Home Screen becomes visible).
func play() -> void:
	if _sheet == null:
		return
	_t = 0.0
	set_process(true)

## Stop + reset (call when leaving the Home Screen) so nothing keeps
## ticking off-screen.
func stop() -> void:
	set_process(false)
	_frame = 0
	_apply_frame(0)

func _process(delta: float) -> void:
	_t += delta
	var step := 1.0 / FPS
	while _t >= step:
		_t -= step
		_frame = (_frame + 1) % FRAMES
		_apply_frame(_frame)
