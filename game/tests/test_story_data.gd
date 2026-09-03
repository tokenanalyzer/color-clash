extends TestCase
## Data-driven campaign story (data/story.json + Story autoload). Beats match
## triggers, play once, and persist "seen" through SaveService.

const _VALID_WHO := ["narrator", "jamie", "jasmine", "jinn"]

func test_story_json_is_well_formed() -> void:
	var data := JsonLoader.load_json("res://data/story.json")
	var beats: Array = data.get("beats", [])
	check("story has beats", beats.size() >= 10)
	for b in beats:
		check("beat has id", String(b.get("id", "")) != "")
		check("beat has trigger", String(b.get("trigger", "")) != "")
		var lines: Array = b.get("lines", [])
		check("beat %s has lines" % b.get("id", "?"), lines.size() > 0)
		for ln in lines:
			check("line who is valid in %s" % b.get("id", "?"),
				String(ln.get("who", "narrator")) in _VALID_WHO, "who=%s" % ln.get("who"))
			check("line has text in %s" % b.get("id", "?"), String(ln.get("text", "")) != "")

func test_opening_beat_matches_campaign_start() -> void:
	Story.reset_seen()
	var b := Story.beat_for("campaign_start")
	check("campaign_start beat found", not b.is_empty())
	check_eq("it is the opening", String(b.get("id", "")), "opening")
	check("first line is the narrator", String((b["lines"][0] as Dictionary).get("who", "")) == "narrator")

func test_seen_beats_do_not_repeat_and_persist() -> void:
	Story.reset_seen()
	var b := Story.beat_for("campaign_start")
	check("pending before", Story.has_pending("campaign_start"))
	Story.mark_seen(String(b["id"]))
	check("not pending after mark_seen", not Story.has_pending("campaign_start"))
	# the seen set is written to the local save under Story.SAVE_KEY
	var saved: Array = SaveService.get_value(Story.SAVE_KEY, [])
	check("mark_seen persisted to SaveService", saved.has(String(b["id"])))
	Story.reset_seen()
	check("reset clears the persisted set", (SaveService.get_value(Story.SAVE_KEY, []) as Array).is_empty())

func test_boss_and_chapter_triggers_resolve() -> void:
	Story.reset_seen()
	check("stage_start:50 (final boss intro) exists", not Story.beat_for("stage_start:50").is_empty())
	check("stage_complete:10 (forest boss aftermath) exists", not Story.beat_for("stage_complete:10").is_empty())
	check("island_start:0 (chapter one card) exists", not Story.beat_for("island_start:0").is_empty())
	check("game finale is stage_complete:50", String(Story.beat_for("stage_complete:50").get("id", "")) == "ending")
	check_eq("trigger helper", Story.stage_start_trigger(20), "stage_start:20")

func test_no_beat_for_an_unused_trigger() -> void:
	check("nothing for stage_start:7", Story.beat_for("stage_start:7").is_empty())
