extends TestCase
## Startup flow (2026-09-08): the Rectangle Studio developer-branding splash
## is the FIRST screen, replacing the old white-background logo splash; the
## EXISTING poster/loading screen (SplashScreen) is the second and is
## unchanged in look. Background game warm-up runs concurrently with the
## branding animation and the poster holds visible until warm-up finishes
## (with no artificial delay when it is already done). No deadlock in either
## finish order.

func _root() -> Node:
	return Engine.get_main_loop().root

# ------------------------------------------- asset / provenance --

func test_studio_intro_video_is_packaged_and_theora() -> void:
	check("studio intro .ogv exists in the project", StudioSplash.asset_available())
	check("it is a Theora .ogv (Godot-native)", ResourceLoader.exists("res://assets/branding/studio_intro.ogv"))
	# the source HTML is kept beside it for provenance
	check("source HTML kept in repo",
		FileAccess.file_exists("res://assets/branding/rectangle_studio_logo_animation.html"))

func test_branding_beat_is_short_no_long_hold() -> void:
	# the clip is the supplied animation trimmed to its actual completion
	# (~3.3s); the safety timeout is a cap, not the normal duration, and the
	# normal path finishes on the video's natural end.
	check("MAX_DURATION is a short safety cap (<= 4.5s), not a 5s+ hold",
		StudioSplash.MAX_DURATION <= 4.5)
	# a ~3.3s 720x1600 Theora clip is well under ~350 KB; a 5s+ held clip
	# would be markedly larger. (Exact length is asserted on-device via logs.)
	var f := FileAccess.open("res://assets/branding/studio_intro.ogv", FileAccess.READ)
	check("branding clip is a short file (no long post-animation hold)",
		f != null and f.get_length() < 350000)
	if f != null:
		f.close()

func test_boot_splash_no_longer_shows_the_poster_image() -> void:
	# the old first splash (poster on the engine boot frame) is bypassed;
	# the poster is now only the SECOND screen (SplashScreen).
	check_eq("boot_splash/show_image disabled",
		ProjectSettings.get_setting("application/boot_splash/show_image"), false)
	var bg = ProjectSettings.get_setting("application/boot_splash/bg_color")
	check("engine boot frame is the near-white of the branding splash (no white/dark flash)",
		bg.r > 0.95 and bg.g > 0.95 and bg.b > 0.98)

# --------------------------------------------- StudioSplash behaviour --

func test_studio_splash_finishes_exactly_once_headless() -> void:
	var s := StudioSplash.new()
	_root().add_child(s)
	var fired := {"n": 0}
	s.finished.connect(func(): fired["n"] += 1)
	s.play()          # headless -> deferred immediate finish, never stalls
	# let the deferred call run
	await _idle()
	await _idle()
	check_eq("finished emitted exactly once", fired["n"], 1)
	check("it stays MOUSE_FILTER_STOP so taps can't leak through the branding beat",
		s.mouse_filter == Control.MOUSE_FILTER_STOP)
	# a second finish is a no-op
	s._finish()
	check_eq("no double finish", fired["n"], 1)
	s.queue_free()

func _idle() -> void:
	await Engine.get_main_loop().process_frame

# ------------------------------------- SplashScreen gate (poster) --

func test_poster_stays_idle_until_begin_then_gates_on_loading() -> void:
	var p := SplashScreen.new()
	_root().add_child(p)
	await _idle()
	check("poster is hidden/idle before begin()", not p.visible and not p._running)

	var ready := {"v": false}
	p.loading_ready = func() -> bool: return ready["v"]
	var done := {"hit": false}
	p.finished.connect(func(): done["hit"] = true)

	p.begin()
	check("poster runs after begin()", p._running and p.visible)

	# force well past its minimum beat
	p._t = p._DURATION + 5.0
	p._process(0.016)
	check("poster HOLDS while loading not ready (Case A)", not done["hit"] and p._running)

	ready["v"] = true
	p._process(0.016)
	# the fade tween runs a callback -> give it a couple of frames
	for i in 40:
		await _idle()
		if done["hit"]:
			break
	check("poster fades out once loading is ready", done["hit"])

func test_poster_does_not_wait_when_loading_already_done_case_b() -> void:
	var p := SplashScreen.new()
	_root().add_child(p)
	await _idle()
	p.loading_ready = func() -> bool: return true   # loading finished first
	var done := {"hit": false}
	p.finished.connect(func(): done["hit"] = true)
	p.begin()
	p._t = p._DURATION + 0.01
	p._process(0.016)   # should immediately start the fade, no extra delay
	for i in 40:
		await _idle()
		if done["hit"]:
			break
	check("poster fades right after its own beat when loading is done", done["hit"])

# NOTE: the full main.tscn startup wiring (branding -> poster -> warm-up, no
# deadlock in either finish order) is exercised in smoke_startup.gd, which
# boots the real scene.
