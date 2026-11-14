class_name LowPolyBuilder
extends RefCounted
## Turns blockout shapes into a stylised low-poly set: shapes are split into
## facets, nudged by a seeded wobble, coloured per facet from a palette, and
## given an ink outline hull. Each shape can "become" something (building,
## tree, bush, rock, hill) which adds the obvious details.
##
## Meshes are built in the prop's own sized space, centred on the box the
## blockout occupies, so the prop transform carries only rotation and position.

const ROLES := ["auto", "plain", "building", "tree", "bush", "rock", "hill"]
const ROLE_NAMES := ["Automatic", "Plain shape", "Building", "Tree", "Bush", "Rock", "Hill"]
const DEFAULT_PROP_COLOR := "8a8f9cff"

const PALETTES := {
	"Storybook": {"ground": "7fa35b", "ground_side": "8b6b4a", "rock": "8d8a86", "wood": "6e4b33",
		"leaf": "4f8a4a", "leaf2": "6aa35a", "wall": "e6d3b3", "roof": "b5523b", "window": "2f3a4f", "door": "5a3b2a"},
	"Dusk": {"ground": "4d5a6e", "ground_side": "4a3f55", "rock": "6c6478", "wood": "4a3a44",
		"leaf": "3f5f62", "leaf2": "4f7470", "wall": "c99f8a", "roof": "6b3f5c", "window": "ffcf7a", "door": "3b2a3a"},
	"Pastel": {"ground": "b8d8a8", "ground_side": "d8c0a8", "rock": "c8c4d4", "wood": "b89a84",
		"leaf": "9ccfa4", "leaf2": "b4dcae", "wall": "f4e4d4", "roof": "e8a4a4", "window": "8ab4d8", "door": "c49a8a"},
	"Desert": {"ground": "d9b77a", "ground_side": "b88a56", "rock": "b07a52", "wood": "7a5a3a",
		"leaf": "7f9a55", "leaf2": "93ad62", "wall": "e8c896", "roof": "c46a42", "window": "3a3240", "door": "6a4430"},
	"Ink & paper": {"ground": "e8e2d6", "ground_side": "cfc7b8", "rock": "d6d0c4", "wood": "bdb4a4",
		"leaf": "dcd6c8", "leaf2": "e6e0d2", "wall": "f2ede4", "roof": "c4bcae", "window": "403c38", "door": "8a8274"},
}

const TOON_SHADER := preload("res://shaders/lowpoly_toon.gdshader")
const INK_SHADER := preload("res://shaders/lowpoly_ink.gdshader")
const CLEAR_SHADER := preload("res://shaders/lowpoly_toon_clear.gdshader")


static func default_settings() -> Dictionary:
	return {
		"on": false, "palette": "Storybook", "shading": "toon", "bands": 3.0,
		"detail": 1.0, "rough": 0.5, "variation": 0.12, "outline": 0.06,
		"ink": "0b0909ff", "seed": 1, "terrain": true, "hills": 1.0,
	}


static func setting(settings: Dictionary, key: String) -> Variant:
	return settings.get(key, default_settings().get(key))


static func palette_color(settings: Dictionary, key: String) -> Color:
	var pal: Dictionary = PALETTES.get(str(setting(settings, "palette")), PALETTES["Storybook"])
	return Color.from_string(str(pal.get(key, "888888")), Color.GRAY)


## What a prop becomes when its role is "auto".
static func resolve_role(p: Dictionary) -> String:
	var role := str(p.get("role", "auto"))
	if role != "auto" and ROLES.has(role):
		return role
	return "rock" if str(p.get("type", "box")) == "sphere" else "plain"


# ================================================================ blockout helpers

