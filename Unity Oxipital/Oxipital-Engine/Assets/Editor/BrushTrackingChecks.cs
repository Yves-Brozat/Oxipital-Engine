using System;
using System.Reflection;
using UnityEditor;
using UnityEngine;

namespace Oxipital.Editor
{
    public static class BrushTrackingChecks
    {
        [MenuItem("Tools/Oxipital/Validate Brush Tracking")]
        public static void Run()
        {
            if (!EditorApplication.isPlaying) throw new InvalidOperationException("Run this check in Play mode.");
            var go = new GameObject("Isolated brush tracking check");
            go.SetActive(false); // No sensor capture or GPU buffers are started.
            TwoHandForceBrush brush = null;
            try
            {
                var force = go.AddComponent<StandardForceGroup>();
                var orb = go.AddComponent<OrbGroup>();
                var input = go.AddComponent<OpticalFlowAzureKinectInput>();
                brush = go.AddComponent<TwoHandForceBrush>();
                brush.input = input;
                brush.target = force;
                brush.orbTarget = orb;
                brush.controlForcePosition = brush.controlForceOrientation = brush.controlBrushParameters = false;
                brush.controlOrbPosition = brush.controlOrbRadius = brush.controlOrbOrientation = false;
                brush.positionMapping = TwoHandForceBrush.PositionMapping.SensorWorld;
                force.dancerIntensity = .7f;
                force.count = 3;
                force.patternSize = 2;
                force.patternSpeed = .4f;
                force.dancerRotation = new Vector3(10, 20, 30);
                orb.dancerIntensity = .8f;
                orb.count = 2;
                Tick(brush);
                Require(Mathf.Approximately(force.dancerIntensity, .7f), "Fixed force was muted without hands.");
                Require(force.count == 3 && force.patternSize == 2 && force.patternSpeed == .4f && force.dancerRotation == new Vector3(10, 20, 30), "Fixed force choreography was overwritten.");
                Require(orb.dancerIntensity == .8f && orb.count == 2, "Fixed orbs were changed without tracking ownership.");
                brush.controlForcePosition = true;
                typeof(TwoHandForceBrush).GetField("gate", BindingFlags.NonPublic | BindingFlags.Instance).SetValue(brush, 0f);
                Tick(brush);
                Require(force.dancerIntensity == 0, "Hand-following force did not mute after tracking loss.");
                brush.controlForcePosition = false;
                Tick(brush);
                Require(Mathf.Approximately(force.dancerIntensity, .7f) && force.count == 3 && force.patternSize == 2, "Switching to fixed mode failed to restore intensity and choreography.");
                brush.input = null;
                force.dancerIntensity = .6f;
                Tick(brush);
                Require(Mathf.Approximately(force.dancerIntensity, .6f), "Missing input muted or replaced a fixed force's authored intensity.");
                Debug.Log("BRUSH_TRACKING_PASS: fixed sources survive lost/missing input; following forces mute; fixed choreography and preset intensity are preserved.");
            }
            finally
            {
                if (brush != null) typeof(TwoHandForceBrush).GetMethod("ReleaseTarget", BindingFlags.NonPublic | BindingFlags.Instance).Invoke(brush, null);
                UnityEngine.Object.DestroyImmediate(go);
            }
        }

        static void Tick(TwoHandForceBrush brush) => typeof(TwoHandForceBrush).GetMethod("Update", BindingFlags.NonPublic | BindingFlags.Instance).Invoke(brush, null);
        static void Require(bool ok, string message) { if (!ok) throw new Exception(message); }
    }
}
