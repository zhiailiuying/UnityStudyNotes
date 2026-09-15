Shader "Unlit/VolumeRay"
{
    Properties
    {
        _VolumeLightColor("Color Tint" , Color) = (1,1,1,1)
        _BlitTexture("Blit Texture" , 2D) = "white"{}
        _Intensity("Intensity" , Float) = 0
        _ScatterFactor("Scatter Factor" , Range(0,1)) = 0.05
        _ExtinctionFactor("Extinction Factor" , Range(0,1)) = 0.02
        _MieScatteringG("Mie Scattering G" , Range(0,0.99)) = 0.5
        _Density("Density" , Range(0,10)) = 1.0
        _RayMaxStep("Ray Max Step" , Range(1,64)) = 32
        _Speed("Partical Speed" , Range(0,1)) = 1
        _ParticalNoise("Partical Noise" , 2D) = "white"{}
    }

    SubShader
    {
        Tags{"RenderPipeline" = "UniversalPipeline" "RenderType" = "Opaque"}

        // ============ Pass 0: 体积光射线步进（主方向光） ============
        Pass
        {
            Name "VOLUME_RAY_MARCH"
            Tags{"LightMode" = "SRPDefaultUnlit"}

            ZTest Always ZWrite Off Cull Off

            HLSLPROGRAM

            // 与 URP ScreenSpaceShadows 全屏 Pass 保持一致的依赖顺序。
            // EntityLighting / ImageBasedLighting 是 Shadows.hlsl 的依赖，缺失会导致 Pass0 编译失败。
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/EntityLighting.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ImageBasedLighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            #pragma vertex vert
            #pragma fragment frag

            // 主光阴影关键词：是否级联 / 是否屏幕空间阴影，由 URP 全局关键词自动决定
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            // 软阴影质量关键词（与灯光的 Soft Shadows 设置对应）
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH

            #define _MIE_PI 3.14159265359f
            // 天空像素（无场景深度）的最大步进距离，让光束在天空 / 树叶缝隙中也能显示
            #define _MAX_MARCH_DISTANCE 60.0

            CBUFFER_START(UnityPerMaterial)
                half4 _VolumeLightColor;
                float3 _VolumeLightDir;
                float _Intensity;
                float _ScatterFactor;
                float _ExtinctionFactor;
                float _MieScatteringG;
                float _Density;
                int _RayMaxStep;
                half _Speed;
                TEXTURE2D(_ParticalNoise);
                SAMPLER(sampler_ParticalNoise);
            CBUFFER_END

            struct Attributes
            {
                uint vertexID : SV_VertexID;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
                output.uv = GetFullScreenTriangleTexCoord(input.vertexID);
                return output;
            }

            // Henyey-Greenstein 米氏散射相函数
            float MieScatterPhase(float cosAngle)
            {
                float g = _MieScatteringG;
                float g2 = g * g;
                float denom = 1.0 + g2 - 2.0 * g * cosAngle;
                return (1.0 - g2) / (_MIE_PI * 4.0 * pow(max(denom, 0.0001), 1.5));
            }

            half GetNoiseDensity(half2 uv)
            {
                half2 offset = half2(_Time.y * _Speed, _Time.y * _Speed);
                uv = half2(uv.x - offset.x,uv.y + offset.y) * 2.0;
                half noise = SAMPLE_TEXTURE2D(_ParticalNoise,sampler_ParticalNoise,uv);
                half density = 1.0;
                density *= noise;
                return density;
            }

            half4 frag(Varyings input) : SV_Target
            {
                float sceneRawDepth = SampleSceneDepth(input.uv);
                float sceneLinear01 = Linear01Depth(sceneRawDepth, _ZBufferParams);

                float3 worldPos = ComputeWorldSpacePosition(input.uv, sceneRawDepth, UNITY_MATRIX_I_VP);
                float3 rayStart = GetCameraPositionWS();

                float3 toScene = worldPos - rayStart;
                float toSceneLength = length(toScene);
                float3 rayDir = toScene / max(toSceneLength, 0.00001);

                // 场景像素：步进到表面；天空像素：步进固定距离，让光束在天空 / 缝隙中也能显示
                float rayLength = (sceneLinear01 >= 0.999) ? _MAX_MARCH_DISTANCE : toSceneLength;

                float stepSize = (rayLength / max(_RayMaxStep, 1));
                //float stepSize = AdaptiveStep;

                // 4x4 Bayer 抖动，减少条带伪影
                const float Dither[16] = {
                    0.0,  0.5,  0.125, 0.625,
                    0.75, 0.25, 0.875, 0.375,
                    0.187, 0.687, 0.0625, 0.562,
                    0.937, 0.437, 0.812, 0.312
                };
                float2 ditherUV = fmod(input.uv * _ScreenParams.xy, 4.0);
                float jitter = Dither[(int)ditherUV.x * 4 + (int)ditherUV.y];

                float3 currentPos = rayStart + rayDir * stepSize * jitter;

                // 指向主光源的方向（视线与它越接近，前向散射越强）
                float3 lightDir = normalize(_VolumeLightDir);
                float phase = MieScatterPhase(dot(lightDir, rayDir));

                float extinction = 0.0;
                float totalLight = 0.0;
                half density = GetNoiseDensity(input.uv) * _Density;

                [loop]
                for (int i = 0; i < _RayMaxStep; i++)
                {
                    // 主光阴影：主光不投影时该函数内部自动返回 1.0
                    float shadow = MainLightRealtimeShadow(TransformWorldToShadowCoord(currentPos));

                    // Beer-Lambert 定律：散射 + 消光衰减
                    float inscatter = _ScatterFactor * stepSize * density;
                    extinction += _ExtinctionFactor * stepSize * density;
                    float atten = inscatter * exp(-extinction) * phase * shadow;

                    totalLight += atten;
                    currentPos += rayDir * stepSize;
                }

                half3 lightColor = _VolumeLightColor.rgb * totalLight * _Intensity;
                return half4(lightColor, 1.0);
            }

            ENDHLSL
        }

        // ============ Pass 1: 加色混合到相机颜色 ============
        Pass
        {
            Name "VOLUME_COMPOSITE"
            Tags{"LightMode" = "SRPDefaultUnlit"}

            ZTest Always ZWrite Off Cull Off
            Blend SrcAlpha One

            HLSLPROGRAM

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            #pragma vertex vert
            #pragma fragment frag

            TEXTURE2D(_BlitTexture);
            SAMPLER(sampler_BlitTexture);

            struct Attributes
            {
                uint vertexID : SV_VertexID;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
                output.uv = GetFullScreenTriangleTexCoord(input.vertexID);
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                half3 light = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, input.uv).rgb;
                return half4(light, 1.0);
            }

            ENDHLSL
        }
    }
    FallBack "Packages/com.unity.render-pipelines.universal/FallBackError"
}
