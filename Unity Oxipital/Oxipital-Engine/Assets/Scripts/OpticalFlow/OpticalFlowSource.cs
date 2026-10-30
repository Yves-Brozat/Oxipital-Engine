using System.Reflection;
using Klak.Spout;
using UnityEngine;

namespace Oxipital
{
    // Input stage : receives Spout, webcam, video, a webcam/video blend or the test source,
    // brings it to the working resolution / orientation and detects new camera frames on the GPU.
    //
    // Spout contract (RGBA 16 bit float) :
    //   SpoutFlow                : R = flow X, G = flow Y (signed), B = body mask, A = normalized depth
    //   SpoutMaskComputeInUnity  : R = luminance / body mask, A = normalized depth
    public class OpticalFlowSource : MonoBehaviour
    {
        // Preserve the serialized Spout values used by scenes and OSC.
        public enum FlowSourceMode { SpoutFlow, SpoutMaskComputeInUnity, Webcam, Video, Blend }
        public enum ChangeDetection { GPUDiff, EveryFrame, FixedRate }

        [Header("Input")]
        public FlowSourceMode mode = FlowSourceMode.SpoutMaskComputeInUnity;
        public string spoutName = "OxipitalFlow";
        public bool useTestSource = false;
        [OSCQuery.DoNotExpose]
        public OpticalFlowVideoInput videoInput;

        [Header("Orientation")]
        [InspectorName("Flip X (Mirror)"), Tooltip("Mirror the input image horizontally, including the flow and its aligned debug views.")]
        public bool mirror = false;
        [Tooltip("Flip the input image vertically, including the flow and its aligned debug views.")]
        public bool flipY = false;
        [Tooltip("Reverse the horizontal flow force without mirroring the input image.")]
        public bool invertX = false;
        [Tooltip("Reverse the vertical flow force without flipping the input image.")]
        public bool invertY = false;
        [Range(0, .45f)]
        public float cropLeft = 0;
        [Range(0, .45f)]
        public float cropRight = 0;
        [Range(0, .45f)]
        public float cropBottom = 0;
        [Range(0, .45f)]
        public float cropTop = 0;

        [Header("New Frame Detection")]
        public ChangeDetection changeDetection = ChangeDetection.GPUDiff;
        [Range(0, .01f)]
        public float changeThreshold = .0001f;
        [Range(1, 120)]
        public float fixedRate = 30;
        // No new frame for longer than this : the flow stops feeding the trail (frozen or lost source)
        [Range(0, 1)]
        public float staleTimeout = .1f;

        [OSCQuery.DoNotExpose]
        public ComputeShader shader;
        [OSCQuery.DoNotExpose]
        public SpoutReceiver receiver;
        [OSCQuery.DoNotExpose]
        public OpticalFlowTestSource testSource;

        RenderTexture input;
        RenderTexture current;
        RenderTexture previous;
        GraphicsBuffer state;
        float fixedRateTimer;

        int kCopy, kDetect, kCommit;
        bool seedHistory;
        Vector4 previousCrop;
        Vector2 previousFlipSign;
        SpoutReceiver suspendedReceiver;

        // Suspend only a receiver that was enabled, so manually disabled
        // receivers stay disabled when switching back from webcam/video.
        internal void SetSpoutActive(bool active)
        {
            if (suspendedReceiver != null && suspendedReceiver != receiver)
            {
                suspendedReceiver.enabled = true;
                suspendedReceiver = null;
            }
            if (receiver == null) return;
            if (active)
            {
                receiver.sourceName = spoutName;
                if (suspendedReceiver == receiver)
                {
                    receiver.enabled = true;
                    suspendedReceiver = null;
                }
            }
            else if (receiver.enabled)
            {
                receiver.enabled = false;
                suspendedReceiver = receiver;
            }
        }

        // The working resolution follows the Spout sender texture. This default is only used
        // until a sender has been received (and by the test source when nothing was ever received).
        const int DefaultWidth = 256;
        const int DefaultHeight = 212;
        Vector2Int receivedSize = new Vector2Int(DefaultWidth, DefaultHeight);
        bool warnedFormat;

