using UnityEngine;
using UnityEngine.UI;

namespace Oxipital
{
    // Debug views of the pipeline (hue = direction, brightness = magnitude) :
    //   view      : screen overlay in the bottom left corner (or into the given RawImage)
    //   planeView : image drawn in the 3D scene on the FlowPlane, to align the camera feed with reality
    public class OpticalFlowDebugView : MonoBehaviour
    {
        public enum View { Off, Source, RawFlow, Trail, Output, Mask }
        // Input follows the source orientation by default; raw input remains available for diagnosis.
        public enum PlaneView { Off, Input, Source, Output }

        [Header("Screen Overlay")]
        public View view = View.Off;
        [Range(.1f, 10)]
        public float gain = 1;
        [Range(64, 1024)]
        public int displayWidth = 320;
        [Tooltip("Fit the video / optical-flow preview to the whole screen while preserving its aspect ratio.")]
        public bool fullscreen = true;
        [Range(0, 1), Tooltip("Opacity of the screen preview over the particles. 0 hides only the image; hands and gauges remain visible.")]
        public float overlayOpacity = .25f;
        [Tooltip("Make black pixels transparent in the screen preview so they do not cover the particle scene.")]
        public bool transparentBackground = true;

        [Header("Flow Plane View")]
        public PlaneView planeView = PlaneView.Off;
        [Tooltip("Show Input with the same crop, Flip X and Flip Y as the optical flow. Disable to inspect the raw input image.")]
        public bool followInputOrientation = true;
        [Range(0, 1)]
        public float planeOpacity = .8f;
        // Unlit HDRP colour, raise it if the scene exposure makes the image too dark
        [Range(0, 50)]
        public float planeBrightness = 1;

        [OSCQuery.DoNotExpose]
        public RawImage target;
        [OSCQuery.DoNotExpose]
        public Material planeMaterial;

        RenderTexture debugTexture;
        GameObject overlay;
        RawImage overlayImage;

        RenderTexture planeTexture;
        GameObject planeQuad;
        Material planeMaterialInstance;

        int kDebug = -1;
        readonly Vector3[] corners = new Vector3[4];

        internal Rect VideoScreenRect(int width, int height)
        {
            if (target != null)
            {
                target.rectTransform.GetWorldCorners(corners);
                Canvas canvas = target.GetComponentInParent<Canvas>();
                Camera camera = canvas != null && canvas.renderMode != RenderMode.ScreenSpaceOverlay ? canvas.worldCamera : null;
                Vector2 min = RectTransformUtility.WorldToScreenPoint(camera, corners[0]);
                Vector2 max = RectTransformUtility.WorldToScreenPoint(camera, corners[2]);
                return Rect.MinMaxRect(min.x, min.y, max.x, max.y);
            }
            var source = GetComponent<OpticalFlowSource>();
            if (source != null && source.framePlayArea)
            {
                // Texture storage keeps its processing size; display the selected
                // play area at its physical aspect instead of stretching it.
                width = Mathf.RoundToInt(Mathf.Max(.1f, source.playAreaAspect) * 10000);
                height = 10000;
            }
            return fullscreen ? FitScreen(width, height) : new Rect(10, 10, displayWidth, displayWidth * height / (float)Mathf.Max(1, width));
        }

        internal static Rect FitScreen(int width, int height)
        {
            float scale = Mathf.Min(Screen.width / (float)Mathf.Max(1, width), Screen.height / (float)Mathf.Max(1, height));
            float w = width * scale, h = height * scale;
            return new Rect((Screen.width - w) * .5f, (Screen.height - h) * .5f, w, h);
        }

        static readonly int UnlitColorMap = Shader.PropertyToID("_UnlitColorMap");
        static readonly int UnlitColor = Shader.PropertyToID("_UnlitColor");

        internal void Render(OpticalFlowManager manager, ComputeShader cs)
        {
            if (kDebug < 0) kDebug = cs.FindKernel("DebugView");

            RenderOverlay(manager, cs);
            RenderPlane(manager, cs);
        }

        void RenderOverlay(OpticalFlowManager manager, ComputeShader cs)
        {
            RawImage image = target != null ? target : overlayImage;

            if (view == View.Off || overlayOpacity <= 0)
            {
                if (overlay != null) overlay.SetActive(false);
                if (target != null) target.enabled = false;
                return;
            }

            OpticalFlowSource source = manager.Source;
            EnsureTexture(ref debugTexture, "OpticalFlow Debug", source.Width, source.Height);

            Texture input;
            int mode = 1;
            Vector4 channel = Vector4.zero;
            switch (view)
            {
                case View.Source:
                    input = source.Current;
                    if (!source.IsFlowMode) { mode = 2; channel = new Vector4(1, 0, 0, 0); }
                    break;
                case View.RawFlow: input = manager.Compute.RawFlow; break;
                case View.Trail: input = manager.Processor.Trail; break;
                case View.Mask: input = manager.Processor.Output; mode = 2; channel = new Vector4(0, 0, 0, 1); break;
                default: input = manager.Processor.Output; break;
            }

            Draw(cs, input, debugTexture, mode, channel, source.Width, source.Height, transparentBackground);

            if (image == null) image = CreateOverlay();
            if (target == null) overlay.SetActive(true);
            image.enabled = true;
            image.texture = debugTexture;
            image.color = new Color(1, 1, 1, overlayOpacity);
            image.raycastTarget = false;
            if (target == null)
            {
                Rect screenRect = VideoScreenRect(source.Width, source.Height);
                image.rectTransform.anchorMin = image.rectTransform.anchorMax = image.rectTransform.pivot = Vector2.zero;
                image.rectTransform.anchoredPosition = screenRect.position;
                image.rectTransform.sizeDelta = screenRect.size;
            }
        }

