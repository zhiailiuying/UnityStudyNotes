using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[Serializable]
public class VolumeRaySettings
{
    internal int DefaultMaxStep = 32;
    internal float DefaultIntensity = 1.0f;
    internal float DefaultScatterFactor = 0.05f;
    internal float DefaultExtinctionFactor = 0.02f;
    internal float DefaultMieScatteringG = 0.5f;
    internal float DefaultDensity = 1.0f;
    internal float DefaultSpeed = 0.0f;

    internal int DefaultBlurIteration = 1;
    internal float DefaultBlurSpread = 0.6f;
    internal int DefaultDownSample = 1;
}

public class VolumeRayRenderFeature : ScriptableRendererFeature
{
    [SerializeField] private Shader VolumeRayShader;

    private Material VolumeRayMaterial;
    private VolumeRayRenderPass VolumeRayPass;

    public override void Create()
    {
        if (VolumeRayShader == null)
        {
            Debug.LogError("体积光Shader为空！请在RenderFeature上赋值 VolumeRay.shader");
            return;
        }

        VolumeRaySettings settings = new VolumeRaySettings();
        VolumeRayMaterial = new Material(VolumeRayShader);
        VolumeRayPass = new VolumeRayRenderPass(settings, VolumeRayMaterial);

        // 在不透明物体与天空盒之后、透明物体之前执行
        VolumeRayPass.renderPassEvent = RenderPassEvent.AfterRenderingSkybox;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (VolumeRayMaterial == null || VolumeRayPass == null)
        {
            return;
        }

        if (renderingData.cameraData.cameraType != CameraType.Game)
        {
            return;
        }

        var stack = VolumeManager.instance.stack;
        var godRayVolume = stack.GetComponent<GodRayVolume>();
        if (godRayVolume != null && godRayVolume.IsActive.value)
        {
            renderer.EnqueuePass(VolumeRayPass);
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (VolumeRayPass != null)
        {
            VolumeRayPass.Dispose();
            VolumeRayPass = null;
        }

#if UNITY_EDITOR
        if (UnityEditor.EditorApplication.isPlaying)
        {
            Material.Destroy(VolumeRayMaterial);
        }
        else
        {
            Material.DestroyImmediate(VolumeRayMaterial);
        }
#else
        Material.Destroy(VolumeRayMaterial);
#endif
    }
}
