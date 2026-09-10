class_name InternalLevelMap
extends Control
## One island's internal level map: the vertical zig-zag path of island parts
## + level boards for that island's 100 world-local levels, over the shared
## fixed SEA CLIP video (owned by app.gd, behind this transparent Control).
## Fixed chrome = a large fantasy Back button + the island name. A node tap
## routes an unlocked world-local level into the existing gameplay flow;
## locked levels toast instead. Progression is per-island and sequential
## (IslandProgress) — completing a level only unlocks the next level of THIS
## island, and only clearing level 100 unlocks the next island.

signal level_selected(world_id: StringName, local_level: int)
signal back_pressed()

var world_id: StringName = &""
var _scroller: InfiniteLevelScroller
var _back_btn: Button
var _title: Label
var _locked_banner: Label
var _top_h := 132.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS

	_scroller = InfiniteLevelScroller.new()
	_scroller.level_chosen.connect(func(wid: StringName, n: int):
		level_selected.emit(wid, n))
	_scroller.inert_level_tapped.connect(_on_inert_tapped)
	add_child(_scroller)

	# Island name — large, readable on a phone.
	_title = VisualTheme.label("", VisualTheme.FS_TITLE, VisualTheme.TEXT_GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)

	_locked_banner = VisualTheme.label("LOCKED", VisualTheme.FS_CAPTION, Color(0.86, 0.72, 0.55), 3)
	_locked_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_locked_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_locked_banner.visible = false
	add_child(_locked_banner)

	_back_btn = UiKit.back_button()
	_back_btn.pressed.connect(func():
		Audio.play(&"button_tap")
		back_pressed.emit())
	_back_btn.z_index = 5
	add_child(_back_btn)

	_relayout()
	get_viewport().size_changed.connect(_relayout)

## Open (or re-open) this screen on a world. Safe to call repeatedly — the
## same scroller pool is reused, only its world assignment changes, so no map
## objects leak between worlds.
func open(id: StringName) -> void:
	world_id = id
	_title.text = String(WorldCatalog.world(id).get("display_name", "")).to_upper()
	_locked_banner.visible = not WorldCatalog.is_island_unlocked(id)
	_scroller.setup(id)
	_relayout()

func refresh() -> void:
	if world_id != &"":
		_scroller.setup(world_id)

func _relayout() -> void:
	var vp := get_viewport_rect().size
	size = vp
	custom_minimum_size = vp
	var si := VisualTheme.safe_insets(self)
	_top_h = si.position.y + 108.0
	_scroller.position = Vector2.ZERO
	_scroller.size = vp
	# Back button lives fully inside the safe margins, comfortably tappable.
	_back_btn.position = Vector2(maxf(si.position.x + 14.0, 14.0), si.position.y + 12.0)
	_title.position = Vector2(0, si.position.y + 26.0)
	_title.size = Vector2(vp.x, 52)
	_locked_banner.position = Vector2(0, si.position.y + 78.0)
	_locked_banner.size = Vector2(vp.x, 26)

func _on_inert_tapped(local_level: int) -> void:
	if not WorldCatalog.is_island_unlocked(world_id):
		var pre := WorldCatalog.prerequisite_name(world_id)
		UiKit.show_toast(self, "Locked — finish %s first" % pre if pre != "" else "This island is locked")
	else:
		UiKit.show_toast(self, "Level %d is locked — clear the level before it first" % local_level)
