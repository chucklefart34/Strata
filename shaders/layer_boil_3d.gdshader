shader_type spatial;
// Per-layer effects for a drawing plane in 3D / renders (see layer_boil.gdshader).
render_mode unshaded, cull_disabled, depth_draw_opaque, specular_disabled;

uniform sampler2D tex : source_color, filter_linear;
uniform float opacity = 1.0;
uniform float amount = 0.0;      // line boil wobble in texture pixels (0 = off)
uniform float step_k = 0.0;      // which wobble (changes every few frames)
uniform vec2 tex_size = vec2(1920.0, 1080.0);
uniform float border = 0.0;      // border effect width in pixels (0 = off)
uniform vec4 border_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform bool border_inner = true; // also draw lines where two colours meet

float h1(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h1(i), h1(i + vec2(1.0, 0.0)), f.x), mix(h1(i + vec2(0.0, 1.0)), h1(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec2 boil(vec2 uv) {
	if (amount <= 0.0) {
		return uv;
	}
	vec2 q = uv * vec2(tex_size.x / tex_size.y, 1.0) * 9.0;
	vec2 w = vec2(vnoise(q + vec2(step_k * 7.31, 0.0)), vnoise(q + vec2(3.7, step_k * 5.17))) - 0.5;
	w += (vec2(vnoise(q * 2.3 + step_k * 1.9), vnoise(q * 2.3 + 11.0 + step_k * 2.3)) - 0.5) * 0.5;
	return uv + w * 2.0 * amount / tex_size;
}

void fragment() {
	vec2 uv = boil(UV);
	vec4 c = texture(tex, uv);
	if (border > 0.0) {
		// Border effect: an outline around every shape (outside its edge),
		// and optionally a line where two colours meet inside the layer.
		vec2 px = 1.0 / tex_size;
		bool solid = c.a > 0.5;
		float reach = solid ? (border_inner ? border * 0.5 : 0.0) : border;
		int r = int(ceil(reach));
		float best = 1e6;
		float edge = 1e6;
		for (int j = -r; j <= r; j++) {
			for (int i = -r; i <= r; i++) {
				float d = length(vec2(float(i), float(j)));
				if (d > reach + 0.5) {
					continue;
				}
				vec4 o = texture(tex, uv + vec2(float(i), float(j)) * px);
				if (o.a > 0.5) {
					best = min(best, d);
					if (solid) {
						vec3 df = abs(o.rgb - c.rgb);
						if (max(max(df.r, df.g), df.b) > 0.12) {
							edge = min(edge, d);
						}
					}
				}
			}
		}
		float outer = solid ? 0.0 : clamp(border + 0.5 - best, 0.0, 1.0);
		float inner = solid ? clamp(border * 0.5 + 0.5 - edge, 0.0, 1.0) : 0.0;
		float ua = border_color.a * outer;
		float a = c.a + ua * (1.0 - c.a);
		vec3 rgb = a > 0.0001 ? (c.rgb * c.a + border_color.rgb * ua * (1.0 - c.a)) / a : vec3(0.0);
		c = vec4(mix(rgb, border_color.rgb, inner * border_color.a), a);
	}
	ALBEDO = c.rgb;
	ALPHA = c.a * opacity;
}
