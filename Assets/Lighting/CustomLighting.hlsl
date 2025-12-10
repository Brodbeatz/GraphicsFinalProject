#ifndef CUSTOM_LIGHTING_INCLUDED
#define CUSTOM_LIGHTING_INCLUDED

#ifndef SHADERGRAPH_PREVIEW
    #include "Packages/com.unity.render-pipelines.universal/Editor/ShaderGraph/Includes/ShaderPass.hlsl"
    #if (SHADERPASS != SHADERPASS_FORWARD)
        #undef REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR
    #endif
#endif

struct CustomLightingData
{
    
    //Position and orientation
    float3 positionWS;
    float3 normalWS;
    float3 viewDirectionWS;
    float4 shadowCoord;
    
    // Surface attributes
    float3 albedo;
    float smoothness;
    float ambientOcclusion;
    
    //Baked lighting
    float3 bakedGI;
};

float GetSmoothnessPower(float rawSmoothness)
{
    return exp2(10 * rawSmoothness + 1);

}

#ifndef SHADERGRAPH_PREVIEW

float CustomGlobalIllumination(CustomLightingData d)
{
    float3 indirectDiffuse = d.albedo * d.bakedGI * d.ambientOcclusion;
    
    return indirectDiffuse;
}

float3 CustomLightHandling(CustomLightingData d, Light light)
{
    float3 radiance = light.color * (light.distanceAttenuation * light.shadowAttenuation);
    
    float diffuse = saturate(dot(d.normalWS, light.direction));
    float specularDot = saturate(dot(d.normalWS, normalize(light.direction + d.viewDirectionWS)));
    float specular = pow(specularDot, GetSmoothnessPower(d.smoothness)) * diffuse;
    
    float3 color = d.albedo * radiance * (diffuse + specular);
    
    return color;

}
#endif

float3 CalculateCustomLighting(CustomLightingData d)
{
    #ifdef SHADERGRAPH_PREVIEW
    float3 lightDir = float3(0.5, 0.5, 0);
    float intensity = saturate(dot(d.normalWS, lightDir)) +
        pow(saturate(dot(d.normalWS, normalize(d.viewDirectionWS + lightDir))), 
        GetSmoothnessPower(d.smoothness));
    return d.albedo * intensity;
    #else
    Light mainLight = GetMainLight(d.shadowCoord, d.positionWS, 1);
    MixRealtimeAndBakedGI(mainLight, d.normalWS, d.bakedGI);
    float3 color = CustomGlobalIllumination(d);
    
    color += CustomLightHandling(d, mainLight);
    
    #ifdef _ADDITIONAL_LIGHTS
        // Shade additional cone and point lights. Functions in URP/ShaderLibrary/Lighting.hlsl
        uint numAdditionalLights = GetAdditionalLightsCount();
        for (uint lightI = 0; lightI < numAdditionalLights; lightI++) {
            Light light = GetAdditionalLight(lightI, d.positionWS, 1);
            color += CustomLightHandling(d, light);
        }
    #endif
    
    return color;
    #endif
}

void CalculateCustomLighting_float(float3 Position, float3 Normal, float3 ViewDirection, 
    float3 Albedo, float Smoothness, float AmbientOcclusion, float2 LightMapUV,
    out float3 Color)
{

    CustomLightingData d;
    d.positionWS = Position;
    d.normalWS = Normal;
    d.viewDirectionWS = ViewDirection;
    d.albedo = Albedo;
    d.smoothness = Smoothness;
    d.ambientOcclusion = AmbientOcclusion;
    
    #ifdef SHADERGRAPH_PREVIEW
        d.shadowCoord = 0;
        d.bakedGI = 0;
    #else
    float4 positionCS = TransformWorldToHClip(Position);
    #if SHADOW_SCREEN
        d.shadowCoord = ComputeScreenPos(positionCS);
    #else
        d.shadowCoord = TransformWorldToShadowCoord(Position);
    #endif
    float2 lightMapUV;
    OUTPUT_LIGHTMAP_UV(LightMapUV, unity_LightmapST, lightMapUV);
    
    float3 vertexSH;
    OUTPUT_SH(Normal, vertexSH);
    
    d.bakedGI = SAMPLE_GI(lightMapUV, vertexSH, Normal);
    #endif
    Color = CalculateCustomLighting(d);
}

#endif