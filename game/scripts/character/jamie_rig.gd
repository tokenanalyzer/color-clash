class_name JamieRig
extends Control
## Jamie's on-screen combat presence for War of Love (Phase C).
##
## The only clean-transparency Jamie art shipped is the single heroic
## portrait (jamie_portrait.png — an RGBA cut-out with his flaming sword on
## the left and blue magic orb on the right). So the rig renders that ONE
## sprite at a real gameplay scale in the combat arena and turns
## JamieActionController phases into a genuine attack read:
##
##   idle  ->  windup (lean back + squash)  ->  lunge/dash toward the enemy
##         ->  weapon hand ignites + a projectile flies from it
##         ->  impact burst on the enemy + the enemy reacts + shake
##         ->  recover back to the (unchanged) battlefield position
##
## It reacts to the controller's authoritative `strike` beat, never to a
## tween finishing, so a dropped frame can't skip or double a hit.
## CombatDirector still owns every number — this is presentation only.
##
##   signals:
##     enemy_reaction(kind, world_pos)  hit | heavy_hit | knockback | stun | none
##     shake_requested(magnitude)

signal enemy_reaction(kind: StringName, world_pos: Vector2)
signal shake_requested(magnitude: float)

const _SHAKE := {&"hit": 5.0, &"heavy_hit": 15.0, &"knockback": 11.0, &"stun": 8.0, &"none": 0.0}
## Where each attack's FX leaves Jamie, as a fraction of the sprite rect.
const _HAND := {&"sword": Vector2(0.17, 0.56), &"orb": Vector2(0.84, 0.42), &"ice": Vector2(0.84, 0.42)}
const _HAND_TINT := {&"sword": Color(1.0, 0.55, 0.15), &"orb": Color(0.35, 0.7, 1.0),
	&"ice": Color(0.65, 0.92, 1.0)}

var controller: JamieActionController

var _actions: Dictionary = {}
var _sprite: TextureRect
var _fx_layer: Control
var _home := Vector2.ZERO
var _enemy := Vector2(360, 0)          # rig-local target point, set by configure()
var _facing := 1.0
var _base_scale := Vector2.ONE

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d := JsonLoader.load_json("res://data/jamie_actions.json")
	_actions = d.get("actions", {})
	controller = JamieActionController.from_dict(d)

	_sprite = TextureRect.new()
	_sprite.texture = Cast.portrait(Cast.WHO_JAMIE)
	_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sprite.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_sprite)

	_fx_layer = Control.new()
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.z_index = 3
	add_child(_fx_layer)
	set_process(false)

## Place Jamie so his feet sit on `floor_y` at `left_x`, rendered `char_h`
## tall, aiming his attacks at `enemy_world` (both in the PARENT's space).
func configure(left_x: float, floor_y: float, char_h: float, enemy_world: Vector2) -> void:
	var tex := Cast.portrait(Cast.WHO_JAMIE)
	var aspect := 0.66
	if tex != null and tex.get_height() > 0:
		aspect = float(tex.get_width()) / float(tex.get_height())
	var w := char_h * aspect
	custom_minimum_size = Vector2(w, char_h)
	size = Vector2(w, char_h)
	pivot_offset = Vector2(w * 0.5, char_h)          # bottom-centre
	_home = Vector2(left_x, floor_y - char_h)
	position = _home
	_facing = 1.0 if enemy_world.x >= (_home.x + w * 0.5) else -1.0
	_sprite.scale = Vector2(_facing, 1.0)
	_base_scale = Vector2(_facing, 1.0)
	_enemy = enemy_world - _home                     # rig-local

func set_enemy_world(enemy_world: Vector2) -> void:
	_enemy = enemy_world - _home

# --------------------------------------------------------------- drive --

func play(action_id: StringName, meta: Dictionary = {}) -> void:
	if controller == null:
		return
	controller.request(action_id, meta)
	if controller.is_busy():
		set_process(true)

