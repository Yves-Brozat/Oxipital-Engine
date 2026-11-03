using UnityEngine;
using System.IO;

namespace Oxipital
{
    [DisallowMultipleComponent]
    public sealed class OpticalFlowAzureKinectInput : OpticalFlowKinectInput
    {
        [Min(0), Tooltip("Azure Kinect SDK device index. Close Azure Kinect Viewer before starting Unity capture.")]
        public int deviceIndex;
        [Tooltip("Both modes request 30 FPS with active IR. NFOV Unbinned: 640x576, narrow view. WFOV Binned: 512x512, wide view. Changing mode restarts capture and body tracking.")]
        public AzureKinectDepthMode depthMode = AzureKinectDepthMode.NFOVUnbinned;
        public string DepthModeDescription
        {
            get
            {
                var profile = AzureKinectModes.Get(depthMode);
                return profile.Name + ", " + profile.Width + " x " + profile.Height + ", 30 FPS requested";
            }
        }
        [Header("Body tracking (DirectML)")]
        public bool bodyTracking;
        [Min(0)] public int bodyTrackingGpu;
        [Tooltip("Empty uses the model imported into StreamingAssets/AzureKinect.")]
        public string bodyModelPath = "";
        [Range(1, 2)] public int minimumHandConfidence = 2;
        [Range(.1f, 1)] public float trackingTimeout = .3f;
        AzureBodyTrackingState bodyState;
        public string BodyStatus => !bodyTracking ? "Body tracking disabled" : bodyState?.Read().Status ?? "Start Azure capture to track hands";
        public float BodyFPS => bodyState?.Read().FPS ?? 0;
        public bool TryProjectSensorPoint(Vector3 point, out Vector2 uv)
        {
            uv = default;
            if (bodyState == null || !bodyState.TryProject(point.x, point.y, point.z, out float u, out float v)) return false;
            uv = new Vector2(u, v);
            return true;
        }
        public bool TryGetHands(out Vector3 left, out Vector3 right, out uint bodyId)
        {
            var frame = bodyState?.Read() ?? default;
            left = new Vector3(frame.Left.X, -frame.Left.Y, frame.Left.Z) * .001f;
            right = new Vector3(frame.Right.X, -frame.Right.Y, frame.Right.Z) * .001f;
            bodyId = frame.BodyId;
            double age = (System.Diagnostics.Stopwatch.GetTimestamp() - frame.ArrivalTicks) / (double)System.Diagnostics.Stopwatch.Frequency;
            return bodyTracking && isActiveAndEnabled && Texture != null && FrameAge < trackingTimeout && frame.HasBody && age < trackingTimeout &&
                !float.IsNaN(left.sqrMagnitude) && !float.IsInfinity(left.sqrMagnitude) &&
                !float.IsNaN(right.sqrMagnitude) && !float.IsInfinity(right.sqrMagnitude) &&
                frame.Left.Confidence >= minimumHandConfidence && frame.Right.Confidence >= minimumHandConfidence;
        }

        internal override string SensorName => "Azure Kinect IR";
        internal override bool IsInfrared => true;
        internal override int SensorWidth => AzureKinectModes.Get(depthMode).Width;
        internal override int SensorHeight => AzureKinectModes.Get(depthMode).Height;
        internal override int Configuration => unchecked(Mathf.Max(0, deviceIndex) * 397 ^ (bodyTracking ? 8191 : 0) ^
            bodyTrackingGpu * 65537 ^ (bodyModelPath ?? "").GetHashCode() ^ (int)depthMode * 104729);
        internal override KinectV2FramePump CreateCapture()
        {
            uint index = (uint)Mathf.Max(0, deviceIndex); // Read Unity state before starting the worker.
            bodyState = bodyTracking ? new AzureBodyTrackingState() : null;
            var sink = bodyState;
            string path = string.IsNullOrWhiteSpace(bodyModelPath)
                ? Path.Combine(Application.streamingAssetsPath, "AzureKinect", "body_model.onnx.bytes") : Path.GetFullPath(bodyModelPath);
            int gpu = Mathf.Max(0, bodyTrackingGpu);
            var mode = depthMode;
            var profile = AzureKinectModes.Get(mode);
            return new KinectV2FramePump(true, _ => new AzureKinectCapture(index, sink, path, gpu, mode), false, profile.FrameBytes,
                "Azure Kinect native SDK not found. Install Sensor SDK 1.4.2, then use Tools > Oxipital > Import Azure Kinect Runtime and restart Unity.");
        }

        void Reset()
        {
            infraredGain = 32;
            processingWidth = 256;
        }
    }
}
