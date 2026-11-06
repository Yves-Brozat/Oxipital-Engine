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
        // OSCQuery excludes MonoBehaviour.enabled; expose an explicit switch so
        // external control can release the groups cleanly through OnDisable.
        public bool remoteControlEnabled { get => enabled; set => enabled = value; }
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
        public bool controlOrbOrientation;
        [Tooltip("Use two dancers in the same Orb Group, one per hand, sharing the group's appearance and physics.")]
        public bool twoHandOrbs;
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
        [Tooltip("Show the geometric overlay (hands, forces and orbs) independently of the camera image or monitor panel. The top-left parameter HUD follows Show Monitor.")]
        public bool showHandOverlay = true;
        [Tooltip("Show blue radius circles for all active force-group elements, including groups independent of hand tracking.")]
        public bool showForceGeometry = true;
        [OSCQuery.DoNotExpose, Tooltip("Force Group numbers visible in the geometric overlay. Independent of the group controlled by the hands.")]
        public System.Collections.Generic.List<int> overlayForceGroups = new System.Collections.Generic.List<int> { 1 };
        [Tooltip("Show magenta emitter outlines for all active orb-group elements, including groups independent of hand tracking.")]
        public bool showOrbGeometry = true;
        [OSCQuery.DoNotExpose, Tooltip("Orb Group numbers visible in the geometric overlay. Independent of the group controlled by the hands.")]
        public System.Collections.Generic.List<int> overlayOrbGroups = new System.Collections.Generic.List<int> { 1 };
        public OverlayProjection overlayProjection = OverlayProjection.OpticalFlowVideo;

        public bool HandsTracked { get; private set; }
        public bool LeftHandTracked { get; private set; }
        public bool RightHandTracked { get; private set; }
        public bool LeftPositionValid { get; private set; }
        public bool RightPositionValid { get; private set; }
        public bool AnyHandTracked => LeftHandTracked || RightHandTracked;
        public bool AnyPositionValid => LeftPositionValid || RightPositionValid;
        public float LeftOrbActivation => orbLeftGate;
        public float RightOrbActivation => orbRightGate;
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
        Quaternion originalOrbRotation;
        bool orbOrientationWasDriven;
        float originalOrbRadius;
        bool orbWasMoved;
        bool orbRadiusWasDriven, previousOrbRadiusTracking;
        bool orbPatternOwned;
        float savedOrbCount, savedOrbSizeSpread;
        Vector3 orbLeftPosition, orbRightPosition;
        float orbLeftGate, orbRightGate;
        bool previousLeftOrbTracking, previousRightOrbTracking;
        uint previousOrbBody;
        ForceBrushPreset original, appliedPreset;
        Vector3 originalPosition, originalScale, direction = Vector3.right, rawDirection = Vector3.right;
        Quaternion originalRotation;
        int appliedSelection = -1;
        float gate, presetIntensity = 1, lastWrittenIntensity = 1;
        uint previousBody;
        bool previousTracking;
        bool forceSizeDriven, forceDirectionDriven;
        Vector3 forcePosition;
        bool forcePatternOwned;
        System.Action savedForcePattern;
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
            if (mappingSource != null)
            {
                Vector4 crop = mappingSource.EffectiveCrop;
                if (!OpticalFlowVideoMapping.SourceToOutput(ref u, ref v,
                    crop.x, 1 - crop.z, crop.y, 1 - crop.w, mappingSource.mirror, mappingSource.flipY)) return false;
            }
            if (u < 0 || u > 1 || v < 0 || v > 1) return false;
            Rect rect;
            if (mappingPreview != null) rect = mappingPreview.VideoScreenRect(width, height);
            else if (mappingSource != null && mappingSource.framePlayArea)
                rect = OpticalFlowDebugView.FitScreen(Mathf.RoundToInt(Mathf.Max(.1f, mappingSource.playAreaAspect) * 10000), 10000);
            else rect = OpticalFlowDebugView.FitScreen(width, height);
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
            LeftPositionValid = RightPositionValid = false;
            if (positionMapping == PositionMapping.SensorWorld)
            {
                LeftPositionValid = LeftHandTracked;
                RightPositionValid = RightHandTracked;
                if (LeftPositionValid) InteractionLeftHand = LeftHand;
                if (RightPositionValid) InteractionRightHand = RightHand;
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
                if (LeftHandTracked && MapToInteractionPlane(LeftHand, camera, plane, out Vector3 left))
                { InteractionLeftHand = left; LeftPositionValid = true; }
                if (RightHandTracked && MapToInteractionPlane(RightHand, camera, plane, out Vector3 right))
                { InteractionRightHand = right; RightPositionValid = true; }
            }
            bool both = LeftPositionValid && RightPositionValid;
            if (both) InteractionHandDistance = Vector3.Distance(InteractionLeftHand, InteractionRightHand);
            return both;
        }

        Vector3 InteractionCenter => LeftPositionValid && RightPositionValid
            ? (InteractionLeftHand + InteractionRightHand) * .5f
            : LeftPositionValid ? InteractionLeftHand : InteractionRightHand;

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
                    originalOrbRotation = boundOrb.transform.rotation;
                    originalOrbRadius = boundOrb.dancerSize;
                }
            }
            Vector3 left = default, right = default;
            uint body = 0;
            bool leftTracked = false, rightTracked = false;
            if (input != null) input.TryGetIndependentHands(out left, out right, out body, out leftTracked, out rightTracked);
            LeftHandTracked = leftTracked;
            RightHandTracked = rightTracked;
            bool tracked = HandsTracked = leftTracked && rightTracked;
            if (leftTracked) LeftHand = sensorOrigin != null ? sensorOrigin.TransformPoint(left) : left;
            if (rightTracked) RightHand = sensorOrigin != null ? sensorOrigin.TransformPoint(right) : right;
            if (tracked) HandDistance = Vector3.Distance(LeftHand, RightHand);
            PositionValid = UpdateInteractionHands();
            float dt = Time.unscaledDeltaTime;
            bool orbActive = controlOrbPosition && AnyPositionValid && boundOrb != null;
            if (controlOrbPosition && boundOrb != null)
            {
                if (!orbPatternOwned)
                {
                    savedOrbCount = boundOrb.count;
                    savedOrbSizeSpread = boundOrb.dancerSizeSpread;
                    orbPatternOwned = true;
                    boundOrb.positionPatternOverride = ApplyOrbHandPattern;
                    orbLeftPosition = orbRightPosition = boundOrb.transform.position;
                }
                bool leftActive = twoHandOrbs ? LeftPositionValid : AnyPositionValid;
                bool rightActive = twoHandOrbs ? RightPositionValid : AnyPositionValid;
                // Each hand reacquires without interpolating from a stale pose.
                float blend = smoothingSeconds <= 0 ? 1 : 1 - Mathf.Exp(-dt / smoothingSeconds);
                bool newBody = body != previousOrbBody;
                if (leftActive) orbLeftPosition = Vector3.Lerp(orbLeftPosition, twoHandOrbs ? InteractionLeftHand : InteractionCenter,
                    !previousLeftOrbTracking || newBody ? 1 : blend);
                if (rightActive) orbRightPosition = Vector3.Lerp(orbRightPosition, twoHandOrbs ? InteractionRightHand : InteractionCenter,
                    !previousRightOrbTracking || newBody ? 1 : blend);
                orbLeftGate = Mathf.MoveTowards(orbLeftGate, leftActive ? 1 : 0, dt / Mathf.Max(.01f, activationFadeSeconds));
                orbRightGate = Mathf.MoveTowards(orbRightGate, rightActive ? 1 : 0, dt / Mathf.Max(.01f, activationFadeSeconds));
                previousLeftOrbTracking = leftActive;
                previousRightOrbTracking = rightActive;
                previousOrbBody = body;
                if (orbActive)
                {
                    // Keep the group anchor (and its feedback) on the same
                    // smoothed positions written to the emitter dancers below.
                    boundOrb.transform.position = !twoHandOrbs || !rightActive ? orbLeftPosition
                        : !leftActive ? orbRightPosition : (orbLeftPosition + orbRightPosition) * .5f;
                    orbWasMoved = true;
                }
            }
            if (!controlOrbPosition) ReleaseOrbPattern();
            if (orbPatternOwned)
            {
                boundOrb.count = twoHandOrbs ? 2 : 1;
                boundOrb.dancerSizeSpread = 0;
            }
            bool orbRadiusActive = controlOrbRadius && PositionValid && boundOrb != null;
            if (orbRadiusActive)
            {
                float blend = !previousOrbRadiusTracking || smoothingSeconds <= 0 ? 1 : 1 - Mathf.Exp(-dt / smoothingSeconds);
                boundOrb.dancerSize = Mathf.Lerp(boundOrb.dancerSize, RequestedOrbRadius, blend);
                orbRadiusWasDriven = true;
            }
            previousOrbRadiusTracking = orbRadiusActive;
            if (controlOrbOrientation && boundOrb != null && PositionValid && HandDistance >= minimumAxisDistance && InteractionHandDistance > .0001f)
            {
                Quaternion rotation = OffsetOrientation((InteractionRightHand - InteractionLeftHand).normalized);
                float blend = !orbOrientationWasDriven || smoothingSeconds <= 0 ? 1 : 1 - Mathf.Exp(-dt / smoothingSeconds);
                boundOrb.transform.rotation = Quaternion.Slerp(boundOrb.transform.rotation, rotation, blend);
                orbOrientationWasDriven = true;
            }
            if (!controlForcePosition) ReleaseForcePattern();
            if (bound == null || input == null)
            {
                Status = input == null ? "Assign Azure Kinect input" : forceManager != null
                    ? "Waiting for Force Group " + forceGroupNumber + " to be created" : "Assign Target or Force Manager + Force Group Number";
                if (orbActive || orbRadiusActive) Status = "Orb control active; " + Status;
                Mute(); return;
            }
            int selection = Mathf.Clamp(selectedBrush, 0, brushes.Length);
            // Chataigne can load or interpolate the current group's intensity
            // while this controller is already bound. Keep that authored value
            // separate from our activation/gesture multiplier.
            if (selection == 0 && !Mathf.Approximately(bound.dancerIntensity, lastWrittenIntensity))
                presetIntensity = bound.dancerIntensity;
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

            bool active = brushEnabled && AnyPositionValid;
            float intensityTarget = intensityMapping == IntensityMapping.Manual ? 1 : tracked
                ? Mathf.InverseLerp(intensityDistanceRange.x, intensityDistanceRange.y, HandDistance) : 0;
            if (intensityMapping != IntensityMapping.Manual && invertGestureIntensity && tracked) intensityTarget = 1 - intensityTarget;
            if (controlBrushParameters && (intensityMapping == IntensityMapping.Manual || PositionValid))
                GestureIntensity = Mathf.Lerp(GestureIntensity, intensityTarget, smoothingSeconds <= 0 ? 1 : 1 - Mathf.Exp(-dt / smoothingSeconds));
            gate = Mathf.MoveTowards(gate, active ? 1 : 0, dt / Mathf.Max(.01f, activationFadeSeconds));
            bound.dancerIntensity = presetIntensity * Mathf.Clamp01(strength) * GestureIntensity * gate;
            lastWrittenIntensity = bound.dancerIntensity;
            if (active)
            {
                Vector3 midpoint = InteractionCenter;
                bool reset = !previousTracking || body != previousBody;
                float blend = reset || smoothingSeconds <= 0 ? 1 : 1 - Mathf.Exp(-dt / smoothingSeconds);
                if (controlForcePosition)
                {
                    forcePosition = Vector3.Lerp(forcePosition, midpoint, blend);
                    bound.transform.position = forcePosition;
                    if (!forcePatternOwned)
                    {
                        savedForcePattern = bound.positionPatternOverride;
                        bound.positionPatternOverride = ApplyForceHandPattern;
                        forcePatternOwned = true;
                    }
                }
                float radius = RequestedRadius;
                if (controlBrushParameters && PositionValid)
                {
                    bound.dancerSize = Mathf.Lerp(reset ? radius : bound.dancerSize, radius, blend);
                    forceSizeDriven = true;
                }
                BrushRadius = bound.dancerSize;
                if (PositionValid && HandDistance >= minimumAxisDistance && InteractionHandDistance > .0001f) rawDirection = (InteractionRightHand - InteractionLeftHand).normalized;
                Quaternion orientation = OffsetOrientation(rawDirection);
                direction = orientation * Vector3.forward;
                if (PositionValid && controlForceOrientation && orientAlongHands)
                {
                    bound.transform.rotation = Quaternion.Slerp(bound.transform.rotation, orientation, blend);
                }
                if (PositionValid && controlForceOrientation && driveLinearDirection)
                {
                    bound.linearDirection = direction;
                    forceDirectionDriven = true;
                }
                previousBody = body;
                Status = PositionValid ? "Brush active (two hands)" : "Brush active (one hand; distance and orientation held)";
            }
            else Status = !brushEnabled ? "Brush inactive" : AnyHandTracked && !AnyPositionValid
                ? "Cannot map hands to particle scene: check Visualization Camera, interaction plane/depth and video crop"
                : input.BodyStatus + " (waiting for a reliable hand)";
            previousTracking = active;
        }

        StandardForceGroup ResolveTarget()
        {
            if (target != null) return target;
            // Managers and their groups are created during Play. Resolve the
            // force manager in our own Ballet, just as for the orb manager,
            // and retry while the scene is still being initialized.
            if (forceManager == null)
            {
                var ballet = GetComponentInParent<Ballet>();
                if (ballet != null) forceManager = ballet.GetComponentInChildren<StandardForceManager>();
            }
            if (forceManager == null || forceGroupNumber < 1 || forceManager.items == null) return null;
            int index = forceGroupNumber - 1;
            return index < forceManager.items.Count ? forceManager.items[index] : null;
        }

        OrbGroup ResolveOrbTarget()
        {
            if (orbTarget != null) return orbTarget;
            if (orbManager == null && (controlOrbPosition || controlOrbRadius || controlOrbOrientation))
            {
                var ballet = GetComponentInParent<Ballet>();
                if (ballet != null) orbManager = ballet.GetComponentInChildren<OrbManager>();
            }
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
            forcePosition = originalPosition;
            originalRotation = bound.transform.rotation;
            originalScale = bound.transform.localScale;
            presetIntensity = bound.dancerIntensity;
            lastWrittenIntensity = bound.dancerIntensity;
            appliedSelection = -1;
            gate = 0;
        }

        void Mute()
        {
            previousTracking = false;
            gate = 0;
            if (bound != null) bound.dancerIntensity = lastWrittenIntensity = 0;
        }

        void ReleaseTarget()
        {
            ReleaseForcePattern();
            if (bound != null && original != null)
            {
                if (appliedPreset != null) original.Apply(bound);
                else
                {
                    // Release only what the gesture controller owned. Preserve
                    // force settings loaded by Chataigne since we bound the group.
                    original.RestoreFields(bound, "count", "patternSize", "patternSpeed", "dancerLookAtMode", "dancerRotation");
                    if (forceSizeDriven) original.RestoreFields(bound, "dancerSize");
                    if (forceDirectionDriven) original.RestoreFields(bound, "linearDirection");
                    bound.dancerIntensity = presetIntensity;
                }
                bound.transform.position = originalPosition;
                bound.transform.rotation = originalRotation;
                bound.transform.localScale = originalScale;
            }
            if (original != null) Destroy(original);
            original = null;
            bound = null;
            appliedPreset = null;
            forceSizeDriven = forceDirectionDriven = false;
            previousTracking = HandsTracked = false;
        }

        void ReleaseOrb()
        {
            ReleaseOrbPattern();
            if (boundOrb != null && orbWasMoved) boundOrb.transform.position = originalOrbPosition;
            if (boundOrb != null && orbRadiusWasDriven) boundOrb.dancerSize = originalOrbRadius;
            if (boundOrb != null && orbOrientationWasDriven) boundOrb.transform.rotation = originalOrbRotation;
            boundOrb = null;
            orbWasMoved = false;
            orbRadiusWasDriven = previousOrbRadiusTracking = false;
            orbOrientationWasDriven = false;
        }

        void ApplyForceHandPattern()
        {
            savedForcePattern?.Invoke();
            if (bound == null || !controlForcePosition || !brushEnabled || !AnyPositionValid || bound.items == null) return;
            // Write the same world center after saved patterns and immediately
            // before the force buffer is packed. Feedback and VFX read it alike.
            bound.transform.position = forcePosition;
            foreach (var dancer in bound.items)
                if (dancer != null) dancer.transform.position = forcePosition;
        }

        void ReleaseForcePattern()
        {
            if (forcePatternOwned && bound != null && bound.positionPatternOverride == ApplyForceHandPattern)
                bound.positionPatternOverride = savedForcePattern;
            savedForcePattern = null;
            forcePatternOwned = false;
        }

        void ApplyOrbHandPattern()
        {
            if (boundOrb == null || boundOrb.items == null) return;
            for (int i = 0; i < boundOrb.items.Count; i++)
                if (boundOrb.items[i] != null)
                {
                    boundOrb.items[i].transform.position = i == 0 ? orbLeftPosition : orbRightPosition;
                    boundOrb.items[i].intensity *= i == 0 ? orbLeftGate : orbRightGate;
                }
        }

        void ReleaseOrbPattern()
        {
            if (orbPatternOwned && boundOrb != null)
            {
                boundOrb.positionPatternOverride = null;
                boundOrb.count = savedOrbCount;
                boundOrb.dancerSizeSpread = savedOrbSizeSpread;
            }
            orbPatternOwned = false;
            orbLeftGate = orbRightGate = 0;
            previousLeftOrbTracking = previousRightOrbTracking = false;
        }

        void OnDisable()
        {
            ReleaseTarget(); ReleaseOrb();
            LeftHandTracked = RightHandTracked = LeftPositionValid = RightPositionValid = PositionValid = false;
        }
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