func is_busy() -> bool:
	return controller != null and controller.is_busy()

func reset_to_idle() -> void:
	if controller != null:
		controller.reset()
	position = _home
	rotation = 0.0
	if _sprite != null:
		_sprite.scale = _base_scale
	set_process(false)

func _process(dt: float) -> void:
	if controller == null:
		set_process(false)
		return
	for ev in controller.tick(dt):
		_on_phase(ev["event"], ev["action"], ev["meta"])
	if not controller.is_busy():
		set_process(false)

func _on_phase(event: StringName, action_id: StringName, meta: Dictionary) -> void:
	var a: Dictionary = _actions.get(String(action_id), {})
	match event:
		&"windup_start":
			# Phase D: the instant-booster beats are not attacks — a light
			# body anticipation only, no weapon-hand charge glow.
			if action_id == &"gesture_shuffle" or action_id == &"brace":
				_move_to(_home + Vector2(-6.0 * _facing, 4.0), 0.1, Tween.TRANS_SINE)
				_scale_to(Vector2(_facing * 1.03, 0.95), 0.1)
				return
			_move_to(_home + Vector2(-16.0 * _facing, 10.0), 0.12, Tween.TRANS_SINE)
			_scale_to(Vector2(_facing * 1.07, 0.9), 0.12)
			_rot_to(-0.05 * _facing, 0.12)
			# A visible charge building in Jamie's hand BEFORE the strike (not
			# just a body lean) — same hand-glow, held through the windup.
			_hand_flash(a, true, maxf(float(a.get("windup", 0.2)), 0.08))
		&"strike":
			# Phase D: instant-booster beats are a self-only flourish — no
			# lunge, no projectile, no impact on the enemy (their action def
			# carries enemy_reaction:none, but we also skip the whole
			# offence path here so nothing spawns over the villain).
			if action_id == &"gesture_shuffle":
				_scale_to(Vector2(_facing * 0.97, 1.05), 0.1)
				_rot_to(0.0, 0.08)
				_battlefield_sweep()
				return
			if action_id == &"brace":
				_move_to(_home + Vector2(0.0, -8.0), 0.1, Tween.TRANS_SINE)
				_scale_to(Vector2(_facing * 1.04, 0.96), 0.1)
				return
			var sub := StringName(String(meta.get("sub_action", action_id)))
			var sa: Dictionary = _actions.get(String(sub), a)
			var lunge := clampf(float(a.get("lunge", 0.4)), -0.35, 0.95)
			_move_to(_home.lerp(_home + _enemy, lunge * 0.42), 0.12, Tween.TRANS_BACK)
			_scale_to(Vector2(_facing * 0.92, 1.11), 0.1)
			_rot_to(0.11 * _facing, 0.1)
			_hand_flash(sa)
			if sub == &"attack_sword":
				_sword_slash(sa)
			_launch_projectile(sa)
			var kind := StringName(String(a.get("enemy_reaction", "hit")))
			_impact_and_react(sa, kind)
		&"recover":
			_move_to(_home, maxf(float(a.get("recover", 0.28)) * 0.75, 0.08), Tween.TRANS_SINE)
			_scale_to(_base_scale, 0.18)
			_rot_to(0.0, 0.16)
		&"action_done":
			if not controller.is_busy():
				position = _home
				rotation = 0.0
				_sprite.scale = _base_scale

# --------------------------------------------------------------- visuals --

func _move_to(pos: Vector2, dur: float, trans: int) -> void:
	if not is_inside_tree():
		position = pos
		return
	var t := create_tween()
	t.tween_property(self, "position", pos, maxf(dur, 0.01)).set_trans(trans).set_ease(Tween.EASE_OUT)

func _scale_to(target: Vector2, dur: float) -> void:
	if _sprite == null:
		return
	if not is_inside_tree():
		_sprite.scale = target
		return
	_sprite.pivot_offset = _sprite.size * Vector2(0.5, 1.0)
	var t := _sprite.create_tween()
	t.tween_property(_sprite, "scale", target, maxf(dur, 0.01)).set_trans(Tween.TRANS_SINE)

