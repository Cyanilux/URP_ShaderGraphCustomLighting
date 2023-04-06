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

#### Main Light
- `Main Light`
  - Outputs : Direction, Colour, CullingMask
- `Main Light Shadows`
  - Inputs : WorldPosition, Shadowmask (can leave at 1,1,1,1 if you don't need it)
  - Outputs : ShadowAtten
  - (Now works with all Shadow Cascades settings!)
- `Main Light Cookie`- For supporting cookies. Will also enable cookies for additional lights (as they use the same keyword)
  - Inputs : WorldPosition
  - Outputs : Cookie
- `Main Light Layer Test` - For supporting Light Layers. Pass your shading calculation from main light through here.
  - Inputs : Shading
  - Output : Out (with layer mask applied)
- `Main Light Diffuse` (handles Lambert / NdotL calculation)
  - Inputs : Normal
  - Outputs : Diffuse
- `Main Light Specular Highlights` - handles specular highlights based on [Phong](https://en.wikipedia.org/wiki/Phong_reflection_model) or [BlinnPhong](https://en.wikipedia.org/wiki/Blinn%E2%80%93Phong_reflection_model) models
  - Inputs : Smoothness, Normal
  - Outputs : Specular

#### Other
- `Additional Lights` - Loops through each additional light, point, spotlights, etc. Handles diffuse, specular and shadows. Supports Forward+ path (in 2022.2+)
  - Also supports cookies if `Main Light Cookie` node is used (or `_LIGHT_COOKIES` Boolean Keyword is defined in Blackboard)
  - Also supports light layers if `Main Light Layer Test` node is used (or `_LIGHT_LAYERS` Boolean Keyword is defined in Blackboard)
  - For creating custom lighting models, you'll need to copy this function and edit it due to the loop, e.g. swap the LightingLambert and LightingSpecular functions out for custom ones. Also see the AdditionalLightsToon function as an example
  - Inputs : SpecularColour, Smoothness, Normal, Shadowmask
  - Outputs : Diffuse, Specular
- `Sample Shadowmask` - attach this to the Shadowmask port on the Main Light Shadows and Additional Lights sub graphs, in order to support Shadowmask baked lighting mode
  - Outputs : Shadowmask
- `Ambient SampleSH` - uses per-pixel SampleSH, use add node to apply this. Can alternatively use the built-in Baked GI node)
  - Inputs : Normal
  - Outputs : Ambient
- `Subtractive GI` - for supporting Subtractive baked lighting mode. Should connect Main Light Shadows node to first port. Uses MixRealtimeAndBakedGI function from URP ShaderLibrary
  - Inputs : ShadowAtten, Normal, BakedGI
  - Outputs : Out (Vector3)
- `Mix Fog` - applies fog to the colour, should be used just before outputting to BaseColor on Master Stack
  - Inputs : Colour
  - Outputs : Out (Vector3, colour with fog applied)
  
#### Deprecated
- `Phong Specular` and `Blinn-Phong Specular` subgraphs are now considered deprecated - use `Main Light Specular Highlights` instead.

### Included Examples
- **Toon** -  Toon/Cel Shading. Main Light (ramp texture) & Additional Lights (number of bands). Also supports Main Light Cookies, BakedGI (including Subtractive & Shadowmask), Fog
- **Shadow Receiver** - Transparent material that receives shadows and can set their colour. Can turn off casting via Mesh Renderer
