class_name ParticlePool
extends Node2D
## Pooled CPUParticles2D bursts for blast feedback. CPUParticles2D (not
## GPUParticles2D) is used deliberately — it runs on the gl_compatibility
## renderer this project targets for low-end Android devices, and a small
## fixed pool avoids per-blast allocation.

const _POOL_SIZE := 24

var _pool: Array[CPUParticles2D] = []

func _ready() -> void:
	for i in _POOL_SIZE:
		var p := _make_particle()
		add_child(p)
		_pool.append(p)

func _make_particle() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 10
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2(0, 260)
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 170.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = Color.WHITE
	return p

## Fires a short burst of `color` particles at `world_pos`. Silently no-ops
## if the pool is fully busy (a large cascade can outrun 24 slots) rather
## than allocating more nodes mid-cascade.
func burst(world_pos: Vector2, color: Color, amount: int = 10) -> void:
	var p := _acquire()
	if p == null:
		return
	p.global_position = world_pos
	p.color = color
	p.amount = clampi(amount, 4, 24)
	p.restart()
	p.emitting = true

func _acquire() -> CPUParticles2D:
	for p in _pool:
		if not p.emitting:
			return p
	return null
