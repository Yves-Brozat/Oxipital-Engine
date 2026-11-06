using UnityEngine;
using UnityEngine.VFX;

namespace Oxipital
{
    // Optical flow pipeline (Kinect -> TouchDesigner -> Spout -> Unity) :
    //   OpticalFlowSource -> OpticalFlowCompute -> OpticalFlowProcessor -> OpticalFlowMetrics
    // Runs the stages in order in LateUpdate (after KlakSpout received the frame in Update).
    // Ballet pushes the result into every OrbGroup through ApplyTo, like the force buffers.
    [DefaultExecutionOrder(-50)]
    [RequireComponent(typeof(OpticalFlowSource), typeof(OpticalFlowCompute), typeof(OpticalFlowProcessor))]
    public class OpticalFlowManager : MonoBehaviour
    {
        [Header("Force")]
        public bool forceEnabled = true;
        [Range(0, 1)]
        public float intensity = 1;
        // Add mode : velocity += flow * strength * dt
        [Range(0, 50)]
        public float strength = 10;
        // Distance from the plane (plane local Z) where particles are still pushed
        [Range(0, 10)]
        public float depthBand = 1;

        [Header("Wind")]
        // 0 = Add (push), 1 = Wind (particles dragged towards the flow speed)
        [Range(0, 1)]
        public float windBlend = 0;
        [Range(0, 20)]
        public float windSpeed = 3;
        [Range(0, 20)]
        public float windDrag = 4;

        [Header("Plane")]
        // Height of the flow plane in meters. The width follows the aspect ratio of the Spout texture (OxipitalFlow),
        // crop included, so the image is never stretched.
        [Range(.1f, 20)]
        public float planeScale = 4;
        [Tooltip("When Frame Play Area is enabled, fit the force plane to the same screen rectangle as the cropped video and hands. Uses the brush Visualization Camera, otherwise Camera.main. The plane keeps its original depth in the scene.")]
        public bool fitPlaneToPlayArea = true;

        [OSCQuery.DoNotExpose]
        public FlowPlane plane;

        OpticalFlowSource source;
        OpticalFlowCompute compute;
        OpticalFlowProcessor processor;
        OpticalFlowMetrics metrics;
        OpticalFlowDebugView debugView;

        bool allocated;
        bool warnedMissingShaders;
        int inputRevision;
        FlowPlane framedPlane;
        Vector3 savedPlanePosition, savedPlaneScale;
        Quaternion savedPlaneRotation;

        public OpticalFlowSource Source => source;
        public OpticalFlowCompute Compute => compute;
        public OpticalFlowProcessor Processor => processor;
        public RenderTexture FlowMap => allocated ? processor.Output : null;

        void OnEnable()
        {
            source = GetComponent<OpticalFlowSource>();
            compute = GetComponent<OpticalFlowCompute>();
            processor = GetComponent<OpticalFlowProcessor>();
            metrics = GetComponent<OpticalFlowMetrics>();
            debugView = GetComponent<OpticalFlowDebugView>();
            if (plane == null) plane = GetComponentInChildren<FlowPlane>();
        }

        void OnDisable()
        {
            RestorePlaneFraming();
            ReleaseAll();
            if (source != null) source.SetSpoutActive(false);
            if (source != null && source.kinectInput != null) source.kinectInput.StopCapture();
            if (source != null && source.azureKinectInput != null) source.azureKinectInput.StopCapture();
        }

        void Update()
        {
            if (!HasShaders()) return;

            // Spout uses its sender size; webcam/video use their configured processing resolution.
            source.UpdateReceivedSize();
            ApplyPlaneScale();
            int w = Mathf.Max(source.DesiredSize.x, 16);
            int h = Mathf.Max(source.DesiredSize.y, 16);
            if (allocated && w == source.Width && h == source.Height && inputRevision == source.InputRevision) return;

            ReleaseAll();
            source.Allocate(w, h);
            compute.Allocate(w, h);
            processor.Allocate(w, h);
            allocated = true;
            inputRevision = source.InputRevision;
        }

        void LateUpdate()
        {
            // VideoPlayer may deliver its first frame after Update; rebuild history on
            // the next Update before processing that new source.
            if (!allocated || inputRevision != source.InputRevision) return;

            source.Execute();
            compute.Execute(source);
            source.Commit();
            processor.Execute(source, compute.RawFlow);

            if (metrics != null && metrics.enabled) metrics.Execute(processor.Output, plane);
            if (debugView != null && debugView.enabled) debugView.Render(this, processor.shader);
        }

        // Plane size from planeScale and the Spout texture aspect ratio. Also called by FlowPlane in edit mode,
        // where OnEnable has not run (until a sender is received, the source default size is used).
        internal void ApplyPlaneScale()
        {
            FlowPlane target = plane != null ? plane : GetComponentInChildren<FlowPlane>();
            OpticalFlowSource input = source != null ? source : GetComponent<OpticalFlowSource>();
            if (target == null || input == null) { RestorePlaneFraming(); return; }
            if (Application.isPlaying && input.framePlayArea && fitPlaneToPlayArea && FitPlaneToPlayArea(target, input)) return;
            RestorePlaneFraming();

            Vector2Int size = input.DesiredSize;
            Vector4 crop = input.EffectiveCrop;
            float width = size.x * (crop.z - crop.x);
            float height = size.y * (crop.w - crop.y);
            float aspect = width > 0 && height > 0 ? width / height : 1;

            Vector3 scale = new Vector3(planeScale * aspect, planeScale, 1);
            if (target.transform.localScale != scale) target.transform.localScale = scale;
        }

