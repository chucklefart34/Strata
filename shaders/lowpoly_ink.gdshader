shader_type spatial;
// Ink outline: an inflated copy of the mesh where only the faces pointing
// away from the camera are drawn, leaving a line around the silhouette.
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec4 ink : source_color = vec4(0.04, 0.035, 0.035, 1.0);

varying vec3 v_n;
varying vec3 v_p;

void vertex() {
	v_n = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	v_p = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 to_cam = PROJECTION_MATRIX[3][3] > 0.5 ? vec3(0.0, 0.0, 1.0) : normalize(-v_p);
	if (dot(normalize(v_n), to_cam) > 0.0) {
		discard;
	}
	ALBEDO = ink.rgb;
}
