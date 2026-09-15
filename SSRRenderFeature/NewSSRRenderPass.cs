using System.Collections;
using System.Collections.Generic;
using Unity.VisualScripting;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class NewSSRRenderPass : ScriptableRenderPass
{
    private NewSSRSettings defaultSettings;
    private Material SSR_Material;
    private RenderTextureDescriptor SSR_TextureDescriptor;
    private RTHandle SSR_RTHandle;

    //设置Mipmap参数
    private int SSR_MipmapCount = 8;
    private int SSR_MaxMipCount = 8;
    private RTHandle SSR_HiZRenderTexture;
    private RTHandle[] SSR_HIZRenderTextures;

    //模糊
    private CaussianBlurBase caussianBlurBase;
    private RTHandle CaussianTargetRT;

    //是否使用Hi-Z
    private bool useHiZ = false;


    public NewSSRRenderPass(NewSSRSettings settings , Material sSR_Material)
    {
        this.defaultSettings = settings;
        this.SSR_Material = sSR_Material;
        this.SSR_TextureDescriptor = new RenderTextureDescriptor(Screen.width, Screen.height, RenderTextureFormat.Default, 0);

        SSR_HIZRenderTextures = new RTHandle[this.SSR_MipmapCount];
        caussianBlurBase = new CaussianBlurBase();

    }

    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
        var VolumeComponent = VolumeManager.instance.stack.GetComponent<NewSSRVolume>();
        bool isUseHiZ = VolumeComponent.SSR_UseHiZ.overrideState ? VolumeComponent.SSR_UseHiZ.value : defaultSettings.DefaultIsUseHiZ;
        //Debug.Log(isUseHiZ);

        //不使用Hi-Z时，不需要分配Hi-Z Mipmap链
        if(!isUseHiZ)
        {
            return;
        }

        int width = renderingData.cameraData.cameraTargetDescriptor.width;
        int height = renderingData.cameraData.cameraTargetDescriptor.height;

        //创建每一级Mipmap高度和宽度
        int widthPow = Mathf.Max((int)Mathf.Ceil(Mathf.Log(width,2) - 1.0f),1);
        int heightPow = Mathf.Max((int)Mathf.Ceil(Mathf.Log(height, 2) - 1.0f), 1);

        width = 1 << widthPow;
        height = 1 << heightPow;

        //分配单张带Mipmap信息的RTHandle，注意要同样为RFloat格式
        RenderTextureDescriptor HiZDesc = new RenderTextureDescriptor(width,height, RenderTextureFormat.RFloat,0, SSR_MipmapCount);
        HiZDesc.useMipMap = true;
        HiZDesc.autoGenerateMips = false;
        HiZDesc.sRGB = false;
        RenderingUtils.ReAllocateIfNeeded(ref SSR_HiZRenderTexture, HiZDesc,name : "_HiZRenderTexture");

        //创建每一级RTHandle
        for(int i = 0; i < SSR_MipmapCount; i++)
        {
            int mipWidth = Mathf.Max(width >> i, 1);
            int mipHeight = Mathf.Max(height >> i, 1);
            //0注意统一为RFloat格式
            RenderTextureDescriptor mipDesc = new RenderTextureDescriptor(mipWidth, mipHeight, RenderTextureFormat.RFloat, 0, 1);
            mipDesc.sRGB = false;
            RenderingUtils.ReAllocateIfNeeded(ref SSR_HIZRenderTextures[i], mipDesc, name: $"_HiZRenderTextures{i}");
        }

        //Debug.Log(width);
        //Debug.Log(height);
    }

    public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
    {
        SSR_TextureDescriptor.width = cameraTextureDescriptor.width;
        SSR_TextureDescriptor.height = cameraTextureDescriptor.height;

        RenderingUtils.ReAllocateIfNeeded(ref SSR_RTHandle, SSR_TextureDescriptor,name: "SSR_RTHandle");

    }

    private void UpDateSettings(NewSSRVolume VolumeComponent)
    {
        if(SSR_Material == null)
        {
            Debug.LogError("该材质为空！");
            return;
        }

        float SSR_Intensity = VolumeComponent.SSR_Intensity.overrideState ? VolumeComponent.SSR_Intensity.value : defaultSettings.DefaultIntensity;
        int SSR_Stride = VolumeComponent.SSR_Stride.overrideState ? VolumeComponent.SSR_Stride.value : defaultSettings.DefaultStride;
        float SSR_Length = VolumeComponent.SSR_Length.overrideState ? VolumeComponent.SSR_Length.value : defaultSettings.DefaultLength;
        int SSR_MaxStep = VolumeComponent.SSR_MaxStep.overrideState ? VolumeComponent.SSR_MaxStep.value : defaultSettings.DefaultMaxStep;
        bool IsBinarySeacrh = VolumeComponent.SSR_IsBinarySearch.overrideState ? VolumeComponent.SSR_IsBinarySearch.value : defaultSettings.DefaultIsBinarySearch;
        int SSR_BinarySeacrhCount = VolumeComponent.SSR_BinarySeachCount.overrideState ? VolumeComponent.SSR_BinarySeachCount.value : defaultSettings.DefaultBinaryCount; 
        float SSR_Thickness = VolumeComponent.SSR_Thickness.overrideState ? VolumeComponent.SSR_Thickness.value : defaultSettings.DefaultThickness;
        float SSR_RayBump = VolumeComponent.SSR_RayBump.overrideState ? VolumeComponent.SSR_RayBump.value : defaultSettings.DefaultRayBump;
        float SSR_Alpha = VolumeComponent.SSR_Alpha.overrideState ? VolumeComponent.SSR_Alpha.value : defaultSettings.DefaultAlpha;
        float SSR_TestAlpha = VolumeComponent.SSR_Alpha.overrideState ? VolumeComponent.SSR_Alpha.value : defaultSettings.DefaultTestAlpha;
        int DebugMode = VolumeComponent.SSR_DebugMode.overrideState ? VolumeComponent.SSR_DebugMode.value : defaultSettings.DefaultDebugMode;
        //是否使用Hi-Z
        useHiZ = VolumeComponent.SSR_UseHiZ.overrideState ? VolumeComponent.SSR_UseHiZ.value : defaultSettings.DefaultIsUseHiZ;
        //是否开启二分查找
        var keyword = new LocalKeyword(SSR_Material.shader, "_USE_BINARYSEARCH");
        //是否开启Hi-Z加速
        var HiZKeyword = new LocalKeyword(SSR_Material.shader, "_USE_HIZ");

        SSR_Material.SetKeyword(keyword, IsBinarySeacrh);
        SSR_Material.SetKeyword(HiZKeyword, useHiZ);
        SSR_Material.SetFloat("_ReflectionIntensity", SSR_Intensity);
        SSR_Material.SetInt("_RayStride", SSR_Stride);
        SSR_Material.SetFloat("_RayLength",SSR_Length);
        SSR_Material.SetInt("_RayMarchMaxStep", SSR_MaxStep);
        SSR_Material.SetInt("_RayBinarySearchCount", SSR_BinarySeacrhCount);
        SSR_Material.SetFloat("_Thickness", SSR_Thickness);
        SSR_Material.SetFloat("_RayBump", SSR_RayBump);
        SSR_Material.SetFloat("_ReflectionAlpha", SSR_Alpha);
        SSR_Material.SetFloat("_TestAlpha", SSR_TestAlpha);
        SSR_Material.SetInt("_DebugMode", DebugMode);
    }

    private void GenerateHiZMipmap(CommandBuffer cmd, RenderingData renderingData)
    {
        //获取深度图
        var cameraDepthTexture = renderingData.cameraData.renderer.cameraDepthTargetHandle;

        //拷贝深度图到mipmap第0层,注意Copy函数要保持Desc格式一致，否则Copy失败
        Blitter.BlitCameraTexture(cmd, cameraDepthTexture, SSR_HIZRenderTextures[0], SSR_Material, 0);
        cmd.CopyTexture(SSR_HIZRenderTextures[0], 0, 0, SSR_HiZRenderTexture, 0, 0);

        for (int i = 1; i < SSR_MipmapCount; i++)
        {
            //设置MipmapID
            SSR_Material.SetFloat("_HiZLevelID", i - 1);
            //降采样Mipmap
            Blitter.BlitCameraTexture(cmd, SSR_HIZRenderTextures[i - 1], SSR_HIZRenderTextures[i], SSR_Material, 0);
            //复制Mipmap
            cmd.CopyTexture(SSR_HIZRenderTextures[i], 0, 0, SSR_HiZRenderTexture, 0, i);
        }

        SSR_Material.SetTexture("_HiZRenderTexture", SSR_HiZRenderTexture);
        SSR_Material.SetInt("_MaxMipCount", SSR_MaxMipCount);

    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        CommandBuffer cmd = CommandBufferPool.Get("SSRPass");
        var CameraTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;
        var CameraSource = CameraTarget;
        var VolumeComponent = VolumeManager.instance.stack.GetComponent<NewSSRVolume>();

        UpDateSettings(VolumeComponent);

        //只有使用Hi-Z时才生成Hi-Z Mipmap链
        if(useHiZ)
        {
            GenerateHiZMipmap(cmd,renderingData);
        }

        Blitter.BlitCameraTexture(cmd,CameraTarget, SSR_RTHandle, SSR_Material,1);
        //高斯模糊
        int iteration = VolumeComponent.SSR_Iteration.overrideState ? VolumeComponent.SSR_Iteration.value : defaultSettings.DefaultIterartion;
        float BlurSpread = VolumeComponent.SSR_BlurSpread.overrideState ? VolumeComponent.SSR_BlurSpread.value : defaultSettings.DefaultBlurSpread;
        int downSample = VolumeComponent.SSR_DownSample.overrideState ? VolumeComponent.SSR_DownSample.value : defaultSettings.DefaultDownSample;

        //改成用函数，不用每一次都new了
        caussianBlurBase.Setup(iteration,BlurSpread,downSample,SSR_TextureDescriptor);
        CaussianTargetRT = caussianBlurBase.CaussianBlurExcute(cmd, SSR_RTHandle, "_BlurSize");

        Blitter.BlitCameraTexture(cmd, CaussianTargetRT, CameraSource, SSR_Material,2);
        //Blit(cmd, CameraTarget,SSR_RTHandle,SSR_Material,0);
        //Blit(cmd, SSR_RTHandle, CameraTarget);

        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }

    public void Dispose()
    {
    #if UNITY_EDITOR
        if(UnityEditor.EditorApplication.isPlaying)
        {
            Material.Destroy(SSR_Material);
        }
        else
        {
            Material.DestroyImmediate(SSR_Material);
        }
    #else
            Material.Destroy(SSR_Material);
    #endif

        if(SSR_RTHandle != null)
        {
            SSR_RTHandle.Release();
            SSR_RTHandle = null;
        }

        for(int i = 0; i < SSR_MaxMipCount; i++)
        {
            if (SSR_HIZRenderTextures[i] != null)
            {
                SSR_HIZRenderTextures[i].Release();
                SSR_HIZRenderTextures[i] = null;
            }
        }

        if(SSR_HiZRenderTexture != null)
        {
            SSR_HiZRenderTexture.Release();
            SSR_HiZRenderTexture = null;
        }

        if(caussianBlurBase != null)
        {
            caussianBlurBase.Dispose();
        }
        
    }
    
}
