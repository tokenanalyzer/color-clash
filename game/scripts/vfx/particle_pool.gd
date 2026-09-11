class_name ParticlePool
extends Node2D
## Pooled blast feedback: CPUParticles2D shard bursts + a small pool of
## expanding "impact flash" rings. CPUParticles2D (not GPU) is deliberate —
## it runs on the gl_compatibility renderer this project targets for low-end
## Android — and fixed pools avoid per-blast allocation mid-cascade.

const _POOL_SIZE := 28
const _FLASH_POOL := 10

var _pool: Array[CPUParticles2D] = []
var _flashes: Array[ImpactFlash] = []

func _ready() -> void:
	for i in _POOL_SIZE:
		var p := _make_particle()
		add_child(p)
		_pool.append(p)
	for i in _FLASH_POOL:
		var f := ImpactFlash.new()
		add_child(f)
		_flashes.append(f)

func _make_particle() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 12
	p.lifetime = 0.55
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2(0, 320)
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 240.0
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.0
	p.damping_min = 40.0
	p.damping_max = 90.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.add_point(0.65, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	var scurve := Curve.new()
	scurve.add_point(Vector2(0, 0.4))
	scurve.add_point(Vector2(0.2, 1.0))
	scurve.add_point(Vector2(1, 0.0))
	p.scale_amount_curve = scurve
	p.color = Color.WHITE
	return p

## Short shard burst of `color` at `world_pos`. No-ops if the pool is
## saturated (a huge cascade can outrun it) rather than allocating.
func burst(world_pos: Vector2, color: Color, amount: int = 12) -> void:
	var p := _acquire()
	if p == null:
		return
	p.global_position = world_pos
	p.color = color
	p.amount = clampi(amount, 5, 26)
	p.restart()
	p.emitting = true

## Expanding ring + core pop — the "impact" punctuation on a blast wave.
func flash(world_pos: Vector2, color: Color, radius: float = 90.0) -> void:
	for f in _flashes:
		if not f.active:
			f.fire(world_pos, color, radius)
			return

func _acquire() -> CPUParticles2D:
	for p in _pool:
		if not p.emitting:
			return p
	return null


class ImpactFlash extends Node2D:
	var active := false
	var _t := 0.0
	var _dur := 0.32
	var _radius := 90.0
	var _color := Color.WHITE

	func _ready() -> void:
		set_process(false)
		z_index = 60

	func fire(pos: Vector2, color: Color, radius: float) -> void:
		global_position = pos
		_color = color
		_radius = radius
		_t = 0.0
		active = true
		set_process(true)
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta / _dur
		if _t >= 1.0:
			active = false
			set_process(false)
		queue_redraw()

	func _draw() -> void:
		if not active:
			return
		var e := 1.0 - pow(1.0 - _t, 3.0) # ease-out
		var ring_r := _radius * e
		var fade := 1.0 - _t
		draw_arc(Vector2.ZERO, ring_r, 0, TAU, 40, Color(_color.r, _color.g, _color.b, 0.55 * fade), maxf(_radius * 0.06 * (1.0 - e), 1.5), true)
		var core := _radius * 0.5 * (1.0 - _t)
		draw_circle(Vector2.ZERO, core, Color(1, 1, 1, 0.7 * fade))
		draw_circle(Vector2.ZERO, core * 1.8, Color(_color.r, _color.g, _color.b, 0.3 * fade))
