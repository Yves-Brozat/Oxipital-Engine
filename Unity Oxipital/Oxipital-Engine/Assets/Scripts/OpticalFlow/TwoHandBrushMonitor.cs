using UnityEngine;

namespace Oxipital
{
    // Presentation only: hiding/disabling this component never changes tracking,
    // force activation or the optical-flow preview.
    [DisallowMultipleComponent]
    [RequireComponent(typeof(TwoHandForceBrush))]
    public sealed class TwoHandBrushMonitor : MonoBehaviour
    {
        TwoHandForceBrush brush;
        Rect window;
        Vector2 scroll;
        bool placed, collapsed;
        GUIStyle wrap, title, small;
        GUIStyle overlayLabel;
        int overlayFontSize;
        string depthCalibrationStatus;
        Texture2D disc;
        StandardForceGroup[] sceneForces;
        OrbGroup[] sceneOrbs;
        float nextGroupScan;
        static readonly Color Cyan = new Color(.25f, .9f, 1);
        static readonly Color Orange = new Color(1, .65f, .25f);
        static readonly Color ForceBlue = new Color(.2f, .45f, 1);
        static readonly Color OrbMagenta = new Color(1, .35f, 1);

        void OnEnable() => brush = GetComponent<TwoHandForceBrush>();

        void OnGUI()
        {
            if (!Application.isPlaying || brush == null) return;
            if (!brush.showMonitor && !brush.showHandOverlay) return;
            if (wrap == null)
            {
                wrap = new GUIStyle(GUI.skin.label) { fontSize = 15, wordWrap = true };
                title = new GUIStyle(GUI.skin.label) { fontSize = 16, fontStyle = FontStyle.Bold };
                small = new GUIStyle(GUI.skin.label) { fontSize = 14, wordWrap = true };
            }
            if (Event.current.type == EventType.Repaint) DrawScreenOverlay();
            if (!brush.showMonitor) return;
            float scale = Mathf.Clamp(brush.monitorScale, 1, 3);
            float screenWidth = Screen.width / scale, screenHeight = Screen.height / scale;
            float width = Mathf.Min(520, Mathf.Max(120, screenWidth - 16));
            float height = collapsed ? 32 : Mathf.Min(760, Mathf.Max(90, screenHeight - 24));
            if (!placed) { window = new Rect(screenWidth - width - 12, 12, width, height); placed = true; }
            window.width = width;
            window.height = height;
            window.x = Mathf.Clamp(window.x, 0, Mathf.Max(0, screenWidth - width));
            window.y = Mathf.Clamp(window.y, 0, Mathf.Max(0, screenHeight - height));
            Matrix4x4 previous = GUI.matrix;
            GUI.matrix = Matrix4x4.Scale(new Vector3(scale, scale, 1)) * previous;
            try { window = GUI.Window(GetInstanceID(), window, DrawWindow, "Pinceau a deux mains"); }
            finally { GUI.matrix = previous; }
        }

        void DrawWindow(int id)
        {
            if (GUI.Button(new Rect(window.width - 55, 3, 24, 21), collapsed ? "+" : "-")) collapsed = !collapsed;
            if (GUI.Button(new Rect(window.width - 28, 3, 24, 21), "X")) brush.showMonitor = false;
            if (!collapsed)
            {
                GUILayout.Space(6);
                scroll = GUILayout.BeginScrollView(scroll, GUILayout.Height(window.height - 37));
                DrawContent();
                GUILayout.EndScrollView();
            }
            GUI.DragWindow(new Rect(0, 0, window.width - 60, 24));
        }

