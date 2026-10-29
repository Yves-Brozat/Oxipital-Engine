using System;
using System.Collections.Generic;
using System.IO;
using UnityEngine;

namespace Oxipital
{
    // Portable, silent recording format: numbered JPEGs and a timestamp manifest.
    // Only one decoded frame is retained in memory during playback.
    internal sealed class WebcamRecording : IDisposable
    {
        [Serializable]
        internal sealed class Manifest
        {
            public int version = 1;
            public int width, height, rotation;
            public bool flipY;
            public double duration;
            public double[] times;
        }

        readonly List<double> times = new List<double>();
        string folder;
        Manifest manifest;
        Texture2D image;
        Color32[] pixels;
        double started, nextCapture;
        int frame = -1;

        public bool IsRecording { get; private set; }
        public Texture Texture => image;
        public int Rotation => manifest != null ? manifest.rotation : 0;
        public bool FlipY => manifest != null && manifest.flipY;
        public double Duration => manifest != null ? manifest.duration : 0;
        public int FrameCount => IsRecording ? times.Count : manifest?.times?.Length ?? 0;
        public string ManifestPath => Path.Combine(folder, "recording.json");

        public void Begin(WebCamTexture camera)
        {
            folder = Path.Combine(Application.persistentDataPath, "WebcamRecordings",
                DateTime.Now.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N").Substring(0, 8));
            Directory.CreateDirectory(folder);
            manifest = new Manifest { width = camera.width, height = camera.height,
                rotation = camera.videoRotationAngle, flipY = camera.videoVerticallyMirrored };
            image = new Texture2D(camera.width, camera.height, TextureFormat.RGB24, false);
            pixels = new Color32[camera.width * camera.height];
            started = Time.realtimeSinceStartupAsDouble;
            nextCapture = started;
            IsRecording = true;
        }

        public void Capture(WebCamTexture camera, int fps, int quality)
        {
            double now = Time.realtimeSinceStartupAsDouble;
            if (!IsRecording || !camera.didUpdateThisFrame || now < nextCapture) return;
            if (camera.width != manifest.width || camera.height != manifest.height ||
                camera.videoRotationAngle != manifest.rotation || camera.videoVerticallyMirrored != manifest.flipY)
                throw new IOException("Webcam format changed during recording. Stop and start a new recording.");

            camera.GetPixels32(pixels);
            image.SetPixels32(pixels);
            image.Apply(false);
            byte[] bytes = image.EncodeToJPG(Mathf.Clamp(quality, 1, 100));
            File.WriteAllBytes(FramePath(times.Count), bytes);
            times.Add(times.Count == 0 ? 0 : now - started);
            nextCapture = now + 1.0 / Mathf.Clamp(fps, 1, 60);
        }

        public string Finish()
        {
            if (!IsRecording) return null;
            IsRecording = false;
            if (times.Count == 0) return null;
            manifest.times = times.ToArray();
            manifest.duration = Math.Max(Time.realtimeSinceStartupAsDouble - started, times[times.Count - 1] + .001);
            File.WriteAllText(ManifestPath, JsonUtility.ToJson(manifest, true));
            return ManifestPath;
        }

        public void Load(string path)
        {
            folder = Path.GetDirectoryName(Path.GetFullPath(path));
            manifest = JsonUtility.FromJson<Manifest>(File.ReadAllText(path));
            if (manifest == null || manifest.version != 1 || manifest.times == null || manifest.times.Length == 0 ||
                manifest.width < 1 || manifest.height < 1 || manifest.width > 8192 || manifest.height > 8192 ||
                double.IsNaN(manifest.duration) || double.IsInfinity(manifest.duration) || manifest.duration <= 0)
                throw new IOException("Invalid webcam recording manifest.");
            for (int i = 0; i < manifest.times.Length; i++)
            {
                double t = manifest.times[i];
                if (double.IsNaN(t) || double.IsInfinity(t) || t < 0 || t >= manifest.duration ||
                    (i > 0 && t <= manifest.times[i - 1])) throw new IOException("Invalid recording timestamps.");
            }
            image = new Texture2D(2, 2, TextureFormat.RGB24, false);
            image.wrapMode = TextureWrapMode.Clamp;
            Sample(0);
        }

        public void Sample(double time)
        {
            int index = Array.BinarySearch(manifest.times, time);
            if (index < 0) index = Math.Max(0, ~index - 1);
            if (index == frame) return;
            if (!image.LoadImage(File.ReadAllBytes(FramePath(index)), false))
                throw new IOException("Cannot decode recorded webcam frame " + index);
            frame = index;
        }

        string FramePath(int index) => Path.Combine(folder, index.ToString("D8") + ".jpg");

        public void Dispose()
        {
            if (image != null) UnityEngine.Object.Destroy(image);
            image = null;
            pixels = null;
        }
    }
}
