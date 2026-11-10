shader_type canvas_item;

// ki_spectral_vision.gdshader — Ethereal Ki Spectral Vision Post-Processing (Phase 9.6, ADR 098)
// Converts world geometry to high-contrast desaturated ethereal monochrome
// with edge luminescence and chromatic scanline resonance.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform bool vision_active = true;
uniform float desaturation : hint_range(0.0, 1.0) = 0.85;
uniform vec4 spectral_tint : source_color = vec4(0.10, 0.15, 0.22, 1.0);
uniform float edge_threshold : hint_range(0.01, 0.5) = 0.06;
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.5;
uniform float scanline_intensity : hint_range(0.0, 0.5) = 0.04;
uniform float pulse_speed = 2.0;
uniform float pulse_time = 0.0;

const vec3 LUM_REC709 = vec3(0.2126, 0.7152, 0.0722);

void fragment() {
	vec4 original = texture(screen_texture, SCREEN_UV);
	if (!vision_active) {
		COLOR = original;
	} else {
		// 1. Desaturación monocroma de alta definición (Rec. 709)
		float luminance = dot(original.rgb, LUM_REC709);
		vec3 desat = mix(original.rgb, vec3(luminance), desaturation);

		// 2. Tinte etéreo de Ki cósmico
		vec3 tinted = desat * spectral_tint.rgb * 2.4;

		// 3. Detección y realce de bordes de silueta
		vec2 pixel_size = SCREEN_PIXEL_SIZE;
		float lum_up = dot(texture(screen_texture, SCREEN_UV + vec2(0.0, pixel_size.y)).rgb, LUM_REC709);
		float lum_down = dot(texture(screen_texture, SCREEN_UV - vec2(0.0, pixel_size.y)).rgb, LUM_REC709);
		float lum_left = dot(texture(screen_texture, SCREEN_UV - vec2(pixel_size.x, 0.0)).rgb, LUM_REC709);
		float lum_right = dot(texture(screen_texture, SCREEN_UV + vec2(pixel_size.x, 0.0)).rgb, LUM_REC709);
		float edge = abs(lum_up - lum_down) + abs(lum_left - lum_right);

		if (edge > edge_threshold) {
			float pulse = 0.8 + 0.2 * sin(pulse_time * pulse_speed);
			tinted += vec3(0.2, 0.45, 0.6) * edge * 2.5 * pulse;
		}

		// 4. Scanlines etéreas sutiles
		float scanline = sin(SCREEN_UV.y * 700.0) * scanline_intensity;
		tinted -= scanline;

		// 5. Viñeta óptica circular
		vec2 uv = SCREEN_UV * (1.0 - SCREEN_UV.yx);
		float vig = uv.x * uv.y * 15.0;
		vig = clamp(pow(vig, vignette_strength), 0.0, 1.0);
		tinted *= vig;

		COLOR = vec4(tinted, original.a);
	}
}
