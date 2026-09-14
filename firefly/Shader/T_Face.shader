Shader "Unlit/T_Face"
{
	Properties
	{
		_BaseColor("Base Color" , 2D) = "white"{}
		_Color("Color Tint" , Color) = (1,1,1,1)
		_SDFMap("SDF Map" , 2D) = "white"{}
		//环境光
		_AmbientIntensity("Ambient Intensity" , Range(0,1)) = 0.5
		_AOIntensity("AO Intensity" , Range(0,1)) = 0.5
		_Brightness("Brightness" , Range(0,20)) = 1.0
		//漫反射
		_HeadForwardDir("Head ForwardDir" , Vector) = (1,1,1)
		_HeadRightDir("Head RightDir" , Vector) = (1,1,1)
		_HeadUpDir("Head UpDir" , Vector) = (1,1,1)
		//描边
		_OutLineWidth("OutLine Width" , Range(0,1)) = 0.5
		_OutLineColor("OutLine Color Tint" , Color) = (0,0,0,1)
		[Toggle(USE_OLWVWD)] _OLWVWD("Scale outline width with distance?" , Float) = 0 
		_NoseOutLineWidth("Nose OutLine Width" , Range(0,0.5)) = 0.5
	}

	SubShader
	{
		Tags{"RenderPipeline" = "UniversalPipeline" "RenderType" = "Opauqe"}

		Pass
		{
			Tags{"LightMode" = "UniversalForward"}

			Stencil
			{
				Ref 0
				Comp Always
				Pass Replace
			}

			Cull Back

			HLSLPROGRAM

			#pragma vertex vert
			#pragma fragment frag
			// 主光源及阴影
			#pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
			// 多光源及阴影
			#pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
			#pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS

			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

			CBUFFER_START(UnityPerMaterial)
				TEXTURE2D(_BaseColor);
				SAMPLER(sampler_BaseColor);
				TEXTURE2D(_SDFMap);
				SAMPLER(sampler_SDFMap);
				half4 _Color;
				half _AmbientIntensity;
				half _AOIntensity;
				half _Brightness;
				half3 _HeadForwardDir;
				half3 _HeadRightDir;
				half3 _HeadUpDir;
				half _NoseOutLineWidth;
			CBUFFER_END

			struct a2v
			{
				float4 vertex : POSITION;
				float2 texcoord : TEXCOORD0;
				float3 normal : NORMAL;
			};

			struct v2f
			{
				float4 pos : SV_POSITION;
				float2 uv : TEXCOORD0;
				float3 WS_Normal : TEXCOORD1;
				float3 ModifyLightDir : TEXCOORD2;
				float3 WS_LightDir : TEXCOORD3;
				float3 WS_ViewDir : TEXCOORD4;
				float3 mainLightColor : TEXCOORD5;
				float3 WS_Position : TEXCOORD6;
			};

			v2f vert(a2v v)
			{
				v2f o;
				o.pos = TransformObjectToHClip(v.vertex);
				o.WS_Normal = TransformObjectToWorldNormal(v.normal);
				Light mainLight = GetMainLight();
				float3 LightDir = TransformObjectToWorldDir(mainLight.direction);
				float3 ProjectLightDir = dot(LightDir,_HeadUpDir) * _HeadUpDir;
				o.ModifyLightDir = LightDir - ProjectLightDir;
				o.WS_LightDir = LightDir;
				float3 WS_VertexPos = TransformObjectToWorld(v.vertex.xyz);
				o.WS_ViewDir = _WorldSpaceCameraPos.xyz - WS_VertexPos;
				o.WS_Position = WS_VertexPos;

				o.uv = v.texcoord;
				o.mainLightColor = mainLight.color.rgb;

				return o;
			}

			half CalculateFaceSDFShadow(half3 WS_LightDir,half2 uv,out half3 DebugColor)
			{
				half2 SDFUV = half2(sign(dot(WS_LightDir,_HeadRightDir)),1) * uv * half2(-1,1);
				half SDFAlphaColor = SAMPLE_TEXTURE2D(_SDFMap,sampler_SDFMap,SDFUV).a;
				half ShadowThreshold = 1 - (dot(_HeadForwardDir,WS_LightDir) * 0.5 + 0.5);
				half SDFColor = step(ShadowThreshold,SDFAlphaColor) + 0.5;

				DebugColor = half3(SDFColor,SDFColor,SDFColor);
				return SDFColor;
			}

			half3 CalculateAmbientColor(half3 TexColor , half3 WS_Normal , half FaceSDFShadow , half2 SDFColorRG,out half3 DebugColor)
			{
				half4 NormalScale = lerp(half4(WS_Normal,1) , half4(1,1,1,1) , _AmbientIntensity);
				half3 SHColor = SampleSH(NormalScale);
				//分离五官
				half SDFColorG = lerp(SDFColorRG.g , FaceSDFShadow , step(SDFColorRG.r,0.5));
				DebugColor = half3(SHColor);
				half AO = lerp(1.0,SDFColorG,_AOIntensity);
				half3 ambient = TexColor * SHColor * _Brightness * AO;
				//DebugColor = half3(ambient);
				return ambient;
			}

			half CalculateNoseOutLine(half SDFColorB, half3 WS_ViewDir, out half3 DebugColor)
			{
				//DebugColor = half3(SDFColorB,SDFColorB,SDFColorB);
				half ViewDotForward = 1.0 - (dot(WS_ViewDir,_HeadForwardDir) * 0.5 + 0.5);
				half OutLineWidth = step(ViewDotForward + _NoseOutLineWidth,SDFColorB);
				OutLineWidth = 1.0 - OutLineWidth;
				DebugColor = half3(OutLineWidth,OutLineWidth,OutLineWidth);
				return OutLineWidth;
			}

			half4 frag(v2f i):SV_Target
			{
				half3 WS_Normal = normalize(i.WS_Normal);
				half3 WS_LightDir = normalize(i.WS_LightDir);
				half3 ModifyLightDir = normalize(i.ModifyLightDir);
				half3 WS_ViewDir = normalize(i.WS_ViewDir);

				half3 LightColor = i.mainLightColor;

				#if defined(_ADDITIONAL_LIGHTS)
				uint PixelLightingCount = GetAdditionalLightsCount();

				for(uint lightIndex = 0; lightIndex < PixelLightingCount; ++lightIndex)
				{
					// 获取当前光源数据
					Light light = GetAdditionalLight(lightIndex, i.WS_Position, half4(1,1,1,1));
					
					half3 addLight = light.color * light.distanceAttenuation * light.shadowAttenuation;
					//sFinalDiffuse += CalculateDiffuseColor(WS_Normal,light.direction,DebugColor) * addLight;
					LightColor += addLight;
				}

				#endif

				half3 TexColor = SAMPLE_TEXTURE2D(_BaseColor,sampler_BaseColor,i.uv) * LightColor;
				half3 SDFColor = SAMPLE_TEXTURE2D(_SDFMap,sampler_SDFMap,i.uv);
				half3 DebugColor = half3(1,1,1);
				half FaceSDFShadow = CalculateFaceSDFShadow(WS_LightDir,i.uv,DebugColor);
				half3 ambient = CalculateAmbientColor(TexColor,WS_Normal,FaceSDFShadow,SDFColor.rg,DebugColor);
				half NoesOutLine = CalculateNoseOutLine(SDFColor.b,WS_ViewDir,DebugColor);
				half3 FinalColor = TexColor * ambient * _Color * NoesOutLine;
				return half4(FinalColor,1.0);
			}

			ENDHLSL
		}

		Pass
		{
			Name "DepthNomals"

			Tags{"LightMode" = "DepthNormals"}

			ZWrite On
			Cull [_Cull]

			HLSLPROGRAM

			#pragma vertex DepthNormalsVertex
			#pragma fragment DepthNormalsFragment
			#pragma target 2.0

			#include "Packages/com.unity.render-pipelines.universal/Shaders/LitDepthNormalsPass.hlsl"

			ENDHLSL
		}

		UsePass "Unlit/T_Body/OutLinePass"
		Pass
		{
			Name "ShadowCaster"
			Tags{"LightMode" = "ShadowCaster"}

			ZWrite On
			ZTest LEqual
			ColorMask 0
			Cull Back

			HLSLPROGRAM

			#pragma target 2.0
			#pragma vertex ShadowPassVertex
			#pragma fragment ShadowPassFragment
			#pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"

			ENDHLSL
		}
	}
	FallBack "Packages/com.unity.render-pipelines.universal/FallbackError"
}
