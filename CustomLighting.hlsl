#ifndef CUSTOM_LIGHTING_INCLUDED
#define CUSTOM_LIGHTING_INCLUDED

// @Cyanilux | https://github.com/Cyanilux/URP_ShaderGraphCustomLighting
// This version is intended for use in Unity 6.1+
// For older versions, see branches on github repo!

//------------------------------------------------------------------------------------------------------
// Keyword Pragmas
//------------------------------------------------------------------------------------------------------

#ifndef SHADERGRAPH_PREVIEW
	#if SHADERPASS != SHADERPASS_FORWARD && SHADERPASS != SHADERPASS_GBUFFER
		// #if to avoid "duplicate keyword" warnings if this is included in a Lit Graph

    	#pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
    	#pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
		#pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
		#pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
		#pragma multi_compile _ _CLUSTER_LIGHT_LOOP

		// Left some keywords (e.g. light layers, cookies) in subgraphs to help avoid unnecessary shader variants
		// But means if those subgraphs are nested in another, you'll need to copy the keywords from blackboard

	#endif
#endif

//------------------------------------------------------------------------------------------------------
// Main Light
//------------------------------------------------------------------------------------------------------

/*
- Obtains the Direction, Color and DistanceAtten for the Main Directional Light
- (DistanceAtten is either 1 or 0, depending if the object is in the light's Culling Mask or not)
- For shadows, see MainLightShadows_float
- For DistanceAtten output to work in the Forward+ path "_CLUSTER_LIGHT_LOOP" keyword is required
*/
void MainLight_float(out float3 Direction, out float3 Color, out float DistanceAtten){
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

/*
- Tests whether the Main Light Layer Mask appears in the Rendering Layers from renderer
- (Used to support Light Layers, pass your shading from Main Light into this)
- To work in an Unlit Graph, requires keywords :
	- Boolean Keyword, Global Multi-Compile "_LIGHT_LAYERS"
*/
void MainLightLayer_float(float3 Shading, out float3 Out){
	#ifdef SHADERGRAPH_PREVIEW
		Out = Shading;
	#else
		Out = 0;
		uint meshRenderingLayers = GetMeshRenderingLayer();
		#ifdef _LIGHT_LAYERS
			if (IsMatchingLightLayer(GetMainLight().layerMask, meshRenderingLayers))
		#endif
		{
			Out = Shading;
		}
	#endif
}

/*
- Obtains the Light Cookie assigned to the Main Light
- (For usage, You'd want to Multiply the result with your Light Colour)
- To work in an Unlit Graph, requires keywords :
	- Boolean Keyword, Global Multi-Compile "_LIGHT_COOKIES"
*/
void MainLightCookie_float(float3 WorldPos, out float3 Cookie){
	Cookie = 1;
	#if defined(_LIGHT_COOKIES)
        Cookie = SampleMainLightCookie(WorldPos);
    #endif
}

//------------------------------------------------------------------------------------------------------
// Main Light Shadows
//------------------------------------------------------------------------------------------------------

/*
- Samples the Shadowmap for the Main Light, based on the World Position passed in. (Position node)
*/
void MainLightShadows_float(float3 WorldPos, half4 Shadowmask, out float ShadowAtten){
	#ifdef SHADERGRAPH_PREVIEW
		ShadowAtten = 1;
	#else
		#if defined(_MAIN_LIGHT_SHADOWS_SCREEN) && !defined(_SURFACE_TYPE_TRANSPARENT)
		float4 shadowCoord = ComputeScreenPos(TransformWorldToHClip(WorldPos));
		#else
		float4 shadowCoord = TransformWorldToShadowCoord(WorldPos);
		#endif
		ShadowAtten = MainLightShadow(shadowCoord, WorldPos, Shadowmask, _MainLightOcclusionProbes);
	#endif
}

void MainLightShadows_float(float3 WorldPos, out float ShadowAtten){
	MainLightShadows_float(WorldPos, half4(1,1,1,1), ShadowAtten);
}

//------------------------------------------------------------------------------------------------------
// Baked GI
//------------------------------------------------------------------------------------------------------

/*
- Used to support "Shadowmask" Baked GI mode in Lighting window.
- Ideally sample once in graph, then input into the Main Light Shadows and/or Additional Light subgraphs/functions.
- To work in an Unlit Graph, likely requires keywords :
	- Boolean Keyword, Global Multi-Compile "SHADOWS_SHADOWMASK" 
	- Boolean Keyword, Global Multi-Compile "LIGHTMAP_SHADOW_MIXING"
	- (also LIGHTMAP_ON, but I believe Shader Graph is already defining this one)
*/
void Shadowmask_half(float2 lightmapUV, out half4 Shadowmask){
	#ifdef SHADERGRAPH_PREVIEW
		Shadowmask = half4(1,1,1,1);
	#else
		OUTPUT_LIGHTMAP_UV(lightmapUV, unity_LightmapST, lightmapUV);
		Shadowmask = SAMPLE_SHADOWMASK(lightmapUV);
	#endif
}

/*
- Used to support "Subtractive" Baked GI mode in Lighting window
- Inputs should be ShadowAtten from Main Light Shadows subgraph, Normal Vector (World space) and Baked GI nodes
- To work in an Unlit Graph, likely requires keywords :
	- Boolean Keyword, Global Multi-Compile "LIGHTMAP_SHADOW_MIXING"
	- (also LIGHTMAP_ON, but I believe Shader Graph is already defining this one)
*/
void SubtractiveGI_float(float ShadowAtten, float3 NormalWS, float3 BakedGI, out half3 result){
	#ifdef SHADERGRAPH_PREVIEW
		result = half3(1,1,1);
	#else
		Light mainLight = GetMainLight();
		mainLight.shadowAttenuation = ShadowAtten;
		MixRealtimeAndBakedGI(mainLight, NormalWS, BakedGI);
		result = BakedGI;
	#endif
}

//------------------------------------------------------------------------------------------------------
// Default Additional Lights
//------------------------------------------------------------------------------------------------------

/*
- Handles additional lights (e.g. additional directional, point, spotlights)
- For custom lighting, you may want to duplicate this and swap the LightingLambert / LightingSpecular functions out. See Toon Example below!
- Requires keywords "_ADDITIONAL_LIGHTS", "_ADDITIONAL_LIGHT_SHADOWS" & "_CLUSTER_LIGHT_LOOP"
*/
void AdditionalLights_float(float3 SpecColor, float Smoothness, float3 WorldPosition, float3 WorldNormal, float3 WorldView, half4 Shadowmask,
							out float3 Diffuse, out float3 Specular) {
	float3 diffuseColor = 0;
	float3 specularColor = 0;
#ifndef SHADERGRAPH_PREVIEW
	Smoothness = exp2(10 * Smoothness + 1);
	uint pixelLightCount = GetAdditionalLightsCount();
	uint meshRenderingLayers = GetMeshRenderingLayer();

	#if USE_CLUSTER_LIGHT_LOOP
	for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++) {
		CLUSTER_LIGHT_LOOP_SUBTRACTIVE_LIGHT_CHECK
		Light light = GetAdditionalLight(lightIndex, WorldPosition, Shadowmask);
	#ifdef _LIGHT_LAYERS
		if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
	#endif
		{
			// Blinn-Phong
			float3 attenuatedLightColor = light.color * (light.distanceAttenuation * light.shadowAttenuation);
			diffuseColor += LightingLambert(attenuatedLightColor, light.direction, WorldNormal);
			specularColor += LightingSpecular(attenuatedLightColor, light.direction, WorldNormal, WorldView, float4(SpecColor, 0), Smoothness);
		}
	}
	#endif

	// For Foward+ the LIGHT_LOOP_BEGIN macro will use inputData.normalizedScreenSpaceUV, inputData.positionWS, so create that:
	InputData inputData = (InputData)0;
	float4 screenPos = ComputeScreenPos(TransformWorldToHClip(WorldPosition));
	inputData.normalizedScreenSpaceUV = screenPos.xy / screenPos.w;
	inputData.positionWS = WorldPosition;

	LIGHT_LOOP_BEGIN(pixelLightCount)
		Light light = GetAdditionalLight(lightIndex, WorldPosition, Shadowmask);
	#ifdef _LIGHT_LAYERS
		if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
	#endif
		{
			// Blinn-Phong
			float3 attenuatedLightColor = light.color * (light.distanceAttenuation * light.shadowAttenuation);
			diffuseColor += LightingLambert(attenuatedLightColor, light.direction, WorldNormal);
			specularColor += LightingSpecular(attenuatedLightColor, light.direction, WorldNormal, WorldView, float4(SpecColor, 0), Smoothness);
		}
	LIGHT_LOOP_END
#endif

	Diffuse = diffuseColor;
	Specular = specularColor;
}

