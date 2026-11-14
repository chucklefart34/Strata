class_name ShapeMesh
extends RefCounted
## Unit-sized shapes (fitting the box -0.5..0.5 on every axis) with UVs, used
## for blockout display, the paint shell you draw on, and ray picking. Each
## shape keeps its triangle list (vertex + UV per corner) so a ray hit can be
## turned into a texture position.

const TYPES := ["box", "sphere", "cylinder", "cone", "pyramid", "ramp", "torus"]
const TYPE_NAMES := ["Box", "Ball", "Pillar", "Cone", "Pyramid", "Ramp", "Ring"]

static var _cache: Dictionary = {}


## {mesh: ArrayMesh, verts: PackedVector3Array (3 per triangle), uvs: PackedVector2Array}
static func unit(type: String) -> Dictionary:
	if not TYPES.has(type):
		type = "box"
	if _cache.has(type):
		return _cache[type]
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	match type:
		"sphere":
			_sphere(verts, uvs, 24, 14)
		"cylinder":
			_lathe(verts, uvs, 20, 0.5, 0.5, true, true)
		"cone":
			_lathe(verts, uvs, 20, 0.5, 0.0, true, false)
		"pyramid":
			_lathe(verts, uvs, 4, 0.5 * sqrt(2.0), 0.0, true, false, PI * 0.25)
		"ramp":
			_ramp(verts, uvs)
		"torus":
			_torus(verts, uvs, 24, 10)
		_:
			_box(verts, uvs)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var oriented := PackedVector3Array()
	for i in range(0, verts.size(), 3):
		var a := verts[i]
		var b := verts[i + 1]
		var c := verts[i + 2]
		var n := (b - a).cross(c - a).normalized()
		# Godot front faces are clockwise: emit so the face points outward.
		var cen := (a + b + c) / 3.0
		var outward := n.dot(cen - _center_for(type, cen)) >= 0.0
		var order := [0, 2, 1] if outward else [0, 1, 2]
		var face_n := n if outward else -n
		# Outward = cross(b - a, c - a) points out of the shape.
		if outward:
			oriented.append_array(PackedVector3Array([verts[i], verts[i + 1], verts[i + 2]]))
		else:
			oriented.append_array(PackedVector3Array([verts[i], verts[i + 2], verts[i + 1]]))
		for k in order:
			var idx: int = i + int(k)
			st.set_normal(_smooth_normal(type, verts[idx], face_n))
			st.set_uv(uvs[idx])
			st.add_vertex(verts[idx])
	var d := {"mesh": st.commit(), "verts": verts, "uvs": uvs, "oriented": oriented}
	_cache[type] = d
	return d


## Rough shape centre used to orient faces (the torus uses its tube centre).
static func _center_for(type: String, p: Vector3) -> Vector3:
	if type == "torus":
		var flat := Vector2(p.x, p.z)
		if flat.length() < 0.0001:
			return Vector3.ZERO
		var on_ring := flat.normalized() * 0.32
		return Vector3(on_ring.x, 0.0, on_ring.y)
	return Vector3.ZERO


static func _smooth_normal(type: String, p: Vector3, face_n: Vector3) -> Vector3:
	match type:
		"sphere":
			return p.normalized()
		"torus":
			var c := _center_for(type, p)
			return (p - c).normalized()
	return face_n


## Triangles with cross(b - a, c - a) pointing outward.
static func oriented(type: String) -> PackedVector3Array:
	return unit(type)["oriented"]


# ---------------------------------------------------------------- builders