        // KlakSpout only exposes our target texture : the sender texture lives in its internal receiver
        static readonly FieldInfo nativeReceiverField = typeof(SpoutReceiver).GetField("_receiver", BindingFlags.NonPublic | BindingFlags.Instance);
        static PropertyInfo nativeTextureProperty;

        // Resolution the pipeline should run at
        internal Vector2Int DesiredSize => receivedSize;

        // Received Spout image as is (before crop / mirror / flip)
        public RenderTexture Input => input;
        public RenderTexture Current => current;
        public RenderTexture Previous => previous;
        public GraphicsBuffer State => state;
        public int Width { get; private set; }
        public int Height { get; private set; }
        public bool IsFlowMode => mode == FlowSourceMode.SpoutFlow;
        public bool IsVideoInput => mode == FlowSourceMode.Webcam || mode == FlowSourceMode.Video || mode == FlowSourceMode.Blend;
        internal int InputRevision => ((int)mode * 397) ^ (useTestSource ? 131 : 0) ^
            (IsVideoInput && videoInput != null ? videoInput.Revision * 7919 : 0);
        public Vector2 FlowSign => new Vector2(invertX ? -1 : 1, invertY ? -1 : 1);
        public Vector4 MaskChannel => IsFlowMode ? new Vector4(0, 0, 1, 0) : new Vector4(1, 0, 0, 0);

        internal void Allocate(int w, int h)
        {
            Width = w;
            Height = h;

            input = OpticalFlowUtil.CreateRT("OpticalFlow Input", w, h, OpticalFlowUtil.RGBAHalf);
            current = OpticalFlowUtil.CreateRT("OpticalFlow Current", w, h, OpticalFlowUtil.RGBAHalf);
            previous = OpticalFlowUtil.CreateRT("OpticalFlow Previous", w, h, OpticalFlowUtil.RGBAHalf);

            state = new GraphicsBuffer(GraphicsBuffer.Target.Structured, 4, sizeof(float));
            state.SetData(new float[] { 1, 0, 0, 0 });
            seedHistory = true;

            kCopy = shader.FindKernel("Copy");
            kDetect = shader.FindKernel("DetectChange");
            kCommit = shader.FindKernel("Commit");
        }

        internal void Release()
        {
            // KlakSpout would otherwise keep blitting into a destroyed texture
            if (receiver != null && receiver.targetTexture == input) receiver.targetTexture = null;

            OpticalFlowUtil.Release(ref input);
            OpticalFlowUtil.Release(ref current);
            OpticalFlowUtil.Release(ref previous);
            OpticalFlowUtil.Release(ref state);
        }

        internal void Execute()
        {
            Texture source = input;

            if (useTestSource && testSource != null)
            {
                source = testSource.Render(this);
            }
            else if (IsVideoInput)
            {
                if (receiver != null && receiver.targetTexture == input) receiver.targetTexture = null;
                if (videoInput != null && videoInput.isActiveAndEnabled) videoInput.Render(shader, input, mode);
                else OpticalFlowUtil.Clear(input);
            }
            else if (receiver != null)
            {
                // Receiving into our own RGBAHalf texture : KlakSpout's internal buffer is 8 bit
                // and would clamp the negative flow values
                receiver.sourceName = spoutName;
                receiver.targetTexture = input;
            }

            shader.SetInts(FlowIDs.Size, Width, Height);

            // Copy with crop / mirror / flip
            Vector2 flipSign = new Vector2(mirror ? -1 : 1, flipY ? -1 : 1);
            Vector4 crop = new Vector4(cropLeft, cropBottom, 1 - cropRight, 1 - cropTop);
            // A change of framing is not camera motion. Restart the frame comparison
            // so toggling a flip does not create a full-frame impulse.
            if (crop != previousCrop || flipSign != previousFlipSign) seedHistory = true;
            previousCrop = crop;
            previousFlipSign = flipSign;
            shader.SetVector(FlowIDs.Crop, crop);
            shader.SetVector(FlowIDs.FlipSign, flipSign);
            shader.SetFloat(FlowIDs.FlowInRG, IsFlowMode ? 1 : 0);
            shader.SetTexture(kCopy, FlowIDs.Input, source);
            shader.SetTexture(kCopy, FlowIDs.Current, current);
            OpticalFlowUtil.Dispatch(shader, kCopy, Width, Height);

            // A new source has no previous camera frame; do not interpret its first image as motion.
            if (seedHistory)
            {
                Graphics.CopyTexture(current, previous);
                seedHistory = false;
            }

            // New frame detection
            shader.SetFloat(FlowIDs.ForceChange, GetForcedChange());
            shader.SetFloat(FlowIDs.ChangeThreshold, changeThreshold);
            shader.SetFloat(FlowIDs.DeltaTime, Time.unscaledDeltaTime);
            shader.SetTexture(kDetect, FlowIDs.CurrentRead, current);
            shader.SetTexture(kDetect, FlowIDs.Previous, previous);
            shader.SetBuffer(kDetect, FlowIDs.State, state);
            shader.Dispatch(kDetect, 1, 1, 1);
        }

