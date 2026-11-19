// Video import "Elements": matte cleanup. Blurs the keep-mask and cuts it
// again: fills small holes, removes specks, smooths the cut edge. `grow`
// moves the edge outward (+) or inward (-).
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D src_tex : filter_linear;  // the key pass (its own viewport)
uniform float radius = 2.0;     // cleanup strength in pixels (0 = off)
uniform float grow = 0.0;       // -1 .. 1
uniform float edge_soft = 0.08; // anti-alias width of the final edge

void fragment() {
	vec2 px = 1.0 / vec2(textureSize(src_tex, 0));
	vec4 c = texture(src_tex, UV);
	float a = c.a;
	if (radius > 0.3) {
		int r = int(min(ceil(radius * 2.0), 12.0));
		float sum = 0.0;
		float wsum = 0.0;
		for (int j = -r; j <= r; j++) {
			for (int i = -r; i <= r; i++) {
				vec2 o = vec2(float(i), float(j));
				float w = exp(-dot(o, o) / (2.0 * radius * radius));
				sum += texture(src_tex, UV + o * px).a * w;
				wsum += w;
			}
		}
		float cut = clamp(0.5 - grow * 0.35, 0.05, 0.95);
		a = smoothstep(cut - edge_soft, cut + edge_soft, sum / wsum);
	}
	COLOR = vec4(c.rgb, a);
}
