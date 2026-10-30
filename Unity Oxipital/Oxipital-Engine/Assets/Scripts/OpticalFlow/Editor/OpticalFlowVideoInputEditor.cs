using UnityEditor;
using UnityEngine;

namespace Oxipital.Editor
{
    [CustomEditor(typeof(OpticalFlowVideoInput))]
    public sealed class OpticalFlowVideoInputEditor : UnityEditor.Editor
    {
        public override bool RequiresConstantRepaint() => Application.isPlaying;

        public override void OnInspectorGUI()
        {
            DrawDefaultInspector();
            var input = (OpticalFlowVideoInput)target;
            var source = input.GetComponent<OpticalFlowSource>();
            if (source != null)
            {
                int selected = (int)source.mode - 2;
                int next = GUILayout.Toolbar(selected, new[] { "Webcam", "Video", "Blend" });
                if (next != selected && next >= 0)
                {
                    Undo.RecordObject(source, "Change optical flow input");
                    source.mode = (OpticalFlowSource.FlowSourceMode)(next + 2);
                    source.useTestSource = false;
                    EditorUtility.SetDirty(source);
                }
            }
            if (GUILayout.Button("Choose video / recording.json"))
            {
                string path = EditorUtility.OpenFilePanel("Video or webcam recording", "", "");
                if (!string.IsNullOrEmpty(path))
                {
                    Undo.RecordObject(input, "Choose optical flow video");
                    input.videoPath = path;
                    EditorUtility.SetDirty(input);
                    if (Application.isPlaying) input.LoadVideo();
                }
            }
            if (GUILayout.Button("Choose webcam"))
            {
                var menu = new GenericMenu();
                foreach (var device in WebCamTexture.devices)
                {
                    string name = device.name;
                    menu.AddItem(new GUIContent(name), input.deviceName == name, () =>
                    {
                        Undo.RecordObject(input, "Choose optical flow webcam");
                        input.deviceName = name;
                        EditorUtility.SetDirty(input);
                        if (Application.isPlaying) input.RestartWebcam();
                    });
                }
                if (WebCamTexture.devices.Length == 0) menu.AddDisabledItem(new GUIContent("No webcams detected"));
                menu.ShowAsContext();
            }
            using (new EditorGUI.DisabledScope(!Application.isPlaying))
            {
                if (GUILayout.Button("Start / Restart Webcam")) input.RestartWebcam();
                if (GUILayout.Button("Load / Play Video")) input.LoadVideo();
                if (GUILayout.Button(input.IsPlaying ? "Pause" : "Play")) input.PlayPause();
                if (GUILayout.Button("Rewind")) input.Rewind();
                if (GUILayout.Button(input.IsRecording ? "Stop Recording" : input.IsRecordingPending ? "Cancel Recording Request" : "Record Webcam")) input.ToggleRecording();
                using (new EditorGUI.DisabledScope(string.IsNullOrEmpty(input.LastRecordingPath)))
                    if (GUILayout.Button("Use Last Recording")) input.UseLastRecording();
            }
            EditorGUILayout.HelpBox(input.Status, MessageType.Info);
            if (!string.IsNullOrEmpty(input.LastRecordingPath))
                EditorGUILayout.SelectableLabel(input.LastRecordingPath, EditorStyles.wordWrappedLabel, GUILayout.Height(40));
            // Reuse the actual processed frame: camera rotation, crop and user flips
            // are already applied, including when video and webcam are blended.
            bool alignedPreview = Application.isPlaying && source != null && source.IsVideoInput && source.Current != null;
            Texture preview = alignedPreview ? source.Current : input.WebcamTexture;
            if (preview != null)
            {
                EditorGUILayout.LabelField(alignedPreview ? "Input Preview (Crop / Flip Applied)" : "Raw Webcam Preview");
                Rect rect = GUILayoutUtility.GetAspectRect((float)preview.width / preview.height);
                EditorGUI.DrawPreviewTexture(rect, preview, null, ScaleMode.ScaleToFit);
            }
        }
    }

    [CustomEditor(typeof(OpticalFlowSource))]
    public sealed class OpticalFlowSourceEditor : UnityEditor.Editor
    {
        public override void OnInspectorGUI()
        {
            DrawDefaultInspector();
            var source = (OpticalFlowSource)target;
            if (!source.IsVideoInput) return;
            var input = source.videoInput != null ? source.videoInput : source.GetComponent<OpticalFlowVideoInput>();
            if (input == null)
            {
                if (GUILayout.Button("Add Webcam / Video Controls"))
                {
                    Undo.RecordObject(source, "Assign optical flow video input");
                    source.videoInput = Undo.AddComponent<OpticalFlowVideoInput>(source.gameObject);
                    EditorUtility.SetDirty(source);
                }
            }
            else
            {
                EditorGUILayout.HelpBox("Configure webcam, video, blend and recording on Optical Flow Video Input below.", MessageType.Info);
                if (GUILayout.Button("Select Video Controls")) EditorGUIUtility.PingObject(input);
            }
        }
    }
}
