Shader "Unlit/T_Body"
{
	Properties
	{
		_BaseColor("Base Color" , 2D) = "white"{}
		[Toggle(USE_BODY_LIGHTMAP)] _UseBodyLightMap("Use Body LightMap" , Float) = 0.0
		_BodyLightMap("Body LightMap" , 2D) = "white"{}
		[Toggle(USE_HAIR_LIGHTMAP)] _UseHairLightMap("Use Hair LightMap" , Float) = 0.0
		_HairLightMap("Hair LightMap" , 2D) = "white"{}
		//环境光
		_AmbientIntensity("Ambient Intensity" , Range(0,1)) = 0.5
		_AOIntensity("AO Intensity" , Range(0,1)) = 0.5
		_Brightness("Brightness" , Range(0,20)) = 1.0
		_Color("Color Tint" , Color) = (1,1,1,1)
		//漫反射
		_ShadowCenterThreshold("Shadow Center Threshould" , Range(0,1)) = 0.5
		_ShadowSoftThreshould("Shadow Soft Threshould" , Range(0,1)) = 0.5
		_RampMap("Ramp Map" , 2D) = "white"{}
		_ShadowOffset("Shadow Offset" , Range(0,1)) = 0.5
		//高光
		_Specular("Specular Color Tint" , Color) = (1,1,1,1)
		_Gloss("Gloss" , Range(0,128)) = 20
		_SpecularIntensity("Specular Intensity" , Range(0,100)) = 1
		//边缘光
		_RimWidth("Rim Width" , Range(0,1)) = 0.5
		_RimColor("Rim Color Tint" , Color) = (1,1,1,1)
		_RimIntensity("Rim Intensity" , Range(0,1)) = 1.0
		_RimThreshould("Rim Threshould" , Range(0,1)) = 1.0
		//描边
		_OutLineWidth("OutLine Width" , Range(0,10)) = 0.5
		_OutLineColor("OutLine Color Tint" , Color) = (0,0,0,1)
		[Toggle(USE_OLWVWD)] _OLWVWD("Scale outline width with distance?" , Float) = 0 

		//测试参数
		_testThreshould("test" ,Range(0,1)) = 0
	}

	SubShader
	{
		Tags{"RenderPipeline" = "UniversalPipeline" "RenderType" = "Opauqe"}

		Pass
		{
			Tags{"LightMode" = "UniversalForward"}

			Stencil
			{
				Ref 1
				Comp Always
				Pass Replace
			}

			Cull Back

			HLSLPROGRAM

			#pragma vertex vert
			#pragma fragment frag
			#pragma shader_feature USE_BODY_LIGHTMAP
			#pragma shader_feature USE_HAIR_LIGHTMAP
			// 主光源及阴影
			#pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
			// 多光源及阴影
			#pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
			#pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS

			#define RAMPAMOUNT 8.0

			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

			CBUFFER_START(UnityPerMaterial)
				TEXTURE2D(_BaseColor);
				SAMPLER(sampler_BaseColor);
				#ifdef USE_BODY_LIGHTMAP
					TEXTURE2D(_BodyLightMap);
					SAMPLER(sampler_BodyLightMap);
				#endif
				#ifdef USE_HAIR_LIGHTMAP
					TEXTURE2D(_HairLightMap);
					SAMPLER(sampler_HairLightMap);
				#endif
				half _AmbientIntensity;
				half _AOIntensity;
				half4 _Color;
				half _Brightness;
				half _ShadowCenterThreshold;
				half _ShadowSoftThreshould;
				TEXTURE2D(_RampMap);
				SAMPLER(sampler_RampMap);
				half _ShadowOffset;
				half4 _Specular;
				half _Gloss;
				half _SpecularIntensity;
				half _RimWidth;
				half4 _RimColor;
				half _RimIntensity;
				half _RimThreshould;

				half _testThreshould;
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
				float3 WS_Position : TEXCOORD2;
				float3 WS_ViewDir : TEXCOORD3;
				float3 VS_Normal : TEXCOORD4;
			};

			v2f vert(a2v v)
			{
				v2f o;
				o.pos = TransformObjectToHClip(v.vertex);
				o.WS_Normal = TransformObjectToWorldNormal(v.normal);
				o.WS_Position = TransformObjectToWorld(v.vertex).xyz;
				o.WS_ViewDir = _WorldSpaceCameraPos.xyz - o.WS_Position.xyz;
				o.VS_Normal = TransformWorldToViewDir(o.WS_Normal);
				o.uv = v.texcoord;
				return o;
			}

			half3 CalculateAmbientColor(half3 TexColor , half3 WS_Normal, half LightMapColorR)
			{
				half4 NormalScale = lerp(half4(WS_Normal,1.0) , half4(1,1,1,1) , _AmbientIntensity);
				half3 SHColor = SampleSH(NormalScale);
				half AOColor = lerp(1.0,LightMapColorR,_AOIntensity);
				half3 ambient = TexColor * SHColor * AOColor * _Brightness;
				return ambient;
			}

			half CalculateDiffuseColor(half3 WS_Normal,half3 WS_LightDir , out half3 DebugColor)
			{
				half HalfLambert = dot(WS_Normal,WS_LightDir) * 0.5 + 0.5;
				half ShadowSmooth = smoothstep(_ShadowSoftThreshould - _ShadowCenterThreshold,_ShadowSoftThreshould + _ShadowCenterThreshold,
					                           HalfLambert);

				DebugColor = half3(ShadowSmooth,ShadowSmooth,ShadowSmooth);
				return ShadowSmooth;
			}

			half3 CalculateRampShadowColor(half3 diffuse,half LightMapColorA,out half3 DebugColor)
			{
				int RampIndex = 0;
				//UV变化都集中在后面将阴影坐标往后偏移
				half2 RampUV = half2(0,0);
				RampUV.x = diffuse * (1 - _ShadowOffset) + _ShadowOffset;

				#ifdef USE_BODY_LIGHTMAP
					RampIndex = round(7.6516 * LightMapColorA + 0.5317);
					//重映射Ramp行数偶数行往后+4
					RampIndex = lerp(RampIndex + 4, RampIndex , fmod(RampIndex,2));
					RampUV.y = (2 * RampIndex - 1) * (1.0 / (2.0 * RAMPAMOUNT));
				#endif

				#ifdef USE_HAIR_LIGHTMAP
					RampUV.y = 0.0625;
				#endif

				half3 RampColor = SAMPLE_TEXTURE2D(_RampMap,sampler_RampMap,RampUV); 
				DebugColor = RampColor;
				return RampColor;
			}

			half3 CalculateSpecularColor(half3 WS_LightDir, half3 WS_Normal, half3 WS_ViewDir,half2 LightMapColorGB,out half3 DebugColor)
			{
				//这里计算高光的感光度，当光源照到的时候金属部分会先发光,看G通道的高光部分
				half NDotL = 1 - (dot(WS_Normal,WS_LightDir) * 0.5 + 0.5);
				half SpecularThreshould = step(NDotL,LightMapColorGB.r);
				
				half3 halfDir = normalize(WS_LightDir + WS_ViewDir);
				half3 Blinn_Phong = _Specular * pow(saturate(dot(WS_Normal,halfDir)),_Gloss);
				Blinn_Phong = smoothstep(0.01,0.02,Blinn_Phong);
				half HighArea = step(0.2 , LightMapColorGB.g);
				half3 HighLight = LightMapColorGB.g * Blinn_Phong * _SpecularIntensity * SpecularThreshould;

				DebugColor = half3(Blinn_Phong);
				return HighLight;
			}

			half CalculateRimLight(half3 VS_Normal , float3 ClipPos , out half3 DebugColor)
			{
				//偏移前的深度
				float SampleDepth = _CameraDepthTexture.Load(int3(ClipPos.xy,0));
				float LinearDepth = LinearEyeDepth(SampleDepth,_ZBufferParams);
				//计算偏移uv,先钳制偏移量，再应用方向就可防止表达式为0
				float2 OffsetUV = sign(VS_Normal.xy) * max(_RimWidth / (1 + LinearDepth) / 100,0.001);
				//偏移后的深度
				float2 OffsetClipPos = ClipPos.xy + OffsetUV * _ScaledScreenParams.xy;
				float OffsetSampleDepth = _CameraDepthTexture.Load(int3(OffsetClipPos.xy,0));
				float OffsetLinearDepth = LinearEyeDepth(OffsetSampleDepth,_ZBufferParams);
				//DebugColor = half3(OffsetLinearDepth,OffsetLinearDepth,OffsetLinearDepth);
				
				//计算边缘光
				float RimLight = saturate(OffsetLinearDepth - (LinearDepth + (_RimThreshould)));
				RimLight *= _RimColor * _RimIntensity;
				DebugColor = half3(RimLight,RimLight,RimLight);

				return RimLight;
			}

			half4 frag(v2f i):SV_Target
			{
				half3 DebugColor = half3(1,1,1);
				half3 WS_Normal = normalize(i.WS_Normal);
				half3 VS_Normal = normalize(i.VS_Normal);
				Light mainLight = GetMainLight();
				half3 WS_LightDir = mainLight.direction;
				//多光源处理
				half3 LightColor = mainLight.color.rgb * mainLight.distanceAttenuation * mainLight.shadowAttenuation;

				//主光漫反射
				half3 FinalDiffuse = CalculateDiffuseColor(WS_Normal,WS_LightDir,DebugColor) * LightColor;

				#if defined(_ADDITIONAL_LIGHTS)
				uint PixelLightingCount = GetAdditionalLightsCount();

				for(uint lightIndex = 0; lightIndex < PixelLightingCount; ++lightIndex)
				{
					// 获取当前光源数据
					Light light = GetAdditionalLight(lightIndex, i.WS_Position, half4(1,1,1,1));
					
					half3 addLight = light.color * light.distanceAttenuation * light.shadowAttenuation;
					FinalDiffuse += CalculateDiffuseColor(WS_Normal,light.direction,DebugColor) * addLight;
					LightColor += addLight;
				}

				#endif

				half3 WS_ViewDir = normalize(i.WS_ViewDir);
				half3 TexColor = SAMPLE_TEXTURE2D(_BaseColor,sampler_BaseColor,i.uv) * LightColor;

				half4 LightMapColor = half4(1,1,1,1);
				#ifdef USE_BODY_LIGHTMAP
					LightMapColor = SAMPLE_TEXTURE2D(_BodyLightMap,sampler_BodyLightMap,i.uv);
				#endif

				#ifdef USE_HAIR_LIGHTMAP
					LightMapColor = SAMPLE_TEXTURE2D(_HairLightMap,sampler_HairLightMap,i.uv);
				#endif

				half3 ambient = CalculateAmbientColor(TexColor,WS_Normal,LightMapColor.r);
				//half3 diffuse = CalculateDiffuseColor(WS_Normal,WS_LightDir,DebugColor);
				half3 RampColor = CalculateRampShadowColor(FinalDiffuse,LightMapColor.a,DebugColor);
				half3 specular = CalculateSpecularColor(WS_LightDir,WS_Normal,WS_ViewDir,LightMapColor.gb,DebugColor) * TexColor;
				half  RimLight = CalculateRimLight(VS_Normal,i.pos.xyz,DebugColor);

				half3 FinalColor = TexColor * ambient * RampColor + specular + RimLight;

				return half4(FinalColor,1.0);
			}

			ENDHLSL
		}

		//这个Pass用于描边
		Pass
		{
			Name "OutLinePass"
			Tags{"LightMode" = "SRPDefaultUnlit"}

			Cull Front

			HLSLPROGRAM

			#pragma vertex OutLineVert
			#pragma fragment OutLineFrag
			#pragma shader_feature USE_OLWVWD
			
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

			CBUFFER_START(UnityPerMaterial)
			    half4 _OutLineColor;
				half _OutLineWidth;
			CBUFFER_END

			struct a2v
			{
				float4 vertex : POSITION;
				float3 normal : NORMAL;
				float3 tangent : TANGENT;
				//float4 color : COLOR;
			};

			struct v2f
			{
				float4 pos : SV_POSITION;
				//float3 VertexColor : TEXCOORD0;
			};

			v2f OutLineVert(a2v v)
			{
				v2f o;
				o.pos = TransformObjectToHClip(v.vertex);
				float3 WS_Normal = TransformObjectToWorldNormal(v.tangent);
				float3 CS_Normal = TransformWorldToHClipDir(WS_Normal);
				//描边偏移方向
				float2 OutLineDir = sign(CS_Normal.xy) * _OutLineWidth * 0.01;
				//纠正描边xy不规则变化问题，比如16：9的屏幕变化会不对,
				float OutLineRatio = _ScaledScreenParams.y / _ScaledScreenParams.x;
				//当x移动1时y移动9/16
				OutLineDir.y /= OutLineRatio;

				//描边随距离变化,顶点着色器之后会做透视除法
				#if USE_OLWVWD
					o.pos.xy += OutLineDir;
				//描边不随距离变化,抵消掉之后的透视剔除
				#else
				    //float maxOutLineSize = clamp(1.0 / o.pos.w , 0.0, 1.0);
					//o.pos.xy += OutLineDir * o.pos.w * maxOutLineSize;
					o.pos.xy += OutLineDir * o.pos.w;
				#endif
				//o.VertexColor = v.color.rgb;

				return o;
			}

			half4 OutLineFrag(v2f i):SV_Target
			{
				return _OutLineColor;
				//return half4(i.VertexColor,1.0);
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
