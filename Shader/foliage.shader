shader_type spatial;
render_mode depth_draw_alpha_prepass, specular_schlick_ggx;
//render_mode blend_mix, cull_disabled, depth_draw_alpha_prepass, specular_disabled;

uniform vec4 TopColor : hint_color = vec4(0.24, 0.47, 0.27, 1.0);
uniform vec4 BottomColor : hint_color = vec4(0.13, 0.33, 0.25, 1.0);
uniform sampler2D Alpha;
uniform vec4 FresnelColor : hint_color = vec4(0.58, 0.65, 0.33, 1.0);

uniform float WindScale : hint_range(1.0, 20.0) = 1.0;
uniform float WindSpeed : hint_range(0.0, 20.0) = 4.0;
uniform float WindStrength : hint_range(1.0, 20.0) = 5.0;
uniform float WindDensity : hint_range(1.0, 20.0) = 5.0;
uniform float ClampTop : hint_range(0.0, 1.0) = 1.0;
uniform float ClampBtm : hint_range(-1.0, 0.0) = 0.0;
uniform float MeshScale : hint_range(-5.0, 5.0) = -0.333;
uniform float ColorRamp : hint_range(0.05, 5.0) = 0.3;

uniform float FaceRoationVariation : hint_range(-3.0, 3.0) = 1.0;

uniform float FresnelStrength : hint_range(-2.0, 2.0) = 0.5;
uniform float FresnelBlend : hint_range(-1.0, 1.0) = 1.0;

// Uniforms for wiggling
uniform sampler2D WiggleNoise : hint_black;
uniform float WiggleFrequency = 3.0;
uniform float WiggleStrength = 0.1;
uniform float WiggleSpeed = 1.0;
uniform float WiggleScale = 3.0;

vec2 rotateUV(vec2 uv, float rotation, vec2 mid)
{
	float cosAngle = cos(rotation);
	float sinAngle = sin(rotation);
	return vec2(
		cosAngle * (uv.x - mid.x) + sinAngle * (uv.y - mid.y) + mid.x,
		cosAngle * (uv.y - mid.y) - sinAngle * (uv.x - mid.x) + mid.y
	);
}

varying vec3 obj_vertex;
void vertex()
{
	//Camera-Orientation based on https://www.youtube.com/watch?v=iASMFba7GeI
	vec3 orient_2d = vec3(1.0, 1.0, 0.0) - vec3(UV.x, UV.y, 0.0);
	orient_2d *= 2.0;
	orient_2d -= vec3(1.0, 1.0, 0.0);
	orient_2d *= -1.0;
	orient_2d *= MeshScale;
	
	//random tilt
	float angle = 6.248 * UV2.x * FaceRoationVariation;
	float cos_ang = cos(angle);
	float sin_ang = sin(angle);
	mat3 rotation = mat3(vec3(cos_ang, -sin_ang, 0.0),vec3(sin_ang, cos_ang, 0.0),vec3(0.0, 0.0, 0.0));
	
	orient_2d *= rotation;
	
	vec3 oriented_offset = reflect((CAMERA_MATRIX * vec4(orient_2d, 0.0)).xyz,CAMERA_MATRIX[0].xyz);
	//vec3 oriented_offset = (CAMERA_MATRIX * vec4(orient_2d, 0.0)).xyz;
	vec3 obj_oriented_offset = (vec4(oriented_offset, 0.0) * WORLD_MATRIX).xyz;
	
	//Wind-Effect
	//adapted from: https://github.com/ruffiely/windshader_godot
//	vec3 world_pos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;	//Generates world coordinates for vertecies
	
	// Removed using world_position due to dragging bug
	// Using local coordinates fixes this issue
//	float offset = fract((-world_pos.x + world_pos.z) * (1.0 / WindScale) + (TIME * WindScale/1000.0));	//Generates linear curve that slides along vertecies in world space
	float offset = fract((-VERTEX.x + VERTEX.z) * (1.0 / WindScale) + (TIME * WindScale/1000.0));	//Generates linear curve that slides along vertecies in world space
	offset = min(1.0 - offset, offset);														//Makes generated curve a smooth gradient
	offset = (1.0 - offset) * offset * 2.0;													//Smoothes gradient further
	
	float t = TIME + sin(TIME + offset + cos(TIME + offset * WindStrength * 2.0) * WindStrength); //Generates noise in world space value
	
	//float mask = fract(v.y * wind_density) * v.y; //Generates vertical mask, so leaves on top move further than leaves on bottom
	//mask = clamp(mask, 0.0, 1.0);                 //Clamps mask
	
	float mask = clamp(VERTEX.y* WindDensity, 0.0, 1.0) * (ClampTop - ClampBtm) + ClampBtm;
	
	
	float si = sin(t) / 20.0 * WindStrength * offset;	//Generates clamped noise, adds strength, applies gradient mask
	float csi = cos(t)/ 20.0 * WindStrength * offset;	//Generates clamped noise with offset, adds strength, applies gradient mask
		
	vec3 wind_offset = vec3(VERTEX.x * si * mask, VERTEX.y * si * mask, VERTEX.z * csi * mask);
	
	float col = VERTEX.y * ColorRamp;
	COLOR = vec4(col, col, col, 1.0);
	VERTEX += obj_oriented_offset + wind_offset;
	
	obj_vertex = VERTEX;
}

void fragment()
{
	float rate_col1 = clamp(COLOR.r,0.0, 1.0);
	float rate_col2 = 1.0 - rate_col1;
	
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float fresnel_rate = clamp(rate_col1,0.1,1);
	
	vec3 albedo = TopColor.rgb* rate_col1 + BottomColor.rgb * rate_col2;
	
	vec3 fres_col = albedo *(1.0 - FresnelStrength);
	fres_col += FresnelColor.rgb * FresnelStrength;
	fres_col *= fresnel;
	fres_col *= fresnel_rate;
	fres_col *= FresnelBlend;
	
	vec2 wiggle_uv = normalize(obj_vertex.xz) / WiggleScale;
	float wiggle = texture(WiggleNoise, wiggle_uv + TIME * WiggleSpeed).r;
	float wiggle_final_strength = wiggle * WiggleStrength;
	wiggle_final_strength *= clamp(sin(TIME * WiggleFrequency), 0.0, 1.0);
	vec2 uv = UV;
	uv = rotateUV(uv, wiggle_final_strength, vec2(0.5));
	uv = clamp(uv, 0.0, 1.0);
	float alpha = texture(Alpha, uv.xy).r;
	
	ALBEDO = albedo;
	ALPHA = alpha;
	EMISSION = fres_col;
}