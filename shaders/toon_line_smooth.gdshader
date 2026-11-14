// Auto-rotoscope line tracing: smooth + clean lines.
// Blurs the thickened ink mask and cuts it at 50% with a soft edge. Long
// strokes survive as smooth, anti-aliased curves; tiny specks and jaggies
// fall below the cut and disappear.
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float smooth_sigma = 1.5;  // blur in pixels (0 = no smoothing)
uniform float softness = 0.08;     // anti-alias width of the cut

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	float center = texture(screen_tex, SCREEN_UV).r;
	float v = center;
	if (smooth_sigma > 0.2) {
		int r = int(min(ceil(smooth_sigma * 2.5), 10.0));
		float sum = 0.0;
		float wsum = 0.0;
		for (int j = -r; j <= r; j++) {
			for (int i = -r; i <= r; i++) {
				vec2 o = vec2(float(i), float(j));
				float w = exp(-dot(o, o) / (2.0 * smooth_sigma * smooth_sigma));
				sum += texture(screen_tex, SCREEN_UV + o * px).r * w;
				wsum += w;
			}
		}
		v = sum / wsum;
	}
	float m = smoothstep(0.5 - softness, 0.5 + softness, v);
	COLOR = vec4(vec3(m), 1.0);
}
