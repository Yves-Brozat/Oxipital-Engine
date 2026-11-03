using System;
using System.Runtime.InteropServices;

namespace Oxipital
{
    public enum AzureKinectDepthMode { NFOVUnbinned, WFOVBinned }

    internal readonly struct AzureKinectProfile
    {
        public readonly int Width, Height, SDKMode;
        public readonly string Name;
        public int FrameBytes => Width * Height * 2;
        public AzureKinectProfile(int width, int height, int sdkMode, string name)
        { Width = width; Height = height; SDKMode = sdkMode; Name = name; }
    }

    internal static class AzureKinectModes
    {
        public static AzureKinectProfile Get(AzureKinectDepthMode mode)
        {
            switch (mode)
            {
                case AzureKinectDepthMode.NFOVUnbinned: return new AzureKinectProfile(640, 576, 2, "NFOV Unbinned");
                case AzureKinectDepthMode.WFOVBinned: return new AzureKinectProfile(512, 512, 3, "WFOV 2x2 Binned");
                default: throw new ArgumentOutOfRangeException(nameof(mode));
            }
        }
    }

    // Azure Kinect Sensor SDK 1.4 C ABI. No body-tracking SDK, cloud service,
    // RGB reader or managed SDK assembly is needed for the IR optical-flow source.
    internal sealed class AzureKinectCapture : IKinectV2FrameReader
    {
        [StructLayout(LayoutKind.Sequential)]
        internal struct DeviceConfiguration
        {
            public int ColorFormat, ColorResolution, DepthMode, CameraFPS;
            public byte SynchronizedImagesOnly;
            public int DepthDelayOffColorUsec, WiredSyncMode;
            public uint SubordinateDelayOffMasterUsec;
            public byte DisableStreamingIndicator;
        }

        internal static DeviceConfiguration GetInfraredConfiguration(AzureKinectDepthMode mode) => new DeviceConfiguration
        {
            ColorFormat = 0, // COLOR_MJPG (unused with color disabled)
            ColorResolution = 0, // COLOR_RESOLUTION_OFF
            DepthMode = AzureKinectModes.Get(mode).SDKMode,
            CameraFPS = 2, // FRAMES_PER_SECOND_30
            SynchronizedImagesOnly = 0,
            WiredSyncMode = 0 // STANDALONE
        };

        const string Library = "k4a";
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        static extern uint k4a_device_get_installed_count();
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        static extern int k4a_device_open(uint index, out IntPtr device);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        static extern int k4a_device_start_cameras(IntPtr device, ref DeviceConfiguration config);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        static extern void k4a_device_stop_cameras(IntPtr device);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        static extern void k4a_device_close(IntPtr device);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        static extern int k4a_device_get_capture(IntPtr device, out IntPtr capture, int timeoutMilliseconds);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        static extern IntPtr k4a_capture_get_ir_image(IntPtr capture);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        static extern void k4a_capture_release(IntPtr capture);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        static extern IntPtr k4a_image_get_buffer(IntPtr image);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        static extern UIntPtr k4a_image_get_size(IntPtr image);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        static extern int k4a_image_get_width_pixels(IntPtr image);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        static extern int k4a_image_get_height_pixels(IntPtr image);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        static extern int k4a_image_get_stride_bytes(IntPtr image);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        static extern ulong k4a_image_get_device_timestamp_usec(IntPtr image);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        static extern void k4a_image_release(IntPtr image);
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        static extern int k4a_device_get_calibration(IntPtr device, int depthMode, int colorResolution, [Out] byte[] calibration);

        IntPtr device, capture, image;
        bool started;
        AzureBodyTracking bodyTracker;
        readonly AzureKinectProfile profile;
        public bool IsAvailable => device != IntPtr.Zero && started;

        public AzureKinectCapture(uint index, AzureBodyTrackingState bodyState = null, string modelPath = null, int gpu = 0,
            AzureKinectDepthMode depthMode = AzureKinectDepthMode.NFOVUnbinned)
        {
            profile = AzureKinectModes.Get(depthMode);
            try
            {
                if (index >= k4a_device_get_installed_count())
                    throw new InvalidOperationException("Azure Kinect not found at this device index. Check USB 3.0, external power and the SDK installation.");
                if (k4a_device_open(index, out device) != 0)
                    throw new InvalidOperationException("Cannot open Azure Kinect. Close Azure Kinect Viewer and other applications using this sensor.");
                var config = GetInfraredConfiguration(depthMode);
                if (k4a_device_start_cameras(device, ref config) != 0)
                    throw new InvalidOperationException("Azure Kinect IR startup failed. Check depthengine_2_0.dll, USB 3.0, firmware and power; test " + profile.Name + " at 30 FPS in Azure Kinect Viewer.");
                started = true;
                if (bodyState != null)
                {
                    // SDK 1.4.2 k4a_calibration_t: 2 x 128-byte cameras,
                    // 4 x 4 x 48-byte extrinsics, two 4-byte enums = 1032 bytes.
                    var calibration = new byte[1032];
                    if (k4a_device_get_calibration(device, config.DepthMode, config.ColorResolution, calibration) == 0)
                    {
                        bodyState.SetCalibration(calibration, profile.Width, profile.Height);
                        bodyTracker = new AzureBodyTracking(calibration, bodyState, modelPath, gpu);
                    }
                    else bodyState.Publish(new AzureHandFrame { Status = "Cannot read Azure Kinect calibration" });
                }
            }
            catch { Dispose(); throw; }
        }

        public bool TryAcquire(out IntPtr pixels, out int bytes, out long timestamp)
        {
            ReleaseFrame();
            pixels = IntPtr.Zero;
            bytes = 0;
            timestamp = 0;
            int result = k4a_device_get_capture(device, out capture, 0);
            if (result == 2) return false; // WAIT_RESULT_TIMEOUT, nonblocking poll
            if (result != 0) throw new InvalidOperationException("Azure Kinect capture failed or sensor disconnected. Check USB/power, then Restart Kinect.");
            bodyTracker?.Submit(capture);
            image = k4a_capture_get_ir_image(capture);
            if (image == IntPtr.Zero) return false;
            if (k4a_image_get_width_pixels(image) != profile.Width || k4a_image_get_height_pixels(image) != profile.Height ||
                k4a_image_get_stride_bytes(image) != profile.Width * 2 || k4a_image_get_size(image).ToUInt64() < (ulong)profile.FrameBytes)
                throw new InvalidOperationException("Unexpected Azure Kinect IR image layout for " + profile.Name + ".");
            pixels = k4a_image_get_buffer(image);
            bytes = profile.FrameBytes;
            timestamp = checked((long)k4a_image_get_device_timestamp_usec(image));
            return true;
        }

        public void ReleaseFrame()
        {
            if (image != IntPtr.Zero) k4a_image_release(image);
            image = IntPtr.Zero;
            if (capture != IntPtr.Zero) k4a_capture_release(capture);
            capture = IntPtr.Zero;
        }

        public void Dispose()
        {
            ReleaseFrame();
            bodyTracker?.Dispose();
            bodyTracker = null;
            if (device == IntPtr.Zero) return;
            // Stop is safe after a partially failed start, too.
            k4a_device_stop_cameras(device);
            k4a_device_close(device);
            device = IntPtr.Zero;
            started = false;
        }
    }
}