        void DrawContent()
        {
            var group = brush.ResolvedTarget;
            GUILayout.Label(group != null ? group.name : "En attente du Force Group " + brush.forceGroupNumber, title);
            GUILayout.BeginHorizontal();
            if (GUILayout.Button("<", GUILayout.Width(28))) brush.selectedBrush = Mathf.Max(0, brush.selectedBrush - 1);
            GUILayout.Label(brush.SelectedBrushName, wrap);
            if (GUILayout.Button(">", GUILayout.Width(28))) brush.selectedBrush = Mathf.Min(brush.brushes.Length, brush.selectedBrush + 1);
            GUILayout.EndHorizontal();
            brush.brushEnabled = GUILayout.Toggle(brush.brushEnabled, "Pinceau active");
            GUILayout.BeginHorizontal();
            brush.controlForcePosition = ControlButton("Position forces", brush.controlForcePosition);
            brush.controlOrbPosition = ControlButton("Position orbe", brush.controlOrbPosition);
            GUILayout.EndHorizontal();
            GUILayout.BeginHorizontal();
            brush.controlBrushParameters = ControlButton("Intensite / rayon", brush.controlBrushParameters);
            brush.controlForceOrientation = ControlButton("Orientation forces", brush.controlForceOrientation);
            GUILayout.EndHorizontal();
            brush.controlOrbRadius = ControlButton("Rayon orbe", brush.controlOrbRadius);
            brush.controlOrbOrientation = ControlButton("Orientation orbe", brush.controlOrbOrientation);
            brush.twoHandOrbs = ControlButton("Deux orbes (une par main)", brush.twoHandOrbs);
            if (brush.controlOrbPosition || brush.controlOrbRadius)
                GUILayout.Label(brush.ResolvedOrbTarget != null ? "Orbe : " + brush.ResolvedOrbTarget.name : "En attente Orb Group " + brush.orbGroupNumber, small);
            if (brush.ResolvedOrbTarget != null)
                Bar("Rayon orbe", brush.ResolvedOrbTarget.dancerSize / Mathf.Max(.01f, brush.MaximumBrushRadius * brush.orbRadiusMultiplier),
                    new Color(1, .35f, 1), brush.ResolvedOrbTarget.dancerSize.ToString("F2"));
            if (GUILayout.Button("Calibrer cette pose vers le haut") && brush.HandsTracked && brush.PositionValid)
                brush.CalibrateDirectionUp();
            brush.showHandOverlay = GUILayout.Toggle(brush.showHandOverlay, "Reperes geometriques sur la vue des particules");
            GUILayout.BeginHorizontal();
            brush.showForceGeometry = ControlButton("Reperes forces", brush.showForceGeometry);
            brush.showOrbGeometry = ControlButton("Reperes orbes", brush.showOrbGeometry);
            GUILayout.EndHorizontal();
            DrawGroupSelections();
            GUILayout.BeginHorizontal();
            GUILayout.Label("Taille de l'interface", small);
            brush.monitorScale = GUILayout.HorizontalSlider(brush.monitorScale, 1, 3, GUILayout.Width(140));
            GUILayout.EndHorizontal();
            var preview = brush.input != null ? brush.input.GetComponent<OpticalFlowDebugView>() : null;
            if (preview != null)
            {
                bool imagesVisible = preview.view != OpticalFlowDebugView.View.Off || preview.planeView != OpticalFlowDebugView.PlaneView.Off;
                bool showImages = GUILayout.Toggle(imagesVisible, "Afficher l'image camera / optical flow");
                if (showImages != imagesVisible)
                {
                    preview.view = showImages ? OpticalFlowDebugView.View.Source : OpticalFlowDebugView.View.Off;
                    preview.planeView = OpticalFlowDebugView.PlaneView.Off;
                }
                GUILayout.BeginHorizontal();
                GUILayout.Label("Opacite de l'image", small);
                preview.overlayOpacity = GUILayout.HorizontalSlider(preview.overlayOpacity, 0, 1, GUILayout.Width(140));
                GUILayout.EndHorizontal();
            }
            var source = brush.input != null ? brush.input.GetComponent<OpticalFlowSource>() : null;
            if (source != null)
            {
                source.framePlayArea = GUILayout.Toggle(source.framePlayArea, "Recadrer la zone de jeu");
                if (source.framePlayArea)
                {
                    if (GUILayout.Button("Zone 4:3 - ecran 8 m x 6 m")) source.playAreaAspect = 4f / 3f;
                    GUILayout.Label("Zoom zone : " + source.playAreaZoom.ToString("F2"), small);
                    source.playAreaZoom = GUILayout.HorizontalSlider(source.playAreaZoom, 1, 4);
                    GUILayout.Label("Centre horizontal : " + source.playAreaCenterX.ToString("F2"), small);
                    source.playAreaCenterX = GUILayout.HorizontalSlider(source.playAreaCenterX, 0, 1);
                    GUILayout.Label("Centre vertical (0 = bas) : " + source.playAreaCenterY.ToString("F2"), small);
                    source.playAreaCenterY = GUILayout.HorizontalSlider(source.playAreaCenterY, 0, 1);
                }
            }
            var oldColor = GUI.contentColor;
            GUI.contentColor = brush.AnyHandTracked ? Cyan : Orange;
            GUILayout.Label(brush.HandsTracked ? "Deux mains suivies" : brush.AnyHandTracked ? "Une main suivie" : "Mains absentes ou suivi insuffisant", title);
            GUI.contentColor = oldColor;
            GUILayout.Label(brush.Status, small);
            if (brush.input != null)
            {
                GUILayout.Label("IR " + brush.input.CaptureFPS.ToString("F1") + " FPS  |  Corps " + brush.input.BodyFPS.ToString("F1") + " FPS", small);
                var input = brush.input;
                GUILayout.Label(input.HandDiagnostics(true), small);
                GUILayout.Label(input.HandDiagnostics(false), small);
                if (brush.LeftHandTracked && !brush.LeftPositionValid) GUILayout.Label("G : hors cadrage / plan de projection invalide", small);
                if (brush.RightHandTracked && !brush.RightPositionValid) GUILayout.Label("D : hors cadrage / plan de projection invalide", small);
                GUILayout.Label("Profondeur capteur : " + input.DepthModeDescription, small);
                if (GUILayout.Button("Mode " + (input.depthMode == AzureKinectDepthMode.WFOVBinned ? "WFOV -> NFOV (plus loin)" : "NFOV -> WFOV (plus large)")))
                    input.depthMode = input.depthMode == AzureKinectDepthMode.WFOVBinned ? AzureKinectDepthMode.NFOVUnbinned : AzureKinectDepthMode.WFOVBinned;
                input.minimumHandConfidence = GUILayout.Toggle(input.minimumHandConfidence == 1, "Accepter confiance faible (suivi moins fiable)") ? 1 : 2;
                GUILayout.Label("Delai maximal du suivi : " + input.trackingTimeout.ToString("F2") + " s", small);
                input.trackingTimeout = GUILayout.HorizontalSlider(input.trackingTimeout, .1f, 1);
                input.filterHandDepth = GUILayout.Toggle(input.filterHandDepth, "Limiter l'activation en profondeur");
                if (input.filterHandDepth)
                {
                    GUILayout.Label("Profondeur minimale : " + input.minimumHandDepth.ToString("F2") + " m", small);
                    input.minimumHandDepth = GUILayout.HorizontalSlider(input.minimumHandDepth, 0, 10);
                    GUILayout.Label("Profondeur maximale : " + input.maximumHandDepth.ToString("F2") + " m", small);
                    input.maximumHandDepth = GUILayout.HorizontalSlider(input.maximumHandDepth, input.minimumHandDepth, 10);
                }
                GUILayout.Label("Marge autour de la pose : +/- " + input.depthCalibrationMargin.ToString("F2") + " m", small);
                input.depthCalibrationMargin = GUILayout.HorizontalSlider(input.depthCalibrationMargin, .1f, 3);
                if (GUILayout.Button("Calibrer la profondeur sur ma position"))
                    depthCalibrationStatus = input.CalibrateHandDepth() ? "Zone de profondeur centree sur les mains suivies." : "Calibration impossible : montrer au moins une main fiable (image recente).";
                if (!string.IsNullOrEmpty(depthCalibrationStatus)) GUILayout.Label(depthCalibrationStatus, small);
                if (brush.controlOrbPosition && brush.twoHandOrbs)
                {
                    Bar("Activation orbe G", brush.LeftOrbActivation, Cyan);
                    Bar("Activation orbe D", brush.RightOrbActivation, Orange);
                }
            }
            DrawHands();
            GUILayout.Label("Mouvements vers parametres", title);
            GUILayout.Label("Ecart des mains : " + (brush.HandsTracked ? brush.HandDistance.ToString("F2") + " m" : "--"));
            GUILayout.Label("Ecart dans la scene : " + (brush.PositionValid ? brush.InteractionHandDistance.ToString("F2") : "--"), small);
            GUILayout.Label("Ecart scene x " + brush.radiusMultiplier.ToString("F2") + " x taille " + brush.sizeMultiplier.ToString("F1") + " -> rayon demande : " +
                (brush.HandsTracked ? brush.RequestedRadius.ToString("F2") + " m" : "--"), small);
            Bar("Rayon demande", brush.HandsTracked ? brush.RequestedRadius / Mathf.Max(.01f, brush.MaximumBrushRadius) : 0, Cyan,
                brush.HandsTracked ? brush.RequestedRadius.ToString("F2") + " m" : "--");
            Bar("Activation du pinceau", brush.Activation, ActivationColor);
            GUILayout.Label("Intensite : " + brush.intensityMapping + "  |  Strength : " + brush.strength.ToString("F2"), small);
            Bar("Signal du geste", brush.GestureIntensity, Cyan);
            if (group == null) return;
            GUILayout.Label("Valeurs actuelles du Force Group", title);
            GUILayout.Label("Position : " + Format(group.transform.position) + " m", small);
            GUILayout.Label("Rotation : " + Format(group.transform.eulerAngles) + " deg", small);
            GUILayout.Label("Rayon applique : " + group.dancerSize.ToString("F2") + " m", small);
            GUILayout.Label("Influence dedans / dehors : " + group.forceFactorInside.ToString("F2") + " / " + group.forceFactorOutside.ToString("F2"), small);
            if (brush.driveLinearDirection) GUILayout.Label("Direction lineaire : " + Format(group.linearDirection), small);
            Bar("Intensite appliquee", group.dancerIntensity, ActivationColor);
            GUILayout.Space(4);
            GUILayout.Label("Forces du preset / Chataigne", title);
            Bar("Radiale", group.radialIntensity, Orange);
            Bar("Axiale", group.axialIntensity, Orange);
            Bar("Lineaire", group.linearIntensity, Orange);
            Bar("Orthoradiale", group.orthoIntensity, Orange);
            Bar("Curl", group.curlIntensity, Orange);
            Bar("Perlin", group.perlinIntensity, Orange);
            Bar("Orthoaxiale", group.orthoaxialIntensity, Orange);
            Bar("Spirale", group.spiralIntensity, Orange);
            GUILayout.Label("Les mains pilotent position, rayon et orientation. Les intensites de force viennent du preset. X masque ce panneau ; Show Monitor le reaffiche dans l'inspecteur.", small);
        }

