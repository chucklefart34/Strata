// Onion skin: draws a drawing's silhouette in a flat tint color, keeping its
// alpha. The tint (and its strength) comes from the draw call's modulate color.
shader_type canvas_item;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	float a = texture(TEXTURE, UV).a;
	COLOR = vec4(tint.rgb, a * tint.a);
}
