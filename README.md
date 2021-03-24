# Shader Graph Custom Lighting
Some custom lighting functions/sub-graphs for Shader Graph, Universal Render Pipeline. v8.3.1, Unity 2020.1.17f1. Also should work in URP v10+ and v11, though doesn't support all features yet (e.g. baked shadows)
If anything breaks, let me know by opening an issue!

You can install the functions/subgraphs as a unity package using the Package Manager window, Add Package from Git URL : https://github.com/Cyanilux/URP_ShaderGraphCustomLighting.git, or download manually and add the folder to your Assets.

Includes Sub Graphs for :
- **Main Light**
  - Outputs : Direction (Vector3), Colour (Vector4), Distance Atten (Vector1/Float)
- **Main Light Shadows**
  - Inputs : World Position (Vector3)
  - Outputs : Shadow Atten (Vector1)
  - (Now works with all Shadow Cascades settings!)
- **Ambient** (uses per-pixel SampleSH, use add node to apply this. Alternatively use the Baked GI node instead of this one)
  - Outputs : Ambient (Vector3)
- **Mix Fog** (applies fog to the colour, should be used just before outputting colour to master)
  - Inputs : Colour (Vector3)
  - Outputs : Out (Vector3, Colour with fog applied)
- **Additional Lights** (Loops through each additional light, point, spotlights, etc, Handling diffuse, specular and shadows. For custom lighting models, you'll need to copy this function and edit it due to the loop, e.g. swap the LightingLambert and LightingSpecular functions out for custom ones. Also see the AdditionalLightsToon function as an example)
  - Inputs : Spec Colour (Vector3), Smoothness (Vector1)
  - Outputs : Diffuse (Vector3), Specular (Vector3)
- **Blinn-Phong Specular** (handles specular lighting using the [Blinn-Phong model](https://en.wikipedia.org/wiki/Blinn%E2%80%93Phong_reflection_model). Note the Specular result should be multiplied by the main light distance atten and colour. This isn't done inside the sub graph in order to allow the specular result to be edited, e.g. using a ramp texture like in the toon example)
  - Inputs : Smoothness (Vector1)
  - Outputs : Specular (Vector1), Light Colour (Vector3), Distance Atten (Vector1),
- **Phong Specular** (same as above, but uses the less efficient [Phong model](https://en.wikipedia.org/wiki/Phong_reflection_model)).
  - Inputs : Smoothness (Vector1)
  - Outputs : Specular (Vector1), Light Colour (Vector3), Distance Atten (Vector1)

Included Examples :
- **Toon (Main Light & optional Additional Lights)**
- **Shadow Receiver** (Transparent object that receives shadows and can set their colour. Can turn off casting via Mesh Renderer)
