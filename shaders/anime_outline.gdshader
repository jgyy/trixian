// Ink outline for the Tripo models, drawn as an inverted hull in a second pass. The hull is pushed
// out along the view-space normal by a fixed width in metres, so the line thins with distance, and
// pushed away from the camera by a depth bias, so it shows around the silhouette but not through
// the layered collars, sleeves and hair strands in front of it. It is coloured with a darkened copy of the albedo rather than flat black, as in anime line art.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float outline_width : hint_range(0.0, 0.05) = 0.004;
// Metres the hull is pushed away from the camera.
uniform float depth_bias : hint_range(0.0, 0.2) = 0.03;
uniform float outline_darkness : hint_range(0.0, 1.0) = 0.3;

void vertex() {
	vec3 view_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec4 view_position = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view_position.xyz += view_normal * outline_width;
	view_position.z -= depth_bias;
	POSITION = PROJECTION_MATRIX * view_position;
}

void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb * albedo_color.rgb * outline_darkness;
}
