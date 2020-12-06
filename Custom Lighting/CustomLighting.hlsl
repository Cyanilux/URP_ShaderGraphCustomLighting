#ifndef CUSTOM_LIGHTING_INCLUDED
#define CUSTOM_LIGHTING_INCLUDED

// @Cyanilux | https://github.com/Cyanilux/URP_ShaderGraphCustomLighting

//------------------------------------------------------------------------------------------------------
// Main Light
//------------------------------------------------------------------------------------------------------

/*
- Obtains the Direction, Color and Distance Atten for the Main Light.
- (DistanceAtten is either 0 or 1 for directional light, depending if the light is in the culling mask or not)
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
- Samples the Shadowmap for the Main Light, based on the World Position passed in. (Position node)
- Bypasses need for MAIN_LIGHT_CALCULATE_SHADOWS / _MAIN_LIGHT_SHADOWS, so will work with Unlit.
- Note it can kinda break/glitch if no shadows are cast on the object.
- To correctly support shadow cascades and soft shadow options, this should be used with the keywords :
	- Boolean Keyword "_MAIN_LIGHT_SHADOWS_CASCADE", Global Multi-Compile
	- Boolean Keyword "_SHADOWS_SOFT", Global Multi-Compile
*/
void MainLightShadows_float (float3 WorldPos, out float ShadowAtten){
	#ifdef SHADERGRAPH_PREVIEW
		ShadowAtten = 1;
	#else
		float4 shadowCoord = TransformWorldToShadowCoord(WorldPos);
		
		ShadowSamplingData shadowSamplingData = GetMainLightShadowSamplingData();
		half4 shadowParams = GetMainLightShadowParams();
		ShadowAtten = SampleShadowmap(TEXTURE2D_ARGS(_MainLightShadowmapTexture, sampler_MainLightShadowmapTexture),
							shadowCoord, shadowSamplingData, shadowParams, false);
	#endif
}

//------------------------------------------------------------------------------------------------------
// Ambient Lighting
//------------------------------------------------------------------------------------------------------

/*
- Uses "SampleSH", the spherical harmonic stuff that ambient lighting uses.
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
- For custom lighting, you'd want to duplicate this and swap the LightingLambert / LightingSpecular functions out.
- See Toon Example below!
- For shadows to work in the Unlit Graph, add the Boolean Keyword "_ADDITIONAL_LIGHT_SHADOWS", Global Multi-Compile.
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
       Light light = GetAdditionalLight(i, WorldPosition);
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
		Light light = GetAdditionalLight(i, WorldPosition);

		// DIFFUSE
		diffuseColor += light.color * (0.5 + step(0.5, light.distanceAttenuation)) * step(0.1, light.distanceAttenuation * light.shadowAttenuation);
		
		/* (LightingLambert)
		half NdotL = saturate(dot(normal, lightDir));
		diffuseColor += lightColor * NdotL;
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