        void RenderPlane(OpticalFlowManager manager, ComputeShader cs)
        {
            bool visible = planeView != PlaneView.Off && manager.plane != null && planeMaterial != null;
            if (!visible)
            {
                if (planeQuad != null) planeQuad.SetActive(false);
                return;
            }

            OpticalFlowSource source = manager.Source;
            EnsureTexture(ref planeTexture, "OpticalFlow Plane View", source.Width, source.Height);

            // Input and Source show the image carrying the body (grey), Output shows the flow colours
            Texture input;
            int mode = 2;
            Vector4 channel = source.MaskChannel;
            switch (planeView)
            {
                case PlaneView.Input: input = followInputOrientation ? source.Current : source.Input; break;
                case PlaneView.Source: input = source.Current; break;
                default: input = manager.Processor.Output; mode = 1; channel = Vector4.zero; break;
            }

            Draw(cs, input, planeTexture, mode, channel, source.Width, source.Height);

            if (planeQuad == null) CreatePlaneQuad();
            if (planeQuad.transform.parent != manager.plane.transform)
                planeQuad.transform.SetParent(manager.plane.transform, false);
            planeQuad.SetActive(true);

            planeMaterialInstance.SetTexture(UnlitColorMap, planeTexture);
            planeMaterialInstance.SetColor(UnlitColor, new Color(planeBrightness, planeBrightness, planeBrightness, planeOpacity));
        }

        void Draw(ComputeShader cs, Texture input, RenderTexture output, int mode, Vector4 channel, int w, int h, bool transparent = false)
        {
            cs.SetInts(FlowIDs.Size, w, h);
            cs.SetInt(FlowIDs.DebugMode, mode);
            cs.SetVector(FlowIDs.DebugChannel, channel);
            cs.SetFloat(FlowIDs.DebugGain, gain);
            cs.SetFloat("_DebugTransparentBackground", transparent ? 1 : 0);
            cs.SetTexture(kDebug, FlowIDs.DebugIn, input);
            cs.SetTexture(kDebug, FlowIDs.DebugOut, output);
            OpticalFlowUtil.Dispatch(cs, kDebug, w, h);
        }

        static void EnsureTexture(ref RenderTexture rt, string name, int w, int h)
        {
            if (rt != null && rt.width == w && rt.height == h) return;
            OpticalFlowUtil.Release(ref rt);
            rt = OpticalFlowUtil.CreateRT(name, w, h, OpticalFlowUtil.RGBAHalf);
        }

        RawImage CreateOverlay()
        {
            overlay = new GameObject("OpticalFlow Debug Overlay", typeof(Canvas));
            overlay.transform.SetParent(transform, false);
            Canvas canvas = overlay.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 1000;

            GameObject imageObject = new GameObject("Image", typeof(RawImage));
            imageObject.transform.SetParent(overlay.transform, false);
            overlayImage = imageObject.GetComponent<RawImage>();
            RectTransform rect = overlayImage.rectTransform;
            rect.anchorMin = rect.anchorMax = rect.pivot = Vector2.zero;
            rect.anchoredPosition = new Vector2(10, 10);
            return overlayImage;
        }

        // Unit quad in the plane local XY, same mapping as the flow force (uv = local.xy + 0.5)
        void CreatePlaneQuad()
        {
            planeQuad = new GameObject("OpticalFlow Plane View", typeof(MeshFilter), typeof(MeshRenderer));
            planeQuad.hideFlags = HideFlags.DontSave;
            planeQuad.GetComponent<MeshFilter>().sharedMesh = Resources.GetBuiltinResource<Mesh>("Quad.fbx");

            planeMaterialInstance = new Material(planeMaterial) { name = "OpticalFlow Plane View (Instance)" };
            MeshRenderer meshRenderer = planeQuad.GetComponent<MeshRenderer>();
            meshRenderer.sharedMaterial = planeMaterialInstance;
            meshRenderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            meshRenderer.receiveShadows = false;
        }

        internal void Release()
        {
            OpticalFlowUtil.Release(ref debugTexture);
            OpticalFlowUtil.Release(ref planeTexture);
            if (overlay != null) Destroy(overlay);
            if (planeQuad != null) Destroy(planeQuad);
            if (planeMaterialInstance != null) Destroy(planeMaterialInstance);
            overlay = null;
            overlayImage = null;
            planeQuad = null;
            planeMaterialInstance = null;
        }

        void OnDisable()
        {
            Release();
        }
    }
}
