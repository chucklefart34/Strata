shader_type canvas_item;
render_mode blend_disabled;
// Temporal hold for rotoscoped video: where the source hasn't really changed
// since the reference frame, keep last frame's result instead of the new
// one, so flat colours and lines stop flickering.
// `fresh` is this frame's value, `held` last frame's value (either the
// rotoscoped output, or the reference source, depending on the pass).

uniform sampler2D cur_src : filter_linear;
uniform sampler2D ref_src : filter_linear;
uniform sampler2D fresh : filter_nearest;
uniform sampler2D held : filter_nearest;
uniform float threshold = 0.05;
uniform float radius = 2.0;
uniform vec2 texel = vec2(0.0005, 0.0009);
uniform bool first_frame = true;

float change_at(vec2 uv) {
	vec4 a = texture(cur_src, uv);
	vec4 b = texture(ref_src, uv);
	return length(vec4(a.rgb * a.a, a.a) - vec4(b.rgb * b.a, b.a));
}

void fragment() {
	if (first_frame) {
		COLOR = texture(fresh, UV);
	} else {
		vec2 px = texel * radius;
		// Look a little around the pixel so moving edges count as change.
		float m = change_at(UV);
		m = max(m, change_at(UV + vec2(px.x, 0.0)));
		m = max(m, change_at(UV - vec2(px.x, 0.0)));
		m = max(m, change_at(UV + vec2(0.0, px.y)));
		m = max(m, change_at(UV - vec2(0.0, px.y)));
		m = max(m, change_at(UV + px));
		m = max(m, change_at(UV - px));
		m = max(m, change_at(UV + vec2(px.x, -px.y)));
		m = max(m, change_at(UV + vec2(-px.x, px.y)));
		COLOR = m < threshold ? texture(held, UV) : texture(fresh, UV);
	}
}
