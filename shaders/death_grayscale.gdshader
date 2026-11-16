// Pantalla de muerte (MMO-Muerte.html): backdrop-filter grayscale(1) brightness(0.55)
// + velo rgba(8,10,14,0.35). Lee el mundo ya dibujado detrás del ColorRect.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float grayscale : hint_range(0.0, 1.0) = 1.0;
uniform float brightness : hint_range(0.0, 2.0) = 0.55;
uniform vec4 tint : source_color = vec4(0.031, 0.039, 0.055, 0.35);

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float g = dot(c, vec3(0.2126, 0.7152, 0.0722));
	vec3 o = mix(c, vec3(g), grayscale) * brightness;
	o = mix(o, tint.rgb, tint.a);
	COLOR = vec4(o, 1.0);
}
