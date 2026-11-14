// Builds a clean background plate: the per-pixel median of 9 frames spread
// across the clip (the caller repeats frames if fewer exist). Anything that
// moves appears in only a few of them, so it drops out and the still
// background remains. Uses the classic 19-step median-of-9 sorting network.
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D f0 : filter_linear;
uniform sampler2D f1 : filter_linear;
uniform sampler2D f2 : filter_linear;
uniform sampler2D f3 : filter_linear;
uniform sampler2D f4 : filter_linear;
uniform sampler2D f5 : filter_linear;
uniform sampler2D f6 : filter_linear;
uniform sampler2D f7 : filter_linear;
uniform sampler2D f8 : filter_linear;

void op(inout vec3 a, inout vec3 b) {
	vec3 t = min(a, b);
	b = max(a, b);
	a = t;
}

void fragment() {
	vec3 p0 = texture(f0, UV).rgb;
	vec3 p1 = texture(f1, UV).rgb;
	vec3 p2 = texture(f2, UV).rgb;
	vec3 p3 = texture(f3, UV).rgb;
	vec3 p4 = texture(f4, UV).rgb;
	vec3 p5 = texture(f5, UV).rgb;
	vec3 p6 = texture(f6, UV).rgb;
	vec3 p7 = texture(f7, UV).rgb;
	vec3 p8 = texture(f8, UV).rgb;
	// Per-channel median (min/max work component-wise).
	op(p1, p2); op(p4, p5); op(p7, p8);
	op(p0, p1); op(p3, p4); op(p6, p7);
	op(p1, p2); op(p4, p5); op(p7, p8);
	op(p0, p3); op(p5, p8); op(p4, p7);
	op(p3, p6); op(p1, p4); op(p2, p5);
	op(p4, p7); op(p4, p2); op(p6, p4);
	op(p4, p2);
	COLOR = vec4(p4, 1.0);
}
