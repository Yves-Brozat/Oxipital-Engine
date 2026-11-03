using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
using Oxipital;

public static class KinectFramePumpTests
{
    sealed class FakeReader : IKinectV2FrameReader
    {
        readonly int owner = Thread.CurrentThread.ManagedThreadId;
        readonly Stopwatch clock = Stopwatch.StartNew();
        readonly byte[] data;
        GCHandle pinned;
        int count;
        bool held;
        public bool Disposed;
        public bool IsAvailable => true;
        public FakeReader(int bytes = 512 * 424 * 2)
        {
            data = new byte[bytes];
            pinned = GCHandle.Alloc(data, GCHandleType.Pinned);
        }
        void CheckThread()
        {
            if (Thread.CurrentThread.ManagedThreadId != owner) throw new Exception("Native access moved between threads");
        }
        public bool TryAcquire(out IntPtr pixels, out int bytes, out long timestamp)
        {
            CheckThread();
            if (held) throw new Exception("Previous native frame not released");
            pixels = IntPtr.Zero; bytes = 0; timestamp = 0;
            if (clock.Elapsed.TotalSeconds < (count + 1) / 30.0) return false;
            count++;
            var marker = BitConverter.GetBytes(count);
            Buffer.BlockCopy(marker, 0, data, 0, 4);
            Buffer.BlockCopy(marker, 0, data, data.Length - 4, 4);
            pixels = pinned.AddrOfPinnedObject(); bytes = data.Length; timestamp = count;
            held = true;
            return true;
        }
        public void ReleaseFrame() { CheckThread(); held = false; }
        public void Dispose()
        {
            CheckThread();
            if (held) throw new Exception("Frame leaked on shutdown");
            pinned.Free(); Disposed = true;
        }
    }

    static void Require(bool condition, string message) { if (!condition) throw new Exception(message); }

