using UnityEditor;
using UnityEngine;

namespace Oxipital.Editor
{
    [CustomEditor(typeof(OpticalFlowKinectInput), true)]
    public sealed class OpticalFlowKinectInputEditor : UnityEditor.Editor
    {
        string depthCalibrationStatus;
        public override bool RequiresConstantRepaint() => Application.isPlaying;

        public override void OnInspectorGUI()
        {
            var input = (OpticalFlowKinectInput)target;
            bool azure = input is OpticalFlowAzureKinectInput;
            if (azure)
            {
                serializedObject.Update();
                DrawPropertiesExcluding(serializedObject, "stream");
                serializedObject.ApplyModifiedProperties();
                var azureInput = (OpticalFlowAzureKinectInput)input;
                EditorGUILayout.HelpBox("Azure IR: " + azureInput.DepthModeDescription + ". Active illumination; color disabled. Changing Depth Mode restarts capture and body tracking. Adjust Infrared Gain to the preview.", MessageType.Info);
                EditorGUILayout.HelpBox(azureInput.BodyStatus, MessageType.Info);
                EditorGUILayout.LabelField("Body tracking FPS", azureInput.BodyFPS.ToString("F1"));
                EditorGUILayout.LabelField(azureInput.HandDiagnostics(true));
                EditorGUILayout.LabelField(azureInput.HandDiagnostics(false));
                EditorGUILayout.HelpBox("Hand depth is measured in sensor metres. Interaction Depth on the brush places effects in the Unity scene; it does not change sensor range. Calibration creates an optional activation zone and requires at least one fresh, reliable hand.", MessageType.Info);
                using (new EditorGUI.DisabledScope(!Application.isPlaying))
                    if (GUILayout.Button("Calibrate Hand Depth at Current Pose"))
                    {
                        Undo.RecordObject(azureInput, "Calibrate hand depth");
                        bool success = azureInput.CalibrateHandDepth();
                        depthCalibrationStatus = success ? "Hand depth zone calibrated." : "No fresh, reliable hand available for calibration.";
                        if (success) EditorUtility.SetDirty(azureInput);
                    }
                if (!string.IsNullOrEmpty(depthCalibrationStatus)) EditorGUILayout.HelpBox(depthCalibrationStatus, MessageType.Info);
                if (azureInput.GetComponent<TwoHandForceBrush>() == null && GUILayout.Button("Add Two-Hand Force Brush"))
                {
                    var brush = Undo.AddComponent<TwoHandForceBrush>(azureInput.gameObject);
                    brush.input = azureInput;
                    Undo.RecordObject(azureInput, "Enable body tracking for brush");
                    azureInput.bodyTracking = true;
                    EditorUtility.SetDirty(azureInput);
                    EditorUtility.SetDirty(brush);
                }
            }
            else DrawDefaultInspector();
            var source = input.GetComponent<OpticalFlowSource>();
            if (source != null && (!source.IsKinectInput || source.IsAzureKinectInput != azure) && GUILayout.Button("Use this Kinect for Optical Flow"))
            {
                Undo.RecordObject(source, "Select Kinect input");
                source.mode = azure ? OpticalFlowSource.FlowSourceMode.AzureKinectIR : OpticalFlowSource.FlowSourceMode.Kinect;
                source.useTestSource = false;
                if (azure) source.azureKinectInput = (OpticalFlowAzureKinectInput)input;
                else source.kinectInput = input;
                EditorUtility.SetDirty(source);
            }
            using (new EditorGUI.DisabledScope(!Application.isPlaying))
                if (GUILayout.Button("Restart Kinect")) input.RestartCapture();
            EditorGUILayout.HelpBox(input.Status, MessageType.Info);
            EditorGUILayout.LabelField("Kinect acquisition FPS", input.CaptureFPS.ToString("F1"));
            EditorGUILayout.LabelField("Unity upload FPS", input.ReceivedFPS.ToString("F1"));
            EditorGUILayout.LabelField("Unity update FPS", input.UnityUpdateFPS.ToString("F1"));
            EditorGUILayout.LabelField("Frames skipped before upload", input.SkippedFrames.ToString());
            EditorGUILayout.LabelField("Average acquisition poll", input.AcquireMilliseconds.ToString("F2") + " ms");
            EditorGUILayout.LabelField("Last texture upload", input.UploadMilliseconds.ToString("F2") + " ms");
            EditorGUILayout.LabelField("Last frame age", float.IsInfinity(input.FrameAge) ? "No frame" : input.FrameAge.ToString("F2") + " s");
            // Show the processed input: fixed IR gain, top-down correction, crop and flips.
            Texture preview = Application.isPlaying && source != null && source.IsKinectInput && source.ActiveKinectInput == input ? source.Current : null;
            if (preview != null)
            {
                EditorGUILayout.LabelField("Kinect Input Preview (Gain / Crop / Flip Applied)");
                EditorGUI.DrawPreviewTexture(GUILayoutUtility.GetAspectRect((float)preview.width / preview.height), preview, null, ScaleMode.ScaleToFit);
            }
            EditorGUILayout.HelpBox("Acquisition runs on its own thread and keeps only the latest image. Acquisition FPS measures frames returned by the Kinect runtime; upload FPS measures frames transferred to Unity. If acquisition is near 30 but upload is near 10, rendering is limiting consumption. If both are near 10 while Unity updates faster, investigate the Kinect runtime / USB path. Allow a few seconds after startup.", MessageType.Info);
        }
    }
}
