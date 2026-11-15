shader_type canvas_item;
render_mode blend_disabled;
// One pass of the episode effects chain (see episode/fx_processor.gd and
// episode/video_fx.gd). `fx` picks the effect; numbers follow VideoFx.EFFECTS.
// Everything random is driven by `frame` and `seed`, so exports are repeatable.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D prev_out : filter_linear, repeat_disable;   // last frame's final picture
uniform sampler2D prev_src : filter_linear, repeat_disable;   // last frame's picture before effects
uniform int fx = 0;
uniform float amount = 1.0;
uniform float param = 0.5;
uniform vec4 tint : source_color = vec4(1.0);
uniform float t = 0.0;         // seconds into the episode
uniform float frame = 0.0;
uniform vec2 res = vec2(1920.0, 1080.0);
uniform bool has_prev = false;
uniform float seed = 0.0;

float h1(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233)) + seed * 0.1371) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h1(i), h1(i + vec2(1.0, 0.0)), f.x), mix(h1(i + vec2(0.0, 1.0)), h1(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec3 src(vec2 uv) {
	return texture(screen_tex, clamp(uv, vec2(0.0005), vec2(0.9995))).rgb;
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = 1.0 / res;
	float ps = res.y / 1080.0;   // keeps pixel-sized looks the same at any resolution
	vec3 base = src(uv);
	vec3 c = base;

	if (fx == 0) {
		// VHS tape: wobbly lines, a rolling tracking band, smeared colour, noise.
		float line = floor(uv.y * res.y / max(1.0, ps * 2.0));
		float wob = (vnoise(vec2(line * 0.05, frame * 0.3)) - 0.5) * 0.006 * amount * (0.5 + param);
		float track = fract(t * 0.13 + seed * 0.01);
		float band = smoothstep(0.05, 0.0, abs(uv.y - track));
		wob += band * (h1(vec2(line, frame)) - 0.5) * 0.05 * amount;
		vec2 u = uv + vec2(wob, 0.0);
		float sh = 3.0 * ps * px.x * amount * (1.0 + param * 3.0);
		vec3 k = vec3(src(u + vec2(sh, 0.0)).r, src(u).g, src(u - vec2(sh, 0.0)).b);
		vec3 bl = (src(u + vec2(sh * 2.5, 0.0)) + src(u - vec2(sh * 2.5, 0.0)) + k) / 3.0;
		vec3 vhs = vec3(luma(k)) + (bl - vec3(luma(bl))) * 0.85;
		vhs *= 0.93 + 0.07 * sin(uv.y * res.y * 1.4 / ps);
		vhs += (h1(uv * res + frame) - 0.5) * 0.12 * (0.4 + param);
		vhs += band * 0.22 * h1(vec2(floor(uv.x * 90.0), frame));
		vhs = mix(vhs, vhs * vec3(1.04, 0.97, 1.08), 0.6);
		c = mix(base, vhs, amount);
	} else if (fx == 1) {
		// Old film: jitter, sepia, grain, scratches, dust, flickering vignette.
		vec2 j = vec2(0.0, (h1(vec2(frame, 1.0)) - 0.5) * 0.004);
		vec3 k = src(uv + j);
		float y = luma(k);
		vec3 film = mix(k, vec3(y) * vec3(1.07, 0.95, 0.78), 0.4 + param * 0.6);
		film += (h1(uv * res / max(1.0, ps * 1.5) + frame * 1.7) - 0.5) * 0.18;
		float sx = h1(vec2(frame * 0.37, 3.1));
		float scratch = step(0.55, h1(vec2(frame, 7.0))) * smoothstep(0.0016, 0.0, abs(uv.x - sx));
		film = mix(film, vec3(0.92), scratch * 0.6);
		float dust = step(0.9988, h1(floor(uv * res / (3.0 * ps)) + frame));
		film = mix(film, vec3(0.05), dust);
		vec2 vc = (uv - 0.5) * 1.3;
		film *= (1.0 - dot(vc, vc) * 0.6) * (0.92 + 0.08 * h1(vec2(frame, 2.0)));
		c = mix(base, film, amount);
	} else if (fx == 2) {
		// CRT TV: curved glass, scanlines, RGB mask, dark corners.
		vec2 cc = uv - 0.5;
		float r2 = dot(cc, cc);
		vec2 bu = 0.5 + cc * (1.0 + r2 * (0.15 + param * 0.45) * amount);
		vec3 k = src(bu);
		if (bu.x < 0.0 || bu.x > 1.0 || bu.y < 0.0 || bu.y > 1.0) { k = vec3(0.0); }
		k *= 0.75 + 0.25 * sin(bu.y * res.y * 3.14159 / max(1.0, ps * 1.5));
		float m = mod(floor(uv.x * res.x / max(1.0, ps)), 3.0);
		vec3 mask = m < 1.0 ? vec3(1.0, 0.75, 0.75) : (m < 2.0 ? vec3(0.75, 1.0, 0.75) : vec3(0.75, 0.75, 1.0));
		k *= mask * 1.25;
		k *= 1.0 - r2 * 1.2;
		c = mix(base, k, amount);
	} else if (fx == 3) {
		// Film grain.
		float s = mix(1.0, 3.5, param) * ps;
		float g = h1(floor(uv * res / s) + frame * 13.1) - 0.5;
		c = base + g * 0.35 * amount * (0.6 + 0.4 * (1.0 - luma(base)));
	} else if (fx == 4) {
		// Glitch: torn slices, colour split, corrupted blocks.
		float step_f = floor(frame / max(1.0, mix(6.0, 1.0, param)));
		float rows = mix(10.0, 46.0, h1(vec2(step_f, 5.0)));
		float row = floor(uv.y * rows);
		float on = step(1.0 - amount * 0.55, h1(vec2(row, step_f)));
		float off = (h1(vec2(row * 1.7, step_f + 1.0)) - 0.5) * 0.18 * amount * on;
		vec2 u = uv + vec2(off, 0.0);
		float sh = (0.012 * on + 0.003) * amount;
		vec3 k = vec3(src(u + vec2(sh, 0.0)).r, src(u).g, src(u - vec2(sh, 0.0)).b);
		vec2 blk = floor(uv * vec2(24.0, 14.0));
		float bc = step(1.0 - amount * 0.14, h1(blk + step_f * 3.1));
		k = mix(k, src(uv + vec2(h1(blk) - 0.5, 0.0) * 0.25).bgr, bc);
		float inv = step(1.0 - amount * 0.04, h1(vec2(row, step_f + 9.0)));
		k = mix(k, 1.0 - k, inv);
		c = k;
	} else if (fx == 5) {
		// Datamosh: last frame's picture is pushed around by this frame's
		// motion instead of being replaced, so old images melt into new ones.
		if (!has_prev) {
			c = base;
		} else {
			float B = 16.0 * ps;
			vec2 cell = floor(uv * res / B);
			vec2 bp = (cell + 0.5) * B / res;
			vec2 dx = vec2(B * px.x * 0.5, 0.0);
			vec2 dy = vec2(0.0, B * px.y * 0.5);
			float ic = luma(texture(screen_tex, bp).rgb);
			float ix = luma(texture(screen_tex, bp + dx).rgb) - luma(texture(screen_tex, bp - dx).rgb);
			float iy = luma(texture(screen_tex, bp + dy).rgb) - luma(texture(screen_tex, bp - dy).rgb);
			float it = ic - luma(texture(prev_src, bp).rgb);
			vec2 g = vec2(ix, iy);
			vec2 v = -it * g / (dot(g, g) + 0.002);
			v = clamp(v, vec2(-2.5), vec2(2.5)) * vec2(dx.x, dy.y) * (1.0 + param * 4.0);
			vec3 old = texture(prev_out, clamp(uv - v, vec2(0.0), vec2(1.0))).rgb;
			float iframe = step(0.988 + 0.012 * amount, h1(cell + floor(frame) * 0.71));
			float refresh = (1.0 - amount) * 0.3;
			c = mix(old, base, clamp(refresh + iframe, 0.0, 1.0));
		}
	} else if (fx == 6) {
		// Gross / crunchy: a badly compressed video — blocky colour, banding,
		// noisy edges.
		float B = mix(4.0, 18.0, param) * ps;
		vec2 lb = (floor(uv * res / B) + 0.5) * B / res;
		vec2 cb = (floor(uv * res / (B * 2.0)) + 0.5) * (B * 2.0) / res;
		vec3 lc = src(lb);
		vec3 cc = src(cb);
		float y = luma(mix(base, lc, 0.7));
		vec3 k = vec3(y) + (cc - vec3(luma(cc))) * 1.25;
		float lv = mix(28.0, 5.0, amount);
		k = floor(k * lv + h1(lb + floor(frame / 3.0)) * 0.6) / lv;
		float e = abs(luma(src(uv + vec2(px.x * 2.0 * ps, 0.0))) - luma(base)) + abs(luma(src(uv + vec2(0.0, px.y * 2.0 * ps))) - luma(base));
		k += (h1(uv * res + frame) - 0.5) * e * 2.0;
		k = mix(k, k * vec3(1.0, 1.04, 0.92), 0.5);
		c = mix(base, k, amount);
	} else if (fx == 7) {
		// Deep fried: oversharpened, oversaturated, crunchy and orange.
		vec2 o = px * ps * 1.5;
		vec3 bl = (src(uv + vec2(o.x, 0.0)) + src(uv - vec2(o.x, 0.0)) + src(uv + vec2(0.0, o.y)) + src(uv - vec2(0.0, o.y))) * 0.25;
		vec3 k = base + (base - bl) * 3.5 * amount;
		k = mix(vec3(luma(k)), k, 1.0 + 2.5 * amount);
		k = (k - 0.5) * (1.0 + 0.9 * amount) + 0.5;
		k *= mix(vec3(1.0), vec3(1.2, 1.0, 0.75), amount);
		float lv = mix(64.0, 9.0, amount);
		k = floor(clamp(k, 0.0, 1.0) * lv) / lv;
		k += (h1(uv * res * 0.5 + frame) - 0.5) * 0.1 * amount;
		c = k;
	} else if (fx == 8) {
		// RGB split.
		float a = param * 6.28318;
		vec2 d = vec2(cos(a), sin(a)) * 0.014 * amount;
		c = vec3(src(uv + d).r, base.g, src(uv - d).b);
	} else if (fx == 9) {
		// Echo trails: blend in the last frame so movement leaves ghosts.
		vec3 old = has_prev ? texture(prev_out, uv).rgb : base;
		c = mix(base, old, amount * 0.88);
	} else if (fx == 10) {
		// Camera shake.
		float sp = mix(0.15, 1.2, param);
		vec2 off = (vec2(vnoise(vec2(frame * sp, 1.0)), vnoise(vec2(frame * sp, 9.0))) - 0.5) * 0.06 * amount;
		float rot = (vnoise(vec2(frame * sp, 17.0)) - 0.5) * 0.05 * amount;
		vec2 cc = (uv - 0.5) / (1.0 + 0.07 * amount);
		cc = vec2(cc.x * cos(rot) - cc.y * sin(rot), cc.x * sin(rot) + cc.y * cos(rot));
		c = src(0.5 + cc + off);
	} else if (fx == 11) {
		// Zoom punch (use fades for the snap in and out).
		c = src(0.5 + (uv - 0.5) / (1.0 + amount * (0.1 + param * 0.6)));
	} else if (fx == 12) {
		// Wavy.
		float f = mix(5.0, 40.0, param);
		vec2 u = uv + vec2(sin(uv.y * f + t * 6.0) * 0.02, cos(uv.x * f * 0.7 + t * 5.0) * 0.01) * amount;
		c = src(u);
	} else if (fx == 13) {
		// Pixelate.
		float B = mix(2.0, 64.0, amount) * ps;
		c = src((floor(uv * res / B) + 0.5) * B / res);
	} else if (fx == 14) {
		// Blur.
		float r = amount * 14.0 * ps;
		vec3 acc = base;
		float n = 1.0;
		for (int i = 0; i < 12; i++) {
			float a = float(i) * 0.5236;
			vec2 d = vec2(cos(a), sin(a)) * px * r;
			acc += src(uv + d) + src(uv + d * 0.5);
			n += 2.0;
		}
		c = acc / n;
	} else if (fx == 15) {
		// Mirror: left/right, top/bottom or four-way.
		vec2 u = uv;
		if (param < 0.34) {
			u.x = u.x > 0.5 ? 1.0 - u.x : u.x;
		} else if (param < 0.67) {
			u.y = u.y > 0.5 ? 1.0 - u.y : u.y;
		} else {
			u = 0.5 - abs(u - 0.5);
		}
		c = mix(base, src(u), amount);
	} else if (fx == 16) {
		// Fisheye.
		vec2 cc = uv - 0.5;
		float r = length(cc);
		vec2 u = 0.5 + cc * mix(1.0, pow(r * 2.0, 0.6) / max(r * 2.0, 0.0001), amount);
		c = src(u);
	} else if (fx == 17) {
		// Black & white.
		float y = luma(base);
		y = (y - 0.5) * (1.0 + param * 1.5) + 0.5;
		c = mix(base, vec3(clamp(y, 0.0, 1.0)), amount);
	} else if (fx == 18) {
		// Sepia.
		float y = luma(base);
		c = mix(base, vec3(y) * vec3(1.1, 0.95, 0.72), amount);
	} else if (fx == 19) {
		c = mix(base, 1.0 - base, amount);
	} else if (fx == 20) {
		float lv = mix(16.0, 2.0, amount);
		c = floor(base * lv + 0.5) / lv;
	} else if (fx == 21) {
		// Colour tint (Mono tint = how much it becomes one colour).
		vec3 mono = vec3(luma(base)) * tint.rgb * 1.6;
		c = mix(base, mix(base * tint.rgb * 1.3, mono, param), amount);
	} else if (fx == 22) {
		// Punchy colours.
		vec3 k = mix(vec3(luma(base)), base, 1.0 + amount);
		k = (k - 0.5) * (1.0 + amount * param * 0.8) + 0.5;
		c = k;
	} else if (fx == 23) {
		// Vignette.
		vec2 cc = (uv - 0.5) * vec2(res.x / res.y, 1.0);
		float r = mix(0.95, 0.35, param);
		float v = smoothstep(r, r * 0.35, length(cc));
		c = mix(tint.rgb, base, mix(1.0, v, amount));
	} else if (fx == 24) {
		// Flash.
		c = mix(base, tint.rgb, amount);
	} else if (fx == 25) {
		// Cinema bars.
		float bar = amount * 0.13;
		if (uv.y < bar || uv.y > 1.0 - bar) { c = vec3(0.0); }
	}
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
