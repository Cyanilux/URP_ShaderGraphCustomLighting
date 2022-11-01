#ifndef CUSTOM_LIGHTING_INCLUDED
#define CUSTOM_LIGHTING_INCLUDED

// @Cyanilux | https://github.com/Cyanilux/URP_ShaderGraphCustomLighting
// Note this version of the package assumes v12+ due to usage of "Branch on Input Connection" node
// For older versions, see branches on github repo!

//------------------------------------------------------------------------------------------------------
// Main Light
//------------------------------------------------------------------------------------------------------

/*
- Obtains the Direction, Color and Distance Atten for the Main Light.
- (DistanceAtten is either 0 or 1 for directional light, depending if the light is in the culling mask or not)
- If you want shadow attenutation, see MainLightShadows_float, or use MainLightFull_float instead
*/
void MainLight_float (out float3 Direction, out float3 Color, out float DistanceAtten){
	#ifdef SHADERGRAPH_PREVIEW
		Direction = normalize(float3(1,1,-0.4));
		Color = float4(1,1,1,1);
		DistanceAtten = 1;
	#else
		Light mainLight = GetMainLight();
		Direction = mainLight.direction;
		Color = mainLight.color;
		DistanceAtten = mainLight.distanceAttenuation;
	#endif
}

//------------------------------------------------------------------------------------------------------
// Shadowmask (v10+)
//------------------------------------------------------------------------------------------------------

/*
- Used to support "Shadowmask" mode in Lighting window.
- Should be sampled once in graph, then input into the Main Light Shadows and/or Additional Light subgraphs/functions.
- To work in an Unlit Graph, likely requires keywords :
	- Boolean Keyword, Global Multi-Compile "SHADOWS_SHADOWMASK" 
	- Boolean Keyword, Global Multi-Compile "LIGHTMAP_SHADOW_MIXING"
	- (also LIGHTMAP_ON, but I believe Shader Graph is already defining this one)
*/
void Shadowmask_half (float2 lightmapUV, out half4 Shadowmask){
	#ifdef SHADERGRAPH_PREVIEW
		Shadowmask = half4(1,1,1,1);
	#else
		OUTPUT_LIGHTMAP_UV(lightmapUV, unity_LightmapST, lightmapUV);
		Shadowmask = SAMPLE_SHADOWMASK(lightmapUV);
	#endif
}

//------------------------------------------------------------------------------------------------------
// Main Light Shadows
//------------------------------------------------------------------------------------------------------

/*
- This undef (un-define) is required to prevent the "invalid subscript 'shadowCoord'" error,
  which occurs when _MAIN_LIGHT_SHADOWS is used with 1/No Shadow Cascades with the Unlit Graph.
- It's not required for the PBR/Lit graph, so I'm using the SHADERPASS_FORWARD to ignore it for that pass
*/
#ifndef SHADERGRAPH_PREVIEW
	#include "Packages/com.unity.render-pipelines.universal/Editor/ShaderGraph/Includes/ShaderPass.hlsl"
	#if (SHADERPASS != SHADERPASS_FORWARD)
		#undef REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR
	#endif
#endif

/*
- Samples the Shadowmap for the Main Light, based on the World Position passed in. (Position node)
- Works in an Unlit Graph with all Shadow Cascade options, see above fix! :)
- For shadows to work in the Unlit Graph, the following keywords must be defined in the blackboard :
	- Boolean Keyword, Global Multi-Compile "_MAIN_LIGHT_SHADOWS" (must be present to also stop the others being stripped from builds)
	- Boolean Keyword, Global Multi-Compile "_MAIN_LIGHT_SHADOWS_CASCADE"
	- Boolean Keyword, Global Multi-Compile "_SHADOWS_SOFT"
- For a PBR/Lit Graph, these keywords are already handled for you.
*/
void MainLightShadows_float (float3 WorldPos, half4 Shadowmask, out float ShadowAtten){
	#ifdef SHADERGRAPH_PREVIEW
		ShadowAtten = 1;
	#else
		float4 shadowCoord = TransformWorldToShadowCoord(WorldPos);
		ShadowAtten = MainLightShadow(shadowCoord, WorldPos, Shadowmask, _MainLightOcclusionProbes);
	#endif
}

void MainLightShadows_float (float3 WorldPos, out float ShadowAtten){
	MainLightShadows_float(WorldPos, half4(1,1,1,1), ShadowAtten);
}

