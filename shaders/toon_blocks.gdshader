// Auto-rotoscope pass 1: flat colour blocks.
// 1. Kuwahara filter (edge-preserving smoothing) turns detail and noise into
//    painted-looking patches while keeping shapes crisp.
// 2. Every pixel snaps to the nearest colour of a small palette (compared in
//    CIE Lab, so matches look right to the eye) and is painted with that
//    palette entry's output colour — this is what lets you recolour footage.
// 3. Optionally, dark areas become solid ink (graphic black shadows).
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform int radius = 3;
uniform int palette_size = 0;
uniform vec3 pal_lab[32];
uniform vec3 pal_out[32];
uniform float ink_threshold = 0.0;   // Lab lightness (0..1) below which areas become ink
uniform vec3 ink_color = vec3(0.0);
uniform int levels = 5;              // fallback banding when no palette is set

vec4 quadrant(sampler2D tex, vec2 uv, vec2 px, int x0, int y0) {
	vec3 sum = vec3(0.0);
	vec3 sum_sq = vec3(0.0);
	float n = 0.0;
	for (int j = 0; j <= radius; j++) {
		for (int i = 0; i <= radius; i++) {
			vec3 c = texture(tex, uv + vec2(float(x0 + i), float(y0 + j)) * px).rgb;
			sum += c;
			sum_sq += c * c;
			n += 1.0;
		}
	}
	vec3 mean = sum / n;
	vec3 variance = abs(sum_sq / n - mean * mean);
	return vec4(mean, variance.r + variance.g + variance.b);
}

float lin(float c) {
	return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

float lab_f(float t) {
	return t > 0.008856 ? pow(t, 1.0 / 3.0) : 7.787 * t + 16.0 / 116.0;
}

vec3 to_lab(vec3 c) {
	vec3 l = vec3(lin(c.r), lin(c.g), lin(c.b));
	float x = dot(l, vec3(0.4124, 0.3576, 0.1805)) / 0.95047;
	float y = dot(l, vec3(0.2126, 0.7152, 0.0722));
	float z = dot(l, vec3(0.0193, 0.1192, 0.9505)) / 1.08883;
	float fx = lab_f(x);
	float fy = lab_f(y);
	float fz = lab_f(z);
	return vec3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz));
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec4 src = texture(screen_tex, SCREEN_UV);
	vec4 best = quadrant(screen_tex, SCREEN_UV, px, -radius, -radius);
	vec4 q = quadrant(screen_tex, SCREEN_UV, px, 0, -radius);
	if (q.a < best.a) { best = q; }
	q = quadrant(screen_tex, SCREEN_UV, px, -radius, 0);
	if (q.a < best.a) { best = q; }
	q = quadrant(screen_tex, SCREEN_UV, px, 0, 0);
	if (q.a < best.a) { best = q; }
	vec3 c = best.rgb;
	vec3 lab = to_lab(c);
	vec3 outc = c;
	if (palette_size > 0) {
		float bd = 1.0e9;
		for (int i = 0; i < 32; i++) {
			if (i >= palette_size) { break; }
			vec3 d = lab - pal_lab[i];
			float dist = dot(d, d);
			if (dist < bd) {
				bd = dist;
				outc = pal_out[i];
			}
		}
	} else {
		float bands = float(max(levels, 2));
		outc = (floor(c * bands) + 0.5) / bands;
	}
	if (lab.x / 100.0 < ink_threshold) {
		outc = ink_color;
	}
	COLOR = vec4(outc, src.a);
}
