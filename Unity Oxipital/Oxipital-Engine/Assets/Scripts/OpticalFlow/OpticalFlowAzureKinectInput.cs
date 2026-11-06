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
                return profile.Name + ", " + profile.Width + " x " + profile.Height + ", 30 FPS requested, depth " +
                    (depthMode == AzureKinectDepthMode.WFOVBinned ? "0.25-2.88 m" : "0.5-3.86 m") + " nominal";
            }
        }
        [Header("Body tracking (DirectML)")]
        public bool bodyTracking;
        [Min(0)] public int bodyTrackingGpu;
        [Tooltip("Empty uses the model imported into StreamingAssets/AzureKinect.")]
        public string bodyModelPath = "";
        [Range(1, 2)] public int minimumHandConfidence = 2;
        [Range(.1f, 1)] public float trackingTimeout = .3f;
        [Header("Hand depth zone (sensor metres)")]
        [Tooltip("Optional activation zone along the sensor Z axis. Does not extend the sensor's physical tracking range.")]
        public bool filterHandDepth;
        [Min(0)] public float minimumHandDepth = .5f;
        [Min(.01f)] public float maximumHandDepth = 4;
        [Range(.1f, 3), Tooltip("Half-width of the depth zone created by Calibrate Hand Depth.")]
        public float depthCalibrationMargin = .75f;
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
            TryGetIndependentHands(out left, out right, out bodyId, out bool leftTracked, out bool rightTracked);
            return leftTracked && rightTracked;
        }

        bool IsFresh(AzureHandFrame frame)
        {
            double age = (System.Diagnostics.Stopwatch.GetTimestamp() - frame.ArrivalTicks) / (double)System.Diagnostics.Stopwatch.Frequency;
            return bodyTracking && isActiveAndEnabled && Texture != null && FrameAge < trackingTimeout && age < trackingTimeout;
        }

        AzureHandRejection Evaluate(AzureHandFrame frame, AzureBodyJoint hand, bool filter)
            => AzureHandTracking.Evaluate(frame, hand, IsFresh(frame), minimumHandConfidence, filter,
                Mathf.Max(0, minimumHandDepth), Mathf.Max(minimumHandDepth, maximumHandDepth));

        public bool TryGetIndependentHands(out Vector3 left, out Vector3 right, out uint bodyId,
            out bool leftTracked, out bool rightTracked)
        {
            var frame = bodyState?.Read() ?? default;
            left = new Vector3(frame.Left.X, -frame.Left.Y, frame.Left.Z) * .001f;
            right = new Vector3(frame.Right.X, -frame.Right.Y, frame.Right.Z) * .001f;
            bodyId = frame.BodyId;
            leftTracked = Evaluate(frame, frame.Left, filterHandDepth) == AzureHandRejection.None;
            rightTracked = Evaluate(frame, frame.Right, filterHandDepth) == AzureHandRejection.None;
            return leftTracked || rightTracked;
        }

        public string HandDiagnostics(bool left)
        {
            var frame = bodyState?.Read() ?? default;
            var hand = left ? frame.Left : frame.Right;
            var reason = Evaluate(frame, hand, filterHandDepth);
            string state = reason == AzureHandRejection.None ? "suivi valide" :
                reason == AzureHandRejection.NoBody ? "aucun corps" :
                reason == AzureHandRejection.StaleFrame ? "image trop ancienne / capture inactive" :
                reason == AzureHandRejection.InvalidPosition ? "position invalide" :
                reason == AzureHandRejection.LowConfidence ? "confiance insuffisante" : "hors plage de profondeur";
            return (left ? "G" : "D") + " : " + state + (frame.HasBody
                ? " | Z " + (hand.Z * .001f).ToString("F2") + " m | confiance " + hand.Confidence + "/3" : "");
        }

        public bool CalibrateHandDepth()
        {
            var frame = bodyState?.Read() ?? default;
            // Ignore the old zone so calibration can recover hands outside it.
            bool left = Evaluate(frame, frame.Left, false) == AzureHandRejection.None;
            bool right = Evaluate(frame, frame.Right, false) == AzureHandRejection.None;
            if (!left && !right) return false;
            float depth = ((left ? frame.Left.Z : 0) + (right ? frame.Right.Z : 0)) * .001f / ((left ? 1 : 0) + (right ? 1 : 0));
            float margin = Mathf.Max(.1f, depthCalibrationMargin);
            minimumHandDepth = Mathf.Max(0, depth - margin);
            maximumHandDepth = depth + margin;
            filterHandDepth = true;
            return true;
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
