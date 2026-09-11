extends SceneTree
## Bakes game/icon.png (1024) — the Color Clash mark: three interlocking
## glossy hex rings (red / blue / gold) on a deep-navy rounded field.
## Original art, code-only.
##   godot --headless --path game --script res://<this copied under game/>

const N := 1024

func _initialize() -> void:
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var c := float(N) * 0.5
	for y in N:
		for x in N:
			var p := Vector2(float(x) - c, float(y) - c)
			var q := p.abs() - Vector2(N * 0.455, N * 0.455)
			var sd: float = Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - N * 0.11
			if sd > 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var rad: float = clampf(p.length() / (c * 1.1), 0.0, 1.0)
			var bg := Color(0.12, 0.16, 0.30).lerp(Color(0.03, 0.05, 0.12), rad)
			img.set_pixel(x, y, Color(bg.r, bg.g, bg.b, clampf(1.0 - sd, 0.0, 1.0)))

	# three rings, drawn back-to-front so they interlock
	var ring_r := N * 0.235
	var thick := N * 0.052
	_ring(img, Vector2(c - N * 0.135, c + N * 0.095), ring_r, thick, Color(0.16, 0.45, 0.96))
	_ring(img, Vector2(c + N * 0.165, c + N * 0.085), ring_r * 0.94, thick, Color(1.0, 0.77, 0.16))
	_ring(img, Vector2(c, c - N * 0.11), ring_r * 1.06, thick, Color(0.95, 0.19, 0.33))

	img.save_png("res://icon.png")
	print("wrote ", ProjectSettings.globalize_path("res://icon.png"))
	quit(0)

func _hex_sdf(p: Vector2, r: float) -> float:
	var q := Vector2(absf(p.y), absf(p.x))
	var k := Vector2(-0.8660254, 0.5)
	var d: float = minf(k.x * q.x + k.y * q.y, 0.0)
	q -= Vector2(2.0 * d * k.x, 2.0 * d * k.y)
	q -= Vector2(clampf(q.x, -0.5773503 * r, 0.5773503 * r), r)
	return q.length() * signf(q.y)

func _ring(img: Image, center: Vector2, r: float, thick: float, base: Color) -> void:
	var top := base.lightened(0.5)
	var deep := base.darkened(0.45)
	var lo := (center - Vector2(r + thick + 6.0, r + thick + 6.0)).max(Vector2.ZERO)
	var hi := (center + Vector2(r + thick + 6.0, r + thick + 6.0)).min(Vector2(N, N))
	for y in range(int(lo.y), int(hi.y)):
		for x in range(int(lo.x), int(hi.x)):
			var p := Vector2(float(x), float(y)) - center
			var sd := _hex_sdf(p, r)
			var band: float = absf(sd) - thick        # <=0 within the ring band
			var a: float = clampf(0.5 - band, 0.0, 1.0)
			if a <= 0.001:
				continue
			# shade across the band thickness + top-lit gradient
			var across: float = clampf(sd / thick * 0.5 + 0.5, 0.0, 1.0)
			var body := top.lerp(deep, across)
			var vy: float = clampf(p.y / (r + thick) * 0.5 + 0.5, 0.0, 1.0)
			body = body.lerp(base, vy * 0.5)
			# rim hotline on the outer-top of the band
			if sd > 0.0 and p.y < 0.0:
				body = body.lerp(Color(1, 1, 1), clampf(1.0 - absf(band) / 3.0, 0.0, 1.0) * 0.6)
			var prev := img.get_pixel(x, y)
			var out := prev.lerp(Color(body.r, body.g, body.b, 1.0), a)
			out.a = maxf(prev.a, a)
			img.set_pixel(x, y, out)
