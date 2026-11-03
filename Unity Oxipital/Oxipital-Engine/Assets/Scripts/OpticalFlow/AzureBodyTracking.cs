using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

namespace Oxipital
{
    [StructLayout(LayoutKind.Sequential)]
    internal struct AzureBodyJoint
    {
        public float X, Y, Z, Qw, Qx, Qy, Qz;
        public int Confidence;
    }

    internal struct AzureHandFrame
    {
        public AzureBodyJoint Left, Right;
        public uint BodyId;
        public bool HasBody;
        public long Sequence, ArrivalTicks;
        public float FPS;
        public string Status;
    }

    internal sealed class AzureBodyTrackingState
    {
        [StructLayout(LayoutKind.Sequential)] struct Point3 { public float X, Y, Z; }
        [StructLayout(LayoutKind.Sequential)] struct Point2 { public float X, Y; }
        [DllImport("k4a", CallingConvention = CallingConvention.Cdecl)]
        static extern int k4a_calibration_3d_to_2d(IntPtr calibration, ref Point3 point, int source, int target, out Point2 pixel, out int valid);
        readonly object gate = new object();
        AzureHandFrame frame;
        byte[] calibration;
        int width, height;
        public void SetCalibration(byte[] value, int w, int h) { lock (gate) { calibration = value; width = w; height = h; } }
        public bool TryProject(float x, float y, float z, out float u, out float v)
        {
            u = v = 0;
            byte[] data;
            int w, h;
            lock (gate) { data = calibration; w = width; h = height; }
            if (data == null || z <= 0) return false;
            var pinned = GCHandle.Alloc(data, GCHandleType.Pinned);
            try
            {
                var point = new Point3 { X = x * 1000, Y = -y * 1000, Z = z * 1000 };
                if (k4a_calibration_3d_to_2d(pinned.AddrOfPinnedObject(), ref point, 0, 0, out var pixel, out int valid) != 0 || valid == 0) return false;
                // UV of the upright IR image after the top-down buffer correction.
                u = (pixel.X + .5f) / w;
                v = 1 - (pixel.Y + .5f) / h;
                return !float.IsNaN(u) && !float.IsNaN(v) && !float.IsInfinity(u) && !float.IsInfinity(v);
            }
            finally { pinned.Free(); }
        }
        public AzureHandFrame Read() { lock (gate) return frame; }
        public void Publish(AzureHandFrame value) { lock (gate) frame = value; }
    }

    // A separate inference worker consumes a latest-capture mailbox. One inference
    // is in flight at a time so a slow GPU cannot create an ever-growing delay.
    internal sealed class AzureBodyTracking : IDisposable
    {
        [StructLayout(LayoutKind.Sequential)]
        internal struct TrackerConfig
        {
            public int Orientation, ProcessingMode, GPU;
            public IntPtr ModelPath;
        }
        [DllImport("k4abt", CallingConvention = CallingConvention.Cdecl)]
        static extern int k4abt_tracker_create(IntPtr calibration, TrackerConfig config, out IntPtr tracker);
        [DllImport("k4abt", CallingConvention = CallingConvention.Cdecl)]
        static extern int k4abt_tracker_enqueue_capture(IntPtr tracker, IntPtr capture, int timeout);
        [DllImport("k4abt", CallingConvention = CallingConvention.Cdecl)]
        static extern int k4abt_tracker_pop_result(IntPtr tracker, out IntPtr frame, int timeout);
        [DllImport("k4abt", CallingConvention = CallingConvention.Cdecl)]
        static extern void k4abt_tracker_shutdown(IntPtr tracker);
        [DllImport("k4abt", CallingConvention = CallingConvention.Cdecl)]
        static extern void k4abt_tracker_destroy(IntPtr tracker);
        [DllImport("k4abt", CallingConvention = CallingConvention.Cdecl)]
        static extern uint k4abt_frame_get_num_bodies(IntPtr frame);
        [DllImport("k4abt", CallingConvention = CallingConvention.Cdecl)]
        static extern uint k4abt_frame_get_body_id(IntPtr frame, uint index);
        [DllImport("k4abt", CallingConvention = CallingConvention.Cdecl)]
        static extern int k4abt_frame_get_body_skeleton(IntPtr frame, uint index, IntPtr skeleton);
        [DllImport("k4abt", CallingConvention = CallingConvention.Cdecl)]
        static extern void k4abt_frame_release(IntPtr frame);
        [DllImport("k4a", CallingConvention = CallingConvention.Cdecl)]
        static extern void k4a_capture_reference(IntPtr capture);
        [DllImport("k4a", CallingConvention = CallingConvention.Cdecl)]
        static extern void k4a_capture_release(IntPtr capture);

        readonly object gate = new object();
        readonly Thread thread;
        readonly AzureBodyTrackingState state;
        readonly byte[] calibration;
        readonly string modelPath;
        readonly int gpu;
        IntPtr pending;
        long pendingArrival;
        bool stopping, finished;

        public AzureBodyTracking(byte[] calibration, AzureBodyTrackingState state, string modelPath, int gpu)
        {
            this.calibration = calibration;
            this.state = state;
            this.modelPath = modelPath;
            this.gpu = gpu;
            state.Publish(new AzureHandFrame { Status = "Initializing body tracker (DirectML)" });
            thread = new Thread(Run) { IsBackground = true, Name = "Oxipital Azure body tracking" };
            thread.Start();
        }