        void DrawHands()
        {
            Rect plot = GUILayoutUtility.GetRect(100, 125, GUILayout.ExpandWidth(true));
            if (Event.current.type != EventType.Repaint) return;
            Fill(plot, new Color(.05f, .07f, .09f, .95f));
            GUI.Label(new Rect(plot.x + 6, plot.y + 3, plot.width - 12, 22), "Vue de face du capteur (schema)", small);
            if (!brush.AnyHandTracked)
            {
                GUI.Label(new Rect(plot.x + 8, plot.y + 48, plot.width - 16, 40), "Montrer une main au capteur", wrap);
                return;
            }
            // Sensor-space frontal projection, deliberately separate from the IR
            // preview: not a pixel registration with the camera or a VFX projection.
            Vector3 left = brush.sensorOrigin != null ? brush.sensorOrigin.InverseTransformPoint(brush.LeftHand) : brush.LeftHand;
            Vector3 right = brush.sensorOrigin != null ? brush.sensorOrigin.InverseTransformPoint(brush.RightHand) : brush.RightHand;
            Rect area = new Rect(plot.x + 16, plot.y + 28, plot.width - 32, plot.height - 40);
            Vector2 a = Project(left, area), b = Project(right, area), midpoint = (a + b) * .5f;
            if (brush.HandsTracked)
            {
                Line(a, b, Cyan);
                Fill(new Rect(midpoint.x - 3, midpoint.y - 3, 6, 6), Color.white);
            }
            if (brush.LeftHandTracked)
            {
                Fill(new Rect(a.x - 4, a.y - 4, 8, 8), Cyan);
                GUI.Label(new Rect(a.x - 9, Mathf.Min(a.y + 5, plot.yMax - 20), 26, 20), "G", small);
            }
            if (brush.RightHandTracked)
            {
                Fill(new Rect(b.x - 4, b.y - 4, 8, 8), Orange);
                GUI.Label(new Rect(b.x - 9, Mathf.Min(b.y + 5, plot.yMax - 20), 26, 20), "D", small);
            }
        }