        bool FitPlaneToPlayArea(FlowPlane target, OpticalFlowSource input)
        {
            var brush = GetComponent<TwoHandForceBrush>();
            Camera camera = brush != null ? brush.ParticleCamera : Camera.main;
            if (camera == null || Screen.width <= 0 || Screen.height <= 0) return false;
            var preview = GetComponent<OpticalFlowDebugView>();
            Vector2Int size = input.DesiredSize;
            Rect rect = preview != null ? preview.VideoScreenRect(size.x, size.y) :
                OpticalFlowDebugView.FitScreen(Mathf.RoundToInt(Mathf.Max(.1f, input.playAreaAspect) * 10000), 10000);
            Rect viewport = camera.rect;
            if (!OpticalFlowVideoMapping.ScreenToViewport(rect.xMin, rect.yMin, Screen.width, Screen.height,
                    viewport.x, viewport.y, viewport.width, viewport.height, out float u0, out float v0) ||
                !OpticalFlowVideoMapping.ScreenToViewport(rect.xMax, rect.yMax, Screen.width, Screen.height,
                    viewport.x, viewport.y, viewport.width, viewport.height, out float u1, out float v1) || u1 <= u0 || v1 <= v0) return false;

            if (framedPlane != target)
            {
                RestorePlaneFraming();
                framedPlane = target;
                savedPlanePosition = target.transform.localPosition;
                savedPlaneRotation = target.transform.localRotation;
                savedPlaneScale = target.transform.localScale;
            }
            Transform parent = target.transform.parent;
            Vector3 anchor = parent != null ? parent.TransformPoint(savedPlanePosition) : savedPlanePosition;
            float depth = Vector3.Dot(anchor - camera.transform.position, camera.transform.forward);
            if (depth <= camera.nearClipPlane)
                depth = Mathf.Max(brush != null ? brush.interactionDepth : 10, camera.nearClipPlane + .01f);
            // ViewportToWorldPoint supports perspective and orthographic cameras,
            // including camera viewport offsets. The quad remains at particle depth.
            Vector3 bottomLeft = camera.ViewportToWorldPoint(new Vector3(u0, v0, depth));
            Vector3 bottomRight = camera.ViewportToWorldPoint(new Vector3(u1, v0, depth));
            Vector3 topLeft = camera.ViewportToWorldPoint(new Vector3(u0, v1, depth));
            Transform frame = target.transform;
            frame.SetPositionAndRotation(bottomLeft + (bottomRight - bottomLeft + topLeft - bottomLeft) * .5f, camera.transform.rotation);
            // Compensate parent scale so a world-space metre remains a metre,
            // including along Z where the force depth band is measured.
            float sx = parent != null ? parent.TransformVector(frame.localRotation * Vector3.right).magnitude : 1;
            float sy = parent != null ? parent.TransformVector(frame.localRotation * Vector3.up).magnitude : 1;
            float sz = parent != null ? parent.TransformVector(frame.localRotation * Vector3.forward).magnitude : 1;
            frame.localScale = new Vector3((bottomRight - bottomLeft).magnitude / Mathf.Max(sx, .0001f),
                (topLeft - bottomLeft).magnitude / Mathf.Max(sy, .0001f), 1 / Mathf.Max(sz, .0001f));
            return true;
        }

        void RestorePlaneFraming()
        {
            if (framedPlane == null) return;
            framedPlane.transform.localPosition = savedPlanePosition;
            framedPlane.transform.localRotation = savedPlaneRotation;
            framedPlane.transform.localScale = savedPlaneScale;
            framedPlane = null;
        }

        void ReleaseAll()
        {
            if (!allocated) return;
            source.Release();
            compute.Release();
            processor.Release();
            allocated = false;
        }

        bool HasShaders()
        {
            if (source.shader != null && compute.shader != null && processor.shader != null) return true;

            if (!warnedMissingShaders) Debug.LogWarning("OpticalFlowManager : compute shaders are not assigned", this);
            warnedMissingShaders = true;
            return false;
        }

        // Pushes the flow into a VFX Graph using the "Optical Flow Force" block. Graphs without it are skipped.
        // weight : per emitter multiplier (OrbGroup.opticalFlowWeight)
        public void ApplyTo(VisualEffect vfx, float weight)
        {
            if (!vfx.HasVector4(FlowIDs.VfxParams)) return;

            float gain = forceEnabled && FlowMap != null && plane != null ? intensity * weight : 0;

            // x = add strength, y = depth band, z = wind speed, w = wind rate
            vfx.SetVector4(FlowIDs.VfxParams, new Vector4(
                strength * (1 - windBlend) * gain,
                depthBand,
                windSpeed,
                windDrag * windBlend * gain));

            if (gain <= 0) return;

            vfx.SetTexture(FlowIDs.VfxFlowMap, FlowMap);
            vfx.SetMatrix4x4(FlowIDs.VfxWorldToPlane, plane.WorldToPlane);
            vfx.SetVector3(FlowIDs.VfxPlaneRight, plane.Right);
            vfx.SetVector3(FlowIDs.VfxPlaneUp, plane.Up);
        }
    }
}