static func _add_tri(verts: PackedVector3Array, uvs: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	verts.append_array(PackedVector3Array([a, b, c]))
	uvs.append_array(PackedVector2Array([ua, ub, uc]))


static func _add_quad(verts: PackedVector3Array, uvs: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, cell: Rect2) -> void:
	# a → b → c → d around the quad; UVs fill `cell` (a = top-left).
	var ua := cell.position
	var ub := cell.position + Vector2(cell.size.x, 0)
	var uc := cell.end
	var ud := cell.position + Vector2(0, cell.size.y)
	_add_tri(verts, uvs, a, b, c, ua, ub, uc)
	_add_tri(verts, uvs, a, c, d, ua, uc, ud)


## Six faces in a 3 × 2 atlas, each face seen upright from outside.
static func _box(verts: PackedVector3Array, uvs: PackedVector2Array) -> void:
	var w := 1.0 / 3.0
	var h := 0.5
	var cells := []
	for r in 2:
		for c in 3:
			cells.append(Rect2(c * w, r * h, w, h).grow(-0.004))
	var m := 0.5
	# front (+z)
	_add_quad(verts, uvs, Vector3(-m, m, m), Vector3(m, m, m), Vector3(m, -m, m), Vector3(-m, -m, m), cells[0])
	# right (+x)
	_add_quad(verts, uvs, Vector3(m, m, m), Vector3(m, m, -m), Vector3(m, -m, -m), Vector3(m, -m, m), cells[1])
	# back (-z)
	_add_quad(verts, uvs, Vector3(m, m, -m), Vector3(-m, m, -m), Vector3(-m, -m, -m), Vector3(m, -m, -m), cells[2])
	# left (-x)
	_add_quad(verts, uvs, Vector3(-m, m, -m), Vector3(-m, m, m), Vector3(-m, -m, m), Vector3(-m, -m, -m), cells[3])
	# top (+y)
	_add_quad(verts, uvs, Vector3(-m, m, -m), Vector3(m, m, -m), Vector3(m, m, m), Vector3(-m, m, m), cells[4])
	# bottom (-y)
	_add_quad(verts, uvs, Vector3(-m, -m, m), Vector3(m, -m, m), Vector3(m, -m, -m), Vector3(-m, -m, -m), cells[5])


static func _sphere(verts: PackedVector3Array, uvs: PackedVector2Array, seg: int, rings: int) -> void:
	for r in rings:
		var v0 := float(r) / rings
		var v1 := float(r + 1) / rings
		var t0 := PI * v0
		var t1 := PI * v1
		for s in seg:
			var u0 := float(s) / seg
			var u1 := float(s + 1) / seg
			var p00 := _sph(u0, t0)
			var p10 := _sph(u1, t0)
			var p11 := _sph(u1, t1)
			var p01 := _sph(u0, t1)
			if r > 0:
				_add_tri(verts, uvs, p00, p10, p11, Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1))
			if r < rings - 1:
				_add_tri(verts, uvs, p00, p11, p01, Vector2(u0, v0), Vector2(u1, v1), Vector2(u0, v1))


static func _sph(u: float, theta: float) -> Vector3:
	var phi := TAU * u
	return Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi)) * 0.5


## Cylinder / cone / pyramid: side in the top 70% of the texture, caps below.
static func _lathe(verts: PackedVector3Array, uvs: PackedVector2Array, seg: int, r_bottom: float, r_top: float, bottom_cap: bool, top_cap: bool, phase: float = 0.0) -> void:
	var side_h := 0.7
	for s in seg:
		var u0 := float(s) / seg
		var u1 := float(s + 1) / seg
		var a0 := TAU * u0 + phase
		var a1 := TAU * u1 + phase
		var b0 := Vector3(cos(a0) * r_bottom, -0.5, sin(a0) * r_bottom)
		var b1 := Vector3(cos(a1) * r_bottom, -0.5, sin(a1) * r_bottom)
		var t0 := Vector3(cos(a0) * r_top, 0.5, sin(a0) * r_top)
		var t1 := Vector3(cos(a1) * r_top, 0.5, sin(a1) * r_top)
		if r_top > 0.0001:
			_add_tri(verts, uvs, t0, t1, b1, Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, side_h))
			_add_tri(verts, uvs, t0, b1, b0, Vector2(u0, 0), Vector2(u1, side_h), Vector2(u0, side_h))
		else:
			_add_tri(verts, uvs, Vector3(0, 0.5, 0), b1, b0, Vector2((u0 + u1) * 0.5, 0), Vector2(u1, side_h), Vector2(u0, side_h))
		var cap_r := (1.0 - side_h) * 0.5 - 0.01
		var c0 := Vector2(cos(a0), sin(a0)) * cap_r
		var c1 := Vector2(cos(a1), sin(a1)) * cap_r
		if bottom_cap:
			var cc := Vector2(0.25, side_h + cap_r + 0.01)
			_add_tri(verts, uvs, Vector3(0, -0.5, 0), b0, b1, cc, cc + c0, cc + c1)
		if top_cap and r_top > 0.0001:
			var ct := Vector2(0.75, side_h + cap_r + 0.01)
			_add_tri(verts, uvs, Vector3(0, 0.5, 0), t1, t0, ct, ct + c1, ct + c0)


