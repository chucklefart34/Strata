// Auto-rotoscope: edge-preserving blur (bilateral filter).
// Averages neighbours that have a similar colour and ignores those across an
// edge, so paper texture, grain and noise wash out while shapes stay sharp.
// Reads the previous pass from the back buffer.
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float radius = 6.0;        // blur radius in pixels
uniform float sigma_color = 0.12;  // how different a colour may be and still blend
uniform float step_px = 1.5;       // sample spacing (keeps big radii fast)

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec4 center = texture(screen_tex, SCREEN_UV);
	if (radius < 0.5) {
		COLOR = center;
	} else {
		int r = int(ceil(radius / step_px));
		float sigma_s = max(radius * 0.5, 0.5);
		vec3 sum = vec3(0.0);
		float wsum = 0.0;
		for (int j = -r; j <= r; j++) {
			for (int i = -r; i <= r; i++) {
				vec2 o = vec2(float(i), float(j)) * step_px;
				vec4 s = texture(screen_tex, SCREEN_UV + o * px);
				if (s.a < 0.5) {
					continue;
				}
				vec3 d = s.rgb - center.rgb;
				float w = exp(-dot(o, o) / (2.0 * sigma_s * sigma_s)) * exp(-dot(d, d) / (2.0 * sigma_color * sigma_color));
				sum += s.rgb * w;
				wsum += w;
			}
		}
		COLOR = vec4(wsum > 0.0 ? sum / wsum : center.rgb, center.a);
	}
}