//------------------------------------------------------------------------------------------------------
// Additional Lights Toon Example
//------------------------------------------------------------------------------------------------------

/*
- Calculates light attenuation values to produce multiple bands for a toon effect. See AdditionalLightsToon function below
*/
#ifndef SHADERGRAPH_PREVIEW
float ToonAttenuation(int lightIndex, float3 positionWS, float pointBands, float spotBands){
	#if !USE_CLUSTER_LIGHT_LOOP
		lightIndex = GetPerObjectLightIndex(lightIndex);
	#endif
	#if USE_STRUCTURED_BUFFER_FOR_LIGHT_DATA
		float4 lightPositionWS = _AdditionalLightsBuffer[lightIndex].position;
		half4 spotDirection = _AdditionalLightsBuffer[lightIndex].spotDirection;
		half4 distanceAndSpotAttenuation = _AdditionalLightsBuffer[lightIndex].attenuation;
	#else
		float4 lightPositionWS = _AdditionalLightsPosition[lightIndex];
		half4 spotDirection = _AdditionalLightsSpotDir[lightIndex];
		half4 distanceAndSpotAttenuation = _AdditionalLightsAttenuation[lightIndex];
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
- Requires keywords "_ADDITIONAL_LIGHTS", "_ADDITIONAL_LIGHT_SHADOWS" & "_CLUSTER_LIGHT_LOOP"
*/
void AdditionalLightsToon_float(float3 SpecColor, float Smoothness, float3 WorldPosition, float3 WorldNormal, float3 WorldView, half4 Shadowmask,
						float PointLightBands, float SpotLightBands,
						out float3 Diffuse, out float3 Specular) {
	float3 diffuseColor = 0;
	float3 specularColor = 0;

#ifndef SHADERGRAPH_PREVIEW
	Smoothness = exp2(10 * Smoothness + 1);
	uint pixelLightCount = GetAdditionalLightsCount();
	uint meshRenderingLayers = GetMeshRenderingLayer();

	#if USE_CLUSTER_LIGHT_LOOP
	for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++) {
		CLUSTER_LIGHT_LOOP_SUBTRACTIVE_LIGHT_CHECK
		Light light = GetAdditionalLight(lightIndex, WorldPosition, Shadowmask);
	#ifdef _LIGHT_LAYERS
		if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
	#endif
		{
			if (PointLightBands <= 1 && SpotLightBands <= 1){
				// Solid colour lights
				diffuseColor += light.color * step(0.0001, light.distanceAttenuation * light.shadowAttenuation);
			}else{
				// Multiple bands
				diffuseColor += light.color * light.shadowAttenuation * ToonAttenuation(lightIndex, WorldPosition, PointLightBands, SpotLightBands);
			}
		}
	}
	#endif

	// For Foward+ the LIGHT_LOOP_BEGIN macro will use inputData.normalizedScreenSpaceUV, inputData.positionWS, so create that:
	InputData inputData = (InputData)0;
	float4 screenPos = ComputeScreenPos(TransformWorldToHClip(WorldPosition));
	inputData.normalizedScreenSpaceUV = screenPos.xy / screenPos.w;
	inputData.positionWS = WorldPosition;

	LIGHT_LOOP_BEGIN(pixelLightCount)
		Light light = GetAdditionalLight(lightIndex, WorldPosition, Shadowmask);
	#ifdef _LIGHT_LAYERS
		if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
	#endif
		{
			if (PointLightBands <= 1 && SpotLightBands <= 1){
				// Solid colour lights
				diffuseColor += light.color * step(0.0001, light.distanceAttenuation * light.shadowAttenuation);
			}else{
				// Multiple bands
				diffuseColor += light.color * light.shadowAttenuation * ToonAttenuation(lightIndex, WorldPosition, PointLightBands, SpotLightBands);
			}
		}
	LIGHT_LOOP_END
#endif

/*
#ifndef SHADERGRAPH_PREVIEW
	Smoothness = exp2(10 * Smoothness + 1);
	WorldNormal = normalize(WorldNormal);
	WorldView = SafeNormalize(WorldView);
	int pixelLightCount = GetAdditionalLightsCount();
	for (int i = 0; i < pixelLightCount; ++i) {
		Light light = GetAdditionalLight(i, WorldPosition, Shadowmask);

		// DIFFUSE
		if (PointLightBands <= 1 && SpotLightBands <= 1){
			// Solid colour lights
			diffuseColor += light.color * step(0.0001, light.distanceAttenuation * light.shadowAttenuation);
		}else{
			// Multiple bands :
			diffuseColor += light.color * light.shadowAttenuation * ToonAttenuation(i, WorldPosition, PointLightBands, SpotLightBands);
		}
	}
#endif
*/

	Diffuse = diffuseColor;
	Specular = specularColor;
	// Didn't really like the look of specular lighting in the toon shader here, so just keeping it at 0
}

