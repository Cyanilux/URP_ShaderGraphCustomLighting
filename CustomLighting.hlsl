#ifndef CUSTOM_LIGHTING_INCLUDED
#define CUSTOM_LIGHTING_INCLUDED

// @Cyanilux | https://github.com/Cyanilux/URP_ShaderGraphCustomLighting

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
// Main Light Shadows
//------------------------------------------------------------------------------------------------------

/*
- This undef (un-define) is required to prevent the "invalid subscript 'shadowCoord'" error,
  which occurs when _MAIN_LIGHT_SHADOWS is used with 1/No Shadow Cascades with the Unlit Graph.
- It's technically not required for the PBR/Lit graph, so I'm using the SHADERPASS_FORWARD to ignore it for the pass.
  (But it would probably still remove the interpolator for other passes in the PBR/Lit graph and use a per-pixel version)
*/
#ifndef SHADERGRAPH_PREVIEW
	#if VERSION_GREATER_EQUAL(9, 0)
		#include "Packages/com.unity.render-pipelines.universal/Editor/ShaderGraph/Includes/ShaderPass.hlsl"
		#if (SHADERPASS != SHADERPASS_FORWARD)
			#undef REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR
		#endif
	#else
		#ifndef SHADERPASS_FORWARD
			#undef REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR
		#endif
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
void MainLightShadows_float (float3 WorldPos, out float ShadowAtten){
	#ifdef SHADERGRAPH_PREVIEW
		ShadowAtten = 1;
	#else
		float4 shadowCoord = TransformWorldToShadowCoord(WorldPos);
		
		#if VERSION_GREATER_EQUAL(10, 1)
			ShadowAtten = MainLightShadow(shadowCoord, WorldPos, half4(1,1,1,1), _MainLightOcclusionProbes);
		#else
			ShadowAtten = MainLightRealtimeShadow(shadowCoord);
		#endif

		/*
		- Used to use this, but while it works in editor it doesn't work in builds. :(
		- Bypasses need for _MAIN_LIGHT_SHADOWS (/MAIN_LIGHT_CALCULATE_SHADOWS), so won't error in an Unlit Graph even at no/1 cascades.
		- Note it can kinda break/glitch if no shadows are cast on the screen.

		ShadowSamplingData shadowSamplingData = GetMainLightShadowSamplingData();
		half4 shadowParams = GetMainLightShadowParams();
		ShadowAtten = SampleShadowmap(TEXTURE2D_ARGS(_MainLightShadowmapTexture, sampler_MainLightShadowmapTexture),
							shadowCoord, shadowSamplingData, shadowParams, false);
		*/
	#endif
}

/*
To Do / Notes
- Currently this method only supports realtime shadows, but there's also baked shadows to look into (shadow masks, introduced in v10). 

- Haven't looked much into URPv11/12+ yet, but they've also changed how the keywords are defined (looking at master branch of Graphics github)
  Rather than a Boolean Keyword, it's an Enum Keyword with 4 modes (off, shadows, cascades and screen). Something to be aware of.
     #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
- Supporting screen would need the clip space position passed in :
	- float4 shadowCoord = ComputeScreenPos(positionCS);
	- Ideally, it would also be handled in vertex shader and passed through fragment, that's not something we can do in shader graph yet though.
- When newer versions are out of beta I might try looking into updating this.
*/

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
void AdditionalLights_float(float3 SpecColor, float Smoothness, float3 WorldPosition, float3 WorldNormal, float3 WorldView,
							out float3 Diffuse, out float3 Specular) {
   float3 diffuseColor = 0;
   float3 specularColor = 0;

#ifndef SHADERGRAPH_PREVIEW
   Smoothness = exp2(10 * Smoothness + 1);
   WorldNormal = normalize(WorldNormal);
   WorldView = SafeNormalize(WorldView);
   int pixelLightCount = GetAdditionalLightsCount();
   for (int i = 0; i < pixelLightCount; ++i) {
		#if VERSION_GREATER_EQUAL(10, 1)
			Light light = GetAdditionalLight(i, WorldPosition, half4(1,1,1,1));
			/*
			URP v10.1.0 introduced an additional shadowMask parameter, which is required for additional lights to do shadow calculations.
			The purpose of this is to support the ShadowMask baked lighting mode.
			The "correct" way to support it is to use :
			   inputData.shadowMask = SAMPLE_SHADOWMASK(input.lightmapUV);
			inside the fragment shader. lightmapUV is TEXCOORD1 input passed through vert->frag
			It would also need the SHADOWS_SHADOWMASK keyword to be defined if using an Unlit Graph. (maybe also LIGHTMAP_SHADOW_MIXING)
			Since this should only be sampled once, it should likely be a separate node and passed in.
			For now, I'm ignoring support for ShadowMask, and just using half4(1,1,1,1)
			*/
		#else
			Light light = GetAdditionalLight(i, WorldPosition);
		#endif

       float3 attenuatedLightColor = light.color * (light.distanceAttenuation * light.shadowAttenuation);
       diffuseColor += LightingLambert(attenuatedLightColor, light.direction, WorldNormal);
       specularColor += LightingSpecular(attenuatedLightColor, light.direction, WorldNormal, WorldView, float4(SpecColor, 0), Smoothness);
   }
#endif

   Diffuse = diffuseColor;
   Specular = specularColor;
}

//------------------------------------------------------------------------------------------------------
// Additional Lights Toon Example
//------------------------------------------------------------------------------------------------------

