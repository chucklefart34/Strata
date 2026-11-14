shader_type spatial;
// See-through version of lowpoly_toon (used when a shape is partly clear).
render_mode cull_disabled, specular_disabled;

uniform bool toon = true;
uniform float alpha = 1.0;
uniform float bands = 3.0;
uniform float band_offset = 0.35;

varying vec3 v_n;

void vertex() {
	v_n = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	NORMAL = normalize(v_n);
	ROUGHNESS = 1.0;
	ALPHA = alpha;
}

void light() {
	float d = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	if (toon) {
		if (bands < 1.5) {
			d = step(0.45, d);
		} else {
			d = clamp(floor(d * bands + band_offset) / bands, 0.0, 1.0);
		}
	}
	DIFFUSE_LIGHT += d * LIGHT_COLOR / PI;
}