        static Vector2 Project(Vector3 hand, Rect area) => new Vector2(
            Mathf.Lerp(area.xMin, area.xMax, Mathf.InverseLerp(-1.5f, 1.5f, hand.x)),
            Mathf.Lerp(area.yMax, area.yMin, Mathf.InverseLerp(-1.2f, 1.2f, hand.y)));

        Color ActivationColor => Color.Lerp(new Color(1, .35f, .25f), new Color(.25f, 1, .45f),
            brush.ResolvedTarget != null ? Mathf.Clamp01(brush.ResolvedTarget.dancerIntensity) : 0);

        void Bar(string name, float value, Color color, string display = null)
        {
            Rect rect = GUILayoutUtility.GetRect(100, 27, GUILayout.ExpandWidth(true));
            if (Event.current.type == EventType.Repaint)
            {
                Fill(rect, new Color(.12f, .14f, .16f));
                Fill(new Rect(rect.x, rect.y, rect.width * Mathf.Clamp01(value), rect.height), color * new Color(1, 1, 1, .55f));
                GUI.Label(new Rect(rect.x + 5, rect.y, rect.width - 10, rect.height), name + " : " + (display ?? value.ToString("F2")), small);
            }
        }

        void DrawScreenOverlay()
        {
            float scale = Mathf.Clamp(brush.monitorScale, 1, 3);
            int size = Mathf.RoundToInt(16 * scale);
            if (overlayLabel == null || overlayFontSize != size)
            {
                overlayFontSize = size;
                overlayLabel = new GUIStyle(GUI.skin.label) { fontSize = size, fontStyle = FontStyle.Bold, wordWrap = true };
            }
            var camera = brush.ParticleCamera;
            var group = brush.ResolvedTarget;
            Vector2 left = default, right = default;
            bool sceneHands = brush.overlayProjection == TwoHandForceBrush.OverlayProjection.SceneCamera;
            bool leftVisible = brush.LeftHandTracked && (!sceneHands || brush.LeftPositionValid) && ProjectOverlay(camera, sceneHands ? brush.InteractionLeftHand : brush.LeftHand, out left);
            bool rightVisible = brush.RightHandTracked && (!sceneHands || brush.RightPositionValid) && ProjectOverlay(camera, sceneHands ? brush.InteractionRightHand : brush.RightHand, out right);
            Color activeColor = ActivationColor;
            float radius = group != null ? group.dancerSize : 0;
            if (brush.showMonitor)
                DrawParameterOverlay(camera, group, leftVisible, rightVisible, scale);
            if (!brush.showHandOverlay) return;
            // World-space groups are independent of hand acquisition and of
            // the sensor/video projection used to place the hand markers.
            if (camera != null) DrawSceneGeometry(camera, scale);
            bool videoSpace = brush.overlayProjection == TwoHandForceBrush.OverlayProjection.OpticalFlowVideo;
            if (!brush.AnyHandTracked || (!videoSpace && camera == null)) return;

            if (leftVisible && rightVisible) Line(left, right, activeColor);
            if (leftVisible) HandMarker(left, "G", Cyan, scale);
            if (rightVisible) HandMarker(right, "D", Orange, scale);
            if (IsForceGroupVisible(group) && ProjectBrush(camera, group.transform.position, out Vector2 center))
            {
                Dot(center, 6 * scale, activeColor);
                if (brush.orientAlongHands)
                {
                    Vector3 tip = group.transform.position + group.transform.forward * Mathf.Max(radius, .1f);
                    if (ProjectBrush(camera, tip, out Vector2 end))
                    {
                        Line(center, end, Color.white);
                        Dot(end, 4 * scale, Color.white);
                    }
                }
            }
        }

