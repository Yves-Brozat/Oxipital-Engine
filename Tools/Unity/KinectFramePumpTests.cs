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
        // Force-plane corners and tracked hands use the same screen -> camera
        // conversion: central 4:3 play area inside a 1920x1080 output.
        Require(OpticalFlowVideoMapping.ScreenToViewport(240, 0, 1920, 1080, 0, 0, 1, 1, out u, out v) &&
            Math.Abs(u - .125f) < .0001f && Math.Abs(v) < .0001f, "Force plane lost the left pillarbox offset");
        Require(OpticalFlowVideoMapping.ScreenToViewport(1680, 1080, 1920, 1080, 0, 0, 1, 1, out u, out v) &&
            Math.Abs(u - .875f) < .0001f && Math.Abs(v - 1) < .0001f, "Force plane covered the cropped side margin");
        Require(OpticalFlowVideoMapping.ScreenToViewport(240, 0, 1920, 1080, .125f, 0, .75f, 1, out u, out v) &&
            Math.Abs(u) < .0001f && Math.Abs(v) < .0001f, "Force plane applied camera viewport offsets twice");
        Require(OpticalFlowVideoMapping.ScreenToViewport(1680, 1080, 1920, 1080, .125f, 0, .75f, 1, out u, out v) &&
            Math.Abs(u - 1) < .0001f && Math.Abs(v - 1) < .0001f, "Force plane failed to fill a 4:3 camera viewport");
        float left = 0, right = 0, bottom = 0, top = 0;
        OpticalFlowVideoMapping.Frame(1, 4f / 3f, 2, .5f, .5f, ref left, ref right, ref bottom, ref top);
        Require(Math.Abs(left - .25f) < .0001f && Math.Abs(right - .25f) < .0001f &&
            Math.Abs(bottom - .3125f) < .0001f && Math.Abs(top - .3125f) < .0001f, "Square sensor did not produce a centred zoomed 4:3 rectangle");
        u = left; v = bottom;
        Require(OpticalFlowVideoMapping.SourceToOutput(ref u, ref v, left, right, bottom, top, false, false) &&
            Math.Abs(u) < .0001f && Math.Abs(v) < .0001f, "Play-area corner did not reach display corner");
        left = .1f; right = .2f; bottom = .05f; top = .1f;
        OpticalFlowVideoMapping.Frame(640f / 576, 4f / 3f, 1.5f, 0, 1, ref left, ref right, ref bottom, ref top);
        Require(left >= .0999f && right >= .1999f && bottom >= .0499f && top >= .0999f,
            "Shifted play area escaped existing crop");
        Require(Math.Abs((1 - left - right) * (640f / 576) / (1 - bottom - top) - 4f / 3f) < .0001f,
            "Shifted NFOV play area changed 4:3 aspect");
        var hands = new AzureHandFrame {
            HasBody = true,
            Left = new AzureBodyJoint { X = -100, Y = 50, Z = 2500, Confidence = 2 },
            Right = new AzureBodyJoint { X = 100, Y = 50, Z = 1500, Confidence = 0 }
        };
        Require(AzureHandTracking.Evaluate(hands, hands.Left, true, 2, false, .5f, 4) == AzureHandRejection.None,
            "Reliable left hand at 2.5 m was rejected because right hand was missing");
        Require(AzureHandTracking.Evaluate(hands, hands.Right, true, 2, false, .5f, 4) == AzureHandRejection.LowConfidence,
            "Unreliable right hand was accepted");
        hands.Right.Confidence = 2; hands.Left.Confidence = 0;
        Require(AzureHandTracking.Evaluate(hands, hands.Right, true, 2, false, .5f, 4) == AzureHandRejection.None,
            "Reliable right hand was rejected because left hand was missing");
        Require(AzureHandTracking.Evaluate(hands, hands.Right, false, 2, false, .5f, 4) == AzureHandRejection.StaleFrame,
            "Stale tracking was accepted");
        hands.Left.Confidence = 1;
        Require(AzureHandTracking.Evaluate(hands, hands.Left, true, 1, false, .5f, 4) == AzureHandRejection.None,
            "Adjustable low confidence threshold was ignored");
        hands.Left.Confidence = 2;
        Require(AzureHandTracking.Evaluate(hands, hands.Left, true, 2, true, 1, 2) == AzureHandRejection.OutsideDepthRange &&
            AzureHandTracking.Evaluate(hands, hands.Right, true, 2, true, 1, 2) == AzureHandRejection.None,
            "Depth filtering did not evaluate each hand independently");
        foreach (float depth in new[] { 1000f, 2000f })
        {
            hands.Left.Z = depth;
            Require(AzureHandTracking.Evaluate(hands, hands.Left, true, 2, true, 1, 2) == AzureHandRejection.None,
                "Hand at depth boundary was rejected");
        }
        hands.Left.Z = float.NaN;
        Require(AzureHandTracking.Evaluate(hands, hands.Left, true, 2, false, .5f, 4) == AzureHandRejection.InvalidPosition,
            "Non-finite hand position was accepted");
        hands.HasBody = false;
        Require(AzureHandTracking.Evaluate(hands, hands.Right, true, 2, false, .5f, 4) == AzureHandRejection.NoBody,
            "Missing body retained an active hand");
        return "PASS: capture lifecycle, native ABI, NFOV/WFOV, crop/mirror mapping, zoomed 4:3 play area, independent hands, confidence, freshness and depth filtering";
    }
}
