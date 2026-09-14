using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
public class T_FireflySDFCoord : MonoBehaviour
{
    //计算人物坐标系
    [SerializeField] private Transform F_Center;
    [SerializeField] private Transform F_Forward;
    [SerializeField] private Transform F_Right;
    private List<Material> materials = new List<Material>();
    private Shader ShaderTargetName_0;
    private Shader ShaderTargetName_1;
    private Shader ShaderTargetName_2;

    private void Start()
    {
        var F_skinnedMeshRenderers = GetComponentsInChildren<SkinnedMeshRenderer>();

        foreach(var F_skinnedMeshRenderer in F_skinnedMeshRenderers)
        {
            if(F_skinnedMeshRenderer == null)
            {
                continue;
            }

            foreach(var material in F_skinnedMeshRenderer.sharedMaterials)
            {
                materials.Add(material);
            }
        }

        ShaderTargetName_0 = Shader.Find("Unlit/T_Face");
        ShaderTargetName_1 = Shader.Find("Unlit/T_Eye");
        ShaderTargetName_2 = Shader.Find("Unlit/T_Eyebrows");
    }

    private void LateUpdate()
    {
        if (F_Center == null || F_Forward == null || F_Right == null)
        {
            Debug.LogError("有组件为空!");
            return;
        }
        
        Vector3 LocalForwardDir = (F_Forward.localPosition - F_Center.localPosition).normalized;
        Vector3 LocalRightDir = (F_Right.localPosition - F_Center.localPosition).normalized;
        Vector3 LocalUpDir = Vector3.Cross(LocalForwardDir, LocalRightDir).normalized;
        Vector3 WSForwardDir = (F_Forward.position - F_Center.position).normalized;
        //Debug.Log(ForwardDir);
        //Debug.Log(UpDir);

        foreach (var material in materials)
        {
            if(material.shader != null && material.shader == ShaderTargetName_0)
            {
                material.SetVector("_HeadForwardDir", LocalForwardDir);
                material.SetVector("_HeadRightDir", LocalRightDir);
                material.SetVector("_HeadUpDir", LocalUpDir);
            }

            if(material.shader != null && material.shader == ShaderTargetName_1)
            {
                material.SetVector("_HeadForwardDir", WSForwardDir);
            }

            if (material.shader != null && material.shader == ShaderTargetName_2)
            {
                material.SetVector("_HeadForwardDir", WSForwardDir);
            }

        }
    }
}