## Wedge rising from +x (low edge) to -x (tall side), matching the blockout ramp.
static func _ramp(verts: PackedVector3Array, uvs: PackedVector2Array) -> void:
	var m := 0.5
	var w := 1.0 / 3.0
	var cells := []
	for r in 2:
		for c in 3:
			cells.append(Rect2(c * w, r * 0.5, w, 0.5).grow(-0.004))
	# slope
	_add_quad(verts, uvs, Vector3(-m, m, -m), Vector3(m, -m, -m), Vector3(m, -m, m), Vector3(-m, m, m), cells[0])
	# tall side (-x)
	_add_quad(verts, uvs, Vector3(-m, m, -m), Vector3(-m, m, m), Vector3(-m, -m, m), Vector3(-m, -m, -m), cells[1])
	# bottom
	_add_quad(verts, uvs, Vector3(-m, -m, m), Vector3(m, -m, m), Vector3(m, -m, -m), Vector3(-m, -m, -m), cells[2])
	var c3: Rect2 = cells[3]
	var c4: Rect2 = cells[4]
	_add_tri(verts, uvs, Vector3(-m, m, m), Vector3(m, -m, m), Vector3(-m, -m, m), c3.position, c3.end, Vector2(c3.position.x, c3.end.y))
	_add_tri(verts, uvs, Vector3(-m, m, -m), Vector3(-m, -m, -m), Vector3(m, -m, -m), c4.position, Vector2(c4.position.x, c4.end.y), c4.end)


static func _torus(verts: PackedVector3Array, uvs: PackedVector2Array, seg: int, sides: int) -> void:
	for s in seg:
		var u0 := float(s) / seg
		var u1 := float(s + 1) / seg
		for t in sides:
			var v0 := float(t) / sides
			var v1 := float(t + 1) / sides
			var p00 := _tor(u0, v0)
			var p10 := _tor(u1, v0)
			var p11 := _tor(u1, v1)
			var p01 := _tor(u0, v1)
			_add_tri(verts, uvs, p00, p10, p11, Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1))
			_add_tri(verts, uvs, p00, p11, p01, Vector2(u0, v0), Vector2(u1, v1), Vector2(u0, v1))


static func _tor(u: float, v: float) -> Vector3:
	var a := TAU * u
	var b := TAU * v
	var rr := 0.32 + 0.18 * cos(b)
	return Vector3(cos(a) * rr, 0.5 * sin(b), sin(a) * rr)


# ---------------------------------------------------------------- picking

## Ray (in the shape's unit space) against the shape's triangles.
## Returns {} or {t, point, uv, tri} for the nearest hit.
static func raycast(type: String, origin: Vector3, dir: Vector3) -> Dictionary:
	var d := unit(type)
	var verts: PackedVector3Array = d["verts"]
	var uvs: PackedVector2Array = d["uvs"]
	var best := {}
	var best_t := INF
	for i in range(0, verts.size(), 3):
		var a := verts[i]
		var b := verts[i + 1]
		var c := verts[i + 2]
		var hit: Variant = Geometry3D.ray_intersects_triangle(origin, dir, a, b, c)
		if hit == null:
			continue
		var p: Vector3 = hit
		var t := (p - origin).dot(dir)
		if t <= 0.0 or t >= best_t:
			continue
		var bc := _barycentric(p, a, b, c)
		best_t = t
		best = {"t": t, "point": p, "uv": uvs[i] * bc.x + uvs[i + 1] * bc.y + uvs[i + 2] * bc.z, "tri": i}
	return best


static func _barycentric(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var d20 := v2.dot(v0)
	var d21 := v2.dot(v1)
	var den := d00 * d11 - d01 * d01
	if absf(den) < 1e-12:
		return Vector3(1, 0, 0)
	var v := (d11 * d20 - d01 * d21) / den
	var w := (d00 * d21 - d01 * d20) / den
	return Vector3(1.0 - v - w, v, w)