const SHAPE_SIZES := {
	"box": [2.0, 2.0, 2.0], "wall": [12.0, 6.0, 0.4], "cylinder": [1.6, 3.0, 1.6],
	"sphere": [2.0, 2.0, 2.0], "ramp": [3.0, 1.5, 3.0], "cone": [2.0, 3.0, 2.0],
	"pyramid": [2.5, 2.5, 2.5], "torus": [3.0, 0.8, 3.0],
}
const ROLE_SHAPES := {
	"building": ["box", [6.0, 9.0, 6.0]], "tree": ["cylinder", [3.2, 7.0, 3.2]],
	"bush": ["sphere", [2.6, 1.6, 2.6]], "rock": ["sphere", [2.2, 1.5, 2.0]],
	"hill": ["sphere", [16.0, 4.0, 12.0]],
}
const ROLE_LABELS := {"building": "Building", "tree": "Tree", "bush": "Bush", "rock": "Rock", "hill": "Hill"}


static func make_prop(type: String, role: String, n: int, pos: Array = [0.0, 0.0, 6.0], size: Array = [], rot_y: float = 0.0) -> Dictionary:
	var shape := type
	var sz: Array = SHAPE_SIZES.get(type, [2.0, 2.0, 2.0])
	if ROLE_SHAPES.has(role) and (type == "" or type == "auto"):
		var rs: Array = ROLE_SHAPES[role]
		shape = str(rs[0])
		sz = rs[1]
	if type == "wall":
		shape = "box"
	if not size.is_empty():
		sz = size
	var names := {"box": "Box", "cylinder": "Pillar", "sphere": "Ball", "ramp": "Ramp", "cone": "Cone", "pyramid": "Pyramid", "torus": "Ring"}
	var label := str(ROLE_LABELS.get(role, names.get(shape, "Piece")))
	if type == "wall":
		label = "Wall"
	return {"id": Ids.make(), "type": shape, "role": role, "name": "%s %d" % [label, n],
		"pos": pos.duplicate(), "rot": [0.0, rot_y, 0.0], "size": sz.duplicate(), "color": DEFAULT_PROP_COLOR,
		"clear": 0.0, "cast_shadow": true}


## Rough layouts to start a set from. Positions are [x, lift, depth].
static func template(template_name: String) -> Array:
	var out: Array = []
	var add := func(type: String, role: String, pos: Array, size: Array) -> void:
		out.append(make_prop(type, role, out.size() + 1, pos, size))
	match template_name:
		"Street":
			add.call("", "building", [-13.0, 0.0, 4.0], [7.0, 9.0, 7.0])
			add.call("", "building", [-14.0, 0.0, 14.0], [7.0, 13.0, 8.0])
			add.call("", "building", [-12.0, 0.0, 26.0], [6.0, 10.0, 7.0])
			add.call("", "building", [13.0, 0.0, 5.0], [7.0, 11.0, 7.0])
			add.call("", "building", [14.0, 0.0, 16.0], [8.0, 8.0, 8.0])
			add.call("", "building", [12.0, 0.0, 28.0], [6.0, 14.0, 7.0])
			add.call("", "building", [0.0, 0.0, 42.0], [14.0, 12.0, 6.0])
			add.call("", "tree", [-7.5, 0.0, 9.0], [2.6, 6.0, 2.6])
			add.call("", "tree", [7.5, 0.0, 12.0], [2.6, 6.0, 2.6])
			add.call("box", "plain", [6.5, 0.0, 2.0], [1.2, 1.0, 1.2])
		"Room":
			add.call("wall", "plain", [0.0, 0.0, 14.0], [26.0, 11.0, 0.5])
			add.call("wall", "plain", [-12.0, 0.0, 4.0], [0.5, 11.0, 20.0])
			add.call("wall", "plain", [12.0, 0.0, 4.0], [0.5, 11.0, 20.0])
			add.call("box", "plain", [3.0, 0.0, 6.0], [4.5, 1.6, 2.4])
			add.call("box", "plain", [-7.0, 0.0, 11.5], [3.0, 5.5, 1.2])
			add.call("cylinder", "plain", [8.5, 0.0, 10.0], [1.2, 2.2, 1.2])
		"Forest":
			var spots := [[-14.0, 4.0], [-9.0, 12.0], [-17.0, 18.0], [-6.0, 24.0], [10.0, 6.0], [15.0, 13.0], [7.0, 20.0], [17.0, 26.0], [-2.0, 34.0], [-12.0, 32.0], [12.0, 36.0]]
			for i in spots.size():
				var sp: Array = spots[i]
				var tall := 6.0 + float(i % 3) * 2.5
				add.call("", "tree", [sp[0], 0.0, sp[1]], [3.0, tall * (1.0 if i % 2 == 0 else 1.6), 3.0])
			add.call("", "bush", [-6.0, 0.0, 3.0], [2.6, 1.6, 2.6])
			add.call("", "bush", [7.0, 0.0, 2.5], [3.0, 1.8, 2.6])
			add.call("", "rock", [4.0, 0.0, 9.0], [2.4, 1.5, 2.0])
			add.call("", "rock", [-3.0, 0.0, 15.0], [1.6, 1.0, 1.5])
		"Hills":
			add.call("", "hill", [-18.0, 0.0, 40.0], [34.0, 9.0, 22.0])
			add.call("", "hill", [16.0, 0.0, 52.0], [40.0, 12.0, 26.0])
			add.call("", "hill", [-2.0, 0.0, 70.0], [60.0, 16.0, 30.0])
			add.call("", "tree", [-10.0, 0.0, 18.0], [3.0, 6.5, 3.0])
			add.call("", "tree", [11.0, 0.0, 22.0], [3.0, 7.5, 3.0])
			add.call("", "rock", [6.0, 0.0, 7.0], [2.4, 1.4, 2.0])
			add.call("", "bush", [-6.0, 0.0, 5.0], [2.8, 1.6, 2.4])
	return out