        public void Submit(IntPtr capture)
        {
            lock (gate)
            {
                if (stopping || finished) return;
                k4a_capture_reference(capture);
                if (pending != IntPtr.Zero) k4a_capture_release(pending);
                pending = capture;
                pendingArrival = Stopwatch.GetTimestamp();
            }
        }

        void Run()
        {
            IntPtr tracker = IntPtr.Zero, skeleton = IntPtr.Zero, path = IntPtr.Zero;
            GCHandle pinned = default;
            try
            {
                if (!File.Exists(modelPath)) throw new FileNotFoundException("Body model missing. Use Tools > Oxipital > Import Azure Body Tracking Runtime.");
                path = Marshal.StringToHGlobalAnsi(modelPath);
                pinned = GCHandle.Alloc(calibration, GCHandleType.Pinned);
                var config = new TrackerConfig { ProcessingMode = 4, GPU = gpu, ModelPath = path }; // DirectML
                if (k4abt_tracker_create(pinned.AddrOfPinnedObject(), config, out tracker) != 0)
                    throw new InvalidOperationException("Body tracker initialization failed. Check DirectML/ONNX dependencies and GPU driver.");
                skeleton = Marshal.AllocHGlobal(32 * 32); // 32 joints, 32 bytes each in k4abttypes.h
                bool awaiting = false;
                long captureArrival = 0;
                var clock = Stopwatch.StartNew();
                double window = 0, lastSeen = -1;
                int results = 0;
                uint selected = uint.MaxValue;
                var output = new AzureHandFrame { Status = "Waiting for a body" };
                while (true)
                {
                    lock (gate) if (stopping) break;
                    if (awaiting)
                    {
                        int result = k4abt_tracker_pop_result(tracker, out IntPtr bodyFrame, 0);
                        if (result == 1) throw new InvalidOperationException("Body tracking inference failed");
                        if (result == 0)
                        {
                            try
                            {
                                uint count = k4abt_frame_get_num_bodies(bodyFrame), candidate = uint.MaxValue;
                                float nearest = float.MaxValue;
                                for (uint i = 0; i < count; i++)
                                {
                                    uint id = k4abt_frame_get_body_id(bodyFrame, i);
                                    if (id == selected) { candidate = i; break; }
                                    if (selected != uint.MaxValue && clock.Elapsed.TotalSeconds - lastSeen < .75) continue;
                                    if (k4abt_frame_get_body_skeleton(bodyFrame, i, skeleton) != 0) continue;
                                    float z = Marshal.PtrToStructure<AzureBodyJoint>(skeleton).Z;
                                    if (z > 0 && z < nearest) { nearest = z; candidate = i; }
                                }
                                output.HasBody = candidate != uint.MaxValue && k4abt_frame_get_body_skeleton(bodyFrame, candidate, skeleton) == 0;
                                if (output.HasBody)
                                {
                                    selected = k4abt_frame_get_body_id(bodyFrame, candidate);
                                    lastSeen = clock.Elapsed.TotalSeconds;
                                    output.BodyId = selected;
                                    output.Left = Marshal.PtrToStructure<AzureBodyJoint>(IntPtr.Add(skeleton, 8 * 32));
                                    output.Right = Marshal.PtrToStructure<AzureBodyJoint>(IntPtr.Add(skeleton, 15 * 32));
                                }
                                output.Sequence++;
                                output.ArrivalTicks = captureArrival;
                                output.Status = output.HasBody ? "Tracking hands" : "Waiting for a body";
                                results++;
                                double now = clock.Elapsed.TotalSeconds;
                                if (now - window >= 1) { output.FPS = (float)(results / (now - window)); window = now; results = 0; }
                                state.Publish(output);
                            }
                            finally { k4abt_frame_release(bodyFrame); }
                            awaiting = false;
                        }
                    }
                    if (!awaiting)
                    {
                        IntPtr capture;
                        lock (gate) { capture = pending; captureArrival = pendingArrival; pending = IntPtr.Zero; }
                        if (capture != IntPtr.Zero)
                        {
                            try
                            {
                                int result = k4abt_tracker_enqueue_capture(tracker, capture, 0);
                                if (result == 1) throw new InvalidOperationException("Body tracking capture submission failed");
                                awaiting = result == 0;
                            }
                            finally { k4a_capture_release(capture); }
                        }
                    }
                    Thread.Sleep(2);
                }
            }
            catch (Exception e)
            {
                state.Publish(new AzureHandFrame { Status = e is DllNotFoundException
                    ? "Body runtime missing. Import Azure Body Tracking Runtime and restart Unity." : e.Message });
            }
            finally
            {
                lock (gate)
                {
                    finished = true;
                    if (pending != IntPtr.Zero) k4a_capture_release(pending);
                    pending = IntPtr.Zero;
                }
                if (tracker != IntPtr.Zero) { k4abt_tracker_shutdown(tracker); k4abt_tracker_destroy(tracker); }
                if (skeleton != IntPtr.Zero) Marshal.FreeHGlobal(skeleton);
                if (path != IntPtr.Zero) Marshal.FreeHGlobal(path);
                if (pinned.IsAllocated) pinned.Free();
            }
        }

        public void Dispose()
        {
            lock (gate) stopping = true;
            thread.Join(2000);
        }
    }
}