//------------------------------------------------------------------------------------------------------
// Ambient Lighting
//------------------------------------------------------------------------------------------------------

/*
- Uses "SampleSH", the spherical harmonic stuff that ambient lighting / light probes uses.
- Will likely be used in the fragment, so will be per-pixel.
- Alternatively could use the Baked GI node, as it'll also handle this for you.
- Could also use the Ambient node, would be cheaper but the result won't automatically adapt based on the Environmental Lighting Source (Lighting tab).
*/
void AmbientSampleSH_float (float3 WorldNormal, out float3 Ambient){
	#ifdef SHADERGRAPH_PREVIEW
		Ambient = float3(0.1, 0.1, 0.1); // Default ambient colour for previews
	#else
		Ambient = SampleSH(WorldNormal);
	#endif
}

//------------------------------------------------------------------------------------------------------
// Mix Fog
//------------------------------------------------------------------------------------------------------

/*
- Adds fog to the colour, based on the Fog settings in the Lighting tab.
- Note : Not required for v12, can use Lerp instead. See "Mix Fog" SubGraph
*/
void MixFog_float (float3 Colour, float Fog, out float3 Out){
	#ifdef SHADERGRAPH_PREVIEW
		Out = Colour;
	#else
		Out = MixFog(Colour, Fog);
	#endif
}

//------------------------------------------------------------------------------------------------------
// Default Additional Lights
//------------------------------------------------------------------------------------------------------

/*
- Handles additional lights (e.g. point, spotlights)
- For custom lighting, you'd want to duplicate this and swap the LightingLambert / LightingSpecular functions out. See Toon Example below!
- For shadows to work in the Unlit Graph, the following keywords must be defined in the blackboard :
	- Boolean Keyword, Global Multi-Compile "_ADDITIONAL_LIGHT_SHADOWS"
	- Boolean Keyword, Global Multi-Compile "_ADDITIONAL_LIGHTS" (required to prevent the one above from being stripped from builds)
- For a PBR/Lit Graph, these keywords are already handled for you.
*/
void AdditionalLights_float(float3 SpecColor, float Smoothness, float3 WorldPosition, float3 WorldNormal, float3 WorldView, half4 Shadowmask,
							out float3 Diffuse, out float3 Specular) {
	float3 diffuseColor = 0;
	float3 specularColor = 0;

#ifndef SHADERGRAPH_PREVIEW
	Smoothness = exp2(10 * Smoothness + 1);
	WorldNormal = normalize(WorldNormal);
	WorldView = SafeNormalize(WorldView);
	int pixelLightCount = GetAdditionalLightsCount();
	for (int i = 0; i < pixelLightCount; ++i) {
		Light light = GetAdditionalLight(i, WorldPosition, half4(1,1,1,1));

		float3 attenuatedLightColor = light.color * (light.distanceAttenuation * light.shadowAttenuation);
		diffuseColor += LightingLambert(attenuatedLightColor, light.direction, WorldNormal);
		specularColor += LightingSpecular(attenuatedLightColor, light.direction, WorldNormal, WorldView, float4(SpecColor, 0), Smoothness);
	}
#endif

	Diffuse = diffuseColor;
	Specular = specularColor;
}

void AdditionalLights_float(float3 SpecColor, float Smoothness, float3 WorldPosition, float3 WorldNormal, float3 WorldView, 
							out float3 Diffuse, out float3 Specular) {
AdditionalLights_float(SpecColor, Smoothness, WorldPosition, WorldNormal, WorldView, half4(1,1,1,1), Diffuse, Specular);
}

//------------------------------------------------------------------------------------------------------
// Additional Lights Toon Example
//------------------------------------------------------------------------------------------------------

