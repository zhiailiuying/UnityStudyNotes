using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class VolumeRayRenderPass : ScriptableRenderPass
{
    private VolumeRaySettings settings;
    private Material volumeRayMat;

    private RenderTextureDescriptor volumeLightDesc;
    private RTHandle volumeLightRT;

    // 高斯模糊（复用 Blur 目录下的 CaussianBlurBase）
    private CaussianBlurBase caussianBlurBase;

    public VolumeRayRenderPass(VolumeRaySettings settings, Material mat)
    {
        this.settings = settings;
        this.volumeRayMat = mat;

        volumeLightDesc = new RenderTextureDescriptor(Screen.width, Screen.height, RenderTextureFormat.Default, 0);
        caussianBlurBase = new CaussianBlurBase();

        // 体积光射线步进需要场景深度纹理来重建世界坐标
        ConfigureInput(ScriptableRenderPassInput.Depth);
    }

    public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
    {
        volumeLightDesc.width = cameraTextureDescriptor.width;
        volumeLightDesc.height = cameraTextureDescriptor.height;
        volumeLightDesc.graphicsFormat = cameraTextureDescriptor.graphicsFormat;
        volumeLightDesc.depthBufferBits = 0;
        volumeLightDesc.msaaSamples = 1;

        RenderingUtils.ReAllocateIfNeeded(ref volumeLightRT, volumeLightDesc, name: "_VolumeLightRT");
    }

    private void UpdateSettings(GodRayVolume volume)
    {
        if (volumeRayMat == null)
        {
            Debug.LogError("体积光材质为空！");
            return;
        }

        int maxStep = volume.GR_Max_Step.overrideState ? volume.GR_Max_Step.value : settings.DefaultMaxStep;
        float intensity = volume.GR_Intensity.overrideState ? volume.GR_Intensity.value : settings.DefaultIntensity;
        float scatter = volume.GR_ScatterFactor.overrideState ? volume.GR_ScatterFactor.value : settings.DefaultScatterFactor;
        float extinction = volume.GR_ExtinctionFactor.overrideState ? volume.GR_ExtinctionFactor.value : settings.DefaultExtinctionFactor;
        float mieG = volume.GR_MieScatteringG.overrideState ? volume.GR_MieScatteringG.value : settings.DefaultMieScatteringG;
        float density = volume.GR_Density.overrideState ? volume.GR_Density.value : settings.DefaultDensity;
        Color color = volume.GR_Color.overrideState ? volume.GR_Color.value : Color.white;
        float speed = volume.GR_Speed.overrideState ? volume.GR_Speed.value : settings.DefaultSpeed;
        var texture = volume.GR_Texture.overrideState ? volume.GR_Texture.value : null;

        //Debug.Log($"[VolumeRay] override={volume.GR_Intensity.overrideState} value={volume.GR_Intensity.value} -> intensity={intensity}");

        volumeRayMat.SetInt("_RayMaxStep", maxStep);
        volumeRayMat.SetFloat("_Intensity", intensity);
        //Debug.Log($"[VolumeRay] mat._Intensity={volumeRayMat.GetFloat("_Intensity")}");
        volumeRayMat.SetFloat("_ScatterFactor", scatter);
        volumeRayMat.SetFloat("_ExtinctionFactor", extinction);
        volumeRayMat.SetFloat("_MieScatteringG", mieG);
        volumeRayMat.SetFloat("_Density", density);
        volumeRayMat.SetColor("_VolumeLightColor", color);
        volumeRayMat.SetFloat("_Speed", speed);
        volumeRayMat.SetTexture("_ParticalNoise", texture);
    }

    private Vector3 GetMainLightDirection(LightData lightData)
    {
        if (lightData.mainLightIndex >= 0 && lightData.mainLightIndex < lightData.visibleLights.Length)
        {
            var mainLight = lightData.visibleLights[lightData.mainLightIndex];
            if (mainLight.light != null && mainLight.lightType == LightType.Directional)
            {
                // 指向光源的方向 = 光源 forward 的反方向
                return -mainLight.light.transform.forward;
            }
        }

        // 没有主光时给一个默认方向（正上方往下照）
        return new Vector3(0.0f, 1.0f, 0.0f);
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        CommandBuffer cmd = CommandBufferPool.Get();

        var cameraColorTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;
        var stack = VolumeManager.instance.stack;
        var godRayVolume = stack.GetComponent<GodRayVolume>();

        if (godRayVolume == null || !godRayVolume.IsActive.value)
        {
            CommandBufferPool.Release(cmd);
            return;
        }

        UpdateSettings(godRayVolume);

        // 从场景主方向光读取方向（指向光源），设置给材质
        Vector3 lightDir = GetMainLightDirection(renderingData.lightData);
        volumeRayMat.SetVector("_VolumeLightDir", lightDir);

        // Pass 0：体积光射线步进 -> volumeLightRT
        Blitter.BlitCameraTexture(cmd, cameraColorTarget, volumeLightRT, volumeRayMat, 0);

        // 高斯模糊 volumeLightRT
        int iteration = godRayVolume.GR_BlurIteration.overrideState ? godRayVolume.GR_BlurIteration.value : settings.DefaultBlurIteration;
        float blurSpread = godRayVolume.GR_BlurSpread.overrideState ? godRayVolume.GR_BlurSpread.value : settings.DefaultBlurSpread;
        int downSample = godRayVolume.GR_DownSample.overrideState ? godRayVolume.GR_DownSample.value : settings.DefaultDownSample;

        caussianBlurBase.Setup(iteration, blurSpread, downSample, volumeLightDesc);
        RTHandle blurredRT = caussianBlurBase.CaussianBlurExcute(cmd, volumeLightRT, "_BlurSize");

        // Pass 1：加色混合到相机颜色
        Blitter.BlitCameraTexture(cmd, blurredRT, cameraColorTarget, volumeRayMat, 1);

        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }

    public void Dispose()
    {
        if (volumeLightRT != null)
        {
            volumeLightRT.Release();
            volumeLightRT = null;
        }

        if (caussianBlurBase != null)
        {
            caussianBlurBase.Dispose();
            caussianBlurBase = null;
        }
    }
}
