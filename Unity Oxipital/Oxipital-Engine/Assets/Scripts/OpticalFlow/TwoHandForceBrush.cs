using UnityEngine;

namespace Oxipital
{
    [DefaultExecutionOrder(-25)] // Before DancerGroup packs its force buffer in Update.
    [DisallowMultipleComponent]
    public sealed class TwoHandForceBrush : MonoBehaviour
    {
        public enum IntensityMapping { Manual, HandDistance }
        public enum OverlayProjection { OpticalFlowVideo, SceneCamera }
        public enum PositionMapping { CameraPlane, SensorWorld }
        [OSCQuery.DoNotExpose] public OpticalFlowAzureKinectInput input;
        [Tooltip("Use a dedicated Force Group with a valid dancer prefab. The brush owns its transform, radius and activation.")]
        [OSCQuery.DoNotExpose] public StandardForceGroup target;
        [Tooltip("When Target is empty, resolve the group created by this manager during Play.")]
        [OSCQuery.DoNotExpose] public StandardForceManager forceManager;
        [Min(1), Tooltip("1 selects Force Group 1, 2 selects Force Group 2, etc. Used when Target is empty.")]
        public int forceGroupNumber = 1;
        [Header("Independent gesture controls")]
        public bool controlForcePosition = true;
        public bool controlBrushParameters = true;
        public bool controlForceOrientation = true;
        public bool controlOrbPosition;
        public bool controlOrbRadius;
        [Min(.01f), Tooltip("Orb radius relative to the hand-distance radius mapping. Independent of the force's position/size activation switches.")]
        public float orbRadiusMultiplier = 1;
        [Tooltip("Euler offset in degrees in the interaction camera axes (Sensor Origin axes in Sensor World). Z +/-90 turns a horizontal direction toward vertical.")]
        public Vector3 orientationOffset = new Vector3(0, 0, 90);
        [Header("Orb position target")]
        [OSCQuery.DoNotExpose] public OrbGroup orbTarget;
        [OSCQuery.DoNotExpose] public OrbManager orbManager;
        [Min(1), Tooltip("Group created during Play. Used when Orb Target is empty.")]
        public int orbGroupNumber = 1;
        [Tooltip("Place this transform at the real sensor's pose in the Unity scene. Sensor coordinates are converted to meters and Y-up.")]
        [OSCQuery.DoNotExpose] public Transform sensorOrigin;
        [Header("Position in particle scene")]
        public PositionMapping positionMapping = PositionMapping.CameraPlane;
        [Tooltip("Camera that renders the particles. Camera Plane maps video coordinates through this camera; empty uses Camera.main.")]
        [OSCQuery.DoNotExpose] public Camera visualizationCamera;
        [Tooltip("Optional interaction plane in the particle scene. Its forward axis is the plane normal. Empty uses a camera-facing plane.")]
        [OSCQuery.DoNotExpose] public Transform interactionPlane;
        [Tooltip("Place the camera-facing plane through the Force Group's initial position, at particle depth.")]
        public bool useTargetDepth = true;
        [Min(.01f), Tooltip("Distance in front of the particle camera when Use Target Depth is off, or the initial target is behind the camera.")]
        public float interactionDepth = 10;
        [OSCQuery.DoNotExpose] public ForceBrushPreset[] brushes = new ForceBrushPreset[0];
        [Tooltip("0 = current Force Group settings / external preset. 1..N = Brushes list.")]
        [Min(0)] public int selectedBrush;
        public bool brushEnabled = true;
        [Range(0, 1)] public float strength = 1;
        [Tooltip("Manual uses Strength and the preset intensity. Hand Distance multiplies them by a normalized hand-distance signal.")]
        public IntensityMapping intensityMapping = IntensityMapping.Manual;
        [Tooltip("Hand distance in world meters corresponding to intensity 0 and 1.")]
        public Vector2 intensityDistanceRange = new Vector2(.1f, 1);
        public bool invertGestureIntensity;
        [Min(.01f)] public float radiusMultiplier = .5f;
        [Min(.01f), Tooltip("Additional size multiplier after the radius limits. 10 makes the brush ten times larger.")]
        public float sizeMultiplier = 1;
        [Min(.01f)] public float minimumRadius = .05f;
        [Min(.01f)] public float maximumRadius = 3;
        [Min(.01f), Tooltip("Freeze orientation when hands are closer than this distance (world meters).")]
        public float minimumAxisDistance = .08f;
        [Range(0, .5f)] public float smoothingSeconds = .08f;
        [Range(.01f, 1)] public float activationFadeSeconds = .12f;
        public bool orientAlongHands = true;
        public bool driveLinearDirection = true;
        [Header("Visual feedback")]
        [Tooltip("Show a movable brush monitor in Game View and builds. Hiding it does not disable the brush.")]
        public bool showMonitor = true;
        [Range(1, 3), Tooltip("Scale of the monitor text, controls and on-screen labels.")]
        public float monitorScale = 1.5f;
        [Tooltip("Show hands, brush radius and live gauges over the particle view, even when the camera image or monitor panel is hidden.")]
        public bool showHandOverlay = true;
        public OverlayProjection overlayProjection = OverlayProjection.OpticalFlowVideo;

