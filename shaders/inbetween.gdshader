shader_type canvas_item;
render_mode blend_disabled;
// Draws one in-between frame from two keyframe drawings and the motion
// between them (drawing_flow.gdshader).
//   0 motion — each line slides along its motion and the two drawings blend
//   1 smear  — the drawing streaks along its motion (a "smear" frame)
//   2 wipe   — the new drawing sweeps in along the motion, smeared at the edge
//   3 fade   — a plain cross-fade, no movement

uniform sampler2D tex_a : filter_linear, repeat_disable;
uniform sampler2D tex_b : filter_linear, repeat_disable;
uniform sampler2D flow_tex : filter_linear, repeat_disable;
uniform float flow_max = 80.0;    // flow encoding range (flow pixels)
uniform float flow_scale = 4.0;   // flow pixels → picture pixels
uniform vec2 res = vec2(1920.0, 1080.0);
uniform float t = 0.5;
uniform int mode = 0;
uniform float smear = 0.4;        // smear length, as a fraction of the move
uniform vec2 wipe_dir = vec2(1.0, 0.0);
uniform vec2 wipe_range = vec2(-0.7, 0.7);

vec2 flow(vec2 uv) {
	return (texture(flow_tex, uv).rg - 0.5) * 2.0 * flow_max * flow_scale / res;
}

vec4 mix_pm(vec4 a, vec4 b, float w) {
	float wa = a.a * (1.0 - w);
	float wb = b.a * w;
	float al = mix(a.a, b.a, w);
	vec3 c = (wa + wb) > 0.0001 ? (a.rgb * wa + b.rgb * wb) / (wa + wb) : vec3(0.0);
	return vec4(c, al);
}

vec4 at(vec2 uv, float tt) {
	vec2 d = flow(uv);
	vec4 a = texture(tex_a, uv - tt * d);
	vec4 b = texture(tex_b, uv + (1.0 - tt) * d);
	return mix_pm(a, b, tt);
}

vec4 smeared(vec2 uv, float tt) {
	vec4 best = vec4(0.0);
	float best_a = 0.0;
	for (int k = 0; k < 12; k++) {
		float f = float(k) / 11.0 - 0.5;
		vec4 s = at(uv, clamp(tt + f * smear, 0.0, 1.0));
		float w = 1.0 - abs(f) * 1.1;
		if (s.a * w > best_a) {
			best_a = s.a * w;
			best = vec4(s.rgb, s.a * w);
		}
	}
	return best;
}

vec4 over(vec4 top, vec4 under) {
	float a = top.a + under.a * (1.0 - top.a);
	vec3 c = a > 0.0001 ? (top.rgb * top.a + under.rgb * under.a * (1.0 - top.a)) / a : vec3(0.0);
	return vec4(c, a);
}

void fragment() {
	vec4 c;
	if (mode == 3) {
		c = mix_pm(texture(tex_a, UV), texture(tex_b, UV), t);
	} else if (mode == 1) {
		c = smeared(UV, t);
	} else if (mode == 2) {
		vec2 d = flow(UV);
		vec4 aw = texture(tex_a, UV - t * d);
		vec4 bw = texture(tex_b, UV + (1.0 - t) * d);
		float n = (dot(UV - 0.5, wipe_dir) - wipe_range.x) / max(0.001, wipe_range.y - wipe_range.x);
		float soft = 0.12;
		float edge = mix(1.0 + soft, -soft, t);
		float mb = smoothstep(edge - soft, edge + soft, n);
		c = mix_pm(aw, bw, mb);
		float zone = 1.0 - abs(mb * 2.0 - 1.0);
		if (zone > 0.01) {
			vec4 s = smeared(UV, t);
			c = over(vec4(s.rgb, s.a * zone), c);
		}
	} else {
		c = at(UV, t);
		c.a = smoothstep(0.06, 0.8, c.a);
	}
	COLOR = c;
}