//------------------------------------------------------------------------------------------------------
// Deprecated / Backwards compatibility
//------------------------------------------------------------------------------------------------------

// For backwards compatibility (before Shadowmask was introduced)
void AdditionalLights_float(float3 SpecColor, float Smoothness, float3 WorldPosition, float3 WorldNormal, float3 WorldView, 
							out float3 Diffuse, out float3 Specular) {
AdditionalLights_float(SpecColor, Smoothness, WorldPosition, WorldNormal, WorldView, half4(1,1,1,1), Diffuse, Specular);
}

// (before Shadowmask was introduced)
void AdditionalLightsToon_float(float3 SpecColor, float Smoothness, float3 WorldPosition, float3 WorldNormal, float3 WorldView,
						float PointLightBands, float SpotLightBands,
						out float3 Diffuse, out float3 Specular) {
AdditionalLightsToon_float(SpecColor, Smoothness, WorldPosition, WorldNormal, WorldView, half4(1,1,1,1),
	PointLightBands, SpotLightBands,Diffuse, Specular);
}

/*
- Adds fog to the input colour, based on the Fog settings in the Lighting tab
- Would usually be connected just before Base Color output in graph
- Not required for v12+, can use Lerp instead. See "Mix Fog" SubGraph
*/
void MixFog_float(float3 Colour, float Fog, out float3 Out){
	#ifdef SHADERGRAPH_PREVIEW
		Out = Colour;
	#else
		Out = MixFog(Colour, Fog);
	#endif
}

/*
- Uses "SampleSH", the spherical harmonic stuff that ambient lighting / light probes uses
- But should use the built-in "Baked GI" node over this function, that handles this and more (including the new Adaptive Probe Volumes, with the appropiate keywords : https://github.com/Cyanilux/URP_ShaderGraphCustomLighting/issues/27)
*/
void AmbientSampleSH_float(float3 WorldNormal, out float3 Ambient){
	#ifdef SHADERGRAPH_PREVIEW
		Ambient = float3(0.1, 0.1, 0.1); // Default ambient colour for previews
	#else
		Ambient = SampleSH(WorldNormal);
	#endif
}

#endif // CUSTOM_LIGHTING_INCLUDED