/*
- Calculates light attenuation values to produce multiple bands for a toon effect. See AdditionalLightsToon function below
*/
#ifndef SHADERGRAPH_PREVIEW
float ToonAttenuation(int i, float3 positionWS, float pointBands, float spotBands){
	int perObjectLightIndex = GetPerObjectLightIndex(i); // (i = index used in loop)
	#if USE_STRUCTURED_BUFFER_FOR_LIGHT_DATA
		float4 lightPositionWS = _AdditionalLightsBuffer[perObjectLightIndex].position;
		half4 spotDirection = _AdditionalLightsBuffer[perObjectLightIndex].spotDirection;
		half4 distanceAndSpotAttenuation = _AdditionalLightsBuffer[perObjectLightIndex].attenuation;
	#else
		float4 lightPositionWS = _AdditionalLightsPosition[perObjectLightIndex];
		half4 spotDirection = _AdditionalLightsSpotDir[perObjectLightIndex];
		half4 distanceAndSpotAttenuation = _AdditionalLightsAttenuation[perObjectLightIndex];
	#endif

	// Point
	float3 lightVector = lightPositionWS.xyz - positionWS * lightPositionWS.w;
	float distanceSqr = max(dot(lightVector, lightVector), HALF_MIN);
	float range = rsqrt(distanceAndSpotAttenuation.x);
	float dist = sqrt(distanceSqr) / range;

	// Spot
	half3 lightDirection = half3(lightVector * rsqrt(distanceSqr));
	half SdotL = dot(spotDirection.xyz, lightDirection);
	half spotAtten = saturate(SdotL * distanceAndSpotAttenuation.z + distanceAndSpotAttenuation.w);
	spotAtten *= spotAtten;
	float maskSpotToRange = step(dist, 1);

	// Atten
	bool isSpot = (distanceAndSpotAttenuation.z > 0);
	return isSpot ? 
		//step(0.01, spotAtten) :		// cheaper if you just want "1" band for spot lights
		(floor(spotAtten * spotBands) / spotBands) * maskSpotToRange :
		saturate(1.0 - floor(dist * pointBands) / pointBands);
}
#endif

/*
- Handles additional lights (e.g. point, spotlights) with banded toon effect
- For shadows to work in the Unlit Graph, the following keywords must be defined in the blackboard :
	- Boolean Keyword, Global Multi-Compile "_ADDITIONAL_LIGHT_SHADOWS"
	- Boolean Keyword, Global Multi-Compile "_ADDITIONAL_LIGHTS" (required to prevent the one above from being stripped from builds)
- For a PBR/Lit Graph, these keywords are already handled for you.
*/
void AdditionalLightsToon_float(float3 SpecColor, float Smoothness, float3 WorldPosition, float3 WorldNormal, float3 WorldView, half4 Shadowmask,
						float PointLightBands, float SpotLightBands,
						out float3 Diffuse, out float3 Specular) {
	float3 diffuseColor = 0;
	float3 specularColor = 0;
	
#ifndef SHADERGRAPH_PREVIEW
	Smoothness = exp2(10 * Smoothness + 1);
	WorldNormal = normalize(WorldNormal);
	WorldView = SafeNormalize(WorldView);
	int pixelLightCount = GetAdditionalLightsCount();
	for (int i = 0; i < pixelLightCount; ++i) {
		Light light = GetAdditionalLight(i, WorldPosition, Shadowmask);

		// DIFFUSE
		/* (LightingLambert)
		half NdotL = saturate(dot(normal, lightDir));
		diffuseColor += lightColor * NdotL;
		*/

		if (PointLightBands <= 1 && SpotLightBands <= 1){
			// Solid colour lights
			diffuseColor += light.color * step(0.0001, light.distanceAttenuation * light.shadowAttenuation);
		}else{
			// Multiple bands :
			diffuseColor += light.color * light.shadowAttenuation * ToonAttenuation(i, WorldPosition, PointLightBands, SpotLightBands);
		}

		// SPECULAR
		// Didn't really like the look of specular lighting in the toon shader here, so just keeping it at 0 (black, no light).
		/* (LightingSpecular)
		float3 halfVec = SafeNormalize(float3(lightDir) + float3(viewDir));
		half NdotH = saturate(dot(normal, halfVec));
		half modifier = pow(NdotH, smoothness);
		half3 specularReflection = specular.rgb * modifier;
		specularColor += lightColor * specularReflection;
		*/
	}
#endif

	Diffuse = diffuseColor;
	Specular = specularColor;
}

void AdditionalLightsToon_float(float3 SpecColor, float Smoothness, float3 WorldPosition, float3 WorldNormal, float3 WorldView,
						float PointLightBands, float SpotLightBands,
						out float3 Diffuse, out float3 Specular) {
AdditionalLightsToon_float(SpecColor, Smoothness, WorldPosition, WorldNormal, WorldView, half4(1,1,1,1),
	PointLightBands, SpotLightBands,Diffuse, Specular);
}

#endif // CUSTOM_LIGHTING_INCLUDED