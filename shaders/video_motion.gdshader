shader_type canvas_item;
render_mode blend_disabled;
// Motion estimation for Datamosh. Each output pixel is one 8×8 block (at
// 1080p) of the picture. It finds where that block was in the previous frame
// (coarse-to-fine block matching), prefers smooth motion (close to its
// neighbours' last motion), and blends with last frame's vectors so the flow
// is fluid.
// Output: RG = motion in pixels at 1080p, encoded as d / (2 * max_motion) + 0.5;
// B = how well the block matched (1 = perfect).

uniform sampler2D cur_tex : filter_linear, repeat_disable;
uniform sampler2D prev_tex : filter_linear, repeat_disable;
uniform sampler2D prev_motion : filter_linear, repeat_disable;
uniform vec2 res = vec2(1920.0, 1080.0);   // picture size in pixels
uniform float ps = 1.0;                    // res.y / 1080
uniform float max_motion = 48.0;           // largest motion stored (1080p pixels)
uniform bool has_prev = false;
uniform bool has_prev_motion = false;

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Difference between the block at uv in this frame and at uv - d (pixels,
// 1080p units) in the last frame, over a 3×3 grid of samples.
float cost(vec2 uv, vec2 d) {
	vec2 px = 1.0 / res;
	vec2 off = d * ps * px;
	float s = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 o = vec2(float(i), float(j)) * 3.0 * ps * px;
			float a = luma(texture(cur_tex, uv + o).rgb);
			float b = luma(texture(prev_tex, uv + o - off).rgb);
			s += abs(a - b);
		}
	}
	return s / 9.0;
}

vec2 decode(vec4 v) {
	return (v.rg - 0.5) * 2.0 * max_motion;
}

void fragment() {
	vec2 uv = UV;
	if (!has_prev) {
		COLOR = vec4(0.5, 0.5, 1.0, 1.0);
	} else {
		vec2 pm = has_prev_motion ? decode(texture(prev_motion, uv)) : vec2(0.0);
		// Start from "no motion" and from last frame's motion, whichever fits.
		vec2 best = vec2(0.0);
		float bc = cost(uv, best) - 0.004;   // slight preference for standing still
		float pc = cost(uv, pm);
		if (pc < bc) {
			best = pm;
			bc = pc;
		}
		// Coarse search around the best guess, then finer.
		float step_px = max_motion / 4.0;
		for (int level = 0; level < 3; level++) {
			vec2 center = best;
			for (int j = -2; j <= 2; j++) {
				for (int i = -2; i <= 2; i++) {
					if (i == 0 && j == 0) { continue; }
					vec2 d = clamp(center + vec2(float(i), float(j)) * step_px, vec2(-max_motion), vec2(max_motion));
					float c = cost(uv, d) + length(d - pm) * 0.0004;   // smoothness
					if (c < bc) {
						bc = c;
						best = d;
					}
				}
			}
			step_px *= 0.35;
		}
		// Temporal smoothing keeps the flow fluid instead of twitchy.
		if (has_prev_motion) {
			best = mix(best, pm, 0.35);
		}
		float conf = clamp(1.0 - bc * 6.0, 0.0, 1.0);
		COLOR = vec4(best / (2.0 * max_motion) + 0.5, conf, 1.0);
	}
}
