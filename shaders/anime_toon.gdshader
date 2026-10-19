// Cel shading for the Tripo models. Replaces their PBR material so colours read as flat anime
// paint instead of glossy, painterly gradients:
// - direct light falls into two hard-edged tones, lit and a tinted shade, with no specular;
// - the albedo is sharpened with an unsharp mask and given a little more saturation, which undoes
//   the blur of Tripo's baked textures;
// - a thin rim of light separates the silhouette from the background.
// Normal maps are not used: cel shading wants the smooth vertex normals, and skipping them also
// avoids the Compatibility renderer's broken skinned tangents.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);
// Colour multiplied into the albedo where the sun does not reach. A cool violet reads as anime shade.
uniform vec4 shade_color : source_color = vec4(0.62, 0.6, 0.78, 1.0);
// N.L where the lit tone begins, and how many units of N.L the edge between the tones spans.
uniform float shade_threshold : hint_range(-1.0, 1.0) = 0.05;
uniform float shade_softness : hint_range(0.0, 0.5) = 0.025;
// Unsharp mask strength and radius in texels.
uniform float sharpen : hint_range(0.0, 2.0) = 0.8;
uniform float sharpen_radius : hint_range(0.5, 4.0) = 1.5;
uniform float saturation : hint_range(0.0, 2.0) = 1.18;
uniform vec4 rim_color : source_color = vec4(1.0, 0.97, 0.92, 1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.22;
uniform float rim_width : hint_range(0.0, 1.0) = 0.28;

void fragment() {
	vec2 texel = sharpen_radius / vec2(textureSize(albedo_texture, 0));
	vec3 centre = texture(albedo_texture, UV).rgb;
	vec3 blur = (
		texture(albedo_texture, UV + vec2(texel.x, 0.0)).rgb
		+ texture(albedo_texture, UV - vec2(texel.x, 0.0)).rgb
		+ texture(albedo_texture, UV + vec2(0.0, texel.y)).rgb
		+ texture(albedo_texture, UV - vec2(0.0, texel.y)).rgb
	) * 0.25;
	vec3 colour = clamp(centre + (centre - blur) * sharpen, 0.0, 1.0);
	float grey = dot(colour, vec3(0.299, 0.587, 0.114));
	colour = clamp(mix(vec3(grey), colour, saturation), 0.0, 1.0);
	ALBEDO = colour * albedo_color.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	float facing = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	EMISSION = rim_color.rgb * ALBEDO * rim_strength * step(1.0 - rim_width, facing);
}

void light() {
	float lit = smoothstep(
		shade_threshold - shade_softness, shade_threshold + shade_softness, dot(NORMAL, LIGHT)
	);
	// Shadows are snapped to the same two tones, so a cast shadow is a clean shade shape.
	lit *= step(0.5, ATTENUATION);
	vec3 tone = mix(shade_color.rgb, vec3(1.0), lit);
	float falloff = LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION;
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * tone * falloff;
}
