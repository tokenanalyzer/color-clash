class_name KineticScrollView
extends ScrollContainer
## Inertial (fling + momentum) vertical ScrollContainer for touch. Same
## behaviour as the private KineticScroll inside level_map.gd, pulled out as a
## reusable class for the new island screens. The base class still does 1:1
## finger tracking + deadzone; this only samples fling velocity on drag and
## keeps it rolling after release, and hides the scrollbar.

var _vel := 0.0
var _dragging := false
var _target := -1.0

func _ready() -> void:
	set_process(true)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	# Lets a finger-drag that STARTS on a child button still scroll the list
	# (without this, world cards eat the drag and the screen feels stuck).
	scroll_deadzone = 22
	var vb := get_v_scroll_bar()
	if vb != null:
		vb.modulate.a = 0.0
	gui_input.connect(_on_gui_input)

func set_scroll_target(y: int) -> void:
	_target = float(y)
	_vel = 0.0

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed:
			_dragging = true
			_vel = 0.0
			_target = -1.0
		else:
			_dragging = false
	elif event is InputEventScreenDrag:
		_target = -1.0
		_vel = lerpf(_vel, -event.relative.y * 56.0, 0.5)

func _process(delta: float) -> void:
	var maxs := 0
	if get_child_count() > 0:
		maxs = int(maxf((get_child(0) as Control).size.y - size.y, 0.0))
	if _target >= 0.0:
		var nxt: float = lerpf(float(scroll_vertical), _target, clampf(delta * 9.0, 0.0, 1.0))
		scroll_vertical = int(round(nxt))
		if absf(nxt - _target) < 1.0:
			scroll_vertical = int(_target)
			_target = -1.0
		return
	if _dragging or absf(_vel) < 6.0:
		return
	scroll_vertical += int(round(_vel * delta))
	if scroll_vertical <= 0 or scroll_vertical >= maxs:
		_vel = 0.0
	_vel *= 0.90
