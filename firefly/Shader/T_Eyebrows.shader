Shader "Unlit/T_Eyebrows"
{
    Properties
	{
		_OccludeColor("Color Tint" , Color) = (1,1,1,1)
		_MainTex("Base Color" , 2D) = "white"{}
		_EyeAlpha("Eye Alpha" , Range(0,1)) = 0.5
		_HeadForwardDir("Head ForwardDir" , Vector) = (1,1,1)
		_Emission("Emission" , Range(0,10)) = 1.0
	}

	SubShader
	{
		Tags{"RenderPipeline" = "UniversalRenderPipeline" "RenderType" = "Transparent" "Queue" = "Transparent+10"}

		Pass
		{
			Tags{"LightMode" = "UniversalForward"}

			Stencil
			{
				Ref 1
				Comp Equal
				Pass Keep
			}

			Blend SrcAlpha OneMinusSrcAlpha
			ZWrite Off ZTest Always 

			HLSLPROGRAM

			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

			#pragma vertex vert
			#pragma fragment frag
			#pragma enable_d3d11_debug_symbols
			#define _MinAngle 0
			#define _MaxAngle 90
			#define _MY_PI 3.14

			CBUFFER_START(UnityPerMaterial)
				half4 _OccludeColor;
				TEXTURE2D(_MainTex);
				SAMPLER(sampler_MainTex);
				float4 _MainTex_ST;
				half _EyeAlpha;
				half3 _HeadForwardDir;
				half _Emission;
			CBUFFER_END

			struct a2v
			{
				float4 vertex : POSITION;
				float2 texcoord : TEXCOORD0;
			};

			struct v2f
			{
				float4 pos : SV_POSITION;
				float2 uv : TEXCOORD0;
				float4 ScreenCoord : TEXCOORD1;
				float3 WS_VertexPos : TEXCOORD2;
			};

			v2f vert(a2v v)
			{
				v2f o;
				o.pos = TransformObjectToHClip(v.vertex);
				o.uv = TRANSFORM_TEX(v.texcoord,_MainTex);
				o.ScreenCoord = ComputeScreenPos(o.pos);
				o.WS_VertexPos = TransformObjectToWorld(v.vertex);

				return o;
			}

			half4 frag(v2f i):SV_Target
			{
				half3 WS_ViewDir = normalize(_WorldSpaceCameraPos.xyz - i.WS_VertexPos);
				half3 TexColor = SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex,i.uv);
				half4 EyeColor = half4(TexColor,1.0);
				//采样当前场景中的深度
				half SceneDepth = SampleSceneDepth(i.ScreenCoord.xy / i.ScreenCoord.w);
				half LinearSceneDepth = LinearEyeDepth(SceneDepth,_ZBufferParams);
				half LinearCurrentDepth = LinearEyeDepth(i.ScreenCoord.z / i.ScreenCoord.w,_ZBufferParams);
				half ViewDotForwardValue = dot(WS_ViewDir,_HeadForwardDir);
				half ViewDotForwardAngle = acos(ViewDotForwardValue) * (180.0 / _MY_PI); 
				ViewDotForwardAngle = clamp(ViewDotForwardAngle,_MinAngle,_MaxAngle);
				half Alpha = 1.0 - ((ViewDotForwardAngle - _MinAngle) / (_MaxAngle - _MinAngle));
				EyeColor.a = Alpha * _EyeAlpha;

				return half4(EyeColor.rgb * _Emission,EyeColor.a);
			}

			ENDHLSL
		}

		Pass
		{
			Tags{"LightMode" = "SRPDefaultUnlit"}

			Stencil
			{
				Ref 1
				Comp NotEqual
				Pass Keep
			}

			HLSLPROGRAM

			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

			#pragma vertex vert
			#pragma fragment frag

			CBUFFER_START(UnityPerMaterial)
				TEXTURE2D(_MainTex);
				SAMPLER(sampler_MainTex);
				float4 _MainTex_ST;
				half _Emission;
			CBUFFER_END

			struct a2v
			{
				float4 vertex : POSITION;
				float2 texcoord : TEXCOORD0;
			};

			struct v2f
			{
				float4 pos : SV_POSITION;
				float2 uv : TEXCOORD0;
			};

			v2f vert(a2v v)
			{
				v2f o;
				o.pos = TransformObjectToHClip(v.vertex);
				o.uv = TRANSFORM_TEX(v.texcoord,_MainTex);

				return o;
			}

			half4 frag(v2f i):SV_Target
			{
				half3 TexColor = SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex,i.uv);
				half4 EyeColor = half4(TexColor,1.0);

				return half4(EyeColor.rgb * _Emission,EyeColor.a);
			}

			ENDHLSL

		}

	}
	FallBack "Packages/com.unity.render-pipelines.universal/FallBackError"
}
