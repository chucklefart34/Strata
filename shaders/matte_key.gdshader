// Video import "Elements": decides which parts of a frame to keep (alpha).
// Modes: 0 keep everything, 1 remove still background (difference from a
// clean plate), 2 remove a colour (chroma key with spill removal),
// 3 remove light areas, 4 remove dark areas, 5 keep a tracked subject
// (low-res subject mask, refined at full resolution with a colour lookup).
// A keep-box crop applies on top.
shader_type canvas_item;
render_mode blend_disabled;

uniform int mode = 0;
uniform sampler2D plate : filter_linear;      // clean background (mode 1)
uniform float threshold = 0.12;               // how different / how far counts as "keep"
uniform float softness = 0.06;                // soft edge of the decision
uniform vec3 key_color = vec3(0.0, 1.0, 0.0); // colour to remove (mode 2)
uniform float spill = 0.6;                    // remove key-colour tint from kept edges
uniform bool invert = false;                  // keep the removed part instead
uniform vec4 box = vec4(0.0, 0.0, 1.0, 1.0);  // keep area in UV: left, top, right, bottom
uniform float box_feather = 0.0;              // soft edge of the keep area (UV)
uniform sampler2D subject_lut : filter_nearest;   // 64×64: colour bin → subject chance (mode 5)
uniform sampler2D subject_mask : filter_linear;   // low-res subject mask for this frame (mode 5)
uniform vec2 mask_texel = vec2(0.004, 0.007);
uniform float edge_detail = 0.7;                  // how much full-res colour shapes the edge

float subject_p(vec3 c) {
	ivec3 q = ivec3(clamp(c * 16.0, vec3(0.0), vec3(15.0)));
	int i = q.r * 256 + q.g * 16 + q.b;
	vec2 uv = (vec2(float(i % 64), float(i / 64)) + 0.5) / 64.0;
	return texture(subject_lut, uv).r;
}

float subject_support(vec2 uv) {
	float s = texture(subject_mask, uv).r * 0.4;
	s += texture(subject_mask, uv + vec2(mask_texel.x, 0.0)).r * 0.15;
	s += texture(subject_mask, uv - vec2(mask_texel.x, 0.0)).r * 0.15;
	s += texture(subject_mask, uv + vec2(0.0, mask_texel.y)).r * 0.15;
	s += texture(subject_mask, uv - vec2(0.0, mask_texel.y)).r * 0.15;
	return s;
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Godot can't pass the built-in TEXTURE and a uniform sampler to the same
// helper function, so the plate gets its own blur and the frame is blurred
// inline in fragment().
vec3 blur3_plate(vec2 uv, vec2 px) {
	vec3 s = vec3(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			s += texture(plate, uv + vec2(float(i), float(j)) * px).rgb;
		}
	}
	return s / 9.0;
}

vec2 chroma(vec3 c) {
	float y = luma(c);
	return vec2((c.b - y) * 0.565, (c.r - y) * 0.713);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec3 rgb = c.rgb;
	float m = 1.0;
	if (mode == 1) {
		vec2 px = TEXTURE_PIXEL_SIZE * 1.5;
		vec3 a = vec3(0.0);
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				a += texture(TEXTURE, UV + vec2(float(i), float(j)) * px).rgb;
			}
		}
		a /= 9.0;
		vec3 b = blur3_plate(UV, px);
		vec3 d = abs(a - b);
		float diff = max(max(d.r, d.g), d.b);
		m = smoothstep(threshold, threshold + softness, diff);
	} else if (mode == 2) {
		float dist = distance(chroma(rgb), chroma(key_color)) + abs(luma(rgb) - luma(key_color)) * 0.15;
		m = smoothstep(threshold, threshold + softness, dist);
		// Spill: pull the key hue out of kept pixels so edges aren't tinted.
		vec3 kdir = key_color - vec3(luma(key_color));
		float kl = length(kdir);
		if (kl > 0.001) {
			kdir /= kl;
			float amount = max(0.0, dot(rgb - vec3(luma(rgb)), kdir));
			rgb = clamp(rgb - kdir * amount * spill, 0.0, 1.0);
		}
	} else if (mode == 3) {
		m = 1.0 - smoothstep(threshold, threshold + softness, luma(rgb));
	} else if (mode == 4) {
		m = smoothstep(threshold - softness, threshold, luma(rgb));
	} else if (mode == 5) {
		float s = subject_support(UV);
		float core = smoothstep(0.3, 0.7, s);
		// Near the mask's edge, let the real pixel colours decide, so the cut
		// follows hair, fingers and outlines instead of the coarse mask.
		float pf = smoothstep(threshold - softness, threshold + softness, subject_p(rgb)) * step(0.04, s);
		float edge = clamp(1.0 - abs(s * 2.0 - 1.0), 0.0, 1.0) * edge_detail;
		m = mix(core, pf, edge);
	}
	if (invert && mode != 0) {
		m = 1.0 - m;
	}
	float f = max(box_feather, 0.0001);
	float inside = smoothstep(box.x - f, box.x + f, UV.x) * (1.0 - smoothstep(box.z - f, box.z + f, UV.x))
		* smoothstep(box.y - f, box.y + f, UV.y) * (1.0 - smoothstep(box.w - f, box.w + f, UV.y));
	COLOR = vec4(rgb, c.a * m * inside);
}
