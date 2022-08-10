# Shader Graph Custom Lighting
Some custom lighting functions/sub-graphs for Shader Graph, Universal Render Pipeline. If anything breaks, let me know by opening an issue!

```diff
+ This version is for URP v12+ (Unity 2021.2+) For use with older versions use the v8 branch!
```

### Setup:
- Install via Package Manager → Add package via git URL : 
  - `https://github.com/Cyanilux/URP_ShaderGraphCustomLighting.git`
- Alternatively, download and put the folder in your Assets

### Includes Sub Graphs for :
- **Main Light**
  - Outputs : Direction (Vector3), Colour (Vector4), Distance Atten (Float)
- **Main Light Shadows**
  - Inputs : World Position (Vector3), Shadowmask (Vector4) (Can leave at 1,1,1,1 if you don't need it)
  - Outputs : Shadow Atten (Float)
  - (Now works with all Shadow Cascades settings!)
- **Sample Shadowmask** (attach this to the Shadowmask port on the Main Light Shadows and Additional Lights sub graphs, in order to support Shadowmask baked lighting mode)
  - Outputs : Shadowmask (Vector4)
- **Ambient** (uses per-pixel SampleSH, use add node to apply this. Alternatively use the Baked GI node instead of this one)
  - Inputs : Normal (Vector3)
  - Outputs : Ambient (Vector3)
- **Mix Fog** (applies fog to the colour, should be used just before outputting colour to master)
  - Inputs : Colour (Vector3)
  - Outputs : Out (Vector3, Colour with fog applied)
- **Additional Lights** (Loops through each additional light, point, spotlights, etc, Handling diffuse, specular and shadows. For custom lighting models, you'll need to copy this function and edit it due to the loop, e.g. swap the LightingLambert and LightingSpecular functions out for custom ones. Also see the AdditionalLightsToon function as an example)
  - Inputs : Spec Colour (Vector3), Smoothness (Float), Normal (Vector3), Shadowmask (Vector4)
  - Outputs : Diffuse (Vector3), Specular (Vector3)
- **Blinn-Phong Specular** (handles specular lighting using the [Blinn-Phong model](https://en.wikipedia.org/wiki/Blinn%E2%80%93Phong_reflection_model). Note the Specular result should be multiplied by the main light distance atten and colour. This isn't done inside the sub graph in order to allow the specular result to be edited, e.g. using a ramp texture like in the toon example)
  - Inputs : Smoothness (Float), Normal (Vector3)
  - Outputs : Specular (Float), Light Colour (Vector3), Distance Atten (Float),
- **Phong Specular** (same as above, but uses the less efficient [Phong model](https://en.wikipedia.org/wiki/Phong_reflection_model)).
  - Inputs : Smoothness (Float), Normal (Vector3)
  - Outputs : Specular (Float), Light Colour (Vector3), Distance Atten (Float)

Included Examples :
- **Toon (Main Light & Additional Lights)**
- **Shadow Receiver** (Transparent object that receives shadows and can set their colour. Can turn off casting via Mesh Renderer)
