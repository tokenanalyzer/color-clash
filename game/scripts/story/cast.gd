class_name Cast
extends RefCounted
## Resolves textures for the three story characters — Jamie (hero), Jasmine
## (princess), Jinn (villain) — from the user-supplied art. Portraits are the
## clean transparent single-character PNGs; Jasmine additionally has an
## 8-pose sheet that is sliced here via AtlasTexture (the source PNG is never
## cropped or modified on disk). Jamie / Jinn pose sheets are opaque-bg
## reference art, so for now every Jamie/Jinn "pose" returns the portrait —
## the pose-sheet slicing for them is a Phase-5 follow-up.

const WHO_JAMIE: StringName = &"jamie"
const WHO_JASMINE: StringName = &"jasmine"
const WHO_JINN: StringName = &"jinn"

## Jasmine's 8-pose sheet is a 4x2 grid. Names map to a cell index.
const JASMINE_POSE_INDEX := {
	&"greet": 0, &"wave": 0, &"happy": 0,
	&"peaceful": 1, &"hopeful": 1, &"calm": 1,
	&"determined": 2, &"point": 2,
	&"worried": 3, &"scared": 3, &"frightened": 3,
	&"calling": 4, &"reach": 4,
	&"thinking": 5, &"surprised": 5,
	&"rescued": 6, &"victory": 6, &"laugh": 6,
	&"captured": 7, &"trapped": 7, &"sad": 7,
}

static var _atlas_cache: Dictionary = {}

static func portrait(who: StringName) -> Texture2D:
	match who:
		WHO_JAMIE: return AssetLibrary.tex(&"story_jamie_portrait")
		WHO_JASMINE: return AssetLibrary.tex(&"story_jasmine_portrait")
		WHO_JINN: return AssetLibrary.tex(&"story_jinn_portrait")
	return null

## A texture for one character in a given emotional/action pose.
static func pose(who: StringName, pose_name: StringName) -> Texture2D:
	if who == WHO_JASMINE:
		var idx: int = JASMINE_POSE_INDEX.get(pose_name, 1)
		return jasmine_pose(idx)
	# Jamie / Jinn: portrait for every pose until the action sheets are sliced.
	return portrait(who)

## AtlasTexture for one cell of Jasmine's 4x2 pose sheet. Cached; null if the
## sheet is missing.
static func jasmine_pose(cell: int) -> Texture2D:
	var key := "jas_%d" % cell
	if _atlas_cache.has(key):
		return _atlas_cache[key]
	var sheet := AssetLibrary.tex(&"story_jasmine_poses")
	var result: Texture2D = null
	if sheet != null:
		var cols := 4
		var rows := 2
		var cw := float(sheet.get_width()) / float(cols)
		var ch := float(sheet.get_height()) / float(rows)
		var c := clampi(cell, 0, 7) % cols
		var r := clampi(cell, 0, 7) / cols
		var at := AtlasTexture.new()
		at.atlas = sheet
		at.region = Rect2(c * cw + cw * 0.02, r * ch + ch * 0.01, cw * 0.96, ch * 0.98)
		at.filter_clip = true
		result = at
	_atlas_cache[key] = result
	return result

static func display_name(who: StringName) -> String:
	match who:
		WHO_JAMIE: return "Jamie"
		WHO_JASMINE: return "Jasmine"
		WHO_JINN: return "Jinn"
	return String(who).capitalize()
