class_name SeaClipBackground
extends Control
## The one shared, fixed, continuously-looping ocean video that sits BEHIND
## both island screens (main-world selection + internal level map). Only one
## of these is ever created (app.gd owns it on its own CanvasLayer); the
## foreground screens scroll over it and it never moves or restarts between
## them.
##
## Godot 4's VideoStreamPlayer only decodes Theora, so the supplied
## `Sea clip.mp4` is transcoded once to `sea_clip.ogv` (the .mp4 is kept
## beside it as the untouched source). Same graceful contract as
## IntroVideoScreen: on headless / when the .ogv is absent, the player is
## skipped and a deep-sea gradient is drawn so the screen is never blank —
## the video is not "replaced by a static image" in the normal runtime path,
## this is only the degradation fallback.

var _player: VideoStreamPlayer
var _fallback: ColorRect
var _want_playing := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fallback = ColorRect.new()
	_fallback.color = Color(0.03, 0.09, 0.16, 1.0)
	_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fallback)

	if _video_available():
		_player = VideoStreamPlayer.new()
		_player.expand = true
		_player.loop = true                # seamless continuous loop
		_player.autoplay = false
		_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_player.stream = load(WorldCatalog.sea_clip_path())
		# Belt-and-braces loop for engine builds where `loop` is ignored.
		_player.finished.connect(func():
			if _want_playing and _player != null:
				_player.play())
		add_child(_player)

	_relayout()
	get_viewport().size_changed.connect(_relayout)

static func _video_available() -> bool:
	var p := WorldCatalog.sea_clip_path()
	return p != "" and ResourceLoader.exists(p) and DisplayServer.get_name() != "headless"

func _video_available_inst() -> bool:
	return _player != null

func _relayout() -> void:
	var vp := get_viewport_rect().size
	size = vp
	position = Vector2.ZERO
	_fallback.size = vp
	_fallback.position = Vector2.ZERO
	if _player == null:
		return
	# Cover the portrait screen: fill on the short axis, overhang the long one,
	# stay centred. VideoStreamPlayer has no cover mode, so size + offset it.
	var native := _player.get_video_texture()
	var vw := 720.0
	var vh := 1280.0
	if native != null and native.get_width() > 0:
		vw = float(native.get_width())
		vh = float(native.get_height())
	var k: float = maxf(vp.x / vw, vp.y / vh)
	var dw := vw * k
	var dh := vh * k
	_player.size = Vector2(dw, dh)
	_player.position = Vector2((vp.x - dw) * 0.5, (vp.y - dh) * 0.5)

## Start (or resume) the loop. Idempotent — safe to call every time either
## island screen becomes visible; never creates a second player or restarts a
## clip that is already running.
func ensure_playing() -> void:
	_want_playing = true
	if _player != null and not _player.is_playing():
		_player.play()
		call_deferred("_relayout")

## Pause the loop (called when both island screens are hidden). Keeps the
## same player + stream so the next ensure_playing() just resumes.
func pause() -> void:
	_want_playing = false
	if _player != null and _player.is_playing():
		_player.paused = true

func _process(_delta: float) -> void:
	if _player != null and _want_playing and _player.paused:
		_player.paused = false
