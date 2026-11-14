// Auto-rotoscope line tracing: thicken lines (max of the ink mask in a disc).
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float thickness = 2.0;   // line radius in pixels
uniform float cut = 0.5;         // mask value that counts as ink

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	float m = 0.0;
	int r = int(ceil(thickness));
	float r2 = thickness * thickness + 0.25;
	for (int j = -r; j <= r; j++) {
		for (int i = -r; i <= r; i++) {
			if (float(i * i + j * j) > r2) {
				continue;
			}
			float v = texture(screen_tex, SCREEN_UV + vec2(float(i), float(j)) * px).r;
			m = max(m, step(cut, v));
		}
	}
	COLOR = vec4(vec3(m), 1.0);
}
