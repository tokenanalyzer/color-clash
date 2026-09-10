class_name StudioSplash
extends Control
## The Rectangle Studio developer-branding splash — the FIRST screen on launch,
## replacing the old white-background logo splash. It plays the supplied
## `rectangle_studio_logo_animation.html` animation, pre-rendered offline to a
## Theora video (`assets/branding/studio_intro.ogv`) because Godot 4 has no
## native HTML surface — same sanctioned pre-render route the project already
## uses for `intro.ogv` / `sea_clip.ogv`. The HTML is the visual source of
## truth and is NOT redesigned; the .ogv is a frame-exact capture of it and
## the .html itself is kept beside it in the repo for provenance.
##
## Contract (mirrors IntroVideoScreen): emits `finished` exactly once, when
## the animation plays out OR a hard safety timeout elapses OR playback is
## impossible (headless / asset missing). The caller starts background game
## warm-up the instant this becomes visible and does NOT wait on the video to
## begin loading.

signal finished()

## HTML bg1 (#fbfdff) — the ground colour, so the engine boot frame, this
## screen and the video all share the same near-white and there is no flash.
const GROUND := Color(0.984, 0.992, 1.0, 1.0)
## Safety cap ONLY — the normal path finishes on the video's natural end
## (`_player.finished`). The clip is the supplied HTML animation trimmed to
## its actual completion (~3.3s), with NO artificial post-animation hold.
const MAX_DURATION := 4.0

const _PATH := "res://assets/branding/studio_intro.ogv"

var _player: VideoStreamPlayer
var _ground: ColorRect
var _done := false
var _elapsed := 0.0

static func asset_available() -> bool:
	return ResourceLoader.exists(_PATH)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # eat taps during the branding beat
	z_index = 300

	_ground = ColorRect.new()
	_ground.color = GROUND
	_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ground)

	_player = VideoStreamPlayer.new()
	_player.expand = true
	_player.autoplay = false
	_player.loop = false
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_player)

	_track_size()
	get_viewport().size_changed.connect(_track_size)
	set_process(false)

func _track_size() -> void:
	var vp := get_viewport_rect().size
	if vp.x < 1.0:
		vp = Vector2(get_viewport().size)
	size = vp
	custom_minimum_size = vp
	position = Vector2.ZERO
	_ground.position = Vector2.ZERO
	_ground.size = vp
	if _player == null:
		return
	# Cover-fit the portrait video (fill the short axis, overhang the long one),
	# centred — the animation is centred art on a soft gradient so a little
	# overhang never clips anything meaningful.
	var vw := 720.0
	var vh := 1600.0
	var tex := _player.get_video_texture()
	if tex != null and tex.get_width() > 0:
		vw = float(tex.get_width())
		vh = float(tex.get_height())
	var k: float = maxf(vp.x / vw, vp.y / vh)
	var dw := vw * k
	var dh := vh * k
	_player.size = Vector2(dw, dh)
	_player.position = Vector2((vp.x - dw) * 0.5, (vp.y - dh) * 0.5)

## Start the branding animation. Headless / auto-skip / missing asset all
## finish immediately (deferred) so the startup flow never stalls.
func play() -> void:
	if StoryScene.auto_skip or DisplayServer.get_name() == "headless" or not asset_available():
		call_deferred("emit_signal", "finished")
		return
	_player.stream = load(_PATH)
	_player.finished.connect(_finish, CONNECT_ONE_SHOT)
	_player.play()
	call_deferred("_track_size")
	set_process(true)
	visible = true
	print("[StudioSplash] playing ", _PATH, "  playing=", _player.is_playing())

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= MAX_DURATION:
		_finish()

func _finish() -> void:
	if _done:
		return
	_done = true
	set_process(false)
	print("[StudioSplash] finished  (elapsed=%.2fs, video_pos=%.2fs)" %
		[_elapsed, (_player.stream_position if _player != null else -1.0)])
	if _player != null and _player.is_playing():
		_player.stop()
	finished.emit()
