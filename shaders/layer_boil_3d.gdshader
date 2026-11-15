shader_type spatial;
// Line boil for a drawing plane in 3D / renders (see layer_boil.gdshader).
render_mode unshaded, cull_disabled, depth_draw_opaque, specular_disabled;

uniform sampler2D tex : source_color, filter_linear;
uniform float opacity = 1.0;
uniform float amount = 0.0;
uniform float step_k = 0.0;
uniform vec2 tex_size = vec2(1920.0, 1080.0);

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
	vec2 q = uv * vec2(tex_size.x / tex_size.y, 1.0) * 9.0;
	vec2 w = vec2(vnoise(q + vec2(step_k * 7.31, 0.0)), vnoise(q + vec2(3.7, step_k * 5.17))) - 0.5;
	w += (vec2(vnoise(q * 2.3 + step_k * 1.9), vnoise(q * 2.3 + 11.0 + step_k * 2.3)) - 0.5) * 0.5;
	return uv + w * 2.0 * amount / tex_size;
}

void fragment() {
	vec4 c = texture(tex, boil(UV));
	ALBEDO = c.rgb;
	ALPHA = c.a * opacity;
}