# ================================================================ materials

static func body_material(settings: Dictionary, alpha: float = 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON_SHADER if alpha >= 0.999 else CLEAR_SHADER
	if alpha < 0.999:
		m.set_shader_parameter("alpha", clampf(alpha, 0.0, 1.0))
	m.set_shader_parameter("toon", str(setting(settings, "shading")) == "toon")
	m.set_shader_parameter("bands", float(setting(settings, "bands")))
	return m


static func ink_material(settings: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = INK_SHADER
	m.set_shader_parameter("ink", Color.from_string(str(setting(settings, "ink")), Color.BLACK))
	return m


# ================================================================ public: build

## Returns {"body": ArrayMesh, "ink": ArrayMesh or null} for one blockout prop.
static func build_prop(p: Dictionary, settings: Dictionary) -> Dictionary:
	var size := _size_of(p)
	var parts := _parts_for(p, size, settings)
	return _assemble(parts, settings, float(setting(settings, "outline")) > 0.001)


## Rolling ground around the action area, at local y = 0 (the floor height).
static func build_terrain(settings: Dictionary) -> ArrayMesh:
	var detail := clampf(float(setting(settings, "detail")), 0.3, 3.0)
	var cell := 2.6 / detail
	var hills := float(setting(settings, "hills"))
	var seed_v := int(setting(settings, "seed"))
	var rough := float(setting(settings, "rough"))
	var s1 := float(seed_v % 97) * 0.731
	var s2 := float(seed_v % 89) * 1.37
	var x0 := -56.0
	var x1 := 56.0
	var d0 := -14.0  # depth (toward camera)
	var d1 := 110.0  # depth (far away)
	var nx := int(ceil((x1 - x0) / cell))
	var nz := int(ceil((d1 - d0) / cell))
	var heights := PackedFloat32Array()
	heights.resize((nx + 1) * (nz + 1))
	var pts := PackedVector3Array()
	pts.resize((nx + 1) * (nz + 1))
	for iz in nz + 1:
		for ix in nx + 1:
			var x := x0 + (x1 - x0) * ix / float(nx)
			var dep := d0 + (d1 - d0) * iz / float(nz)
			# Keep the acting area flat so drawings stand on level ground.
			var away := maxf(maxf(absf(x) - 13.0, dep - 13.0), 0.0)
			var mask := smoothstep(0.0, 10.0, away)
			var n := sin(x * 0.11 + s1) * cos(dep * 0.09 + s2) + 0.6 * sin(x * 0.23 - dep * 0.17 + s2 * 2.0) + 0.35 * cos(x * 0.47 + dep * 0.41 + s1)
			var h := maxf(0.0, n * 0.5 + 0.55) * 3.2 * hills * mask
			var j := _jitter(Vector3(x, 0, dep), seed_v)
			var jx := 0.0
			var jz := 0.0
			if ix > 0 and ix < nx and iz > 0 and iz < nz:
				jx = j.x * cell * 0.3 * rough
				jz = j.z * cell * 0.3 * rough
				h += j.y * cell * 0.12 * rough * (0.3 + mask)
			pts[iz * (nx + 1) + ix] = Vector3(x + jx, h, -(dep + jz))
	var grass := palette_color(settings, "ground")
	var dirt := palette_color(settings, "ground_side")
	var variation := float(setting(settings, "variation"))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in nz:
		for ix in nx:
			var a := pts[iz * (nx + 1) + ix]
			var b := pts[iz * (nx + 1) + ix + 1]
			var c := pts[(iz + 1) * (nx + 1) + ix]
			var d := pts[(iz + 1) * (nx + 1) + ix + 1]
			var tris := [[a, b, d], [a, d, c]] if (ix + iz) % 2 == 0 else [[a, b, c], [b, d, c]]
			for t in tris:
				var tv: Array = t
				var p0: Vector3 = tv[0]
				var p1: Vector3 = tv[1]
				var p2: Vector3 = tv[2]
				var nrm := (p1 - p0).cross(p2 - p0).normalized()
				if nrm.y < 0.0:
					nrm = -nrm
				var base := grass if nrm.y > 0.86 else grass.lerp(dirt, clampf((0.86 - nrm.y) * 4.0, 0.0, 1.0))
				var cen := (p0 + p1 + p2) / 3.0
				_emit(st, p0, p1, p2, nrm, _vary(base, cen, seed_v, variation))
	return st.commit()


# ================================================================ parts per role

static func _size_of(p: Dictionary) -> Vector3:
	var s: Variant = p.get("size")
	if typeof(s) == TYPE_ARRAY:
		var a: Array = s
		if a.size() >= 3:
			return Vector3(maxf(0.05, float(a[0])), maxf(0.05, float(a[1])), maxf(0.05, float(a[2])))
	return Vector3.ONE


static func _main_color(p: Dictionary, settings: Dictionary, palette_key: String) -> Color:
	var pc := str(p.get("color", DEFAULT_PROP_COLOR))
	if pc == DEFAULT_PROP_COLOR or pc == "":
		return palette_color(settings, palette_key)
	return Color.from_string(pc, Color.GRAY)


## A part: {tris: Array[PackedVector3Array(3)], color, center, rough (multiplier),
## level (subdivisions), sphere (Vector3 radii) or none, ink (bool), top (Color, optional)}
static func _parts_for(p: Dictionary, s: Vector3, settings: Dictionary) -> Array:
	var role := resolve_role(p)
	var type := str(p.get("type", "box"))
	var h := s * 0.5
	var parts: Array = []
	var detail := clampf(float(setting(settings, "detail")), 0.3, 3.0)
	match role:
		"building":
			var body_h := s.y * 0.72
			var body_c := Vector3(0, -h.y + body_h * 0.5, 0)
			parts.append(_part(_box_tris(body_c, Vector3(s.x, body_h, s.z)), _main_color(p, settings, "wall"), body_c, 0.15, _level_for(maxf(s.x, s.z), detail)))
			var roof_c := Vector3(0, -h.y + body_h + (s.y - body_h) * 0.4, 0)
			parts.append(_part(_gable_tris(-h.y + body_h, h.y, h.x + 0.25, h.z + 0.35), palette_color(settings, "roof"), roof_c, 0.2, 0))
			var win := palette_color(settings, "window")
			var cols := maxi(1, int(s.x / 1.7))
			var rows := maxi(1, int(body_h / 2.0))
			for face in [1.0, -1.0]:
				var fz: float = face
				for r in rows:
					for c in cols:
						var wx := -h.x + s.x * (c + 0.5) / cols
						var wy := -h.y + body_h * (r + 0.6) / (rows + 0.25)
						if fz > 0.0 and r == 0 and c == cols / 2:
							# Door on the front.
							var dh := minf(body_h * 0.42, 2.2)
							var dc := Vector3(wx, -h.y + dh * 0.5, fz * (h.z + 0.04))
							parts.append(_part(_box_tris(dc, Vector3(minf(1.1, s.x / cols * 0.6), dh, 0.1)), palette_color(settings, "door"), dc, 0.0, 0, false))
							continue
						var wc := Vector3(wx, wy, fz * (h.z + 0.04))
						var ws := Vector3(minf(0.9, s.x / cols * 0.5), minf(1.1, body_h / rows * 0.45), 0.1)
						parts.append(_part(_box_tris(wc, ws), win, wc, 0.0, 0, false))
			var side_cols := maxi(1, int(s.z / 2.2))
			for face in [1.0, -1.0]:
				var fx: float = face
				for r in rows:
					for c in side_cols:
						var wz := -h.z + s.z * (c + 0.5) / side_cols
						var wy := -h.y + body_h * (r + 0.6) / (rows + 0.25)
						var wc := Vector3(fx * (h.x + 0.04), wy, wz)
						parts.append(_part(_box_tris(wc, Vector3(0.1, minf(1.1, body_h / rows * 0.45), minf(0.9, s.z / side_cols * 0.5))), win, wc, 0.0, 0, false))
		"tree":
			var trunk_r := maxf(0.12, minf(s.x, s.z) * 0.1)
			var tall := s.y / maxf(s.x, s.z) >= 2.2
			var trunk_h := s.y * (0.3 if tall else 0.45)
			var tc := Vector3(0, -h.y + trunk_h * 0.5, 0)
			parts.append(_part(_cyl_tris(tc, trunk_r, trunk_h, 5), palette_color(settings, "wood"), tc, 0.3, 0))
			var leaf := _main_color(p, settings, "leaf")
			if tall:
				# Pine: stacked cones.
				var y0 := -h.y + trunk_h * 0.7
				var tiers := 3
				for i in tiers:
					var t := float(i) / tiers
					var base_y := y0 + (h.y - y0) * t * 0.78
					var top_y := minf(h.y, base_y + (h.y - y0) * 0.5)
					var rr := maxf(s.x, s.z) * 0.5 * (1.0 - t * 0.35)
					var cc := Vector3(0, (base_y + top_y) * 0.5, 0)
					var col := leaf if i % 2 == 0 else palette_color(settings, "leaf2")
					parts.append(_part(_cone_tris(base_y, top_y, rr, 7), col, cc, 0.6, 0))
			else:
				var can_h := s.y - trunk_h * 0.75
				var cc := Vector3(0, h.y - can_h * 0.5, 0)
				parts.append(_sphere_part(cc, Vector3(h.x, can_h * 0.5, h.z), leaf, 1.0, 1 if detail >= 1.4 else 0))
		"bush":
			var leaf := _main_color(p, settings, "leaf")
			var blobs := [[Vector3(0, 0, 0), 1.0], [Vector3(-0.32, -0.12, 0.08), 0.7], [Vector3(0.34, -0.15, -0.05), 0.65]]
			for i in blobs.size():
				var b: Array = blobs[i]
				var off: Vector3 = b[0]
				var k: float = b[1]
				var r := Vector3(h.x * 0.62 * k, h.y * k, h.z * 0.75 * k)
				var cc := Vector3(off.x * s.x, -h.y + r.y, off.z * s.z)
				parts.append(_sphere_part(cc, r, leaf if i == 0 else palette_color(settings, "leaf2"), 1.1, 0, -h.y))
		"rock":
			parts.append(_sphere_part(Vector3.ZERO, h, _main_color(p, settings, "rock"), 1.8, 1 if detail >= 0.8 else 0, -h.y))
		"hill":
			var r := Vector3(h.x, s.y, h.z)
			var hp := _sphere_part(Vector3(0, -h.y, 0), r, palette_color(settings, "ground_side"), 1.0, _level_for(maxf(s.x, s.z) * 0.6, detail) , -h.y)
			hp["top"] = _main_color(p, settings, "ground")
			parts.append(hp)
		_:
			var col := _main_color(p, settings, "rock")
			match type:
				"cylinder":
					parts.append(_part(_cyl_tris(Vector3.ZERO, maxf(h.x, h.z), s.y, int(round(6 + detail * 2.0))), col, Vector3.ZERO, 0.6, _level_for(s.y, detail)))
				"sphere":
					parts.append(_sphere_part(Vector3.ZERO, h, col, 0.8, 1, -h.y))
				"ramp":
					parts.append(_part(_ramp_tris(h), col, Vector3(-h.x * 0.33, -h.y * 0.33, 0), 0.6, _level_for(maxf(s.x, s.z), detail)))
				"cone", "pyramid", "torus":
					var src: PackedVector3Array = ShapeMesh.oriented(type)
					var tris: Array = []
					for i in range(0, src.size(), 3):
						tris.append(PackedVector3Array([src[i] * s, src[i + 1] * s, src[i + 2] * s]))
					var pp := _part(tris, col, Vector3.ZERO, 0.5 if type != "torus" else 0.25, 0)
					pp["oriented"] = true
					parts.append(pp)
				_:
					parts.append(_part(_box_tris(Vector3.ZERO, s), col, Vector3.ZERO, 0.6, _level_for(maxf(s.x, maxf(s.y, s.z)), detail)))
	return parts


static func _part(tris: Array, color: Color, center: Vector3, rough: float, level: int, ink: bool = true) -> Dictionary:
	return {"tris": tris, "color": color, "center": center, "rough": rough, "level": level, "ink": ink}


## Ellipsoid from a subdivided icosahedron. Vertices below `floor_y` are flattened.
static func _sphere_part(center: Vector3, radii: Vector3, color: Color, rough: float, level: int, floor_y: float = -INF) -> Dictionary:
	var d := _part(_ico_tris(), color, center, rough, level)
	d["sphere"] = radii
	d["floor"] = floor_y
	return d


static func _level_for(extent: float, detail: float) -> int:
	var cell := 3.0 / detail
	if extent <= cell:
		return 0
	return clampi(int(ceil(log(extent / cell) / log(2.0))), 0, 3)


# ================================================================ assembly

static func _assemble(parts: Array, settings: Dictionary, with_ink: bool) -> Dictionary:
	var seed_v := int(setting(settings, "seed"))
	var rough := float(setting(settings, "rough"))
	var variation := float(setting(settings, "variation"))
	var outline := float(setting(settings, "outline"))
	var detail := clampf(float(setting(settings, "detail")), 0.3, 3.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ink_tris: Array = []  # [a, b, c, face normal]
	for item in parts:
		var part: Dictionary = item
		var tris: Array = part["tris"]
		for i in int(part["level"]):
			tris = _subdivide(tris)
		var center: Vector3 = part["center"]
		var is_sphere := part.has("sphere")
		var radii: Vector3 = part.get("sphere", Vector3.ONE)
		var floor_y: float = part.get("floor", -INF)
		var min_y := INF
		if not is_sphere:
			for t in tris:
				var tv: PackedVector3Array = t
				for v in tv:
					min_y = minf(min_y, v.y)
		# Wobble amount in world units, relative to facet size.
		var facet := 3.0 / detail / pow(2.0, float(part["level"]))
		if is_sphere:
			facet = minf(radii.x, minf(radii.y, radii.z)) * (0.55 if int(part["level"]) == 0 else 0.3)
		var amp := float(part["rough"]) * rough * minf(facet * 0.18, 0.6)
		var top_col: Variant = part.get("top")
		var base_col: Color = part["color"]
		for t in tris:
			var tv: PackedVector3Array = t
			var q := PackedVector3Array()
			for v0 in tv:
				var v: Vector3 = v0
				if is_sphere:
					v = center + v.normalized() * radii
				var key := v
				if amp > 0.0:
					var j := _jitter(key, seed_v) * amp
					var grounded := (is_sphere and v.y <= floor_y + 0.001) or (not is_sphere and v.y <= min_y + 0.001)
					if grounded:
						j.y = 0.0
					v += j
				if is_sphere and v.y < floor_y:
					v.y = floor_y
				q.append(v)
			var nrm := (q[1] - q[0]).cross(q[2] - q[0])
			if nrm.length_squared() < 1e-10:
				continue
			nrm = nrm.normalized()
			var cen := (q[0] + q[1] + q[2]) / 3.0
			if not bool(part.get("oriented", false)) and nrm.dot(cen - center) < 0.0:
				nrm = -nrm
			var col := base_col
			if top_col != null and nrm.y > 0.55:
				var tc: Color = top_col
				col = tc
			_emit(st, q[0], q[1], q[2], nrm, _vary(col, cen, seed_v, variation))
			if with_ink and bool(part["ink"]):
				ink_tris.append([q[0], q[1], q[2], nrm])
	var out := {"body": st.commit(), "ink": null}
	if with_ink and not ink_tris.is_empty():
		out["ink"] = _ink_hull(ink_tris, outline)
	return out


## Inflated copy along averaged normals, for the ink outline.
static func _ink_hull(tris: Array, thickness: float) -> ArrayMesh:
	var acc := {}
	for t in tris:
		var tv: Array = t
		var n: Vector3 = tv[3]
		for i in 3:
			var p: Vector3 = tv[i]
			var k := _key(p)
			var prev: Vector3 = acc.get(k, Vector3.ZERO)
			acc[k] = prev + n
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in tris:
		var tv: Array = t
		var verts: Array[Vector3] = []
		var norms: Array[Vector3] = []
		for i in 3:
			var p: Vector3 = tv[i]
			var an: Vector3 = acc[_key(p)]
			var face_n: Vector3 = tv[3]
			an = an.normalized() if an.length_squared() > 1e-8 else face_n
			verts.append(p + an * thickness)
			norms.append(an)
		for i in 3:
			st.set_normal(norms[i])
			st.add_vertex(verts[i])
	return st.commit()


static func _emit(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	# Godot treats clockwise triangles as front faces; order to match `n`.
	var lin := col.srgb_to_linear()
	var order: Array[Vector3] = [a, b, c]
	if (b - a).cross(c - a).dot(n) > 0.0:
		order = [a, c, b]
	for v in order:
		st.set_color(lin)
		st.set_normal(n)
		st.add_vertex(v)


static func _vary(c: Color, at: Vector3, seed_v: int, amount: float) -> Color:
	if amount <= 0.0:
		return c
	var j := _jitter(at * 3.17, seed_v + 7)
	var k := 1.0 + j.x * amount
	var out := Color(c.r * k, c.g * k, c.b * k, 1.0)
	# A touch of hue drift toward warm/cool keeps big areas lively.
	out = out.lerp(Color(out.r * 1.04, out.g, out.b * 0.96), clampf(j.y * 0.5 + 0.5, 0.0, 1.0) * amount)
	return Color(clampf(out.r, 0, 1), clampf(out.g, 0, 1), clampf(out.b, 0, 1), 1.0)


static func _key(p: Vector3) -> Vector3i:
	return Vector3i(roundi(p.x * 1000.0), roundi(p.y * 1000.0), roundi(p.z * 1000.0))


## Deterministic offset in [-1, 1]^3 for a position (same input → same output,
## so shared vertices move together and no cracks appear).
static func _jitter(p: Vector3, seed_v: int) -> Vector3:
	var k := _key(p)
	var h := hash([k.x, k.y, k.z, seed_v])
	return Vector3(
		float(h & 1023) / 511.5 - 1.0,
		float((h >> 10) & 1023) / 511.5 - 1.0,
		float((h >> 20) & 1023) / 511.5 - 1.0)


static func _subdivide(tris: Array) -> Array:
	var out: Array = []
	for t in tris:
		var tv: PackedVector3Array = t
		var a := tv[0]
		var b := tv[1]
		var c := tv[2]
		var ab := (a + b) * 0.5
		var bc := (b + c) * 0.5
		var ca := (c + a) * 0.5
		out.append(PackedVector3Array([a, ab, ca]))
		out.append(PackedVector3Array([ab, b, bc]))
		out.append(PackedVector3Array([ca, bc, c]))
		out.append(PackedVector3Array([ab, bc, ca]))
	return out


# ================================================================ base shapes

static func _tri(a: Vector3, b: Vector3, c: Vector3) -> PackedVector3Array:
	return PackedVector3Array([a, b, c])


static func _quad(out: Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	out.append(_tri(a, b, c))
	out.append(_tri(a, c, d))


static func _box_tris(c: Vector3, s: Vector3) -> Array:
	var h := s * 0.5
	var p := []
	for i in 8:
		p.append(c + Vector3(h.x if (i & 1) != 0 else -h.x, h.y if (i & 2) != 0 else -h.y, h.z if (i & 4) != 0 else -h.z))
	var out: Array = []
	_quad(out, p[0], p[1], p[3], p[2])  # back (-z)
	_quad(out, p[4], p[5], p[7], p[6])  # front (+z)
	_quad(out, p[0], p[1], p[5], p[4])  # bottom
	_quad(out, p[2], p[3], p[7], p[6])  # top
	_quad(out, p[0], p[2], p[6], p[4])  # left
	_quad(out, p[1], p[3], p[7], p[5])  # right
	return out


static func _cyl_tris(c: Vector3, r: float, height: float, sides: int) -> Array:
	var out: Array = []
	var y0 := c.y - height * 0.5
	var y1 := c.y + height * 0.5
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := Vector3(c.x + cos(a0) * r, 0, c.z + sin(a0) * r)
		var p1 := Vector3(c.x + cos(a1) * r, 0, c.z + sin(a1) * r)
		_quad(out, Vector3(p0.x, y0, p0.z), Vector3(p1.x, y0, p1.z), Vector3(p1.x, y1, p1.z), Vector3(p0.x, y1, p0.z))
		out.append(_tri(Vector3(c.x, y1, c.z), Vector3(p0.x, y1, p0.z), Vector3(p1.x, y1, p1.z)))
		out.append(_tri(Vector3(c.x, y0, c.z), Vector3(p1.x, y0, p1.z), Vector3(p0.x, y0, p0.z)))
	return out


static func _cone_tris(y0: float, y1: float, r: float, sides: int) -> Array:
	var out: Array = []
	var apex := Vector3(0, y1, 0)
	for i in sides:
		var a0 := TAU * i / sides + 0.3
		var a1 := TAU * (i + 1) / sides + 0.3
		var p0 := Vector3(cos(a0) * r, y0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, y0, sin(a1) * r)
		out.append(_tri(apex, p0, p1))
		out.append(_tri(Vector3(0, y0, 0), p1, p0))
	return out


## Pitched roof with the ridge along x.
static func _gable_tris(y0: float, y1: float, hx: float, hz: float) -> Array:
	var out: Array = []
	var a := Vector3(-hx, y0, -hz)
	var b := Vector3(hx, y0, -hz)
	var c := Vector3(hx, y0, hz)
	var d := Vector3(-hx, y0, hz)
	var r0 := Vector3(-hx, y1, 0)
	var r1 := Vector3(hx, y1, 0)
	_quad(out, a, b, r1, r0)
	_quad(out, d, c, r1, r0)
	out.append(_tri(a, d, r0))
	out.append(_tri(b, c, r1))
	_quad(out, a, b, c, d)
	return out


## Wedge rising from +x (low) to -x (high), like Godot's PrismMesh with left_to_right = 0.
static func _ramp_tris(h: Vector3) -> Array:
	var out: Array = []
	var a := Vector3(-h.x, -h.y, -h.z)
	var b := Vector3(h.x, -h.y, -h.z)
	var c := Vector3(h.x, -h.y, h.z)
	var d := Vector3(-h.x, -h.y, h.z)
	var e := Vector3(-h.x, h.y, -h.z)
	var f := Vector3(-h.x, h.y, h.z)
	_quad(out, a, b, c, d)  # bottom
	_quad(out, a, d, f, e)  # tall side
	_quad(out, b, c, f, e)  # slope
	out.append(_tri(a, b, e))
	out.append(_tri(d, c, f))
	return out


static func _ico_tris() -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v := [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	var f := [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]
	var out: Array = []
	for face in f:
		var fa: Array = face
		var a: Vector3 = v[fa[0]]
		var b: Vector3 = v[fa[1]]
		var c: Vector3 = v[fa[2]]
		out.append(_tri(a.normalized(), b.normalized(), c.normalized()))
	return out
