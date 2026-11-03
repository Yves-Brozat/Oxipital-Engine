using System;
using UnityEngine;

namespace Oxipital
{
    public class OpticalFlowKinectInput : MonoBehaviour
    {
        public enum KinectStream { Infrared, RGB }
        [Tooltip("Infrared opens only an IR reader; it does not wait for RGB exposure or synchronized RGB frames.")]
        public KinectStream stream = KinectStream.Infrared;
        [Range(64, 512)] public int processingWidth = 256;
        [Range(.1f, 128), Tooltip("Fixed IR intensity multiplier. Avoid saturation; changing the gain resets flow history.")]
        public float infraredGain = 4;

        public Texture Texture => texture;
        public float CaptureFPS { get; private set; }
        public float ReceivedFPS { get; private set; }
        public float UnityUpdateFPS { get; private set; }
        public float AcquireMilliseconds { get; private set; }
        public float UploadMilliseconds { get; private set; }
        public long SkippedFrames { get; private set; }
        public float FrameAge => texture != null ? (float)(Time.realtimeSinceStartupAsDouble - lastArrival) : float.PositiveInfinity;
        public long FrameNumber { get; private set; }
        public int Revision { get; private set; }
        public string Status { get; private set; } = "Select Kinect on Optical Flow Source to start";
        internal virtual string SensorName => "Kinect V2";
        internal virtual bool IsInfrared => stream == KinectStream.Infrared;
        internal virtual int SensorWidth => IsInfrared ? 512 : 1920;
        internal virtual int SensorHeight => IsInfrared ? 424 : 1080;
        internal virtual int Configuration => (int)stream;
        internal virtual KinectV2FramePump CreateCapture() => new KinectV2FramePump(IsInfrared);
        internal Vector2Int WorkingSize => new Vector2Int(Mathf.Clamp(processingWidth, 64, 512),
            Mathf.RoundToInt(Mathf.Clamp(processingWidth, 64, 512) * (float)SensorHeight / SensorWidth));

        KinectV2FramePump capture;
        byte[] uploadBuffer;
        Texture2D texture;
        int openedConfiguration;
        bool attempted;
        int windowFrames, windowUpdates;
        double windowStart, lastArrival;
        long uploadedSequence;
        float appliedGain;

        // Polled by the manager before allocation/processing, independent of script Update order.
        internal void PrepareInput()
        {
            if (!Application.isPlaying || !isActiveAndEnabled) return;
            if (attempted && openedConfiguration != Configuration) StopCapture();
            if (!attempted) StartCapture();
            if (capture == null) return;
            try
            {
                if (appliedGain != infraredGain) { appliedGain = infraredGain; Revision++; }
                windowUpdates++;
                if (capture.TryCopyLatest(ref uploadBuffer, uploadedSequence, out var stats))
                {
                    long uploadStarted = System.Diagnostics.Stopwatch.GetTimestamp();
                    if (texture == null)
                    {
                        texture = new Texture2D(SensorWidth, SensorHeight,
                            IsInfrared ? TextureFormat.R16 : TextureFormat.RGBA32, false, true);
                        texture.name = SensorName + (IsInfrared ? " Infrared" : " RGB");
                        texture.wrapMode = TextureWrapMode.Clamp;
                        texture.filterMode = FilterMode.Bilinear;
                        Revision++;
                    }
                    texture.LoadRawTextureData(uploadBuffer);
                    texture.Apply(false, false);
                    UploadMilliseconds = (float)((System.Diagnostics.Stopwatch.GetTimestamp() - uploadStarted)
                        * 1000.0 / System.Diagnostics.Stopwatch.Frequency);
                    SkippedFrames += Math.Max(0, stats.Sequence - uploadedSequence - 1);
                    uploadedSequence = stats.Sequence;
                    FrameNumber++;
                    windowFrames++;
                    lastArrival = Time.realtimeSinceStartupAsDouble;
                    Status = "Receiving " + texture.name;
                }
                CaptureFPS = stats.CaptureFPS;
                AcquireMilliseconds = stats.AcquireMilliseconds;
                if (stats.Error != null)
                {
                    if (Status != stats.Error) Debug.LogWarning("OpticalFlowKinectInput: " + stats.Error, this);
                    ReceivedFPS = 0;
                    Status = stats.Error;
                    return;
                }
                double now = Time.realtimeSinceStartupAsDouble;
                if (now - windowStart >= 1)
                {
                    ReceivedFPS = (float)(windowFrames / (now - windowStart));
                    UnityUpdateFPS = (float)(windowUpdates / (now - windowStart));
                    windowFrames = 0;
                    windowUpdates = 0;
                    windowStart = now;
                }
                if (now - lastArrival > 2) Status = stats.Available
                    ? "Sensor available, but no new frames; check connection, then Restart Kinect"
                    : "Kinect unavailable; check USB 3.0 and power, then Restart Kinect";
            }
            catch (Exception e) { Fail(e); }
        }

        void StartCapture()
        {
            attempted = true;
            openedConfiguration = Configuration;
            windowStart = lastArrival = Time.realtimeSinceStartupAsDouble;
#if UNITY_EDITOR_WIN || UNITY_STANDALONE_WIN
            try
            {
                capture = CreateCapture();
                Status = "Waiting for " + SensorName;
                Revision++;
            }
            catch (Exception e) { Fail(e); }
#else
            Status = SensorName + " input requires Windows";
#endif
        }

        public void RestartCapture()
        {
            StopCapture();
            if (Application.isPlaying && isActiveAndEnabled) StartCapture();
        }

        internal void StopCapture()
        {
            bool hadInput = capture != null || texture != null || attempted;
            capture?.Dispose();
            capture = null;
            if (texture != null) Destroy(texture);
            texture = null;
            uploadBuffer = null;
            attempted = false;
            CaptureFPS = ReceivedFPS = UnityUpdateFPS = UploadMilliseconds = AcquireMilliseconds = 0;
            windowFrames = windowUpdates = 0;
            uploadedSequence = SkippedFrames = 0;
            if (hadInput) Revision++;
            if (hadInput) Status = "Kinect stopped";
        }

        void Fail(Exception error)
        {
            StopCapture();
            attempted = true; // Retry explicitly; do not reopen a failing device every frame.
            Status = error is DllNotFoundException ? "Install Kinect for Windows Runtime 2.x (Kinect20.dll missing)" : error.Message;
            Debug.LogWarning("OpticalFlowKinectInput: " + Status, this);
        }

        internal void Render(ComputeShader shader, RenderTexture target)
        {
            int kernel = shader.FindKernel("VideoInput");
            shader.SetInts("_Size", target.width, target.height);
            shader.SetTexture(kernel, "_Webcam", texture != null ? texture : Texture2D.blackTexture);
            shader.SetTexture(kernel, "_Video", Texture2D.blackTexture);
            shader.SetTexture(kernel, "_VideoOut", target);
            float aspect = (float)SensorWidth / SensorHeight;
            // Kinect buffers are top-down; Unity textures use bottom-up UVs.
            shader.SetVector("_WebcamInfo", new Vector4(aspect, 0, 1, texture != null ? 1 : 0));
            shader.SetVector("_VideoInfo", Vector4.zero);
            shader.SetFloat("_WebcamGain", IsInfrared ? infraredGain : 1);
            shader.SetFloat("_WebcamMonochrome", IsInfrared ? 1 : 0);
            shader.SetFloat("_VideoBlend", 0);
            OpticalFlowUtil.Dispatch(shader, kernel, target.width, target.height);
        }

        protected void OnDisable() => StopCapture();
    }
}
