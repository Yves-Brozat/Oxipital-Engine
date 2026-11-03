using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEngine;

namespace Oxipital.Editor
{
    public static class AzureKinectRuntimeImporter
    {
        const string Destination = "Assets/Plugins/AzureKinect/x86_64";

        [MenuItem("Tools/Oxipital/Import Azure Body Tracking Runtime")]
        public static void ImportBodyTracking()
        {
            if (Application.isPlaying) { Debug.LogWarning("Stop Play Mode before importing body tracking."); return; }
            string installed = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Azure Kinect Body Tracking SDK");
            string root = EditorUtility.OpenFolderPanel("Select Azure Kinect Body Tracking SDK", installed, "");
            if (string.IsNullOrEmpty(root)) return;
            try
            {
                string[] libraries = { "k4abt.dll", "onnxruntime.dll", "directml.dll" };
                string[] sources = libraries.Select(name => FindX64Library(root, name)).ToArray();
                string model = Directory.GetFiles(root, "dnn_model_2_0_op11.onnx", SearchOption.AllDirectories).FirstOrDefault();
                if (model == null) throw new FileNotFoundException("Body tracking ONNX model not found in this SDK.");
                Directory.CreateDirectory(Destination);
                foreach (string source in sources) ImportLibrary(source);
                foreach (string name in new[] { "LICENSE.txt", "ThirdPartyNotices.txt", "REDIST.txt" })
                {
                    string notice = Path.Combine(root, name);
                    if (File.Exists(notice)) File.Copy(notice, Path.Combine(Destination, "BodyTracking-" + name), true);
                }
                Directory.CreateDirectory("Assets/StreamingAssets/AzureKinect");
                File.Copy(model, "Assets/StreamingAssets/AzureKinect/body_model.onnx.bytes", true);
                AssetDatabase.Refresh();
                Debug.Log("DirectML body runtime and model imported. Restart Unity, then enable Body Tracking on Optical Flow Azure Kinect Input.");
            }
            catch (Exception e) { Debug.LogError("Azure body runtime import: " + e.Message); }
        }

        [MenuItem("Tools/Oxipital/Import Azure Kinect Runtime")]
        public static void Import()
        {
            if (Application.isPlaying)
            {
                Debug.LogWarning("Stop Play Mode before importing Azure Kinect native libraries.");
                return;
            }
            string programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            string installed = Path.Combine(programFiles, "Azure Kinect SDK v1.4.2");
            string root = EditorUtility.OpenFolderPanel("Select the installed Azure Kinect SDK folder", Directory.Exists(installed) ? installed : programFiles, "");
            if (string.IsNullOrEmpty(root)) return;
            try
            {
                string k4a = FindX64Library(root, "k4a.dll");
                string depth = FindX64Library(root, "depthengine_2_0.dll");
                Directory.CreateDirectory(Destination);
                ImportLibrary(k4a);
                ImportLibrary(depth);
                // Keep any notices distributed with the installed SDK alongside its binaries.
                foreach (string notice in Directory.GetFiles(root, "*", SearchOption.TopDirectoryOnly)
                    .Where(p => Path.GetFileName(p).StartsWith("LICENSE", StringComparison.OrdinalIgnoreCase) ||
                                Path.GetFileName(p).StartsWith("NOTICE", StringComparison.OrdinalIgnoreCase) ||
                                Path.GetFileName(p).StartsWith("ThirdParty", StringComparison.OrdinalIgnoreCase)))
                    File.Copy(notice, Path.Combine(Destination, Path.GetFileName(notice)), true);
                AssetDatabase.Refresh();
                Debug.Log("Azure Kinect x64 runtime imported. Restart Unity before using Azure Kinect IR. The build will include k4a.dll and depthengine_2_0.dll.");
            }
            catch (Exception e) { Debug.LogError("Azure Kinect runtime import: " + e.Message); }
        }

        static string FindX64Library(string root, string name)
        {
            string result = Directory.GetFiles(root, name, SearchOption.AllDirectories)
                .OrderBy(p => p.IndexOf("amd64", StringComparison.OrdinalIgnoreCase) >= 0 ? 0 : 1)
                .FirstOrDefault(IsX64);
            if (result == null) throw new FileNotFoundException("Could not find an x64 " + name + " in this SDK folder. Install Azure Kinect Sensor SDK 1.4.2 and select its installation directory.");
            return result;
        }

        static bool IsX64(string path)
        {
            using (var reader = new BinaryReader(File.OpenRead(path)))
            {
                if (reader.BaseStream.Length < 64 || reader.ReadUInt16() != 0x5a4d) return false;
                reader.BaseStream.Position = 0x3c;
                int offset = reader.ReadInt32();
                if (offset < 0 || offset > reader.BaseStream.Length - 6) return false;
                reader.BaseStream.Position = offset;
                return reader.ReadUInt32() == 0x00004550 && reader.ReadUInt16() == 0x8664;
            }
        }

        static void ImportLibrary(string source)
        {
            string target = Destination + "/" + Path.GetFileName(source);
            File.Copy(source, target, true);
            AssetDatabase.ImportAsset(target, ImportAssetOptions.ForceSynchronousImport);
            var importer = (PluginImporter)AssetImporter.GetAtPath(target);
            importer.SetCompatibleWithAnyPlatform(false);
            importer.SetCompatibleWithEditor(true);
            importer.SetEditorData("OS", "Windows");
            importer.SetEditorData("CPU", "x86_64");
            importer.SetCompatibleWithPlatform(BuildTarget.StandaloneWindows64, true);
            importer.SetPlatformData(BuildTarget.StandaloneWindows64, "CPU", "x86_64");
            importer.SaveAndReimport();
        }
    }
}
