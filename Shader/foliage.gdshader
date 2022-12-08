shader_type spatial;
render_mode depth_draw_opaque, specular_schlick_ggx, depth_prepass_alpha ;
//render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_disabled;

uniform vec4 TopColor : source_color = vec4(0.24, 0.47, 0.27, 1.0);
uniform vec4 BottomColor : source_color = vec4(0.13, 0.33, 0.25, 1.0);
uniform sampler2D Alpha;
uniform vec4 FresnelColor : source_color = vec4(0.58, 0.65, 0.33, 1.0);

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
uniform bool DeactivateGlobalVariation;
// Uniforms for wiggling
uniform sampler2D WiggleNoise : hint_default_black;
uniform float WiggleFrequency = 3.0;
uniform float WiggleStrength = 0.1;
uniform float WiggleSpeed = 1.0;
uniform float WiggleScale = 3.0;

uniform float DistanceScale : hint_range(0.0, 5.0) = 0.5;
uniform float DistanceStart = 0;
uniform float DistanceScaleRange = 70;

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
	float distanceScale = 1.0;
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;	//Generates world coordinates for vertecies
	vec3 distance_vector = world_pos - (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float square_distance = distance_vector.x * distance_vector.x + distance_vector.y * distance_vector.y + distance_vector.z * distance_vector.z;
	float square_end = (DistanceScaleRange + DistanceStart) * (DistanceScaleRange + DistanceStart);
	float square_start = DistanceStart * DistanceStart;
	float square_range = square_end - square_start;
	
	float distance_influence = clamp((square_distance - square_start) / square_range, 0.0, 1.0);
	//Camera-Orientation based on https://www.youtube.com/watch?v=iASMFba7GeI
	vec3 orient_2d = vec3(1.0, 1.0, 0.0) - vec3(UV.x, UV.y, 0.0);
	orient_2d *= 2.0;
	orient_2d -= vec3(1.0, 1.0, 0.0);
	orient_2d *= -1.0;
	orient_2d *= MeshScale;
	orient_2d *= (1.0 + distance_influence * DistanceScale);
	
	//random tilt
	float angle = 6.248 * UV2.x * FaceRoationVariation;
	float cos_ang = cos(angle);
	float sin_ang = sin(angle);
	mat3 rotation = mat3(vec3(cos_ang, -sin_ang, 0.0),vec3(sin_ang, cos_ang, 0.0),vec3(0.0, 0.0, 0.0));
	
	orient_2d *= rotation;
	
	vec3 oriented_offset = reflect((INV_VIEW_MATRIX * vec4(orient_2d, 0.0)).xyz,INV_VIEW_MATRIX[0].xyz);
	//vec3 oriented_offset = (INV_VIEW_MATRIX * vec4(orient_2d, 0.0)).xyz;
	vec3 obj_oriented_offset = (vec4(oriented_offset, 0.0) * MODEL_MATRIX).xyz;
	
	//Wind-Effect
	//adapted from: https://github.com/ruffiely/windshader_godot
	float contribution = 1.0 * (1.0 - float(DeactivateGlobalVariation));
	vec3 world_pos_eff = world_pos * contribution;	//Generates world coordinates for vertecies
	// Removed using world_position due to dragging bug
	float positional_influence = -VERTEX.x + VERTEX.z -world_pos_eff.x + world_pos_eff.z;
	float offset = fract(positional_influence * (1.0 / WindScale) + (TIME * WindScale/1000.0));	//Generates linear curve that slides along vertecies in world space
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
	COLOR = vec4(col, positional_influence, distance_influence, 1.0);
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
	//fres_col *= (1.0 - COLOR.b);
	
	vec2 wiggle_uv = normalize(obj_vertex.xz) / WiggleScale;
	float wiggle = texture(WiggleNoise, wiggle_uv + TIME * WiggleSpeed).r;
	float wiggle_final_strength = wiggle * WiggleStrength;
	wiggle_final_strength *= clamp(sin(TIME * WiggleFrequency + COLOR.g * 0.2), 0.0, 1.0);
	vec2 uv = UV;
	uv = rotateUV(uv, wiggle_final_strength, vec2(0.5));
	uv = clamp(uv, 0.0, 1.0);
	vec3 tex = texture(Alpha, uv.xy).rgb;
	float x = COLOR.b;
	float alpha = clamp(tex.r + tex.g * 2.0 * COLOR.b ,0.0, 1.0);
	alpha = clamp((clamp(tex.g * 1.0 , 1.0 - x, 1.0) - (1.0 - x)) * 10.0 + tex.r, 0.0, 1.0);
	//albedo = vec3(COLOR.b,COLOR.b,COLOR.b);
	ALBEDO = albedo;
	ALPHA = alpha;
	EMISSION = fres_col;
}