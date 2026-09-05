extends TestCase
## StoryScene's cinematic-presentation additions (Phase C follow-up): a
## per-line colour flash, a short shake, a one-shot magic particle burst,
## and a mid-beat background swap — all presentation-only, none of it baked
## into any supplied art. `play()` itself auto-skips headless (by design,
## for automated runs), so these are exercised directly like other widget
## tests reach into "private" methods.

func _root() -> Node:
	return Engine.get_main_loop().root

func test_flash_shake_particles_and_bg_swap_do_not_crash() -> void:
	var s := StoryScene.new()
	_root().add_child(s)
	# flash: named presets + a literal hex both resolve without error
	s._play_flash("red")
	s._play_flash("dark_magic")
	s._play_flash("#336699")
	# shake: a real node in the tree, must not throw
	s._play_shake(8.0)
	s._play_shake(0.0)   # zero strength is a documented no-op
	# particles: a real supplied VFX id resolves and cleans itself up
	s._play_particles(&"vfx_energy_burst")
	# an unknown vfx id is a safe no-op, not an error
	s._play_particles(&"not_a_real_vfx_id")
	check("still a valid node after all effects", is_instance_valid(s))
	s.queue_free()

func test_bg_swap_changes_the_texture_once_and_is_idempotent() -> void:
	var s := StoryScene.new()
	_root().add_child(s)
	s._swap_bg(&"env_floating_islands")
	# swapping to the SAME id again must be a no-op (the guard in _swap_bg)
	var before := s._bg.texture
	s._swap_bg(&"env_floating_islands")
	check("same id is a no-op", s._bg.texture == before)
	s.queue_free()

func test_opening_beat_uses_the_new_cinematic_fields() -> void:
	var data := JsonLoader.load_json("res://data/story.json")
	var beat := {}
	for b in data.get("beats", []):
		if String(b.get("id", "")) == "opening":
			beat = b
			break
	check("opening beat found", not beat.is_empty())
	var lines: Array = beat.get("lines", [])
	check("opening has a real scene count (7-beat kidnapping arc)", lines.size() >= 8)
	var has_flash := false
	var has_shake := false
	var has_particles := false
	var has_captured_pose := false
	for ln in lines:
		if ln.has("flash"):
			has_flash = true
		if ln.has("shake"):
			has_shake = true
		if ln.has("particles"):
			has_particles = true
		if String(ln.get("who", "")) == "jasmine" and String(ln.get("pose", "")) == "captured":
			has_captured_pose = true
	check("opening uses a flash beat (Jinn's dark magic)", has_flash)
	check("opening uses a shake beat", has_shake)
	check("opening uses a particle beat", has_particles)
	check("Jasmine actually shows the captured pose during the kidnapping", has_captured_pose)

func test_opening_dialogue_has_no_mojibake() -> void:
	var data := JsonLoader.load_json("res://data/story.json")
	for b in data.get("beats", []):
		for ln in b.get("lines", []):
			var text := String(ln.get("text", ""))
			check("no mojibake em-dash in %s" % b.get("id", "?"), not text.contains("â€"),
				"text=%s" % text)
