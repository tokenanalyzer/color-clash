class_name SpriteFX
extends Node2D
## Pooled one-shot textured VFX for the prepared burst artwork (assets 19-26,
## 39, 70-74). A sprite is placed at a world point, then scaled up + faded out
## (with an optional spin) over a short life and recycled. Additive blend by
## default so bright-on-transparent art melts into the scene instead of sitting
## on top of it; pass add=false for solid debris / confetti.
##
## Same "fixed pool, no per-blast allocation" contract as ParticlePool, cheap on
## the gl_compatibility renderer. A missing texture is a silent no-op so the
## caller's other feedback (particles, shake, sound) still lands.

const _POOL := 20

var _pool: Array = []

func _ready() -> void:
	z_index = 58
	for i in _POOL:
		var s := _Shot.new()
		add_child(s)
		_pool.append(s)

## world_pos is GLOBAL; `px` is the sprite's on-screen diameter near its peak.
func play(id: StringName, world_pos: Vector2, px: float, col: Color = Color(1, 1, 1),
		life: float = 0.42, add: bool = true, spin: float = 0.0, grow := 2.1) -> void:
	var tex := AssetLibrary.tex(id)
	if tex == null:
		return
	for s in _pool:
		if not s.busy:
			s.fire(tex, to_local(world_pos), px, col, life, add, spin, grow)
			return

## A softer variant that starts near full size and mostly just fades (rings,
## emblems, portals that shouldn't balloon).
func play_hold(id: StringName, world_pos: Vector2, px: float, col: Color = Color(1, 1, 1),
		life: float = 0.6, add: bool = true, spin: float = 0.0) -> void:
	play(id, world_pos, px, col, life, add, spin, 1.25)


class _Shot extends Sprite2D:
	var busy := false
	var _t := 0.0
	var _life := 0.4
	var _spin := 0.0
	var _s0 := 1.0
	var _s1 := 1.6
	var _mat: CanvasItemMaterial

	func _ready() -> void:
		visible = false
		centered = true
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_mat = CanvasItemMaterial.new()
		material = _mat
		set_process(false)

	func fire(tex: Texture2D, local_pos: Vector2, px: float, col: Color,
			life: float, add: bool, spin: float, grow: float) -> void:
		texture = tex
		position = local_pos
		modulate = col
		var base: float = maxf(float(tex.get_width()), float(tex.get_height()))
		_s0 = (px / base) / sqrt(grow)
		_s1 = _s0 * grow
		scale = Vector2(_s0, _s0)
		rotation = randf() * TAU
		_spin = spin
		_life = maxf(life, 0.05)
		_t = 0.0
		busy = true
		visible = true
		_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD if add else CanvasItemMaterial.BLEND_MODE_MIX
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta / _life
		if _t >= 1.0:
			busy = false
			visible = false
			set_process(false)
			return
		var e := 1.0 - pow(1.0 - _t, 3.0)
		scale = Vector2.ONE * lerpf(_s0, _s1, e)
		modulate.a = 1.0 - _t * _t
		rotation += _spin * delta
