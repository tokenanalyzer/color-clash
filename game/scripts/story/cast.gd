class_name Cast
extends RefCounted
## Resolves textures for the three story characters — Jamie (hero), Jasmine
## (princess), Jinn (villain) — from the user-supplied art.
##
## Portraits are the clean transparent single-character PNGs (used as-is).
## Jamie / Jinn additionally have big action/expression COLLAGE sheets, but
## every one of those sheets ships as either RGB-with-a-baked-checkerboard
## or a continuous painted background with no per-pose separation, so they
## cannot be sliced into clean runtime sprites — Jamie/Jinn "poses" resolve
## to the clean portrait; JamieRig animates that one sprite with real
## transform phases + VFX instead of pose swaps (see jamie_rig.gd).
##
## Jasmine is the exception: she has TWO genuinely usable sheets.
##   - jasmine_poses_8.png is a clean, evenly-gridded 4x2 pose sheet, but
##     shipped RGB with the same baked checkerboard bug — keyed to real
##     alpha by tools/keyed_sprites/key_jasmine_poses.py into
##     jasmine_poses_8_keyed.png (original untouched). Measured (not
##     guessed) cell regions below.
##   - jasmine_expressions_ref.png is genuinely RGBA with real per-pose
##     transparency and holds the story-critical emotional poses (scared,
##     crying, captured/roped, a rescue hug) that the pose grid doesn't
##     have. Measured, individually verified crop regions below — each was
##     composited over a solid background and checked for checkerboard /
##     clipping / stray neighbour fragments before being used here.
##
## `Cast.jasmine_state(name)` is the state-driven entry point Jasmine's
## on-screen presence (jasmine_actor.gd) uses; `pose()` stays for the
## existing story/CharacterDirector callers.

const WHO_JAMIE: StringName = &"jamie"
const WHO_JASMINE: StringName = &"jasmine"
const WHO_JINN: StringName = &"jinn"

## Jasmine's 8-pose grid (jasmine_poses_8_keyed.png), measured cell regions
## — normalized [x0,y0,x1,y1]. Row-major: 0-3 top row, 4-7 bottom row.
const JASMINE_POSE_CELLS := [
	[0.006, 0.028, 0.238, 0.475],   # 0 wave / greet / happy
	[0.249, 0.028, 0.490, 0.475],   # 1 hands-on-hip / confident
	[0.497, 0.028, 0.749, 0.475],   # 2 wink + point / determined
	[0.758, 0.028, 0.987, 0.475],   # 3 clasped hands / sweet / hopeful
	[0.006, 0.514, 0.264, 0.956],   # 4 reaching / welcoming
	[0.267, 0.514, 0.492, 0.956],   # 5 finger-to-chin / thinking
	[0.499, 0.514, 0.754, 0.956],   # 6 laughing + open arms / cheering
	[0.762, 0.514, 0.977, 0.956],   # 7 turned away / shy
]

## Jasmine's dedicated emotion crops (jasmine_expressions_ref.png, genuinely
## alpha-clean, no keying needed) — the story-critical states the pose grid
## doesn't cover. Measured + individually verified.
const JASMINE_EMOTION_REGIONS := {
	&"scared": [0.005, 0.315, 0.140, 0.545],
	&"worried": [0.150, 0.315, 0.278, 0.545],
	&"crying": [0.283, 0.300, 0.425, 0.550],
	&"captured": [0.725, 0.300, 0.860, 0.565],
	&"rescued": [0.825, 0.540, 0.998, 0.830],
	&"victory": [0.660, 0.560, 0.805, 0.820],
}

## Jasmine story/gameplay STATE -> which art to show. Every state a caller
## can ask for (jasmine_actor.gd) resolves through here.
const JASMINE_STATE_TABLE := {
	&"idle": {"sheet": "pose", "cell": 0},
	&"happy": {"sheet": "pose", "cell": 0},
	&"determined": {"sheet": "pose", "cell": 2},
	&"hopeful": {"sheet": "pose", "cell": 3},
	&"cheering": {"sheet": "pose", "cell": 6},
	&"thinking": {"sheet": "pose", "cell": 5},
	&"scared": {"sheet": "emotion", "id": "scared"},
	&"worried": {"sheet": "emotion", "id": "worried"},
	&"crying": {"sheet": "emotion", "id": "crying"},
	&"captured": {"sheet": "emotion", "id": "captured"},
	&"rescued": {"sheet": "emotion", "id": "rescued"},
	&"victory": {"sheet": "emotion", "id": "victory"},
}

