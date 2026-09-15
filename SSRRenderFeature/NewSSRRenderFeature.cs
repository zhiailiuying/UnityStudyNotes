using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[Serializable]
public class NewSSRSettings
{
    internal bool DefaultIsBinarySearch = false;
    internal bool DefaultIsUseHiZ = false;
    internal int DefaultDebugMode = 0;
    internal float DefaultIntensity = 1.0f;
    internal int DefaultStride = 32;
    internal float DefaultLength = 20.0f;
    internal int DefaultMaxStep = 8;
    internal int DefaultBinaryCount = 4;
    internal float DefaultThickness = 0.2f;
    internal float DefaultRayBump = 0.5f;
    internal float DefaultAlpha = 1.0f;
    internal int DefaultIterartion = 1;
    internal float DefaultBlurSpread = 0.6f;
    internal int DefaultDownSample = 1;
    internal float DefaultTestAlpha = 0.5f;
}

public class NewSSRRenderFeature : ScriptableRendererFeature
{
    [SerializeField] private NewSSRSettings defaultSettings;
    [SerializeField] private CaussianBlurSettings defaultBlurSettings;
    [SerializeField] private Shader SSR_Shader;
    [SerializeField] private Shader CSR_Shader;
    private Material SSR_Material;
    private Material CSR_BlurMaterial;
    private NewSSRRenderPass SSR_RenderPass;
    private CaussianBlurRenderPass CSR_BlurPass;

    public override void Create()
    {
        if(SSR_Shader == null)
        {
            Debug.LogError("反射Shader为空!");
            return;
        }

        if(CSR_Shader == null)
        {
            Debug.LogError("模糊Shader为空!");
        }
        SSR_Material = new Material(SSR_Shader);
        CSR_BlurMaterial = new Material(CSR_Shader);
        SSR_RenderPass = new NewSSRRenderPass(defaultSettings,SSR_Material);
        CSR_BlurPass = new CaussianBlurRenderPass(defaultBlurSettings, CSR_BlurMaterial);

        SSR_RenderPass.renderPassEvent = RenderPassEvent.AfterRenderingSkybox;
        CSR_BlurPass.renderPassEvent = RenderPassEvent.AfterRenderingSkybox;
    }



    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if(SSR_Material != null && renderingData.cameraData.cameraType == CameraType.Game)
        {
            var VolumeInstance = VolumeManager.instance.stack;
            var ssr = VolumeInstance.GetComponent<NewSSRVolume>();
            if(ssr != null && ssr.isactive.value)
            {
                renderer.EnqueuePass(SSR_RenderPass);
            }
            
        }

        if(CSR_BlurMaterial != null && renderingData.cameraData.cameraType == CameraType.Game)
        {
            var VolumeInstance = VolumeManager.instance.stack;
            var BlurVolume = VolumeInstance.GetComponent<CaussianBlurVolume>();
            if(BlurVolume != null && BlurVolume.isActive.value)
            {
                renderer.EnqueuePass(CSR_BlurPass);
            }
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (SSR_RenderPass != null)
        {
            SSR_RenderPass.Dispose();
        }

        if(CSR_BlurPass != null)
        {
            CSR_BlurPass.Dispose();
        }

    #if UNITY_EDITOR
        if (UnityEditor.EditorApplication.isPlaying)
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
    }
}
