// Auto-rotoscope line tracing: XDoG (extended difference of Gaussians).
// Compares two blurs of the brightness; where the image gets darker across
// an edge — or along a dark stroke — it produces ink. Output: line strength
// in red (1 = ink, 0 = paper). Reads the previous pass from the back buffer.
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float sigma = 1.2;       // blur size: larger = bolder, simpler lines
uniform float k_ratio = 1.6;     // ratio between the two blurs
uniform float tau = 0.985;       // edge emphasis
uniform float epsilon = 0.01;    // threshold: higher = more lines
uniform float phi = 60.0;        // sharpness of the ink edge

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec4 src = texture(screen_tex, SCREEN_UV);
	float s1 = max(sigma, 0.3);
	float s2 = s1 * k_ratio;
	int r = int(min(ceil(s2 * 2.5), 12.0));
	float g1 = 0.0;
	float g2 = 0.0;
	float w1 = 0.0;
	float w2 = 0.0;
	for (int j = -r; j <= r; j++) {
		for (int i = -r; i <= r; i++) {
			vec2 o = vec2(float(i), float(j));
			float d2 = dot(o, o);
			vec4 s = texture(screen_tex, SCREEN_UV + o * px);
			float l = s.a < 0.5 ? luma(src.rgb) : luma(s.rgb);
			float a = exp(-d2 / (2.0 * s1 * s1));
			float b = exp(-d2 / (2.0 * s2 * s2));
			g1 += l * a;
			w1 += a;
			g2 += l * b;
			w2 += b;
		}
	}
	g1 /= w1;
	g2 /= w2;
	float d = g1 - tau * g2;
	float e = d >= epsilon ? 1.0 : 1.0 + tanh(phi * (d - epsilon));
	float line = clamp(1.0 - e, 0.0, 1.0) * step(0.5, src.a);
	COLOR = vec4(vec3(line), 1.0);
}
