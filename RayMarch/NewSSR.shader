Shader "Unlit/NewSSR"
{
	Properties
	{
		_Color("Color Tint" , Color) = (1,1,1,1)
		_BlitTexture("Blit Texture Color" , 2D) = "white"{}
		_ReflectionIntensity("Reflection Intensity" , Range(0,1)) = 0.5
		_RayLength("Ray Length" , Range(0,100)) = 20
		_RayMarchMaxStep("RayMarch Step" , Range(0,64)) = 8
		_RayStride("Ray Stride" , Range(0,64)) = 32
		_RayBinarySearchCount("Ray BinarySearch Count" , Range(0,16)) = 4
		_Thickness("Thickness" , Range(0,1)) = 0.2
		_RayBump("Ray Bump" , Range(0,1)) = 0.5
		_ReflectionAlpha("Reflection Alpha" , Range(0,1)) = 1
		_TestAlpha("Test Alpha" , Range(0,1)) = 0.5
		_DebugMode("Debug Mode (0=Off 1=HitUV 2=DepthError)" , Int) = 0
	}

	SubShader
	{
		Tags{"RenderPipeline" = "UniversalPipeline" "RenderType" = "Opaque"}

		//降采样生成MipMap链
		Pass
		{
			Tags{"LightMode" = "SRPDefaultUnlit"}
			
			HLSLPROGRAM

			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

			#pragma vertex vert
			#pragma fragment frag

			CBUFFER_START(UnityPerMaterial)
				TEXTURE2D(_BlitTexture);
				SAMPLER(sampler_BlitTexture);
				half4 _BlitTexture_TexelSize;
				int _HiZLevelID;
			CBUFFER_END

			struct a2v
			{
				uint vertexID: SV_VertexID;
			};

			struct v2f
			{
				float4 pos : SV_POSITION;
				half2 uv[4] : TEXCOORD0;
			};

			v2f vert(a2v v)
			{
				v2f o;
				o.pos = GetFullScreenTriangleVertexPosition(v.vertexID);
				half2 uv = GetFullScreenTriangleTexCoord(v.vertexID);
				float2 offset = _BlitTexture_TexelSize.xy * 4; 
				o.uv[0] = uv + half2(-1,-1) * offset;
				o.uv[1] = uv + half2( 1,-1) * offset;
				o.uv[2] = uv + half2(-1, 1) * offset;
				o.uv[3] = uv + half2( 1, 1) * offset;

				return o;
			}

			inline half GetSourceDepth(half2 uv)
			{
				half SceneDepth = SAMPLE_TEXTURE2D_LOD(_BlitTexture,sampler_BlitTexture,uv,_HiZLevelID);
				return SceneDepth;
			}

			half frag(v2f i):SV_Target
			{
				//half4 TexColor = SAMPLE_TEXTURE2D(_BlitTexture,sampler_BlitTexture,i.uv[0]);
				half4 aroundDepth = half4(GetSourceDepth(i.uv[0]),GetSourceDepth(i.uv[1]),GetSourceDepth(i.uv[2]),GetSourceDepth(i.uv[3]));
				half maxDepth = max(max(aroundDepth.r,aroundDepth.g),max(aroundDepth.b,aroundDepth.a));

				return maxDepth;
			}

			ENDHLSL
		}

		Pass
		{
			Tags{"LightMode" = "UniversalForward"}

			HLSLPROGRAM

			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"

			#pragma vertex vert
			#pragma fragment frag
			#pragma shader_feature_local _USE_BINARYSEARCH
			#pragma shader_feature_local _USE_HIZ
			#pragma enable_d3d11_debug_symbols
			
			#define REFLECTION_EDGE 0.95

			CBUFFER_START(UnityPerMaterial)
				half4 _Color;
				TEXTURE2D(_BlitTexture);
				SAMPLER(sampler_BlitTexture);
				half4 _BlitTexture_TexelSize;
				half _ReflectionIntensity;
				half _RayLength;
				half _RayMarchMaxStep;
				int _RayStride;
				int _RayBinarySearchCount;
				int _MaxMipCount;
				half _TestAlpha;
				TEXTURE2D(_HiZRenderTexture);
				SAMPLER(sampler_HiZRenderTexture);
				half _Thickness;
				half _RayBump;
				half _ReflectionAlpha;
				int _DebugMode;
			CBUFFER_END

			struct a2v
			{
				uint vertexID : SV_VertexID;
			};

			struct v2f
			{
				float4 pos : SV_POSITION;
				float2 uv : TEXCOORD0;
				float3 VS_RayDir : TEXCOORD1;
			};

			v2f vert(a2v v)
			{
				v2f o;
				o.pos = GetFullScreenTriangleVertexPosition(v.vertexID);
				o.uv = GetFullScreenTriangleTexCoord(v.vertexID);
				float4 CS_RayDir = float4(o.uv * 2.0 - 1.0,1.0,1.0);
				float4 VS_RayDir = mul(unity_CameraInvProjection,CS_RayDir);
				o.VS_RayDir = VS_RayDir.xyz / VS_RayDir.w;

				return o;
			}

			inline float GetCurrentSceneDepth(float2 uv,float mipLevel)
			{
				float SceneDepth;
				#if _USE_HIZ
					SceneDepth = SAMPLE_TEXTURE2D_LOD(_HiZRenderTexture,sampler_HiZRenderTexture,uv,mipLevel);
				#else
					//不使用Hi-Z时，直接采样场景深度图（始终在mip 0下测试）
					SceneDepth = SampleSceneDepth(uv);
				#endif
				//float SceneDepth = SampleSceneDepth(uv);
				float linearEyeDepth = -LinearEyeDepth(SceneDepth,_ZBufferParams);

				return linearEyeDepth;
			}

			bool Intersected(inout float4 pqk,inout float4 dpqk, inout float2 VS_CurrentZ,float2 HitScreenUV,inout float mipLevel)
			{
				VS_CurrentZ = (VS_CurrentZ.x < VS_CurrentZ.y) ? VS_CurrentZ.yx : VS_CurrentZ.xy;

				float CurrentSceneDepth = GetCurrentSceneDepth(HitScreenUV,mipLevel);

				//DebugColor = float4(VS_CurrentZ.y,VS_CurrentZ.y,VS_CurrentZ.y,1.0);

				if(VS_CurrentZ.y <= CurrentSceneDepth)
				{
					#if _USE_HIZ
					if(mipLevel == 0)
					{
					#endif
						if(VS_CurrentZ.x >= CurrentSceneDepth - _Thickness)
						{
							return true;
						}
						return false;
					#if _USE_HIZ
					}
					
					pqk -= dpqk * exp2(mipLevel);
					VS_CurrentZ.x = VS_CurrentZ.y;
					VS_CurrentZ.y = pqk.z / pqk.w;
					mipLevel--;
					#endif
				}
				else
				{
					#if _USE_HIZ
					mipLevel = min(mipLevel + 1,_MaxMipCount);
					#endif
				}
				
				return false;
			}

			// half2 BinarySearch(float4 pqk, float4 dpqk, float2 VS_CurrentZ,float mipLevel,out half hitZ,out half4 DebugColor)
			// {
			// 	pqk -= dpqk;
			// 	// VS_CurrentZ.x = VS_CurrentZ.y;
			// 	// VS_CurrentZ.y = pqk.z / pqk.w;
			// 	float2 HitScreenUV = pqk.xy * 0.5 + 0.5;
			// 	half2 hitPixel = half2(0,0);

			// 	[loop]
			// 	for(int i = 0; i < _RayBinarySearchCount;i++)
			// 	{
			// 		dpqk *= 0.5;
			// 		pqk = (VS_CurrentZ.y <= GetCurrentSceneDepth(HitScreenUV,mipLevel)) ? (pqk - dpqk) : (pqk + dpqk);
			// 		VS_CurrentZ.x = VS_CurrentZ.y;
			// 		VS_CurrentZ.y = pqk.z / pqk.w;

			// 		HitScreenUV = (pqk.xy - dpqk * 0.5) * 0.5 + 0.5;
			// 		if(Intersected(pqk,dpqk,VS_CurrentZ,HitScreenUV,mipLevel) && VS_CurrentZ.y >= GetCurrentSceneDepth(HitScreenUV,mipLevel) - 0.5)
			// 		{
			// 			if(VS_CurrentZ.x >= GetCurrentSceneDepth(HitScreenUV,mipLevel) - 0.2)
			// 			{
			// 				hitZ = VS_CurrentZ.y;
			// 				hitPixel = HitScreenUV;
			// 				//DebugColor = float4(hitZ,0.0,1.0);
			// 				return hitPixel;
			// 			}
			// 		}

			// 	} 
			// 	DebugColor = float4(1.0,1.0,1.0,1.0);
			// 	hitPixel = HitScreenUV;
			// 	return hitPixel;
			// }

			half2 BinarySearch(float4 pqk, float4 dpqk, out half hitZ, out half4 DebugColor)
			{
				pqk -= dpqk;                         

				[loop]
				for (int i = 0; i < _RayBinarySearchCount; i++)
				{
					dpqk *= 0.5;                      
					pqk += dpqk;                      
					float2 uv = pqk.xy * 0.5 + 0.5;
					float VS_RayZ = pqk.z / pqk.w;
					float sceneDepth = GetCurrentSceneDepth(uv, 0.0);

					if (VS_RayZ <= sceneDepth)       
						pqk -= dpqk;                  
				}

				hitZ = pqk.z / pqk.w;
				DebugColor = half4(hitZ, hitZ, hitZ, 1.0);
				return pqk.xy * 0.5 + 0.5;
			}

			bool RayTracing(half3 VS_start,half3 VS_marchDir,out half2 hitPixel,out half MarchPersent,out half hitZ,out half4 DebugColor)
			{
				//钳制光线的最短距离在近平面
				float MinLength = ((VS_start.z + VS_marchDir.z * _RayLength) > -_ProjectionParams.y) ? 
				                   (-_ProjectionParams.y - VS_start.z) / VS_marchDir.z : _RayLength;

				float3 VS_ReflectionRayDir = VS_start + VS_marchDir * MinLength;
				//在屏幕空间步进光线
				float4 CS_RayStart = mul(unity_CameraProjection,float4(VS_start,1.0));
				float4 CS_RayDir = mul(unity_CameraProjection,float4(VS_ReflectionRayDir,1.0));

				//DebugColor = half4(CS_RayDir);

				float2 ScreenRayStart = CS_RayStart.xy / CS_RayStart.w;
				float2 ScreenRayDir = CS_RayDir.xy / CS_RayDir.w;

				//矫正系数
				float k0 = 1.0 / CS_RayStart.w;
				float k1 = 1.0 / CS_RayDir.w;

				//这里视图深度透视矫正的原因是：
				//1、在2D空间中深度值z是非线性变化的，因此不能用透视空间的z,用视图空间下线性变化的深度值z即可、
				//2、如果不进行透视除法，在屏幕中用一个常数步进的话，会因为每一个像素画面占比近大远小出现问题
				float ViewSpaceQ0 = VS_start.z * k0;
				float ViewSpaceQ1 = VS_ReflectionRayDir.z * k1;

				ScreenRayDir = (dot(ScreenRayDir - ScreenRayStart,ScreenRayDir - ScreenRayStart) < 0.001) ? ScreenRayDir + _BlitTexture_TexelSize.xy : ScreenRayDir;
				float2 deltaPixel = (ScreenRayDir - ScreenRayStart) * _BlitTexture_TexelSize.zw;
				float step = min(abs(1.0 / deltaPixel.x),abs(1.0 / deltaPixel.y));
				float ProjectFactor = 1.0 - min(1.0,-VS_start.z / 100);
				step *= _RayStride;
				step *= (1.0 + ProjectFactor);

				float4 pqk = float4(ScreenRayStart,ViewSpaceQ0,k0);
				float4 dpqk = float4(ScreenRayDir - ScreenRayStart,ViewSpaceQ1 - ViewSpaceQ0,k1 - k0) * step;
				//DebugColor = float4(step,step,step,1.0);

				bool IsIntersect = false;
				float CurrentStep = step;
				float preZEstimate = VS_start.z;
				//x存放ZMax(光线尾巴),y存放ZMin(光线的头),这里存的是视图空间的Z
				float2 VS_CurrentZ = float2(0.0,0.0);
				float2 HitScreenUV = float2(0.0,0.0);
				half mipLevel = 0.0;

			    //Bayer矩阵
				const half Ditter[16] = {0.0, 0.5, 0.125,0.625,
					                      0.75,0.25,0.875,0.375,
							              0.187,0.687,0.0625,0.562,
							              0.937,0.437,0.812,0.312};
				half2 DitterUV = fmod((pqk * 0.5 + 0.5) * _ScaledScreenParams.xy, 4);
				half jitter = Ditter[(int)DitterUV.x * 4 + (int)DitterUV.y];
				pqk += dpqk * jitter;

				//步进光线
				[loop]
				for(int i = 0; i < _RayMarchMaxStep && CurrentStep <= 1.0; i++)
				{
					#if _USE_HIZ
						pqk += dpqk * exp2(mipLevel);
						HitScreenUV = (pqk.xy - dpqk * 0.5 * exp2(mipLevel)) * 0.5 + 0.5;
					#else
						//不使用Hi-Z时，光线步进直接使用固定步长 pqk += dpqk
						pqk += dpqk;
						HitScreenUV = (pqk.xy - dpqk * 0.5) * 0.5 + 0.5;
					#endif
					VS_CurrentZ.x = preZEstimate;
					VS_CurrentZ.y = pqk.z / pqk.w;
					CurrentStep += step;

					if(Intersected(pqk,dpqk,VS_CurrentZ,HitScreenUV,mipLevel))
					{
						hitZ = VS_CurrentZ.y;
						#if _USE_BINARYSEARCH
							//hitZ = BinarySearch(pqk,dpqk,VS_CurrentZ,HitScreenUV,mipLevel,DebugColor);
							//hitPixel = BinarySearch(pqk,dpqk,VS_CurrentZ,mipLevel,hitZ,DebugColor);
							hitPixel = BinarySearch(pqk, dpqk, hitZ, DebugColor);   // 去掉了 VS_CurrentZ / mipLevel
						#else
							hitPixel = HitScreenUV;
						#endif
						//DebugColor = half4(hitZ,0.0,1.0);
						MarchPersent = (float)i / (float)_RayMarchMaxStep;
						IsIntersect = true;
						return IsIntersect;
					}
					else
					{
						preZEstimate = VS_CurrentZ.y;
					}
				}

				DebugColor = half4(1.0,1.0,.0,1.0);

				return IsIntersect;
			}

			half CalculateReflectionAlpha(half2 hitPixel,half MarchPersent,half hitZ)
			{
				half alpha = 1.0;
				alpha *= saturate(-5 * hitZ);
				hitPixel = (hitPixel - 0.5) * 2;
				half XEdgeDis = clamp(abs(hitPixel.x),REFLECTION_EDGE,1.0);
				half YEdgeDis = clamp(abs(hitPixel.y),REFLECTION_EDGE,1.0);
				half alphaFactor = max((XEdgeDis - REFLECTION_EDGE) / (1.0 - REFLECTION_EDGE),(YEdgeDis - REFLECTION_EDGE) / (1.0 - REFLECTION_EDGE));
				alpha *= 1.0 - alphaFactor;
				alpha *= 1.0 - MarchPersent;
				alpha *= _ReflectionAlpha * 2;

				return alpha;
			}

			half4 frag(v2f i):SV_Target
			{
				half4 DebugColor = half4(1,1,1,1);
				half4 TexColor = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, i.uv);
				half linear01Depth = Linear01Depth(SampleSceneDepth(i.uv),_ZBufferParams);
				half3 WS_Normal = SampleSceneNormals(i.uv);
				half3 VS_Normal = normalize(TransformWorldToViewDir(WS_Normal));
				//这里的向量是有长度信息的，不能单位化
				half3 VS_RayDir = i.VS_RayDir;
				//这里反射代表光线追踪的方向
				half3 ReflectRayDir = normalize(reflect(VS_RayDir,VS_Normal));
				//计算光线的起点
				half3 OriginPoint = VS_RayDir * linear01Depth;
				half2 hitPixel = half2(0,0);
				half3 ReflectionColor = half3(0,0,0);
				half MarchPersent = 0.0;
				half ReflectionEdgeAlpha = 1.0;
				half hitZ = 0.0;

				if(RayTracing(OriginPoint + VS_Normal * _RayBump,ReflectRayDir,hitPixel,MarchPersent,hitZ,DebugColor))
				{
					ReflectionEdgeAlpha = CalculateReflectionAlpha(hitPixel,MarchPersent,hitZ);
					ReflectionColor = SAMPLE_TEXTURE2D(_BlitTexture,sampler_BlitTexture,hitPixel) * _ReflectionIntensity * ReflectionEdgeAlpha;
					//调试输出：0=正常 1=命中UV 2=深度误差
					if(_DebugMode == 1)
					{
						return half4(hitPixel, 0.0, 1.0);
					}
					if(_DebugMode == 2)
					{
						float depthErr = abs(hitZ - GetCurrentSceneDepth(hitPixel, 0.0));
						return half4(depthErr, depthErr, depthErr, 1.0);
					}
				}

				half3 FinalColor = ReflectionColor + 0.6 * TexColor.rgb;
				//DebugColor = half4(ReflectionColor,1);

				return half4(FinalColor,1.0);
			}

			ENDHLSL
		}

		//混合
		Pass
		{
			Tags{"LightMode" = "SRPDefaultUnlit"}

			Blend SrcAlpha OneMinusSrcAlpha

			HLSLPROGRAM

			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

			#pragma vertex BlendVert
			#pragma fragment BlendFrag

			CBUFFER_START(UnityPerMaterial)
				TEXTURE2D(_BlitTexture);
				SAMPLER(sampler_BlitTexture);
			CBUFFER_END

			struct a2v
			{
				uint vertexID : SV_VertexID;
			};

			struct v2f
			{
				float4 pos : SV_POSITION;
				float2 uv : TEXCOORD0;
			};

			v2f BlendVert(a2v v)
			{
				v2f o;
				o.pos = GetFullScreenTriangleVertexPosition(v.vertexID);
				o.uv = GetFullScreenTriangleTexCoord(v.vertexID);
				return o;
			}

			half4 BlendFrag(v2f i):SV_Target
			{
				half3 TexColor = SAMPLE_TEXTURE2D(_BlitTexture,sampler_BlitTexture,i.uv);
				return half4(TexColor,0.5);
			}

			ENDHLSL
		}
	}

	FallBack "Packages/com.unity.render-pipelines.universal/FallBackError"
}