    public static string Run()
    {
        FakeReader reader = null;
        byte[] upload = null;
        long sequence = 0, skipped = 0;
        int uploaded = 0;
        KinectV2FrameStats stats = default;
        var pump = new KinectV2FramePump(true, ir => reader = new FakeReader(), false);
        try
        {
            for (int i = 0; i < 35; i++)
            {
                Thread.Sleep(100); // Deliberately consume at only 10 FPS.
                if (pump.TryCopyLatest(ref upload, sequence, out stats))
                {
                    Require(BitConverter.ToInt32(upload, 0) == stats.Sequence, "Stale frame delivered");
                    Require(BitConverter.ToInt32(upload, upload.Length - 4) == stats.Sequence, "Torn frame delivered");
                    skipped += stats.Sequence - sequence - 1;
                    sequence = stats.Sequence;
                    uploaded++;
                    bool another = pump.TryCopyLatest(ref upload, sequence, out var duplicate);
                    Require(!another || duplicate.Sequence > sequence, "Duplicate frame delivered");
                }
                Require(stats.Error == null, stats.Error);
            }
            Require(stats.CaptureFPS > 25 && stats.CaptureFPS < 35, "Capture rate was throttled by slow consumer");
            Require(skipped > 40, "Latest-frame mailbox did not skip old frames");
            Require(uploaded >= 30, "Slow consumer failed to receive latest frames");
        }
        finally { pump.Dispose(); }
        Require(reader != null && reader.Disposed, "Reader was not disposed on shutdown");
        pump.Dispose(); // Idempotent shutdown.

        var failing = new KinectV2FramePump(true, ir => throw new InvalidOperationException("test disconnect"), false);
        try
        {
            var wait = Stopwatch.StartNew();
            do
            {
                Thread.Sleep(5);
                failing.TryCopyLatest(ref upload, 0, out stats);
            } while (stats.Error == null && wait.Elapsed.TotalSeconds < 1);
            Require(stats.Error == "test disconnect", "Worker error did not reach main thread");
            Require(stats.CaptureFPS == 0, "Failed capture retained nonzero FPS");
        }
        finally { failing.Dispose(); }
        // Confirm the native struct uses the C ABI's one-byte bools and 4-byte alignment.
        Require(Marshal.SizeOf(typeof(AzureKinectCapture.DeviceConfiguration)) == 36, "Azure configuration ABI size mismatch");
        Require(Marshal.OffsetOf(typeof(AzureKinectCapture.DeviceConfiguration), "SynchronizedImagesOnly").ToInt32() == 16, "Azure bool offset mismatch");
        Require(Marshal.OffsetOf(typeof(AzureKinectCapture.DeviceConfiguration), "DepthDelayOffColorUsec").ToInt32() == 20, "Azure alignment mismatch");
        Require(Marshal.OffsetOf(typeof(AzureKinectCapture.DeviceConfiguration), "DisableStreamingIndicator").ToInt32() == 32, "Azure final bool offset mismatch");
        Require(Marshal.SizeOf(typeof(AzureBodyJoint)) == 32, "Body joint native ABI size mismatch");
        Require(Marshal.OffsetOf(typeof(AzureBodyJoint), "Confidence").ToInt32() == 28, "Joint confidence ABI offset mismatch");
        Require(Marshal.SizeOf(typeof(AzureBodyTracking.TrackerConfig)) == (IntPtr.Size == 8 ? 24 : 16), "Body tracker config ABI size mismatch");

        // Exercise buffer resizing and shutdown in both directions when the user
        // switches modes, keeping the same upload buffer as the component does.
        foreach (var mode in new[] { AzureKinectDepthMode.NFOVUnbinned, AzureKinectDepthMode.WFOVBinned, AzureKinectDepthMode.NFOVUnbinned })
        {
            int expectedBytes = mode == AzureKinectDepthMode.NFOVUnbinned ? 640 * 576 * 2 : 512 * 512 * 2;
            var profile = AzureKinectModes.Get(mode);
            FakeReader azureReader = null;
            var azure = new KinectV2FramePump(true, ir => azureReader = new FakeReader(expectedBytes), false,
                profile.FrameBytes, "Azure runtime missing");
            try
            {
                var wait = Stopwatch.StartNew();
                bool received;
                do
                {
                    Thread.Sleep(5);
                    received = azure.TryCopyLatest(ref upload, 0, out stats);
                } while (!received && stats.Error == null && wait.Elapsed.TotalSeconds < 1);
                Require(received && upload.Length == expectedBytes, "Azure IR mode switch did not resize upload buffer");
                Require(BitConverter.ToInt32(upload, upload.Length - 4) == stats.Sequence, "Azure IR frame was truncated");
            }
            finally { azure.Dispose(); }
            Require(azureReader != null && azureReader.Disposed, "Azure reader not closed on mode switch");
        }
        // Round-trip the actual shader order: output -> flip -> crop -> source.
        float u = .725f, v = .275f;
        Require(OpticalFlowVideoMapping.SourceToOutput(ref u, ref v, .2f, .1f, .1f, .2f, true, true), "Cropped video projection rejected a valid hand");
        Require(Math.Abs(u - .25f) < .0001f && Math.Abs(v - .75f) < .0001f, "Hand projection does not invert shader crop/mirror order");
        u = .1f; v = .5f;
        Require(!OpticalFlowVideoMapping.SourceToOutput(ref u, ref v, .2f, .1f, 0, 0, false, false), "Hand outside crop was displayed inside frame");
        u = .5f; v = .5f;
        Require(OpticalFlowVideoMapping.SourceToOutput(ref u, ref v, 0, 0, 0, 0, false, false) && u == .5f && v == .5f, "Uncropped projection moved image center");
        Require(OpticalFlowVideoMapping.ScreenToViewport(500, 800, 1000, 1000, 0, 0, 1, 1, out u, out v) &&
            Math.Abs(u - .5f) < .0001f && Math.Abs(v - .8f) < .0001f, "High hands did not map to the upper camera viewport");
        Require(OpticalFlowVideoMapping.ScreenToViewport(500, 200, 1000, 1000, .25f, 0, .5f, 1, out u, out v) &&
            Math.Abs(u - .5f) < .0001f && Math.Abs(v - .2f) < .0001f, "Sub-viewport camera mapping changed image coordinates");
        Require(!OpticalFlowVideoMapping.ScreenToViewport(0, 0, 1000, 1000, 0, 0, 0, 1, out u, out v), "Zero-width camera viewport was accepted");
        return "PASS: capture lifecycle, native ABI, NFOV/WFOV, crop/mirror mapping and particle-camera viewport mapping";
    }
}
