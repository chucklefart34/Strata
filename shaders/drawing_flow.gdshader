shader_type canvas_item;
render_mode blend_disabled;
// Motion between two drawings (for auto in-betweens). Works on blurred "ink
// density" pictures (1 = ink, 0 = paper), so blank paper near a line still
// knows which way the line went. Each output pixel: where the content at
// this spot in drawing B was in drawing A (B(p) ≈ A(p - d)).
// Output RG = d / (2 * max_motion) + 0.5, in this viewport's pixels.

uniform sampler2D cur_tex : filter_linear, repeat_disable;   // B density
uniform sampler2D prev_tex : filter_linear, repeat_disable;  // A density
uniform sampler2D init_tex : filter_linear, repeat_disable;  // coarser result
uniform bool has_init = false;
uniform float init_max = 32.0;    // init_tex encoding range (its pixels)
uniform float init_scale = 2.0;   // its pixels → these pixels
uniform float max_motion = 64.0;  // output encoding range (these pixels)
uniform float search = 16.0;      // search radius (these pixels)
uniform vec2 res = vec2(480.0, 270.0);
uniform vec2 base_shift = vec2(0.0); // starting guess without init_tex (these pixels)

float cost(vec2 uv, vec2 d) {
	vec2 px = 1.0 / res;
	float s = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 o = vec2(float(i), float(j)) * 2.0 * px;
			s += abs(texture(cur_tex, uv + o).r - texture(prev_tex, uv + o - d * px).r);
		}
	}
	return s / 9.0;
}

void fragment() {
	vec2 pm = base_shift;
	if (has_init) {
		pm = (texture(init_tex, UV).rg - 0.5) * 2.0 * init_max * init_scale;
	}
	vec2 best = pm;
	float bc = cost(UV, pm);
	// nothing to match here (no ink nearby in either drawing): keep the guess
	vec2 px = 1.0 / res;
	float ink = 0.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			vec2 o = vec2(float(i), float(j)) * 3.0 * px;
			ink = max(ink, max(texture(cur_tex, UV + o).r, texture(prev_tex, UV + o).r));
		}
	}
	if (ink > 0.02) {
		float step_px = search / 2.0;
		for (int level = 0; level < 4; level++) {
			vec2 center = best;
			for (int j = -2; j <= 2; j++) {
				for (int i = -2; i <= 2; i++) {
					if (i == 0 && j == 0) {
						continue;
					}
					vec2 d = clamp(center + vec2(float(i), float(j)) * step_px, vec2(-max_motion), vec2(max_motion));
					float c = cost(UV, d) + length(d - pm) * 0.0006;
					if (c < bc) {
						bc = c;
						best = d;
					}
				}
			}
			step_px *= 0.45;
		}
	}
	COLOR = vec4(clamp(best / (2.0 * max_motion) + 0.5, 0.0, 1.0), ink, 1.0);
}
