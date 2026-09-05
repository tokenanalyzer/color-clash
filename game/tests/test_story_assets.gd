extends TestCase
## The user-supplied "Jamie, Jasmine & Jinn" art (assets/story/) loads, and
## the pose / enemy sheets slice into valid AtlasTexture regions without
## touching the source PNGs.

func test_all_story_art_loads() -> void:
	var a := AssetLibrary.story_art_audit()
	check_eq("story-art registry size", int(a["total"]), 17)
	check("every story-art id resolves", a["missing"].is_empty(), "missing: %s" % str(a["missing"]))

func test_cast_portraits_resolve() -> void:
	check("Jamie portrait", Cast.portrait(Cast.WHO_JAMIE) != null)
	check("Jasmine portrait", Cast.portrait(Cast.WHO_JASMINE) != null)
	check("Jinn portrait", Cast.portrait(Cast.WHO_JINN) != null)
	check_eq("display name", Cast.display_name(Cast.WHO_JINN), "Jinn")

func test_jasmine_pose_slices_are_atlas_in_bounds() -> void:
	var sheet := AssetLibrary.tex(&"story_jasmine_poses_keyed")
	check("jasmine keyed pose sheet present", sheet != null)
	var ok := 0
	for i in range(8):
		var t := Cast.jasmine_pose(i)
		if not (t is AtlasTexture):
			check("pose %d is AtlasTexture" % i, false)
			continue
		var r: Rect2 = (t as AtlasTexture).region
		var inside := r.position.x >= 0.0 and r.position.y >= 0.0 \
			and r.end.x <= float(sheet.get_width()) + 1.0 and r.end.y <= float(sheet.get_height()) + 1.0 \
			and r.size.x > 30.0 and r.size.y > 30.0
		check("pose %d region in bounds" % i, inside, "region=%s" % r)
		if inside:
			ok += 1
	check_eq("all 8 jasmine poses valid", ok, 8)

func test_pose_name_lookup_maps_to_cells() -> void:
	# "captured" is a story-critical emotion (roped/kneeling) with its own
	# dedicated crop from jasmine_expressions_ref.png, not a pose-grid cell.
	check("captured -> the roped/kneeling emotion crop",
		Cast.pose(Cast.WHO_JASMINE, &"captured") == Cast.jasmine_emotion(&"captured"))
	check("hopeful -> clasped-hands cell 3", Cast.pose(Cast.WHO_JASMINE, &"hopeful") == Cast.jasmine_pose(3))
	# Jamie / Jinn fall back to portrait for now
	check("jamie pose -> portrait", Cast.pose(Cast.WHO_JAMIE, &"sword_attack") == Cast.portrait(Cast.WHO_JAMIE))

func test_jasmine_state_table_resolves_every_state() -> void:
	for state in Cast.JASMINE_STATE_TABLE:
		var t := Cast.jasmine_state(state)
		check("state '%s' resolves to a texture" % state, t != null)

func test_jasmine_emotion_regions_are_atlas_in_bounds() -> void:
	var sheet := AssetLibrary.tex(&"story_jasmine_expr")
	check("jasmine expressions sheet present", sheet != null)
	var ok := 0
	for id in Cast.JASMINE_EMOTION_REGIONS:
		var t := Cast.jasmine_emotion(id)
		if not (t is AtlasTexture):
			check("emotion '%s' is AtlasTexture" % id, false)
			continue
		var r: Rect2 = (t as AtlasTexture).region
		var inside := r.position.x >= 0.0 and r.position.y >= 0.0 \
			and r.end.x <= float(sheet.get_width()) + 1.0 and r.end.y <= float(sheet.get_height()) + 1.0 \
			and r.size.x > 30.0 and r.size.y > 30.0
		check("emotion '%s' region in bounds" % id, inside, "region=%s" % r)
		if inside:
			ok += 1
	check_eq("all jasmine emotion crops valid", ok, Cast.JASMINE_EMOTION_REGIONS.size())

func test_enemy_faces_slice_in_bounds() -> void:
	var sheet := AssetLibrary.tex(&"story_enemies")
	check("enemy sheet present", sheet != null)
	var ok := 0
	for id in EnemyModel.all_enemy_ids():
		var t := EnemyModel.enemy_face(id)
		# 5 enemies (data/enemies.json `art` field) got dedicated single-
		# character art (2026-09-05) instead of a sheet slice — those
		# resolve to a plain Texture2D, not an AtlasTexture region.
		if String(EnemyModel.enemy_def(id).get("art", "")) != "":
			check("%s face resolves to dedicated art" % id, t != null)
			if t != null:
				ok += 1
			continue
		if not (t is AtlasTexture):
			check("%s face is AtlasTexture" % id, false)
			continue
		var r: Rect2 = (t as AtlasTexture).region
		if r.position.x >= 0.0 and r.end.x <= float(sheet.get_width()) + 1.0 and r.size.x > 20.0:
			ok += 1
		else:
			check("%s face region in bounds" % id, false, "region=%s" % r)
	check_eq("all 10 enemy faces valid", ok, 10)
	check("jinn face falls back to portrait", EnemyModel.enemy_face(&"jinn") == Cast.portrait(Cast.WHO_JINN))

func test_dedicated_villain_art_torso_in_bounds() -> void:
	# Regression guard for the targeting bug: EnemyActor.configure() uses
	# `torso_y` per dedicated-art enemy (data/enemies.json) instead of a
	# fixed ratio — assert it actually falls inside that image's real
	# opaque-pixel bounding box, not off in empty glow/aura padding (the
	# actual bug: a fixed ratio landed in the surrounding aura for some of
	# these images).
	for id in EnemyModel.all_enemy_ids():
		var art := String(EnemyModel.enemy_def(id).get("art", ""))
		if art == "":
			continue
		var torso_y: float = EnemyModel.enemy_def(id).get("torso_y", 0.44)
		var path := "res://assets/story/villains/%s.png" % art
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		check("%s villain art loads" % id, img != null)
		if img == null:
			continue
		var top := -1
		var bottom := -1
		var h := img.get_height()
		var w := img.get_width()
		for y in h:
			var row_has_solid := false
			for x in range(0, w, maxi(1, w / 64)):  # sparse sample, this is a test not a tool
				if img.get_pixel(x, y).a >= 0.78:
					row_has_solid = true
					break
			if row_has_solid:
				if top == -1:
					top = y
				bottom = y
		check("%s has measurable opaque content" % id, top >= 0 and bottom > top)
		if top < 0:
			continue
		var torso_px := torso_y * float(h)
		check("%s torso_y (%.3f, px=%.0f) falls within opaque bounds [%d, %d]" % [id, torso_y, torso_px, top, bottom],
			torso_px >= float(top) and torso_px <= float(bottom))
