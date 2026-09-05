class_name EnemyActor
extends Control
## The villain's on-screen presence in the combat arena (Phase C). On a
## normal stage it shows the current chapter's minor villain
## (EnemyModel.enemy_for_stage); on a boss stage (10/20/30/40/50) it shows
## that stage's boss and takes over the combat presentation, while the top
## BossBar keeps the name + HP. Jinn (stage 50) uses the clean portrait.
##
## Presentation only — HP / defeat still come from CombatDirector. It just
## flinches, knocks back and flashes when Jamie's rig reports a hit.
##
##   play_hit(kind)   hit | heavy_hit | knockback | stun
##   play_defeat()

var _sprite: TextureRect
var _home := Vector2.ZERO
var _facing := -1.0                     # faces left, toward Jamie
var _is_boss := false
var _defeated := false
var _idle_tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sprite = TextureRect.new()
	_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sprite.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_sprite)

## Pick + place the villain for `level_id`. `right_x` is the arena's right
## edge, `floor_y` the arena floor, `char_h` the target height — all in the
## PARENT's space. Returns the villain's torso point (parent space) for the
## Jamie rig to aim at.
func configure(level_id: int, right_x: float, floor_y: float, char_h: float) -> Vector2:
	_defeated = false
	_is_boss = EnemyModel.is_boss_stage(level_id)
	var id := EnemyModel.boss_for_stage(level_id) if _is_boss else EnemyModel.enemy_for_stage(level_id)
	var tex: Texture2D = null
	if id == &"jinn":
		tex = Cast.portrait(Cast.WHO_JINN)
	elif id != &"":
		tex = EnemyModel.enemy_face(id)
	_sprite.texture = tex
	visible = tex != null

	var h := char_h * (1.16 if _is_boss else 1.0)
	var aspect := 0.8
	if tex != null and tex.get_height() > 0:
		aspect = float(tex.get_width()) / float(tex.get_height())
	var w := h * aspect
	custom_minimum_size = Vector2(w, h)
	size = Vector2(w, h)
	pivot_offset = Vector2(w * 0.5, h)              # bottom-centre
	_home = Vector2(right_x - w, floor_y - h)
	# The chapter's minor villain first appears (stage 1/11/21/31/41 of its
	# island) with a brief gradual approach — sliding in from further out
	# rather than popping in already at Jamie/Jasmine's side. Every other
	# stage in that same chapter snaps straight to _home: the villain is
	# already an established presence, not re-entering the scene each time.
	var is_chapter_start := (level_id - 1) % EnemyModel.BOSS_EVERY == 0
	if is_chapter_start and is_inside_tree():
		position = _home + Vector2(w * 0.55, 0.0)
		modulate = Color(1, 1, 1, 0.0)
	else:
		position = _home
		modulate = Color(1, 1, 1, 1)
	# The shared 10-cell sheet was drawn facing right and always flipped to
	# face Jamie; the 5 dedicated single-character pieces (2026-09-05) are
	# each artist-posed at their own specific angle and must render exactly
	# as supplied — mirroring them would alter that angle/facing, which is
	# explicitly not allowed.
	var has_dedicated_art := String(EnemyModel.enemy_def(id).get("art", "")) != ""
	_facing = 1.0 if has_dedicated_art else -1.0
	_sprite.scale = Vector2(_facing, 1.0)
	rotation = 0.0
	_start_idle_bob()
	if is_chapter_start and is_inside_tree():
		var t := create_tween()
		t.set_parallel(true)
		t.tween_property(self, "position", _home, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.tween_property(self, "modulate:a", 1.0, 0.5)
	# Fixed 0.44 default matches the old uniform sheet's padding; enemies
	# with dedicated art (data/enemies.json `torso_y`, measured per-image —
	# see tools/keyed_sprites/measure_torso.py) override it, since their
	# glow/aura padding varies a lot more than the sheet's did.
	var torso_frac: float = EnemyModel.enemy_def(id).get("torso_y", 0.44)
	return _home + Vector2(w * 0.5, h * torso_frac)  # torso, parent space

## Objective-progress "weakening" tint (2026-09-05) — deepens as the
## stage's objectives progress, so clearing them reads as wearing the
## villain down, not just a board-side checklist. Sets `self.modulate`
## (the node's own tint), independent of `play_hit()`'s transient white
## flash which only ever touches the child `_sprite.modulate`, so the two
## compose correctly instead of fighting.
func set_weakened(fraction: float) -> void:
	if _defeated:
		return
	var f := clampf(fraction, 0.0, 1.0)
	modulate = Color(1, 1, 1).lerp(Color(0.62, 0.42, 0.5), f * 0.55)

## A slow, cheap breathing bob so the villain reads as alive even between
## attacks, instead of a pasted-on static image. One looped tween on the
## sprite's own offset — never touches `self.position` (that's owned by the
## hit-knockback / defeat tweens).
func _start_idle_bob() -> void:
	if _idle_tween != null and _idle_tween.is_valid():
		_idle_tween.kill()
	if _sprite == null or not is_inside_tree():
		return
	_sprite.position = Vector2.ZERO
	_idle_tween = create_tween().set_loops()
	_idle_tween.tween_property(_sprite, "position:y", -5.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_property(_sprite, "position:y", 0.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func play_hit(kind: StringName) -> void:
	if _defeated or _sprite == null or not is_inside_tree():
		return
	var knock: float = {&"hit": 10.0, &"heavy_hit": 34.0, &"knockback": 46.0, &"stun": 18.0}.get(kind, 10.0)
	var t := create_tween()
	t.tween_property(self, "position", _home + Vector2(knock, -knock * 0.25), 0.05).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "position", _home, 0.28).set_trans(Tween.TRANS_ELASTIC)
	# white hit flash
	var f := _sprite.create_tween()
	f.tween_property(_sprite, "modulate", Color(2.4, 2.4, 2.4, 1.0), 0.04)
	f.tween_property(_sprite, "modulate", Color(1, 1, 1, 1), 0.20)
	if kind == &"stun":
		var s := create_tween()
		s.tween_property(self, "rotation", 0.12, 0.06)
		s.tween_property(self, "rotation", -0.12, 0.12)
		s.tween_property(self, "rotation", 0.0, 0.1)

func play_defeat() -> void:
	if _defeated:
		return
	_defeated = true
	if _idle_tween != null and _idle_tween.is_valid():
		_idle_tween.kill()
	if not is_inside_tree():
		visible = false
		return
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "modulate:a", 0.0, 0.5)
	t.tween_property(self, "position", _home + Vector2(-14.0, 24.0), 0.5)
	t.tween_property(self, "rotation", -0.5, 0.5)
	t.chain().tween_callback(func(): visible = false)

func is_boss_actor() -> bool:
	return _is_boss
