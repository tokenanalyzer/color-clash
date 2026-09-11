class_name IntroVideoScreen
extends Control
## The real War of Love intro cinematic (2026-09-05 polish pass) — plays once
## before the very first campaign stage, replacing the old code-driven
## StoryScene "opening" beat. The video already carries the full narrative
## (peaceful moment -> villain's approach -> Jasmine's fear -> the poster-tear
## reveal -> Jamie's fight -> the kidnapping) AND its own voice/music audio
## track, so this screen only has to play it cleanly:
##   - KEEP_ASPECT (never COVERED) so a device with a different aspect ratio
##     than the source letterboxes instead of cropping the artwork.
##   - a dark ground behind it (SplashScreen's pattern) so the letterbox
##     bars read as intentional, not a broken/blank surface.
##   - SKIP always available; finishing naturally or tapping SKIP both just
##     emit `finished` once, so app.gd's await-based flow doesn't care which.
##
## Caller is responsible for muting/restoring the adaptive Music system
## around this (see app.gd) — the video's own embedded audio is the only
## thing that should be audible while this plays.

signal finished()

var _player: VideoStreamPlayer
var _ground: ColorRect
var _skip: Button
var _done := false

const _PATH := "res://assets/story/intro.ogv"

## True when the transcoded asset is present — app.gd checks this to decide
## between the video and the StoryScene fallback beat, so a missing asset
## (e.g. an export target that stripped it) never leaves a blank screen.
static func asset_available() -> bool:
	return ResourceLoader.exists(_PATH)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 260

	_ground = ColorRect.new()
	_ground.color = Color(0.0, 0.0, 0.0, 1.0)
	_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ground)

	_player = VideoStreamPlayer.new()
	_player.expand = true
	_player.autoplay = false
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_player)

	_skip = UiKit.button("SKIP", &"tertiary", VisualTheme.FS_MICRO)
	_skip.custom_minimum_size = Vector2(96, 44)
	_skip.pressed.connect(_finish)
	add_child(_skip)

	_track_size()
	get_viewport().size_changed.connect(_track_size)

func _track_size() -> void:
	var vp := get_viewport_rect().size
	size = vp
	custom_minimum_size = vp
	_ground.size = vp
	_ground.position = Vector2.ZERO
	_player.size = vp
	_player.position = Vector2.ZERO
	var si := VisualTheme.safe_insets(self)
	_skip.position = Vector2(vp.x - 96.0 - 16.0, si.position.y + 16.0)

## Plays the transcoded intro; no-op (immediate finish) if the asset or a
## headless/auto-skip context makes playback impossible, matching
## StoryScene's existing headless-safe contract.
func play() -> void:
	if StoryScene.auto_skip or DisplayServer.get_name() == "headless" or not asset_available():
		call_deferred("emit_signal", "finished")
		return
	_player.stream = load(_PATH)
	_player.finished.connect(_finish, CONNECT_ONE_SHOT)
	_player.play()
	visible = true

func _finish() -> void:
	if _done:
		return
	_done = true
	if _player.is_playing():
		_player.stop()
	visible = false
	finished.emit()