func _rot_to(rad: float, dur: float) -> void:
	if not is_inside_tree():
		rotation = rad
		return
	var t := create_tween()
	t.tween_property(self, "rotation", rad, maxf(dur, 0.01)).set_trans(Tween.TRANS_SINE)

## Cap transient FX so a rapid combo / Fever burst can't pile up TextureRects
## and drop frames on the mobile GPU.
func _fx_saturated() -> bool:
	return _fx_layer != null and _fx_layer.get_child_count() >= 5

## `charge`=true is the slower, dimmer pre-strike buildup played at
## windup_start (`dur` ~ the windup length); false is the sharp strike pulse.
## Same asset either way — just a different envelope, so no new art needed.
func _hand_flash(sa: Dictionary, charge: bool = false, dur: float = 0.0) -> void:
	if _fx_saturated():
		return
	var hand := StringName(String(sa.get("hand", "sword")))
	var at: Vector2 = size * (_HAND.get(hand, Vector2(0.5, 0.5)) as Vector2)
	var tint: Color = _HAND_TINT.get(hand, Color(1, 1, 1))
	var g := TextureRect.new()
	var gt := AssetLibrary.tex(&"vfx_glow_orb")
	g.texture = gt if gt != null else AssetLibrary.tex(&"vfx_energy_burst")
	g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.size = Vector2(size.y * 0.5, size.y * 0.5)
	g.position = at - g.size * 0.5
	g.pivot_offset = g.size * 0.5
	g.modulate = Color(tint.r, tint.g, tint.b, 0.0)
	g.scale = Vector2(0.4, 0.4)
	_fx_layer.add_child(g)
	if not is_inside_tree():
		g.queue_free()
		return
	var t := g.create_tween()
	if charge:
		var build := maxf(dur, 0.1)
		t.tween_property(g, "modulate:a", 0.55, build * 0.7).set_trans(Tween.TRANS_SINE)
		t.parallel().tween_property(g, "scale", Vector2(0.8, 0.8), build * 0.7).set_trans(Tween.TRANS_SINE)
		t.tween_property(g, "modulate:a", 0.0, 0.1)
		t.tween_callback(g.queue_free)
	else:
		t.tween_property(g, "modulate:a", 0.95, 0.06)
		t.parallel().tween_property(g, "scale", Vector2(1.2, 1.2), 0.12).set_trans(Tween.TRANS_BACK)
		t.tween_property(g, "modulate:a", 0.0, 0.16)
		t.tween_callback(g.queue_free)

