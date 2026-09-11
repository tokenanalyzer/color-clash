class_name JasmineActor
extends Control
## Jasmine's dynamic presence in the combat arena. Unlike a permanently-happy
## corner portrait, her pose/expression tracks the actual story/gameplay
## state via Cast.jasmine_state() (data/character-driven, see cast.gd) —
## CAPTURED / SCARED / CRYING / WORRIED / HOPEFUL / DETERMINED / CHEERING /
## VICTORY / RESCUED all resolve to real supplied art. She also shifts a
## little toward Jamie on a positive state and back on a fearful one, so she
## reads as reacting to the battle rather than standing frozen in one spot.
## Presentation only — nothing here drives gameplay.

signal changed(state: StringName)

## Which way (and how far, as a fraction of the arena width) each state
## nudges her from the neutral centre spot.
const _BIAS := {
	&"scared": -0.10, &"worried": -0.06, &"crying": -0.08, &"captured": -0.14,
	&"cheering": 0.08, &"victory": 0.10, &"rescued": 0.16, &"hopeful": 0.04,
	&"determined": 0.02,
}

var _sprite: TextureRect
var _state: StringName = &"idle"
var _home := Vector2.ZERO
var _center_x := 0.0
var _width := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sprite = TextureRect.new()
	_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sprite.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_sprite)
	_sprite.texture = Cast.jasmine_state(_state)

## Stand Jasmine centred at `center_x`, feet on `floor_y`, `h` tall — she
## can drift up to `arena_width * bias` either side of that centre as her
## state changes. All in the PARENT's space.
func configure(center_x: float, floor_y: float, h: float, arena_width: float) -> void:
	_center_x = center_x
	_width = arena_width
	var tex := _sprite.texture
	var aspect := 0.78
	if tex != null and tex.get_height() > 0:
		aspect = float(tex.get_width()) / float(tex.get_height())
	var w := h * aspect
	custom_minimum_size = Vector2(w, h)
	size = Vector2(w, h)
	pivot_offset = Vector2(w * 0.5, h)
	var bias := float(_BIAS.get(_state, 0.0)) * _width
	_home = Vector2(_center_x + bias - w * 0.5, floor_y - h)
	position = _home

func state() -> StringName:
	return _state

## Where she's headed for the current state (position animates toward this
## over a short tween; this is the settled value, useful for tests/logic
## that don't want to wait out the tween).
func target_position() -> Vector2:
	return _home

## Change her pose/expression. `emote` plays a small punch so a state change
## reads as a real reaction, not a silent texture swap.
func set_state(new_state: StringName, emote: bool = true) -> void:
	if new_state == _state:
		return
	_state = new_state
	_sprite.texture = Cast.jasmine_state(_state)
	if size.x > 0.0:
		var bias := float(_BIAS.get(_state, 0.0)) * _width
		var target := Vector2(_center_x + bias - size.x * 0.5, _home.y)
		_home = target
		if is_inside_tree():
			var t := create_tween()
			t.tween_property(self, "position", target, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		else:
			position = target
	if emote and is_inside_tree():
		_sprite.pivot_offset = _sprite.size * Vector2(0.5, 1.0)
		_sprite.scale = Vector2(0.88, 1.14)
		var st := _sprite.create_tween()
		st.tween_property(_sprite, "scale", Vector2(1.05, 0.94), 0.12).set_trans(Tween.TRANS_BACK)
		st.tween_property(_sprite, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_ELASTIC)
	changed.emit(_state)
