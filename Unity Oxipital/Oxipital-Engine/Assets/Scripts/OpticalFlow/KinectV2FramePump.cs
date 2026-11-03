using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

namespace Oxipital
{
    internal interface IKinectV2FrameReader : IDisposable
    {
        bool IsAvailable { get; }
        bool TryAcquire(out IntPtr pixels, out int bytes, out long timestamp);
        void ReleaseFrame();
    }

    internal struct KinectV2FrameStats
    {
        public long Sequence, ArrivalTicks;
        public float CaptureFPS, AcquireMilliseconds;
        public bool Available;
        public string Error;
    }

    // Owns the native reader on one MTA thread. A latest-frame mailbox replaces
    // older frames instead of building a queue when rendering cannot keep up.
    // No Unity APIs, textures, or Unity objects are touched by this thread.
    internal sealed class KinectV2FramePump : IDisposable
    {
        [DllImport("ole32.dll")]
        static extern int CoInitializeEx(IntPtr reserved, uint apartment);
        [DllImport("ole32.dll")]
        static extern void CoUninitialize();

        readonly object gate = new object();
        readonly ManualResetEvent stop = new ManualResetEvent(false);
        readonly Thread thread;
        readonly bool infrared;
        readonly Func<bool, IKinectV2FrameReader> open;
        readonly bool initializeCom;
        readonly int frameBytes;
        readonly string missingRuntimeMessage;
        byte[] latest, staging;
        KinectV2FrameStats stats;
        int disposeRequested;

        public KinectV2FramePump(bool infrared)
            : this(infrared, ir => new KinectV2Capture(ir), true) { }

        // Factory permits testing thread ownership and frame dropping without hardware.
        internal KinectV2FramePump(bool infrared, Func<bool, IKinectV2FrameReader> open, bool initializeCom)
            : this(infrared, open, initializeCom, infrared ? 512 * 424 * 2 : 1920 * 1080 * 4,
                "Install Kinect for Windows Runtime 2.x (Kinect20.dll missing)") { }

        internal KinectV2FramePump(bool infrared, Func<bool, IKinectV2FrameReader> open, bool initializeCom,
            int frameBytes, string missingRuntimeMessage)
        {
            this.infrared = infrared;
            this.open = open;
            this.initializeCom = initializeCom;
            this.frameBytes = frameBytes;
            this.missingRuntimeMessage = missingRuntimeMessage;
            latest = new byte[frameBytes];
            staging = new byte[frameBytes];
            thread = new Thread(Run) { IsBackground = true, Name = "Oxipital Kinect acquisition" };
            thread.Start();
        }

        public bool TryCopyLatest(ref byte[] destination, long previousSequence, out KinectV2FrameStats snapshot)
        {
            lock (gate)
            {
                snapshot = stats;
                if (snapshot.Sequence == 0 || snapshot.Sequence == previousSequence) return false;
                if (destination == null || destination.Length != frameBytes) destination = new byte[frameBytes];
                Buffer.BlockCopy(latest, 0, destination, 0, frameBytes);
                return true;
            }
        }

        void Run()
        {
            bool comInitialized = false;
            try
            {
                if (initializeCom)
                {
                    int result = CoInitializeEx(IntPtr.Zero, 0); // COINIT_MULTITHREADED
                    if (result < 0) Marshal.ThrowExceptionForHR(result);
                    comInitialized = true;
                }
                using (var reader = open(infrared))
                {
                    var clock = Stopwatch.StartNew();
                    double windowStart = 0, acquireTime = 0, nextAvailabilityCheck = 0;
                    int frames = 0, polls = 0;
                    long previousTimestamp = -1;
                    while (!stop.WaitOne(0))
                    {
                        long begin = Stopwatch.GetTimestamp();
                        try
                        {
                            if (reader.TryAcquire(out IntPtr pixels, out int bytes, out long timestamp) && timestamp != previousTimestamp)
                            {
                                if (pixels == IntPtr.Zero || bytes != frameBytes)
                                    throw new InvalidOperationException("Unexpected Kinect frame buffer size.");
                                Marshal.Copy(pixels, staging, 0, bytes);
                                previousTimestamp = timestamp;
                                lock (gate)
                                {
                                    var swap = latest;
                                    latest = staging;
                                    staging = swap;
                                    stats.Sequence++;
                                    stats.ArrivalTicks = Stopwatch.GetTimestamp();
                                }
                                frames++;
                            }
                        }
                        finally { reader.ReleaseFrame(); }
                        acquireTime += (Stopwatch.GetTimestamp() - begin) * 1000.0 / Stopwatch.Frequency;
                        polls++;
                        double now = clock.Elapsed.TotalSeconds;
                        if (now >= nextAvailabilityCheck)
                        {
                            bool available = reader.IsAvailable;
                            lock (gate) stats.Available = available;
                            nextAvailabilityCheck = now + 1;
                        }
                        if (now - windowStart >= 1)
                        {
                            lock (gate)
                            {
                                stats.CaptureFPS = (float)(frames / (now - windowStart));
                                stats.AcquireMilliseconds = (float)(acquireTime / Math.Max(polls, 1));
                            }
                            frames = polls = 0;
                            acquireTime = 0;
                            windowStart = now;
                        }
                        stop.WaitOne(2);
                    }
                }
            }
            catch (Exception e)
            {
                lock (gate)
                {
                    stats.CaptureFPS = 0;
                    stats.Error = e is DllNotFoundException
                        ? missingRuntimeMessage : e.Message;
                }
            }
            finally
            {
                if (comInitialized) CoUninitialize();
                // Event lifetime belongs to the worker; Dispose never frees a handle
                // while the native API may still be returning from a call.
                lock (gate) stop.Dispose();
            }
        }

        public void Dispose()
        {
            if (Interlocked.Exchange(ref disposeRequested, 1) != 0) return;
            lock (gate)
            {
                // Run can have already terminated after an error.
                if (thread.IsAlive)
                {
                    try { stop.Set(); }
                    catch (ObjectDisposedException) { }
                }
            }
            // Native resources remain owned by the worker if the driver is stuck.
            // Do not close COM pointers from the Unity thread or block the editor indefinitely.
            thread.Join(2000);
        }
    }
}
