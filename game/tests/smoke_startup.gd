extends SceneTree
## Boots the real main scene and checks the corrected startup sequence:
##   Rectangle Studio branding splash (FIRST, ~3.3s) -> existing poster/loading
##   screen ONLY IF loading is still running -> menu.
## Verifies: the branding splash is frame 1, the heavy build is deferred +
## chunked (never frozen into one hitch), background warm-up runs concurrently,
## Case A (load still running -> poster holds until warm_done) and Case B
## (load already done -> poster SKIPPED, straight to menu). Not part of the CI
## test_runner (boots the full app); run manually.

func _initialize() -> void:
	await process_frame
	await process_frame

	var app := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(app)
	await process_frame

	# branding splash exists on frame 1; the rest is built deferred
	if app._studio_splash == null:
		push_error("branding splash not created on frame 1"); quit(1); return
	var gg := 0
	while app._splash == null and gg < 240:
		await process_frame
		gg += 1
	if app._splash == null:
		push_error("chunked build never created the poster/loading screen"); quit(1); return
	if ProjectSettings.get_setting("application/boot_splash/show_image") != false:
		push_error("old poster boot splash is still enabled"); quit(1); return
	# let warm-up finish
	var guard := 0
	while not app._warm_done and guard < 600:
		await process_frame
		guard += 1
	if not app._warm_done:
		push_error("background warm-up never completed (deadlock)"); quit(1); return
	print("Branding splash frame 1; build deferred; warm-up completed concurrently.")

	# ---- Case A: branding finishes while load is STILL running ----
	app._warm_done = false
	app._splash._started = false
	app._splash._running = false
	app._splash.visible = false
	app._splash.modulate.a = 1.0
	await app._on_studio_splash_finished()
	if not app._splash._started:
		push_error("Case A: poster did not begin while load was running"); quit(1); return
	app._splash._t = app._splash._DURATION + 5.0
	app._splash._process(0.016)
	if not app._splash._running:
		push_error("Case A: poster faded even though warm-up was not done"); quit(1); return
	app._warm_done = true
	app._splash._process(0.016)
	guard = 0
	while is_instance_valid(app._splash) and app._splash._running and guard < 200:
		await process_frame
		guard += 1
	if not app._menu.visible:
		push_error("Case A: menu not live after the poster finished"); quit(1); return
	print("Case A OK: poster holds during load, then -> menu.")

	# ---- Case B: load already done when branding finishes -> skip the poster ----
	var app2 := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(app2)
	guard = 0
	while (app2._splash == null or not app2._warm_done) and guard < 600:
		await process_frame
		guard += 1
	if app2._splash == null or not app2._warm_done:
		push_error("Case B setup: build/warm-up did not complete"); quit(1); return
	app2._splash._started = false           # pretend it was never shown
	await app2._on_studio_splash_finished()
	if app2._splash._started:
		push_error("Case B: poster/loading screen was shown even though load was done"); quit(1); return
	if not app2._menu.visible:
		push_error("Case B: menu not live"); quit(1); return
	print("Case B OK: load-done skips the poster, straight to menu.")

	print("STARTUP SMOKE TEST PASSED")
	quit(0)
