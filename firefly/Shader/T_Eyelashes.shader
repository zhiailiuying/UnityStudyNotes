Shader "Unlit/T_Eyelashes"
{
    Properties
	{
		_OccludeColor("Color Tint" , Color) = (1,1,1,1)
		_MainTex("Base Color" , 2D) = "white"{}
		_EyeAlpha("Eye Alpha" , Range(0,1)) = 0.5
		_HeadForwardDir("Head ForwardDir" , Vector) = (1,1,1)
	}

	SubShader
	{
		Tags{"RenderPipeline" = "UniversalRenderPipeline" "RenderType" = "Transparent" "Queue" = "Transparent+10"}

		Pass
		{
			Tags{"LightMode" = "SRPDefaultUnlit"}

			// Stencil
			// {
			// 	Ref 1
			// 	Comp NotEqual
			// 	Pass Keep
			// }
			Blend SrcAlpha OneMinusSrcAlpha

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
				half4 _Color;
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

				return half4(EyeColor.rgb * _Color,0.7);
			}

			ENDHLSL

		}

	}
	FallBack "Packages/com.unity.render-pipelines.universal/FallBackError"
}