## A quick rotated streak sweeping across Jamie's sword hand at `strike` —
## the "slash" a static portrait otherwise can't show. Fire-tinted, reuses
## the existing dash-trail art rather than a new asset.
func _sword_slash(sa: Dictionary) -> void:
	if _fx_saturated():
		return
	var tex := AssetLibrary.tex(&"vfx_energy_trail_head")
	if tex == null or not is_inside_tree():
		return
	var hand := StringName(String(sa.get("hand", "sword")))
	var at: Vector2 = size * (_HAND.get(hand, Vector2(0.17, 0.56)) as Vector2)
	var slash := TextureRect.new()
	slash.texture = tex
	slash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	slash.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	slash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slash.modulate = Color(1.0, 0.6, 0.2, 0.0)
	slash.size = Vector2(size.y * 0.7, size.y * 0.22)
	slash.pivot_offset = Vector2(slash.size.x * 0.2, slash.size.y * 0.5)
	slash.position = at - slash.pivot_offset
	slash.rotation = -0.9 * _facing
	_fx_layer.add_child(slash)
	var t := slash.create_tween()
	t.tween_property(slash, "modulate:a", 0.9, 0.03)
	t.parallel().tween_property(slash, "rotation", 0.9 * _facing, 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(slash, "modulate:a", 0.0, 0.1)
	t.tween_callback(slash.queue_free)

## Phase D — the Shuffle-booster read: a wide expanding ring sweeping out of
## Jamie across the whole arena, "stirring" the battlefield. Reuses the
## shockwave-ring art, tinted cool so it doesn't read as an attack. One
## tween, self-freeing, capped by _fx_saturated().
func _battlefield_sweep() -> void:
	if _fx_saturated() or not is_inside_tree():
		return
	var tex := AssetLibrary.tex(&"vfx_shockwave_ring")
	if tex == null:
		return
	var ring := TextureRect.new()
	ring.texture = tex
	ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ring.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.modulate = Color(0.45, 0.8, 1.0, 0.0)
	var start := size.y * 0.5
	ring.size = Vector2(start, start)
	ring.pivot_offset = ring.size * 0.5
	ring.position = size * Vector2(0.5, 0.55) - ring.size * 0.5
	var reach: float = maxf(absf(_enemy.x), size.x) * 2.0
	_fx_layer.add_child(ring)
	var t := ring.create_tween()
	t.tween_property(ring, "modulate:a", 0.7, 0.06)
	t.parallel().tween_property(ring, "scale", Vector2(reach / start, reach / start), 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(ring, "modulate:a", 0.0, 0.14)
	t.tween_callback(ring.queue_free)

## A travelling projectile from Jamie's attacking hand to the enemy.
func _launch_projectile(sa: Dictionary) -> void:
	var vid := StringName(String(sa.get("projectile", "")))
	var tex: Texture2D = AssetLibrary.tex(vid) if vid != &"" else null
	if tex == null or not is_inside_tree() or _fx_saturated():
		return
	var hand := StringName(String(sa.get("hand", "sword")))
	var from: Vector2 = size * (_HAND.get(hand, Vector2(0.5, 0.5)) as Vector2)
	var shot := TextureRect.new()
	shot.texture = tex
	shot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	shot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shot.size = Vector2(size.y * 0.42, size.y * 0.42)
	shot.pivot_offset = shot.size * 0.5
	shot.position = from - shot.size * 0.5
	_fx_layer.add_child(shot)
	var to := _enemy - shot.size * 0.5
	var t := shot.create_tween()
	t.tween_property(shot, "position", to, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(shot, "rotation", _facing * 2.4, 0.15)
	t.parallel().tween_property(shot, "scale", Vector2(1.25, 1.25), 0.15)
	t.tween_callback(shot.queue_free)

func _impact_and_react(sa: Dictionary, kind: StringName) -> void:
	var anchor_parent := position + _enemy
	if is_inside_tree() and not _fx_saturated():
		var iid := StringName(String(sa.get("impact", "vfx_energy_burst")))
		var itex := AssetLibrary.tex(iid)
		if itex != null:
			var burst := TextureRect.new()
			burst.texture = itex
			burst.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			burst.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var bs: float = size.y * (1.1 if kind == &"heavy_hit" else 0.8)
			burst.size = Vector2(bs, bs)
			burst.position = _enemy - burst.size * 0.5
			burst.pivot_offset = burst.size * 0.5
			burst.scale = Vector2(0.35, 0.35)
			burst.modulate.a = 0.0
			_fx_layer.add_child(burst)
			var t := burst.create_tween()
			t.tween_property(burst, "scale", Vector2(1.3, 1.3), 0.12).set_trans(Tween.TRANS_BACK)
			t.parallel().tween_property(burst, "modulate:a", 1.0, 0.06)
			t.tween_property(burst, "modulate:a", 0.0, 0.22)
			t.tween_callback(burst.queue_free)
	var sfx := StringName(String(sa.get("sfx", "")))
	if sfx != &"":
		Audio.play(sfx, 0.6 if kind == &"hit" else 1.0)
	shake_requested.emit(float(_SHAKE.get(kind, 5.0)))
	enemy_reaction.emit(kind, anchor_parent)