        void DrawSceneGeometry(Camera camera, float scale)
        {
            if (!brush.showForceGeometry && !brush.showOrbGeometry) return;
            // Groups can be created or deleted by Chataigne during Play.
            // Cache discovery, but read each dancer's live VFX-buffer data.
            RefreshSceneGroups();
            if (brush.showForceGeometry)
                foreach (var force in sceneForces)
                {
                    if (force == null || !force.isActiveAndEnabled || force.items == null) continue;
                    if (!IsForceGroupVisible(force)) continue;
                    for (int i = 0; i < force.items.Count; i++)
                    {
                        var dancer = force.items[i];
                        if (!VisibleDancer(dancer)) continue;
                        WorldEllipse(camera, dancer.transform.position, camera.transform.right * dancer.size,
                            camera.transform.up * dancer.size, ForceBlue);
                        GeometryMarker(camera, dancer.transform.position, force.name + " / " + (i + 1), ForceBlue, scale);
                    }
                }
            if (brush.showOrbGeometry)
                foreach (var orb in sceneOrbs)
                {
                    if (orb == null || !orb.isActiveAndEnabled || orb.items == null) continue;
                    if (brush.overlayOrbGroups == null || !brush.overlayOrbGroups.Contains(OrbGroupNumber(orb))) continue;
                    for (int i = 0; i < orb.items.Count; i++)
                    {
                        var dancer = orb.items[i];
                        if (!VisibleDancer(dancer)) continue;
                        DrawOrbGeometry(camera, orb, dancer);
                        GeometryMarker(camera, dancer.transform.position, orb.name + " / " + (i + 1), OrbMagenta, scale);
                    }
                }
        }

        void RefreshSceneGroups()
        {
            if (sceneForces != null && Time.unscaledTime < nextGroupScan) return;
            sceneForces = FindObjectsByType<StandardForceGroup>(FindObjectsSortMode.None);
            System.Array.Sort(sceneForces, (a, b) => ForceGroupNumber(a).CompareTo(ForceGroupNumber(b)));
            sceneOrbs = FindObjectsByType<OrbGroup>(FindObjectsSortMode.None);
            System.Array.Sort(sceneOrbs, (a, b) => OrbGroupNumber(a).CompareTo(OrbGroupNumber(b)));
            nextGroupScan = Time.unscaledTime + .5f;
        }