## Legacy name -> state, kept so the existing CharacterDirector pose table
## (data/character.json: hype/cheer/worried/scared/victory/...) still resolves.
const JASMINE_POSE_INDEX := {
	&"greet": &"idle", &"wave": &"idle", &"happy": &"happy",
	&"peaceful": &"hopeful", &"hopeful": &"hopeful", &"calm": &"hopeful",
	&"determined": &"determined", &"point": &"determined", &"power_up": &"determined",
	&"worried": &"worried", &"scared": &"scared", &"frightened": &"scared",
	&"calling": &"determined", &"reach": &"determined",
	&"thinking": &"thinking", &"surprised": &"scared",
	&"rescued": &"rescued", &"victory": &"victory", &"laugh": &"cheering",
	&"cheer": &"cheering", &"hype": &"cheering",
	&"captured": &"captured", &"trapped": &"captured", &"sad": &"crying",
}

static var _atlas_cache: Dictionary = {}

static func portrait(who: StringName) -> Texture2D:
	match who:
		WHO_JAMIE: return AssetLibrary.tex(&"story_jamie_portrait")
		WHO_JASMINE: return AssetLibrary.tex(&"story_jasmine_portrait")
		WHO_JINN: return AssetLibrary.tex(&"story_jinn_portrait")
	return null

## A texture for one character in a given emotional/action pose. Kept for
## existing callers (CharacterDirector reactions, StoryScene lines).
static func pose(who: StringName, pose_name: StringName) -> Texture2D:
	if who == WHO_JASMINE:
		var state: StringName = JASMINE_POSE_INDEX.get(pose_name, &"idle")
		return jasmine_state(state)
	if who == WHO_JAMIE:
		return jamie_pose(pose_name)
	if who == WHO_JINN:
		return jinn_pose(pose_name)
	return portrait(who)

## Jamie / Jinn "pose" texture — see the class docstring for why every pose
## resolves to the clean portrait.
static func jamie_pose(_pose_name: StringName) -> Texture2D:
	return portrait(WHO_JAMIE)

static func jinn_pose(_pose_name: StringName) -> Texture2D:
	return portrait(WHO_JINN)

## The primary Jasmine entry point: a story/gameplay STATE (see
## JASMINE_STATE_TABLE) -> the right supplied art. Unknown states fall back
## to idle, never to a missing texture.
static func jasmine_state(state: StringName) -> Texture2D:
	var entry: Dictionary = JASMINE_STATE_TABLE.get(state, JASMINE_STATE_TABLE[&"idle"])
	if String(entry.get("sheet", "")) == "emotion":
		var t := jasmine_emotion(StringName(String(entry.get("id", ""))))
		if t != null:
			return t
		entry = JASMINE_STATE_TABLE[&"idle"]
	return jasmine_pose(int(entry.get("cell", 0)))

## AtlasTexture for one cell of Jasmine's keyed 4x2 pose sheet. Cached;
## null if the sheet is missing.
static func jasmine_pose(cell: int) -> Texture2D:
	var key := "jas_pose_%d" % cell
	if _atlas_cache.has(key):
		return _atlas_cache[key]
	var sheet := AssetLibrary.tex(&"story_jasmine_poses_keyed")
	if sheet == null:
		sheet = AssetLibrary.tex(&"story_jasmine_poses")
	var result: Texture2D = _region_atlas(sheet, JASMINE_POSE_CELLS[clampi(cell, 0, 7)])
	_atlas_cache[key] = result
	return result

## AtlasTexture for one of Jasmine's dedicated emotion crops
## (jasmine_expressions_ref.png — real alpha, no keying needed). null if the
## name or the sheet is unknown.
static func jasmine_emotion(id: StringName) -> Texture2D:
	if not JASMINE_EMOTION_REGIONS.has(id):
		return null
	var key := "jas_emo_%s" % id
	if _atlas_cache.has(key):
		return _atlas_cache[key]
	var sheet := AssetLibrary.tex(&"story_jasmine_expr")
	var result: Texture2D = _region_atlas(sheet, JASMINE_EMOTION_REGIONS[id])
	_atlas_cache[key] = result
	return result

static func _region_atlas(sheet: Texture2D, r: Array) -> Texture2D:
	if sheet == null or r.size() != 4:
		return null
	var w := float(sheet.get_width())
	var h := float(sheet.get_height())
	var at := AtlasTexture.new()
	at.atlas = sheet
	at.region = Rect2(float(r[0]) * w, float(r[1]) * h, (float(r[2]) - float(r[0])) * w, (float(r[3]) - float(r[1])) * h)
	at.filter_clip = true
	return at

static func display_name(who: StringName) -> String:
	match who:
		WHO_JAMIE: return "Jamie"
		WHO_JASMINE: return "Jasmine"
		WHO_JINN: return "Jinn"
	return String(who).capitalize()
