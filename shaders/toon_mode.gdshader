// Auto-rotoscope: shape smoothing (weighted majority filter).
// Every pixel takes the palette colour that is most common in a soft circle
// around it. Repeating this rounds off jagged borders and swallows small
// islands, leaving smooth, clean colour shapes.
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float radius = 5.0;
uniform int palette_size = 0;
uniform vec3 pal_out[32];
uniform vec3 ink_color = vec3(0.0);

const int SAMPLES = 40;

int index_of(vec3 c) {
	for (int i = 0; i < 32; i++) {
		if (i >= palette_size) {
			break;
		}
		vec3 d = abs(c - pal_out[i]);
		if (max(max(d.r, d.g), d.b) < 0.01) {
			return i;
		}
	}
	vec3 di = abs(c - ink_color);
	if (max(max(di.r, di.g), di.b) < 0.01) {
		return 32;
	}
	return -1;
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec4 center = texture(screen_tex, SCREEN_UV);
	if (radius < 0.5 || center.a < 0.5) {
		COLOR = center;
	} else {
		float votes[33];
		for (int i = 0; i < 33; i++) {
			votes[i] = 0.0;
		}
		int ci = index_of(center.rgb);
		if (ci >= 0) {
			votes[ci] += 1.0;
		}
		for (int k = 0; k < SAMPLES; k++) {
			float rr = radius * sqrt((float(k) + 0.5) / float(SAMPLES));
			float ang = float(k) * 2.39996323;
			vec2 o = vec2(cos(ang), sin(ang)) * rr;
			vec4 s = texture(screen_tex, SCREEN_UV + o * px);
			if (s.a < 0.5) {
				continue;
			}
			int idx = index_of(s.rgb);
			if (idx >= 0) {
				votes[idx] += exp(-(rr * rr) / (radius * radius));
			}
		}
		int best = -1;
		float best_v = 0.0;
		for (int i = 0; i < 33; i++) {
			if (votes[i] > best_v) {
				best_v = votes[i];
				best = i;
			}
		}
		vec3 outc = center.rgb;
		if (best == 32) {
			outc = ink_color;
		} else if (best >= 0) {
			outc = pal_out[best];
		}
		COLOR = vec4(outc, center.a);
	}
}