        static int OrbGroupNumber(OrbGroup orb)
        {
            var manager = orb.GetComponentInParent<OrbManager>();
            if (manager != null && manager.items != null)
            {
                int index = manager.items.IndexOf(orb);
                if (index >= 0) return index + 1;
            }
            string name = orb.name;
            int lastSpace = name.LastIndexOf(' ');
            return int.TryParse(name.Substring(lastSpace + 1), out int number) ? number : 1;
        }

        static int ForceGroupNumber(StandardForceGroup force)
        {
            var manager = force.GetComponentInParent<StandardForceManager>();
            if (manager != null && manager.items != null)
            {
                int index = manager.items.IndexOf(force);
                if (index >= 0) return index + 1;
            }
            string name = force.name;
            int lastSpace = name.LastIndexOf(' ');
            return int.TryParse(name.Substring(lastSpace + 1), out int number) ? number : 1;
        }

        bool IsForceGroupVisible(StandardForceGroup group) => group != null && brush.showForceGeometry &&
            brush.overlayForceGroups != null && brush.overlayForceGroups.Contains(ForceGroupNumber(group));

        void DrawGroupSelections()
        {
            RefreshSceneGroups();
            if (brush.overlayForceGroups == null) brush.overlayForceGroups = new System.Collections.Generic.List<int> { 1 };
            if (brush.overlayOrbGroups == null) brush.overlayOrbGroups = new System.Collections.Generic.List<int> { 1 };
            DrawGroupSelection(sceneForces, brush.overlayForceGroups, ForceGroupNumber, "Force Group");
            DrawGroupSelection(sceneOrbs, brush.overlayOrbGroups, OrbGroupNumber, "Orb Group");
        }

        void DrawGroupSelection<T>(T[] groups, System.Collections.Generic.List<int> selection,
            System.Func<T, int> groupNumber, string label) where T : Component
        {
            GUILayout.Label(label + "s visibles (selection multiple)", small);
            int count = 0;
            foreach (var group in groups)
            {
                if (group == null) continue;
                if (count % 4 == 0) GUILayout.BeginHorizontal();
                int number = groupNumber(group);
                bool selected = selection.Contains(number);
                bool next = GUILayout.Toggle(selected, label + " " + number, GUI.skin.button, GUILayout.MinHeight(26));
                if (next != selected)
                {
                    if (next) selection.Add(number);
                    else selection.Remove(number);
                }
                count++;
                if (count % 4 == 0) GUILayout.EndHorizontal();
            }
            if (count % 4 != 0) GUILayout.EndHorizontal();
            if (count == 0) GUILayout.Label("En attente des " + label + "s", small);
        }

        static bool VisibleDancer(Dancer dancer) => dancer != null && dancer.isActiveAndEnabled &&
            dancer.weight > 0 && dancer.size > 0 && dancer.killProgress < 1;

        void GeometryMarker(Camera camera, Vector3 position, string label, Color color, float scale)
        {
            if (!ProjectWorld(camera, position, out Vector2 point)) return;
            Dot(point, 4 * scale, color);
            LabelAt(point + new Vector2(8 * scale, 5 * scale), label, color, scale * .75f);
        }

        void DrawOrbGeometry(Camera camera, OrbGroup orb, Dancer dancer)
        {
            Vector3 position = dancer.transform.position;
            // Rotation and size are exactly those packed into the orb buffer;
            // transform.lossyScale would wrongly apply the group's scale twice.
            Matrix4x4 matrix = Matrix4x4.TRS(position, dancer.targetRotation, orb.EffectiveEmitterScale * dancer.size);
            if (orb.emitterShape == OrbGroup.EmitterShape.Sphere || orb.emitterShape == OrbGroup.EmitterShape.Circle)
            {
                Vector3 right = orb.emitterShape == OrbGroup.EmitterShape.Circle ? Vector3.right :
                    Quaternion.Inverse(dancer.targetRotation) * camera.transform.right;
                Vector3 up = orb.emitterShape == OrbGroup.EmitterShape.Circle ? Vector3.up :
                    Quaternion.Inverse(dancer.targetRotation) * camera.transform.up;
                WorldEllipse(camera, position, matrix.MultiplyVector(right), matrix.MultiplyVector(up), OrbMagenta);
                return;
            }
            // Mesh bounds preserve the plane's actual axes and dimensions.
            // Other volume/custom emitters use their oriented bounding box.
            var meshFilter = dancer.GetComponent<MeshFilter>();
            Bounds bounds = meshFilter != null && meshFilter.sharedMesh != null
                ? meshFilter.sharedMesh.bounds : new Bounds(Vector3.zero, Vector3.one * 2);
            if (orb.emitterShape == OrbGroup.EmitterShape.Line)
                bounds = new Bounds(Vector3.zero, new Vector3(2, .03f, .03f));
            DrawBounds(camera, matrix, bounds, OrbMagenta);
        }

