shader_type spatial;
// Faceted low-poly set pieces with cel (banded) lighting, so 3D blends with
// flat-coloured 2D drawings. Uses its own normal varying, so it doesn't depend
// on triangle winding.
render_mode cull_disabled, specular_disabled;

uniform bool toon = true;
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
