using System;
using System.Runtime.InteropServices;

namespace Oxipital
{
    // Minimal Kinect20 C ABI binding. Slot numbers/signatures follow Kinect SDK 2.0
    // inc/Kinect.h. Uses the installed runtime, without Microsoft.Kinect.dll or a
    // separate bridge process. Each returned COM reference has exactly one owner.
    internal sealed class KinectV2Capture : IKinectV2FrameReader
    {
        [DllImport("Kinect20", CallingConvention = CallingConvention.StdCall)]
        static extern int GetDefaultKinectSensor(out IntPtr sensor);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        delegate int Command(IntPtr self);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        delegate int GetObject(IntPtr self, out IntPtr value);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        delegate int GetBuffer(IntPtr self, out uint count, out IntPtr buffer);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        delegate int GetTime(IntPtr self, out long ticks);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        delegate int GetBoolean(IntPtr self, out byte value);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        delegate int CopyColor(IntPtr self, uint capacity, IntPtr buffer, int format);

        IntPtr sensor, reader, frame, colorBuffer;
        GetObject acquire;
        GetBuffer accessInfrared;
        GetTime frameTime;
        CopyColor copyColor;
        GetBoolean isAvailable;
        readonly bool infrared;
        public int Width => infrared ? 512 : 1920;
        public int Height => infrared ? 424 : 1080;
        public bool IsAvailable
        {
            get
            {
                Check(isAvailable(sensor, out byte available));
                return available != 0;
            }
        }

        static T Method<T>(IntPtr instance, int slot) where T : Delegate =>
            Marshal.GetDelegateForFunctionPointer<T>(Marshal.ReadIntPtr(Marshal.ReadIntPtr(instance), slot * IntPtr.Size));

        static void Check(int result)
        {
            if (result < 0) Marshal.ThrowExceptionForHR(result);
        }

        public KinectV2Capture(bool infrared)
        {
            this.infrared = infrared;
            IntPtr source = IntPtr.Zero;
            try
            {
                Check(GetDefaultKinectSensor(out sensor));
                if (sensor == IntPtr.Zero) throw new InvalidOperationException("No Kinect V2 sensor found.");
                Check(Method<Command>(sensor, 6)(sensor)); // IKinectSensor.Open
                isAvailable = Method<GetBoolean>(sensor, 9);
                Check(Method<GetObject>(sensor, infrared ? 14 : 10)(sensor, out source));
                Check(Method<GetObject>(source, 7)(source, out reader)); // OpenReader
                acquire = Method<GetObject>(reader, 6); // AcquireLatestFrame (no frame queue)
                if (!infrared) colorBuffer = Marshal.AllocHGlobal(Width * Height * 4);
            }
            catch { Dispose(); throw; }
            finally { Release(ref source); }
        }

        // The IR pointer is valid until ReleaseFrame; RGB uses our reusable buffer.
        public bool TryAcquire(out IntPtr pixels, out int bytes, out long timestamp)
        {
            ReleaseFrame();
            pixels = IntPtr.Zero;
            bytes = 0;
            timestamp = 0;
            int result = acquire(reader, out frame);
            if (result == unchecked((int)0x8000000A)) { ReleaseFrame(); return false; } // E_PENDING
            Check(result);
            if (frame == IntPtr.Zero) return false;
            frameTime ??= Method<GetTime>(frame, infrared ? 6 : 10);
            Check(frameTime(frame, out timestamp));
            if (infrared)
            {
                accessInfrared ??= Method<GetBuffer>(frame, 4);
                Check(accessInfrared(frame, out uint count, out pixels));
                if (count < Width * Height) throw new InvalidOperationException("Incomplete Kinect IR frame.");
                bytes = Width * Height * 2;
            }
            else
            {
                copyColor ??= Method<CopyColor>(frame, 7);
                bytes = Width * Height * 4;
                Check(copyColor(frame, (uint)bytes, colorBuffer, 1)); // ColorImageFormat_Rgba
                pixels = colorBuffer;
            }
            return true;
        }

        public void ReleaseFrame() => Release(ref frame);

        static void Release(ref IntPtr value)
        {
            if (value == IntPtr.Zero) return;
            Marshal.Release(value);
            value = IntPtr.Zero;
        }

        public void Dispose()
        {
            ReleaseFrame();
            Release(ref reader);
            if (sensor != IntPtr.Zero)
            {
                // Close this client's sensor handle; other processes retain theirs.
                Method<Command>(sensor, 7)(sensor);
                Release(ref sensor);
            }
            if (colorBuffer != IntPtr.Zero) Marshal.FreeHGlobal(colorBuffer);
            colorBuffer = IntPtr.Zero;
        }
    }
}