        void DrawBounds(Camera camera, Matrix4x4 matrix, Bounds bounds, Color color)
        {
            Vector3 min = bounds.min, max = bounds.max;
            for (int corner = 0; corner < 8; corner++)
            {
                Vector3 a = new Vector3((corner & 1) == 0 ? min.x : max.x,
                    (corner & 2) == 0 ? min.y : max.y, (corner & 4) == 0 ? min.z : max.z);
                for (int axis = 0; axis < 3; axis++)
                {
                    if ((corner & (1 << axis)) != 0) continue;
                    Vector3 b = a;
                    b[axis] = max[axis];
                    WorldLine(camera, matrix.MultiplyPoint3x4(a), matrix.MultiplyPoint3x4(b), color);
                }
            }
        }

        void WorldEllipse(Camera camera, Vector3 center, Vector3 right, Vector3 up, Color color)
        {
            const int segments = 64;
            Vector3 previous = center + right;
            for (int i = 1; i <= segments; i++)
            {
                float angle = i * (Mathf.PI * 2 / segments);
                Vector3 point = center + right * Mathf.Cos(angle) + up * Mathf.Sin(angle);
                WorldLine(camera, previous, point, color);
                previous = point;
            }
        }

        static void WorldLine(Camera camera, Vector3 a, Vector3 b, Color color)
        {
            // Keep contours crossing the screen edges, even if their center
            // or an endpoint is outside the viewport. Reject the near plane.
            Vector3 p = camera.WorldToViewportPoint(a), q = camera.WorldToViewportPoint(b);
            float near = camera.nearClipPlane + .0001f;
            if (p.z < near && q.z < near) return;
            if (p.z < near)
            {
                a = Vector3.Lerp(a, b, (near - p.z) / (q.z - p.z));
                p = camera.WorldToViewportPoint(a);
            }
            else if (q.z < near)
            {
                b = Vector3.Lerp(b, a, (near - q.z) / (p.z - q.z));
                q = camera.WorldToViewportPoint(b);
            }
            Rect viewport = camera.rect;
            Line(new Vector2((viewport.x + p.x * viewport.width) * Screen.width,
                    (1 - viewport.y - p.y * viewport.height) * Screen.height),
                new Vector2((viewport.x + q.x * viewport.width) * Screen.width,
                    (1 - viewport.y - q.y * viewport.height) * Screen.height), color);
        }

        void DrawParameterOverlay(Camera camera, StandardForceGroup group, bool leftVisible, bool rightVisible, float scale)
        {
            Color activeColor = ActivationColor;
            float hudWidth = Mathf.Min(440 * scale, Screen.width - 24);
            float row = 31 * scale;
            Rect hud = new Rect(12, 12, hudWidth, row * 5);
            Fill(hud, new Color(.025f, .035f, .045f, .88f));
            GUI.Label(new Rect(hud.x + 10, hud.y + 4, hud.width - 20, row), brush.SelectedBrushName, overlayLabel);
            ScreenGauge(new Rect(hud.x + 10, hud.y + row, hud.width - 20, row - 5), "Activation", brush.Activation, activeColor, (brush.Activation * 100).ToString("F0") + " %");
            ScreenGauge(new Rect(hud.x + 10, hud.y + row * 2, hud.width - 20, row - 5), "Intensite", group != null ? group.dancerIntensity : 0, activeColor,
                group != null ? group.dancerIntensity.ToString("F2") : "--");
            float radius = group != null ? group.dancerSize : 0;
            ScreenGauge(new Rect(hud.x + 10, hud.y + row * 3, hud.width - 20, row - 5), "Rayon", radius / Mathf.Max(.01f, brush.MaximumBrushRadius), Cyan,
                group != null ? radius.ToString("F2") + " m" : "--");
            bool videoSpace = brush.overlayProjection == TwoHandForceBrush.OverlayProjection.OpticalFlowVideo;
            string state = !brush.AnyHandTracked ? "En attente d'une main" : !videoSpace && camera == null ? "Assigner Visualization Camera" :
                !leftVisible && !rightVisible ? "Mains hors cadrage / calibration" : "G : " + (leftVisible ? "active" : "inactive") + " | D : " + (rightVisible ? "active" : "inactive");
            GUI.Label(new Rect(hud.x + 10, hud.y + row * 4, hud.width - 20, row), state, overlayLabel);
        }

        static bool ControlButton(string label, bool value)
        {
            Color previous = GUI.backgroundColor;
            GUI.backgroundColor = value ? new Color(.3f, .9f, .55f) : new Color(.55f, .55f, .55f);
            bool result = GUILayout.Toggle(value, label + (value ? " : ON" : " : OFF"), GUI.skin.button, GUILayout.MinHeight(27));
            GUI.backgroundColor = previous;
            return result;
        }