/*
- Obtains the DistanceSqr and Range of Additional Light
- Is an alternative to produce multiple bands rather than solid colour. See AdditionalLightsToon function below
*/
/*
#ifndef SHADERGRAPH_PREVIEW
void GetAdditionalLightDistanceSqrRange(int i, float3 positionWS, out float distanceSqr, out float range){
	int perObjectLightIndex = GetPerObjectLightIndex(i); // (i = index used in loop)
	#if USE_STRUCTURED_BUFFER_FOR_LIGHT_DATA
		float4 lightPositionWS = _AdditionalLightsBuffer[perObjectLightIndex].position;
		half4 distanceAndSpotAttenuation = _AdditionalLightsBuffer[perObjectLightIndex].attenuation;
	#else
		float4 lightPositionWS = _AdditionalLightsPosition[perObjectLightIndex];
		half4 distanceAndSpotAttenuation = _AdditionalLightsAttenuation[perObjectLightIndex];
	#endif

	float3 lightVector = lightPositionWS.xyz - positionWS * lightPositionWS.w;
	distanceSqr = max(dot(lightVector, lightVector), HALF_MIN);
	range = rsqrt(distanceAndSpotAttenuation.x);
}
#endif
*/

void AdditionalLightsToon_float(float3 SpecColor, float Smoothness, float3 WorldPosition, float3 WorldNormal, float3 WorldView,
							out float3 Diffuse, out float3 Specular) {
	float3 diffuseColor = 0;
	float3 specularColor = 0;
	
#ifndef SHADERGRAPH_PREVIEW
	Smoothness = exp2(10 * Smoothness + 1);
	WorldNormal = normalize(WorldNormal);
	WorldView = SafeNormalize(WorldView);
	int pixelLightCount = GetAdditionalLightsCount();
	for (int i = 0; i < pixelLightCount; ++i) {
		#if VERSION_GREATER_EQUAL(10, 1)
			Light light = GetAdditionalLight(i, WorldPosition, half4(1,1,1,1));
			// see AdditionalLights_float for explanation of this
		#else
			Light light = GetAdditionalLight(i, WorldPosition);
		#endif
		
		// DIFFUSE
		/* (LightingLambert)
		half NdotL = saturate(dot(normal, lightDir));
		diffuseColor += lightColor * NdotL;
		*/
		
		// Toon / Solid colour lights
		diffuseColor += light.color * step(0.0001, light.distanceAttenuation * light.shadowAttenuation);
		
		// Multiple band alternatives :
		/*
		float atten = light.distanceAttenuation * light.shadowAttenuation;
		diffuseColor += light.color * (
			0.33 * step(0.1, atten) +
			0.33 * step(0.03, atten) +
			0.33 * step(0.0001, atten)
		);
		*/
		// The above doesn't work great when changing light range though, another alternative that fixes this :
		/*
		float distanceSqr, range;
		GetAdditionalLightDistanceSqrRange(i, WorldPosition, distanceSqr, range); // also uncomment function above
		float Steps = 3;
		diffuseColor += light.color * light.shadowAttenuation * saturate(1.0 - floor(sqrt(distanceSqr) / range * Steps) * (1.0 / Steps));
		*/
		
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

//------------------------------------------------------------------------------------------------------
// Older functions below, I'd use the ones above instead! Have to keep these around since I still have some graphs using them! :D
//------------------------------------------------------------------------------------------------------

void MainLightFull_float (float3 WorldPos, out float3 Direction, out float3 Color, out float DistanceAtten, out float ShadowAtten){
	#ifdef SHADERGRAPH_PREVIEW
		Direction = normalize(float3(1,1,-0.4));
		Color = float4(1,1,1,1);
		DistanceAtten = 1;
		ShadowAtten = 1;
	#else
		float4 shadowCoord = TransformWorldToShadowCoord(WorldPos);
		Light mainLight = GetMainLight(shadowCoord);

		Direction = mainLight.direction;
		Color = mainLight.color;
		DistanceAtten = mainLight.distanceAttenuation;
		ShadowAtten = mainLight.shadowAttenuation;
	#endif
}

void MainLightFullAlternative_float (float3 WorldPos, out float3 Direction, out float3 Color, out float DistanceAtten, out float ShadowAtten){
	#ifdef SHADERGRAPH_PREVIEW
		Direction = normalize(float3(1,1,-0.4));
		Color = float4(1,1,1,1);
		DistanceAtten = 1;
		ShadowAtten = 1;
	#else
		Light mainLight = GetMainLight();
		Direction = mainLight.direction;
		Color = mainLight.color;
		DistanceAtten = mainLight.distanceAttenuation;

		float4 shadowCoord = TransformWorldToShadowCoord(WorldPos);

		// If cascades are needed for an Unlit Graph,
		// define the _MAIN_LIGHT_SHADOWS_CASCADE global multi_compile keyword in the graph and TransformWorldToShadowCoord will take care of it.
		// Could also hardcode as this, but not recommended :
		// half cascadeIndex = ComputeCascadeIndex(WorldPos);
		// float4 shadowCoord = mul(_MainLightWorldToShadow[cascadeIndex], float4(WorldPos, 1.0));

		ShadowSamplingData shadowSamplingData = GetMainLightShadowSamplingData();
		float shadowStrength = GetMainLightShadowStrength();
		ShadowAtten = SampleShadowmap(shadowCoord, TEXTURE2D_ARGS(_MainLightShadowmapTexture, sampler_MainLightShadowmapTexture), shadowSamplingData, shadowStrength, false);
	
		// If soft shadows are needed for Unlit,
		// define the _SHADOWS_SOFT global multi_compile keyword and SampleShadowmap will take care of it.
		// hardcoding that is again probably possible but less flexible so don't recommend,
		// see the SampleShadowmap function in URP's ShaderLibrary, Shadows.hlsl though
	#endif
}

#endif // CUSTOM_LIGHTING_INCLUDED
