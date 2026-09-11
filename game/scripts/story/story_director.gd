extends Node
## Autoload "Story". Owns the data-driven campaign narrative (data/story.json)
## for "Jamie, Jasmine & Jinn". Modular: beats are matched to triggers, each
## beat plays at most once (recorded through SaveService, so it survives a
## restart), and adding chapters means editing JSON, not code.
##
## The app drives it explicitly around the existing flow —
##   app._start_level  -> Story.beat_for("campaign_start" / "island_start:N"
##                        / "stage_start:N")
##   app._on_level_won -> Story.beat_for("stage_complete:N")
## — so a story moment can be sequenced cleanly before/after the win panel
## without racing the board. Nothing here touches ProgressService or the
## board; it is pure presentation state.

const SAVE_KEY := "story_seen"

var _beats: Array = []          # ordered beat dicts
var _seen: Dictionary = {}      # id -> true

func _ready() -> void:
	var data := JsonLoader.load_json("res://data/story.json")
	_beats = data.get("beats", [])
	for id in SaveService.get_value(SAVE_KEY, []):
		_seen[String(id)] = true

## First not-yet-seen beat whose `trigger` equals `trigger`, or {} if none.
## Does NOT mark it seen — call mark_seen(beat.id) once it has actually played.
func beat_for(trigger: String) -> Dictionary:
	for b in _beats:
		if String(b.get("trigger", "")) == trigger and not _seen.has(String(b.get("id", ""))):
			return b
	return {}

func has_pending(trigger: String) -> bool:
	return not beat_for(trigger).is_empty()

func mark_seen(beat_id: String) -> void:
	if beat_id == "" or _seen.has(beat_id):
		return
	_seen[beat_id] = true
	SaveService.set_value(SAVE_KEY, _seen.keys())
	SaveService.save()

## Convenience for app.gd — the trigger strings for a given campaign level.
func stage_start_trigger(level_id: int) -> String:
	return "stage_start:%d" % level_id

func stage_complete_trigger(level_id: int) -> String:
	return "stage_complete:%d" % level_id

func island_start_trigger(island_idx: int) -> String:
	return "island_start:%d" % island_idx

## Total beats defined / seen — for a "story so far" screen later.
func progress() -> Dictionary:
	return {"total": _beats.size(), "seen": _seen.size()}

## Test / new-game helper: forget all seen beats.
func reset_seen() -> void:
	_seen.clear()
	SaveService.set_value(SAVE_KEY, [])
	SaveService.save()
