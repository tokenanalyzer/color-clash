extends SceneTree
## DEV TOOL (not a test): renders the real gameplay top section for a few
## stages into user://shots/ so the LEVEL badge / GOAL panel centring can be
## eyeballed without a device.
##   godot --headless --path game --script res://tests/_capture_topbar.gd

const OUT := "user://shots"
const SHOT_SIZE := Vector2i(1080, 2377)

var _svp: SubViewport

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	await _frames(3)
	DirAccess.make_dir_recursive_absolute(OUT)
	_svp = SubViewport.new()
	_svp.size = SHOT_SIZE
	_svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(_svp)
	var app = load("res://scenes/main.tscn").instantiate()
	_svp.add_child(app)
	await _frames(12)
	await app._on_menu_play_pressed()
	await _frames(20)

	for sid: int in [1, 8, 22]:
		app._debug_start_authored_level(sid)
		await _frames(40)
		# report the measured centres
		var hud = app._hud
		var inner: float = _svp.size.x - 44.0
		var mid := inner * 0.5
		var lvl: Control = hud._level_label
		var lvl_c: float = lvl.position.x + lvl.size.x * 0.5
		var gz: Control = hud._tb_goal_zone
		var gz_c: float = gz.position.x + gz.size.x * 0.5
		print("L%-2d  inner=%.0f  centre=%.1f  |  LEVEL badge centre=%.1f (off %+.1f)  |  GOAL zone centre=%.1f (off %+.1f)"
			% [sid, inner, mid, lvl_c, lvl_c - mid, gz_c, gz_c - mid])
		await _shot("topbar_L%d" % sid)

	print("shots -> ", ProjectSettings.globalize_path(OUT))
	quit(0)

func _shot(name: String) -> void:
	await _frames(2)
	var tex := _svp.get_texture()
	if tex == null:
		print("  no texture -> skip ", name); return
	var img := tex.get_image()
	if img == null:
		print("  null image -> skip ", name); return
	# crop to the top ~640px so the file is small and focused
	var crop := img.get_region(Rect2i(0, 0, img.get_width(), 640))
	crop.save_png("%s/%s.png" % [OUT, name])
	print("  saved ", name)
