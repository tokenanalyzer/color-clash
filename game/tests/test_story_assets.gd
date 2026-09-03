extends TestCase
## The user-supplied "Jamie, Jasmine & Jinn" art (assets/story/) loads, and
## the pose / enemy sheets slice into valid AtlasTexture regions without
## touching the source PNGs.

func test_all_story_art_loads() -> void:
	var a := AssetLibrary.story_art_audit()
	check_eq("story-art registry size", int(a["total"]), 10)
	check("every story-art id resolves", a["missing"].is_empty(), "missing: %s" % str(a["missing"]))

func test_cast_portraits_resolve() -> void:
	check("Jamie portrait", Cast.portrait(Cast.WHO_JAMIE) != null)
	check("Jasmine portrait", Cast.portrait(Cast.WHO_JASMINE) != null)
	check("Jinn portrait", Cast.portrait(Cast.WHO_JINN) != null)
	check_eq("display name", Cast.display_name(Cast.WHO_JINN), "Jinn")

func test_jasmine_pose_slices_are_atlas_in_bounds() -> void:
	var sheet := AssetLibrary.tex(&"story_jasmine_poses")
	check("jasmine pose sheet present", sheet != null)
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
	check("captured -> back-turned cell 7", Cast.pose(Cast.WHO_JASMINE, &"captured") == Cast.jasmine_pose(7))
	check("hopeful -> cell 1", Cast.pose(Cast.WHO_JASMINE, &"hopeful") == Cast.jasmine_pose(1))
	# Jamie / Jinn fall back to portrait for now
	check("jamie pose -> portrait", Cast.pose(Cast.WHO_JAMIE, &"sword_attack") == Cast.portrait(Cast.WHO_JAMIE))

func test_enemy_faces_slice_in_bounds() -> void:
	var sheet := AssetLibrary.tex(&"story_enemies")
	check("enemy sheet present", sheet != null)
	var ok := 0
	for id in EnemyModel.all_enemy_ids():
		var t := EnemyModel.enemy_face(id)
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
