using System.IO;
using UnityEditor;
using UnityEngine;

namespace Oxipital.Editor
{
    [CustomEditor(typeof(TwoHandForceBrush))]
    public sealed class TwoHandForceBrushEditor : UnityEditor.Editor
    {
        public override bool RequiresConstantRepaint() => Application.isPlaying;

        public override void OnInspectorGUI()
        {
            serializedObject.Update();
            DrawPropertiesExcluding(serializedObject, "selectedBrush");
            var brush = (TwoHandForceBrush)target;
            var list = serializedObject.FindProperty("brushes");
            var names = new string[list.arraySize + 1];
            names[0] = "Current Group / Chataigne";
            for (int i = 0; i < list.arraySize; i++)
            {
                var preset = list.GetArrayElementAtIndex(i).objectReferenceValue;
                names[i + 1] = preset != null ? preset.name : "(Unassigned preset)";
            }
            var selection = serializedObject.FindProperty("selectedBrush");
            selection.intValue = EditorGUILayout.Popup("Selected Brush", Mathf.Clamp(selection.intValue, 0, names.Length - 1), names);
            serializedObject.ApplyModifiedProperties();
            EditorGUILayout.LabelField("Orientation offset (interaction camera axes)", EditorStyles.boldLabel);
            for (int axis = 0; axis < 3; axis++)
            {
                GUILayout.BeginHorizontal();
                GUILayout.Label(new[] { "X", "Y", "Z" }[axis], GUILayout.Width(20));
                if (GUILayout.Button("-90 deg")) RotateOffset(brush, axis, -90);
                if (GUILayout.Button("+90 deg")) RotateOffset(brush, axis, 90);
                GUILayout.EndHorizontal();
            }
            using (new EditorGUI.DisabledScope(!Application.isPlaying || !brush.PositionValid || !brush.HandsTracked))
            {
                if (GUILayout.Button("Calibrate current hand pose -> Up"))
                {
                    Undo.RecordObject(brush, "Calibrate brush orientation");
                    if (brush.CalibrateDirectionUp()) EditorUtility.SetDirty(brush);
                }
            }
            GUILayout.BeginHorizontal();
            if (GUILayout.Button(brush.showMonitor ? "Hide Brush Monitor" : "Show Brush Monitor"))
            {
                Undo.RecordObject(brush, "Toggle brush monitor");
                brush.showMonitor = !brush.showMonitor;
                EditorUtility.SetDirty(brush);
            }
            if (GUILayout.Button(brush.showHandOverlay ? "Hide Hand Overlay" : "Show Hand Overlay"))
            {
                Undo.RecordObject(brush, "Toggle hand overlay");
                brush.showHandOverlay = !brush.showHandOverlay;
                EditorUtility.SetDirty(brush);
            }
            GUILayout.EndHorizontal();
            EditorGUILayout.HelpBox("For groups created during Play: leave Target empty, assign Force Manager and choose Force Group Number. The brush waits for that group and reconnects if it is recreated. Use a group dedicated to this brush.", MessageType.Info);
            var resolved = brush.ResolvedTarget;
            using (new EditorGUI.DisabledScope(true))
                EditorGUILayout.ObjectField("Resolved Force Group", resolved, typeof(StandardForceGroup), true);
            using (new EditorGUI.DisabledScope(true))
                EditorGUILayout.ObjectField("Resolved Orb Group", brush.ResolvedOrbTarget, typeof(OrbGroup), true);
            EditorGUILayout.HelpBox("Gesture controls are independent: disabling one freezes its last value. Brush Enabled gates the force; Orb Position can remain active independently. Orb Target or Orb Manager + Orb Group Number selects the emitter group to move.", MessageType.Info);
            if (brush.input != null && !brush.input.bodyTracking)
                EditorGUILayout.HelpBox("Enable Body Tracking on the Azure Kinect input.", MessageType.Warning);
            using (new EditorGUI.DisabledScope(resolved == null))
            {
                if (GUILayout.Button("Save Force Group as Brush Preset")) SavePreset(brush);
                if (GUILayout.Button("Create Attract / Repel / Vortex Presets")) CreateExamples(brush);
            }
            if (Application.isPlaying)
                EditorGUILayout.HelpBox("Presets saved during Play remain as assets. Changes to this component's Brushes list and selection revert when Play stops: assign the saved assets to Brushes in Edit Mode to keep the configuration.", MessageType.Info);
            EditorGUILayout.HelpBox(brush.Status, MessageType.Info);
            EditorGUILayout.LabelField("Hand distance", brush.HandDistance.ToString("F2") + " m");
            EditorGUILayout.LabelField("Brush radius", brush.BrushRadius.ToString("F2") + " m");
        }

