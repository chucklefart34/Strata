shader_type canvas_item;
render_mode blend_disabled;
// Temporal steadiness for rotoscoped video, motion-aware:
//   * still areas: where the source hasn't really changed since it was last
//     refreshed, keep last frame's result → flat colours and lines stop
//     flickering;
//   * moving areas: the held result is first moved along with the motion
//     (so a pan doesn't count as change), and anything that really changed
//     is redrawn fresh from this frame → lines stay on the moving subject
//     instead of lagging or sticking.
// `fresh` is this frame's value, `held` last frame's (the rotoscoped output,
// or the reference source, depending on the pass).

uniform sampler2D cur_src : filter_linear;
uniform sampler2D ref_src : filter_linear;
uniform sampler2D fresh : filter_nearest;
uniform sampler2D held : filter_nearest;
uniform sampler2D motion_tex : filter_linear;   // from video_motion.gdshader
uniform bool has_motion = false;
uniform float max_motion = 48.0;
uniform float ps = 1.0;
uniform float threshold = 0.05;
uniform float radius = 2.0;
uniform vec2 texel = vec2(0.0005, 0.0009);
uniform bool first_frame = true;

float change_at(vec2 uv, vec2 duv) {
	vec4 a = texture(cur_src, uv);
	vec4 b = texture(ref_src, uv - duv);
	return length(vec4(a.rgb * a.a, a.a) - vec4(b.rgb * b.a, b.a));
}

void fragment() {
	if (first_frame) {
		COLOR = texture(fresh, UV);
	} else {
		vec2 d = vec2(0.0);
		if (has_motion) {
			d = (texture(motion_tex, UV).rg - 0.5) * 2.0 * max_motion * ps;   // pixels at this size
		}
		float moving = length(d);
		vec2 duv = moving < 0.6 ? vec2(0.0) : d * texel;
		vec2 px = texel * radius;
		// Look a little around the pixel so moving edges count as change.
		float m = change_at(UV, duv);
		m = max(m, change_at(UV + vec2(px.x, 0.0), duv));
		m = max(m, change_at(UV - vec2(px.x, 0.0), duv));
		m = max(m, change_at(UV + vec2(0.0, px.y), duv));
		m = max(m, change_at(UV - vec2(0.0, px.y), duv));
		m = max(m, change_at(UV + px, duv));
		m = max(m, change_at(UV - px, duv));
		m = max(m, change_at(UV + vec2(px.x, -px.y), duv));
		m = max(m, change_at(UV + vec2(-px.x, px.y), duv));
		// Moving areas refresh more readily, so lines keep up with the motion.
		float thr = moving < 0.6 ? threshold : threshold * 0.55;
		COLOR = m < thr ? texture(held, UV - duv) : texture(fresh, UV);
	}
}