        // Reads the size (and format) of the texture shared by the Spout sender.
        // Keeps the last known size while no sender is connected.
        internal void UpdateReceivedSize()
        {
            SetSpoutActive(!useTestSource && !IsVideoInput);
            if (IsVideoInput && !useTestSource)
            {
                if (videoInput == null) videoInput = GetComponent<OpticalFlowVideoInput>();
                if (videoInput == null) videoInput = gameObject.AddComponent<OpticalFlowVideoInput>();
                videoInput.PrepareInput(mode);
                receivedSize = videoInput.WorkingSize(mode);
                return;
            }
            if (useTestSource || receiver == null || nativeReceiverField == null) return;

            object nativeReceiver = nativeReceiverField.GetValue(receiver);
            if (nativeReceiver == null) return;

            if (nativeTextureProperty == null) nativeTextureProperty = nativeReceiver.GetType().GetProperty("Texture");
            Texture2D senderTexture = nativeTextureProperty?.GetValue(nativeReceiver) as Texture2D;
            if (senderTexture == null || senderTexture.width <= 0 || senderTexture.height <= 0) return;

            receivedSize = new Vector2Int(senderTexture.width, senderTexture.height);

            // An 8 bit sender clamps the signed flow values sent by TouchDesigner
            bool eightBit = senderTexture.format == TextureFormat.RGBA32 || senderTexture.format == TextureFormat.BGRA32;
            if (IsFlowMode && eightBit && !warnedFormat)
            {
                Debug.LogWarning($"OpticalFlowSource : Spout sender '{spoutName}' is 8 bit ({senderTexture.format}), negative flow values are lost. Set the TouchDesigner pixel format to 16-bit float (RGBA).", this);
                warnedFormat = true;
            }
        }

        // Called once the flow has been computed, so the flow stage still sees the previous frame
        internal void Commit()
        {
            shader.SetInts(FlowIDs.Size, Width, Height);
            shader.SetTexture(kCommit, FlowIDs.CurrentRead, current);
            shader.SetTexture(kCommit, FlowIDs.PreviousOut, previous);
            shader.SetBuffer(kCommit, FlowIDs.State, state);
            OpticalFlowUtil.Dispatch(shader, kCommit, Width, Height);
        }

        float GetForcedChange()
        {
            switch (changeDetection)
            {
                case ChangeDetection.EveryFrame:
                    return 1;

                case ChangeDetection.FixedRate:
                    float period = 1f / Mathf.Max(fixedRate, 1);
                    fixedRateTimer += Time.unscaledDeltaTime;
                    if (fixedRateTimer < period) return 0;
                    fixedRateTimer = Mathf.Repeat(fixedRateTimer, period);
                    return 1;

                default:
                    return -1;
            }
        }
    }
}