        static void RotateOffset(TwoHandForceBrush brush, int axis, float degrees)
        {
            Undo.RecordObject(brush, "Rotate brush orientation offset");
            var value = brush.orientationOffset;
            value[axis] = Mathf.DeltaAngle(0, value[axis] + degrees);
            brush.orientationOffset = value;
            EditorUtility.SetDirty(brush);
        }

        static void SavePreset(TwoHandForceBrush brush)
        {
            string path = EditorUtility.SaveFilePanelInProject("Save force brush", "Force Brush", "asset", "Save the current Force Group parameters");
            if (string.IsNullOrEmpty(path)) return;
            var preset = ScriptableObject.CreateInstance<ForceBrushPreset>();
            if (!brush.CaptureCurrentSettings(preset)) { DestroyImmediate(preset); return; }
            AssetDatabase.CreateAsset(preset, path);
            AssetDatabase.SaveAssets();
            Undo.RecordObject(brush, "Add brush preset");
            var list = new System.Collections.Generic.List<ForceBrushPreset>(brush.brushes) { preset };
            brush.brushes = list.ToArray();
            brush.selectedBrush = brush.brushes.Length;
            EditorUtility.SetDirty(brush);
        }

        static void CreateExamples(TwoHandForceBrush brush)
        {
            string path = EditorUtility.SaveFilePanelInProject("Choose brush preset destination", "Attract", "asset", "Three presets will be saved in this folder");
            if (string.IsNullOrEmpty(path)) return;
            string folder = Path.GetDirectoryName(path).Replace('\\', '/');
            string[] names = { "Attract", "Repel", "Vortex" };
            var presets = new ForceBrushPreset[3];
            for (int i = 0; i < presets.Length; i++)
            {
                var preset = ScriptableObject.CreateInstance<ForceBrushPreset>();
                if (!brush.CaptureCurrentSettings(preset)) { DestroyImmediate(preset); return; }
                foreach (string field in new[] { "radialIntensity", "axialIntensity", "linearIntensity", "orthoIntensity", "curlIntensity", "perlinIntensity", "orthoaxialIntensity", "spiralIntensity" }) preset.Set(field, 0);
                preset.Set("dancerIntensity", 1);
                preset.Set("dancerHyperSize", 0);
                preset.Set("forceFactorInside", 1);
                preset.Set("forceFactorOutside", 0);
                preset.Set("radialAmplitudeWave", 0);
                preset.Set("radialIntensity", i == 2 ? 0 : .7f);
                preset.Set("radialInOut", i == 1 ? 1 : 0);
                preset.Set("orthoIntensity", i == 2 ? .7f : 0);
                preset.Set("orthoClockwise", 1);
                preset.Set("orthoFactor", 2);
                preset.Set("orthoInnerRadius", .5f);
                AssetDatabase.CreateAsset(preset, AssetDatabase.GenerateUniqueAssetPath(folder + "/" + names[i] + ".asset"));
                presets[i] = preset;
            }
            Undo.RecordObject(brush, "Assign example brushes");
            brush.brushes = presets;
            brush.selectedBrush = 1;
            EditorUtility.SetDirty(brush);
            AssetDatabase.SaveAssets();
        }
    }
}