        public bool HandsTracked { get; private set; }
        public float HandDistance { get; private set; }
        public float BrushRadius { get; private set; }
        public string Status { get; private set; } = "Assign Azure Kinect input and a dedicated Force Group";
        public Vector3 LeftHand { get; private set; }
        public Vector3 RightHand { get; private set; }
        public Vector3 InteractionLeftHand { get; private set; }
        public Vector3 InteractionRightHand { get; private set; }
        public float InteractionHandDistance { get; private set; }
        public bool PositionValid { get; private set; }
        public StandardForceGroup ResolvedTarget => ResolveTarget();
        public OrbGroup ResolvedOrbTarget => ResolveOrbTarget();
        public float Activation => gate;
        public float GestureIntensity { get; private set; } = 1;
        public float MaximumBrushRadius => Mathf.Max(minimumRadius, maximumRadius) * Mathf.Max(.01f, sizeMultiplier);
        public float RequestedRadius => Mathf.Clamp(InteractionHandDistance * radiusMultiplier, minimumRadius, Mathf.Max(minimumRadius, maximumRadius)) * Mathf.Max(.01f, sizeMultiplier);
        public float RequestedOrbRadius => RequestedRadius * Mathf.Max(.01f, orbRadiusMultiplier);
        public string SelectedBrushName => selectedBrush <= 0 ? "Current Group / Chataigne" :
            selectedBrush <= brushes.Length && brushes[selectedBrush - 1] != null ? brushes[selectedBrush - 1].name : "Preset manquant";

        StandardForceGroup bound;
        OrbGroup boundOrb;
        Vector3 originalOrbPosition;
        float originalOrbRadius;
        bool orbWasMoved, previousOrbTracking;
        bool orbRadiusWasDriven, previousOrbRadiusTracking;
        ForceBrushPreset original, appliedPreset;
        Vector3 originalPosition, originalScale, direction = Vector3.right, rawDirection = Vector3.right;
        Quaternion originalRotation;
        int appliedSelection = -1;
        float gate, presetIntensity = 1;
        uint previousBody;
        bool previousTracking;
        OpticalFlowAzureKinectInput mappingInput;
        OpticalFlowSource mappingSource;
        OpticalFlowDebugView mappingPreview;

        public Camera ParticleCamera => visualizationCamera != null ? visualizationCamera : Camera.main;

        public bool TryGetVideoScreenPoint(Vector3 sensorWorld, out Vector2 screen)
        {
            screen = default;
            if (mappingInput != input)
            {
                mappingInput = input;
                mappingSource = input != null ? input.GetComponent<OpticalFlowSource>() : null;
                mappingPreview = input != null ? input.GetComponent<OpticalFlowDebugView>() : null;
            }
            if (input == null) return false;
            Vector3 sensor = sensorOrigin != null ? sensorOrigin.InverseTransformPoint(sensorWorld) : sensorWorld;
            if (!input.TryProjectSensorPoint(sensor, out Vector2 uv)) return false;
            int width = mappingSource != null && mappingSource.Width > 0 ? mappingSource.Width : input.SensorWidth;
            int height = mappingSource != null && mappingSource.Height > 0 ? mappingSource.Height : input.SensorHeight;
            float u = uv.x, v = uv.y;
            float sourceAspect = (float)input.SensorWidth / input.SensorHeight, outputAspect = (float)width / height;
            if (sourceAspect > outputAspect) v = (v - .5f) * outputAspect / sourceAspect + .5f;
            else u = (u - .5f) * sourceAspect / outputAspect + .5f;
            if (mappingSource != null && !OpticalFlowVideoMapping.SourceToOutput(ref u, ref v,
                mappingSource.cropLeft, mappingSource.cropRight, mappingSource.cropBottom, mappingSource.cropTop, mappingSource.mirror, mappingSource.flipY)) return false;
            if (u < 0 || u > 1 || v < 0 || v > 1) return false;
            Rect rect = mappingPreview != null ? mappingPreview.VideoScreenRect(width, height) : OpticalFlowDebugView.FitScreen(width, height);
            screen = new Vector2(rect.x + u * rect.width, rect.y + v * rect.height); // Bottom-left origin.
            return true;
        }

