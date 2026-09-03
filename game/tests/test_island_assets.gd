extends TestCase
## Verifies the user-supplied campaign island art (game/assets/islands/, 15
## PNGs = 5 islands x hero/stages/map) is registered, loads, and slices into
## 50 independently-addressable stage faces WITHOUT modifying the source PNGs
## (the slice is an AtlasTexture region, not a crop on disk).

func test_all_15_island_art_ids_load() -> void:
	var a := AssetLibrary.island_art_audit()
	check_eq("registry has 15 island-art ids", int(a["total"]), 15)
	check("every island-art id resolves to a texture", a["missing"].is_empty(),
		"missing: %s" % str(a["missing"]))

func test_each_island_has_hero_stages_map() -> void:
	for i in range(5):
		check("island %d hero art" % (i + 1), IslandModel.island_hero_art(i) != null)
		check("island %d stages sheet" % (i + 1), IslandModel.island_stages_sheet(i) != null)
		check("island %d map art" % (i + 1), IslandModel.island_map_art(i) != null)

func test_50_stage_faces_are_atlas_regions_within_bounds() -> void:
	var ok_faces := 0
	for isl in range(5):
		var sheet := IslandModel.island_stages_sheet(isl)
		check("island %d sheet present" % isl, sheet != null)
		if sheet == null:
			continue
		for stg in range(10):
			var face := IslandModel.stage_face(isl, stg)
			if not (face is AtlasTexture):
				check("island %d stage %d -> AtlasTexture" % [isl, stg], false)
				continue
			var at := face as AtlasTexture
			var reg: Rect2 = at.region
			var inside := reg.position.x >= 0.0 and reg.position.y >= 0.0 \
				and reg.end.x <= float(sheet.get_width()) + 1.0 \
				and reg.end.y <= float(sheet.get_height()) + 1.0 \
				and reg.size.x > 20.0 and reg.size.y > 20.0
			check("island %d stage %d region within sheet bounds" % [isl, stg], inside,
				"region=%s sheet=%sx%s" % [reg, sheet.get_width(), sheet.get_height()])
			check("island %d stage %d atlas is the sheet" % [isl, stg], at.atlas == sheet)
			if inside:
				ok_faces += 1
	check_eq("all 50 stage faces valid", ok_faces, 50)

func test_stage_faces_are_cached_stable() -> void:
	var a := IslandModel.stage_face(2, 4)
	var b := IslandModel.stage_face(2, 4)
	check("same face instance returned twice (cache)", a == b)

func test_frosthaven_uses_explicit_regions_others_uniform() -> void:
	# Island 2 (index 1) has explicit stage_regions in islands.json.
	var r0 := IslandModel.stage_region_norm(1, 0)
	var r4 := IslandModel.stage_region_norm(1, 4)
	check("frosthaven stage 1 region is explicit (not the uniform grid x)",
		absf(r0.position.x - 0.006) > 0.01)
	check("frosthaven stage 5 sits on the bottom row (y ~0.54)", r4.position.y > 0.4)
	# Island 1 (index 0) has no explicit regions -> uniform 5x2 grid.
	var u0 := IslandModel.stage_region_norm(0, 0)
	var u6 := IslandModel.stage_region_norm(0, 6)  # row 1, col 1
	check("uniform grid stage 1 near top-left", u0.position.x < 0.05 and u0.position.y < 0.05)
	check("uniform grid stage 7 on second row", u6.position.y > 0.4)

func test_node_positions_flow_bottom_to_top() -> void:
	for isl in range(5):
		var first := IslandModel.node_position_norm(isl, 0, 10)
		var last := IslandModel.node_position_norm(isl, 9, 10)
		check("island %d stage 1 lower on screen than stage 10" % isl, first.y > last.y)
		for s in range(10):
			var p := IslandModel.node_position_norm(isl, s, 10)
			check("island %d stage %d x in [0,1]" % [isl, s], p.x >= 0.0 and p.x <= 1.0)
			check("island %d stage %d y in [0,1]" % [isl, s], p.y >= 0.0 and p.y <= 1.0)
