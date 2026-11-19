// Auto-rotoscope final pass: lines on top of the colour fills.
// Traced lines come from the original frame (trace_tex, made by the line
// pipeline) so smoothing the fills never removes them; optional outlines
// around colour areas are added from the fills themselves.
// Reads the flat-colour result of pass 1 through the back buffer.
// 1. Speck cleanup: a pixel that matches almost none of its neighbours takes
//    the most common neighbouring colour, removing noise islands.
// 2. Outlines: a solid line wherever neighbouring colour blocks differ.
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float thickness = 2.0;      // line radius in pixels (0 = no lines)
uniform float sensitivity = 0.12;   // colour difference that counts as an edge
uniform vec4 line_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float speck_radius = 0.0;   // 0 = no cleanup (shape smoothing does this now)
uniform sampler2D trace_tex : filter_linear;  // traced line mask (red = ink)
uniform bool use_trace = true;
uniform bool area_lines = true;
// The source frame: its alpha (a cut-out) is used for the result, because a
// screen-texture copy loses alpha on Forward+.
uniform sampler2D alpha_tex : filter_linear;

bool same(vec3 a, vec3 b) {
	vec3 d = abs(a - b);
	return max(max(d.r, d.g), d.b) < 0.02;
}

vec3 cleaned(vec2 uv, vec2 px) {
	vec3 c = texture(screen_tex, uv).rgb;
	if (speck_radius <= 0.0) {
		return c;
	}
	vec3 n[8];
	n[0] = texture(screen_tex, uv + vec2(-1.0, -1.0) * px * speck_radius).rgb;
	n[1] = texture(screen_tex, uv + vec2(0.0, -1.0) * px * speck_radius).rgb;
	n[2] = texture(screen_tex, uv + vec2(1.0, -1.0) * px * speck_radius).rgb;
	n[3] = texture(screen_tex, uv + vec2(-1.0, 0.0) * px * speck_radius).rgb;
	n[4] = texture(screen_tex, uv + vec2(1.0, 0.0) * px * speck_radius).rgb;
	n[5] = texture(screen_tex, uv + vec2(-1.0, 1.0) * px * speck_radius).rgb;
	n[6] = texture(screen_tex, uv + vec2(0.0, 1.0) * px * speck_radius).rgb;
	n[7] = texture(screen_tex, uv + vec2(1.0, 1.0) * px * speck_radius).rgb;
	int matches = 0;
	for (int i = 0; i < 8; i++) {
		if (same(c, n[i])) { matches++; }
	}
	if (matches >= 2) {
		return c;
	}
	int best_count = -1;
	vec3 best = c;
	for (int i = 0; i < 8; i++) {
		int count = 0;
		for (int j = 0; j < 8; j++) {
			if (same(n[i], n[j])) { count++; }
		}
		if (count > best_count) {
			best_count = count;
			best = n[i];
		}
	}
	return best;
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	float a = texture(alpha_tex, SCREEN_UV).a;
	vec3 c = cleaned(SCREEN_UV, px);
	float edge = 0.0;
	if (area_lines && thickness > 0.0) {
		int r = int(ceil(thickness));
		float r2 = thickness * thickness + 0.25;
		for (int j = -r; j <= r; j++) {
			for (int i = -r; i <= r; i++) {
				if (float(i * i + j * j) > r2) {
					continue;
				}
				vec2 o_uv = SCREEN_UV + vec2(float(i), float(j)) * px;
				vec4 o = texture(screen_tex, o_uv);
				if (texture(alpha_tex, o_uv).a < 0.5) {
					continue; // no outline against transparent padding
				}
				vec3 d = abs(o.rgb - c);
				edge = max(edge, max(max(d.r, d.g), d.b));
			}
		}
	}
	float e = smoothstep(sensitivity, sensitivity * 1.5 + 0.02, edge) * step(0.5, a);
	if (use_trace) {
		e = max(e, texture(trace_tex, SCREEN_UV).r * step(0.5, a));
	}
	COLOR = vec4(mix(c, line_color.rgb, e * line_color.a), a);
}