        bool MapToInteractionPlane(Vector3 sensorWorld, Camera camera, Plane plane, out Vector3 world)
        {
            world = default;
            if (!TryGetVideoScreenPoint(sensorWorld, out Vector2 screen)) return false;
            Rect viewport = camera.rect;
            if (!OpticalFlowVideoMapping.ScreenToViewport(screen.x, screen.y, Screen.width, Screen.height,
                viewport.x, viewport.y, viewport.width, viewport.height, out float u, out float v)) return false;
            var point = new Vector3(u, v, 0);
            Ray ray = camera.ViewportPointToRay(point);
            if (!plane.Raycast(ray, out float distance)) return false;
            world = ray.GetPoint(distance);
            return true;
        }

        bool UpdateInteractionHands()
        {
            if (positionMapping == PositionMapping.SensorWorld)
            {
                InteractionLeftHand = LeftHand;
                InteractionRightHand = RightHand;
            }
            else
            {
                Camera camera = ParticleCamera;
                if (camera == null) return false;
                Vector3 depthAnchor = bound != null ? originalPosition : boundOrb != null ? originalOrbPosition : Vector3.zero;
                float depth = useTargetDepth ? Vector3.Dot(depthAnchor - camera.transform.position, camera.transform.forward) : interactionDepth;
                if (depth <= camera.nearClipPlane) depth = Mathf.Max(interactionDepth, camera.nearClipPlane + .01f);
                Plane plane = interactionPlane != null ? new Plane(interactionPlane.forward, interactionPlane.position)
                    : new Plane(camera.transform.forward, camera.transform.position + camera.transform.forward * depth);
                if (!MapToInteractionPlane(LeftHand, camera, plane, out Vector3 left) ||
                    !MapToInteractionPlane(RightHand, camera, plane, out Vector3 right)) return false;
                InteractionLeftHand = left;
                InteractionRightHand = right;
            }
            InteractionHandDistance = Vector3.Distance(InteractionLeftHand, InteractionRightHand);
            return true;
        }