        static bool ProjectWorld(Camera camera, Vector3 world, out Vector2 point)
        {
            Vector3 screen = camera.WorldToViewportPoint(world);
            Rect viewport = camera.rect;
            point = new Vector2((viewport.x + screen.x * viewport.width) * Screen.width,
                (1 - viewport.y - screen.y * viewport.height) * Screen.height);
            return screen.z >= camera.nearClipPlane && screen.x >= 0 && screen.x <= 1 && screen.y >= 0 && screen.y <= 1;
        }

        bool ProjectOverlay(Camera camera, Vector3 world, out Vector2 point)
        {
            point = default;
            if (brush.overlayProjection == TwoHandForceBrush.OverlayProjection.SceneCamera)
                return camera != null && ProjectWorld(camera, world, out point);
            if (!brush.TryGetVideoScreenPoint(world, out Vector2 screen)) return false;
            point = new Vector2(screen.x, Screen.height - screen.y);
            return true;
        }

        bool ProjectBrush(Camera camera, Vector3 world, out Vector2 point)
        {
            point = default;
            return brush.positionMapping == TwoHandForceBrush.PositionMapping.CameraPlane
                ? camera != null && ProjectWorld(camera, world, out point) : ProjectOverlay(camera, world, out point);
        }

        void HandMarker(Vector2 point, string label, Color color, float scale)
        {
            Dot(point, 11 * scale, new Color(0, 0, 0, .85f));
            Dot(point, 8 * scale, color);
            LabelAt(point + new Vector2(14 * scale, -17 * scale), label, color, scale);
        }

        void LabelAt(Vector2 point, string text, Color color, float scale)
        {
            float width = Mathf.Min(Screen.width, overlayLabel.CalcSize(new GUIContent(text)).x + 12);
            Rect rect = new Rect(Mathf.Clamp(point.x, 0, Mathf.Max(0, Screen.width - width)),
                Mathf.Clamp(point.y, 0, Mathf.Max(0, Screen.height - 34 * scale)), width, 34 * scale);
            Fill(rect, new Color(0, 0, 0, .65f));
            Color previous = GUI.contentColor;
            GUI.contentColor = color;
            GUI.Label(rect, text, overlayLabel);
            GUI.contentColor = previous;
        }

        void ScreenGauge(Rect rect, string label, float value, Color color, string display)
        {
            Fill(rect, new Color(.1f, .12f, .14f, .95f));
            Fill(new Rect(rect.x, rect.y, rect.width * Mathf.Clamp01(value), rect.height), color * new Color(1, 1, 1, .6f));
            GUI.Label(new Rect(rect.x + 6, rect.y, rect.width - 12, rect.height), label + " : " + display, overlayLabel);
        }

        void Dot(Vector2 point, float radius, Color color)
        {
            if (disc == null)
            {
                disc = new Texture2D(32, 32, TextureFormat.RGBA32, false) { name = "Brush monitor marker", hideFlags = HideFlags.HideAndDontSave };
                var pixels = new Color[32 * 32];
                for (int y = 0; y < 32; y++) for (int x = 0; x < 32; x++)
                    pixels[y * 32 + x] = new Color(1, 1, 1, Mathf.Clamp01(15.5f - Vector2.Distance(new Vector2(x, y), new Vector2(15.5f, 15.5f))));
                disc.SetPixels(pixels);
                disc.Apply(false, true);
            }
            Color previous = GUI.color;
            GUI.color = color;
            GUI.DrawTexture(new Rect(point.x - radius, point.y - radius, radius * 2, radius * 2), disc);
            GUI.color = previous;
        }

        void OnDisable()
        {
            if (disc != null) Destroy(disc);
            disc = null;
        }

        static string Format(Vector3 v) => v.x.ToString("F2") + " / " + v.y.ToString("F2") + " / " + v.z.ToString("F2");

        static void Fill(Rect rect, Color color)
        {
            Color previous = GUI.color;
            GUI.color = color;
            GUI.DrawTexture(rect, Texture2D.whiteTexture);
            GUI.color = previous;
        }

        static void Line(Vector2 from, Vector2 to, Color color)
        {
            Matrix4x4 previous = GUI.matrix;
            GUIUtility.RotateAroundPivot(Mathf.Atan2(to.y - from.y, to.x - from.x) * Mathf.Rad2Deg, from);
            Fill(new Rect(from.x, from.y - 1, Vector2.Distance(from, to), 2), color);
            GUI.matrix = previous;
        }
    }
}
