class_name EnemyModel
extends RefCounted
## Data-driven enemy roster for the "Jamie, Jasmine & Jinn" campaign
## (data/enemies.json). Pure accessors + AtlasTexture slices of the labelled
## 10-enemy row on assets/story/enemies_and_bosses.png (source PNG untouched).
## Adds NO save state — boss results still flow through ProgressService /
## Economy / Boosters.

const BOSS_EVERY := 10

static var _data: Dictionary = {}
static var _by_id: Dictionary = {}
static var _atlas_cache: Dictionary = {}

static func _ensure() -> void:
	if not _data.is_empty():
		return
	_data = JsonLoader.load_json("res://data/enemies.json")
	for e in _data.get("enemies", []):
		_by_id[String(e["id"])] = e

static func enemy_def(id: StringName) -> Dictionary:
	_ensure()
	return _by_id.get(String(id), {})

static func all_enemy_ids() -> Array:
	_ensure()
	var out: Array = []
	for e in _data.get("enemies", []):
		out.append(StringName(String(e["id"])))
	return out

static func _island_entry(island_idx: int) -> Dictionary:
	_ensure()
	for isl in _data.get("islands", []):
		if int(isl.get("index", -1)) == island_idx:
			return isl
	return {}

static func roster_for_island(island_idx: int) -> Array:
	var out: Array = []
	for id in _island_entry(island_idx).get("roster", []):
		out.append(StringName(String(id)))
	return out

## True on every 10th campaign stage.
static func is_boss_stage(level_id: int) -> bool:
	return level_id > 0 and level_id % BOSS_EVERY == 0

## The boss id for a boss stage — an enemy id, or &"jinn" for stage 50.
## &"" when `level_id` is not a boss stage.
static func boss_for_stage(level_id: int) -> StringName:
	if not is_boss_stage(level_id):
		return &""
	var island_idx := (level_id - 1) / BOSS_EVERY
	return StringName(String(_island_entry(island_idx).get("boss", "")))

## The persistent minor villain for a normal stage — ONE enemy per island,
## present across all 10 of its stages (2026-09-05 correction), not a
## rotating pick. Falls back to the old roster-cycling only if an island is
## missing `minor_villain` (shouldn't happen for the 5 defined islands).
static func enemy_for_stage(level_id: int) -> StringName:
	if is_boss_stage(level_id):
		return boss_for_stage(level_id)
	var island_idx := (level_id - 1) / BOSS_EVERY
	var mv := String(_island_entry(island_idx).get("minor_villain", ""))
	if mv != "":
		return StringName(mv)
	var roster := roster_for_island(island_idx)
	if roster.is_empty():
		return &""
	return roster[(level_id - 1) % roster.size()]

## ISLAND-AWARE villain selection for the 100-level-per-island progression
## (2026-09-10). `island_index` is 0-based (WorldCatalog world order - 1);
## `is_finale` is true ONLY on the island's final local level. Returns
## `{id, is_boss}`.
##
## Unlike is_boss_stage()/boss_for_stage()/enemy_for_stage() — which key off a
## flat 1..50 campaign id and treat `id % 10 == 0` as a chapter finale — this
## takes the REAL island + finale position, so:
##   * the chapter boss (and Jinn) appear ONLY on the island finale, never on
##     an ordinary mid-island level, no matter which authored level the slot
##     happens to reuse;
##   * an island with no roster entry yet (indices 5..9) gets no villain at
##     all rather than a wrong-chapter boss (or Jinn) leaking in.
static func island_villain(island_index: int, is_finale: bool) -> Dictionary:
	_ensure()
	var isl := _island_entry(island_index)
	if isl.is_empty():
		return {"id": &"", "is_boss": false}
	if is_finale:
		var b := String(isl.get("boss", ""))
		if b != "":
			return {"id": StringName(b), "is_boss": true}
	var mv := String(isl.get("minor_villain", ""))
	if mv != "":
		return {"id": StringName(mv), "is_boss": false}
	var roster := roster_for_island(island_index)
	return {"id": (roster[0] if not roster.is_empty() else &""), "is_boss": false}

## AtlasTexture for a labelled enemy on the 10-wide top row of the enemy
## sheet. Uses the checkerboard-KEYED copy (story_enemies_keyed) so the
## in-arena enemy actor renders with clean transparency. null for &"jinn"
## (use Cast.portrait) or a missing sheet.
static func enemy_face(id: StringName) -> Texture2D:
	if id == &"jinn":
		return Cast.portrait(Cast.WHO_JINN)
	_ensure()
	var def := enemy_def(id)
	if def.is_empty():
		return null
	# A dedicated single-character art (2026-09-05 polish pass) takes
	# priority over the shared sheet — see data/enemies.json's `art` field.
	var art := String(def.get("art", ""))
	if art != "":
		var dedicated := AssetLibrary.tex(StringName("story_villain_%s" % art))
		if dedicated != null:
			return dedicated
	var cell := int(def.get("cell", 0))
	var key := "en_%d" % cell
	if _atlas_cache.has(key):
		return _atlas_cache[key]
	var sheet := AssetLibrary.tex(&"story_enemies_keyed")
	if sheet == null:
		sheet = AssetLibrary.tex(&"story_enemies")
	var result: Texture2D = null
	if sheet != null:
		var w := float(sheet.get_width())
		var h := float(sheet.get_height())
		var cw := w / 10.0
		var cx := (float(cell) + 0.5) * cw
		# generous per-enemy window (keyed margins are transparent, so a
		# little neighbour aura at the edges is harmless), clamped to the
		# sheet and stopping above the label bar at ~0.31.
		var x0 := clampf(cx - cw * 0.60, 0.0, w)
		var x1 := clampf(cx + cw * 0.60, 0.0, w)
		var at := AtlasTexture.new()
		at.atlas = sheet
		# The sheet has a "10 MINI BOSSES (JIN'S SERVANTS)" title banner at
		# y~0.010-0.055 and the "N. NAME" label bar at y~0.27+ — start
		# inside the clean gap between them (measured) so neither ever gets
		# picked up (a mirrored fragment of the title showed as garbled
		# "10 MIN..." text above the enemy on a real device before this).
		at.region = Rect2(x0, h * 0.065, x1 - x0, h * 0.202)
		at.filter_clip = true
		result = at
	_atlas_cache[key] = result
	return result