        void Update()
        {
            var resolved = ResolveTarget();
            if (bound != resolved) { ReleaseTarget(); BindTarget(resolved); }
            var resolvedOrb = ResolveOrbTarget();
            if (boundOrb != resolvedOrb)
            {
                ReleaseOrb();
                boundOrb = resolvedOrb;
                if (boundOrb != null)
                {
                    originalOrbPosition = boundOrb.transform.position;
                    originalOrbRadius = boundOrb.dancerSize;
                }
            }
            Vector3 left = default, right = default;
            uint body = 0;
            bool tracked = input != null && input.TryGetHands(out left, out right, out body);
            HandsTracked = tracked;
            if (tracked)
            {
                LeftHand = sensorOrigin != null ? sensorOrigin.TransformPoint(left) : left;
                RightHand = sensorOrigin != null ? sensorOrigin.TransformPoint(right) : right;
                HandDistance = Vector3.Distance(LeftHand, RightHand);
            }
            PositionValid = tracked && UpdateInteractionHands();
            float dt = Time.unscaledDeltaTime;
            bool orbActive = controlOrbPosition && PositionValid && boundOrb != null;
            if (orbActive)
            {
                float blend = !previousOrbTracking || smoothingSeconds <= 0 ? 1 : 1 - Mathf.Exp(-dt / smoothingSeconds);
                boundOrb.transform.position = Vector3.Lerp(boundOrb.transform.position, (InteractionLeftHand + InteractionRightHand) * .5f, blend);
                orbWasMoved = true;
            }
            previousOrbTracking = orbActive;
            bool orbRadiusActive = controlOrbRadius && PositionValid && boundOrb != null;
            if (orbRadiusActive)
            {
                float blend = !previousOrbRadiusTracking || smoothingSeconds <= 0 ? 1 : 1 - Mathf.Exp(-dt / smoothingSeconds);
                boundOrb.dancerSize = Mathf.Lerp(boundOrb.dancerSize, RequestedOrbRadius, blend);
                orbRadiusWasDriven = true;
            }
            previousOrbRadiusTracking = orbRadiusActive;
            if (bound == null || input == null)
            {
                Status = input == null ? "Assign Azure Kinect input" : forceManager != null
                    ? "Waiting for Force Group " + forceGroupNumber + " to be created" : "Assign Target or Force Manager + Force Group Number";
                if (orbActive || orbRadiusActive) Status = "Orb control active; " + Status;
                Mute(); return;
            }
            int selection = Mathf.Clamp(selectedBrush, 0, brushes.Length);
            ForceBrushPreset preset = selection > 0 ? brushes[selection - 1] : null;
            if (selection > 0 && preset == null) { Mute(); Status = "Assign the selected brush preset"; return; }
            if (selection != appliedSelection || preset != appliedPreset)
            {
                // Restore only the un-gated intensity before sampling current/external settings.
                bound.dancerIntensity = presetIntensity;
                if (preset != null) preset.Apply(bound);
                presetIntensity = bound.dancerIntensity;
                appliedSelection = selection;
                appliedPreset = preset;
            }
            // One stationary force source; the hands supply its choreography.
            bound.count = 1;
            bound.patternSize = bound.patternSpeed = 0;
            bound.dancerLookAtMode = 0;
            bound.dancerRotation = Vector3.zero;

            bool active = brushEnabled && tracked && PositionValid;
            float intensityTarget = intensityMapping == IntensityMapping.Manual ? 1 : tracked
                ? Mathf.InverseLerp(intensityDistanceRange.x, intensityDistanceRange.y, HandDistance) : 0;
            if (intensityMapping != IntensityMapping.Manual && invertGestureIntensity && tracked) intensityTarget = 1 - intensityTarget;
            if (controlBrushParameters)
                GestureIntensity = Mathf.Lerp(GestureIntensity, intensityTarget, smoothingSeconds <= 0 ? 1 : 1 - Mathf.Exp(-dt / smoothingSeconds));
            gate = Mathf.MoveTowards(gate, active ? 1 : 0, dt / Mathf.Max(.01f, activationFadeSeconds));
            bound.dancerIntensity = presetIntensity * Mathf.Clamp01(strength) * GestureIntensity * gate;
            if (active)
            {
                Vector3 midpoint = (InteractionLeftHand + InteractionRightHand) * .5f;
                bool reset = !previousTracking || body != previousBody;
                float blend = reset || smoothingSeconds <= 0 ? 1 : 1 - Mathf.Exp(-dt / smoothingSeconds);
                if (controlForcePosition) bound.transform.position = Vector3.Lerp(bound.transform.position, midpoint, blend);
                float radius = RequestedRadius;
                if (controlBrushParameters) bound.dancerSize = Mathf.Lerp(reset ? radius : bound.dancerSize, radius, blend);
                BrushRadius = bound.dancerSize;
                if (HandDistance >= minimumAxisDistance && InteractionHandDistance > .0001f) rawDirection = (InteractionRightHand - InteractionLeftHand).normalized;
                Quaternion orientation = OffsetOrientation(rawDirection);
                direction = orientation * Vector3.forward;
                if (controlForceOrientation && orientAlongHands)
                {
                    bound.transform.rotation = Quaternion.Slerp(bound.transform.rotation, orientation, blend);
                }
                if (controlForceOrientation && driveLinearDirection) bound.linearDirection = direction;
                previousBody = body;
                Status = "Brush active";
            }
            else Status = !brushEnabled ? "Brush inactive" : tracked && !PositionValid
                ? "Cannot map hands to particle scene: check Visualization Camera, interaction plane/depth and video crop"
                : input.BodyStatus + " (waiting for two reliable hands)";
            previousTracking = active;
        }

        StandardForceGroup ResolveTarget()
        {
            if (target != null) return target;
            if (forceManager == null || forceGroupNumber < 1 || forceManager.items == null) return null;
            int index = forceGroupNumber - 1;
            return index < forceManager.items.Count ? forceManager.items[index] : null;
        }

        OrbGroup ResolveOrbTarget()
        {
            if (orbTarget != null) return orbTarget;
            if (orbManager == null || orbGroupNumber < 1 || orbManager.items == null) return null;
            int index = orbGroupNumber - 1;
            return index < orbManager.items.Count ? orbManager.items[index] : null;
        }

        Quaternion OrientationReference => positionMapping == PositionMapping.CameraPlane && ParticleCamera != null
            ? ParticleCamera.transform.rotation : sensorOrigin != null ? sensorOrigin.rotation : Quaternion.identity;

        Quaternion OffsetOrientation(Vector3 axis)
        {
            Quaternion reference = OrientationReference;
            Vector3 up = reference * Vector3.up;
            if (Mathf.Abs(Vector3.Dot(axis, up)) > .95f) up = reference * Vector3.forward;
            // Rotate the whole frame, preserving roll as well as the direction.
            return reference * Quaternion.Euler(orientationOffset) * Quaternion.Inverse(reference) * Quaternion.LookRotation(axis, up);
        }

        public bool CalibrateDirectionUp()
        {
            if (!HandsTracked || !PositionValid || HandDistance < minimumAxisDistance || InteractionHandDistance < .0001f) return false;
            Vector3 axis = (InteractionRightHand - InteractionLeftHand).normalized;
            Vector3 local = Quaternion.Inverse(OrientationReference) * axis;
            orientationOffset = Quaternion.FromToRotation(local, Vector3.up).eulerAngles;
            return true;
        }

        public bool CaptureCurrentSettings(ForceBrushPreset preset)
        {
            var group = ResolveTarget();
            if (group == null || preset == null) return false;
            preset.Capture(group);
            // Tracking loss/activation can temporarily mute dancerIntensity. Save
            // the un-gated preset strength rather than baking that mute into the asset.
            if (Application.isPlaying && group == bound) preset.Set("dancerIntensity", presetIntensity);
            return true;
        }

        void BindTarget(StandardForceGroup resolved)
        {
            if (resolved == null) return;
            bound = resolved;
            original = ScriptableObject.CreateInstance<ForceBrushPreset>();
            original.hideFlags = HideFlags.HideAndDontSave;
            original.Capture(bound);
            originalPosition = bound.transform.position;
            originalRotation = bound.transform.rotation;
            originalScale = bound.transform.localScale;
            presetIntensity = bound.dancerIntensity;
            appliedSelection = -1;
            gate = 0;
        }

        void Mute()
        {
            previousTracking = false;
            gate = 0;
            if (bound != null) bound.dancerIntensity = 0;
        }

        void ReleaseTarget()
        {
            if (bound != null && original != null)
            {
                original.Apply(bound);
                bound.transform.position = originalPosition;
                bound.transform.rotation = originalRotation;
                bound.transform.localScale = originalScale;
            }
            if (original != null) Destroy(original);
            original = null;
            bound = null;
            appliedPreset = null;
            previousTracking = HandsTracked = false;
        }

        void ReleaseOrb()
        {
            if (boundOrb != null && orbWasMoved) boundOrb.transform.position = originalOrbPosition;
            if (boundOrb != null && orbRadiusWasDriven) boundOrb.dancerSize = originalOrbRadius;
            boundOrb = null;
            orbWasMoved = previousOrbTracking = false;
            orbRadiusWasDriven = previousOrbRadiusTracking = false;
        }

        void OnDisable() { ReleaseTarget(); ReleaseOrb(); }
        void OnEnable()
        {
            if (Application.isPlaying && GetComponent<TwoHandBrushMonitor>() == null)
                gameObject.AddComponent<TwoHandBrushMonitor>();
        }
        void Reset() => input = GetComponent<OpticalFlowAzureKinectInput>();

        void OnDrawGizmosSelected()
        {
            if (!HandsTracked) return;
            Gizmos.color = Color.cyan;
            Gizmos.DrawLine(LeftHand, RightHand);
            if (bound != null) Gizmos.DrawWireSphere(bound.transform.position, BrushRadius);
        }
    }
}
