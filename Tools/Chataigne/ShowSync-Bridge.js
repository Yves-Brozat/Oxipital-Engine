// Helpers installed into the existing Oxipital bridge by Add-ShowSynchronization.ps1.
function isUnityEditing() {
    return local.parameters.setup && local.parameters.setup.unityEditMode && local.parameters.setup.unityEditMode.get();
}

function processPresetPushes() {
    if (isUnityEditing()) return;
    var now = util.getTime();
    if (presetPushAt >= 0 && now >= presetPushAt) {
        presetPushAt = -1;
        pushAllToUnity();
    }
    if (presetFinalAt >= 0 && now >= presetFinalAt) {
        presetFinalAt = -1;
        pushAllToUnity();
    }
}

function handleShowSyncControl(param) {
    var setup = local.parameters.setup;
    if (!setup) return false;
    if (setup.applyCurrentValues && param.is(setup.applyCurrentValues)) {
        if (!isUnityEditing()) {
            var duration = setup.presetApplyDuration ? setup.presetApplyDuration.get() : 0;
            presetPushAt = util.getTime() + 0.1;
            presetFinalAt = util.getTime() + Math.max(0, duration) + 0.2;
        }
        return true;
    }
    if (setup.unityEditMode && param.is(setup.unityEditMode)) {
        presetPushAt = isUnityEditing() ? -1 : util.getTime() + 0.2;
        presetFinalAt = -1;
        return true;
    }
    return false;
}

function unityOSCName(name) {
    return name.split(" ").join("_").split("(").join("").split(")").join("");
}

function updateUnityParam(managerName, itemName, paramPath, value, forceSend) {
    if (value == null || isUnityEditing()) return;
    // Preset transforms must still reach Unity when its OSCQuery tree is
    // missing or stale. These two addresses are fixed by the bridge schema.
    if (forceSend && (paramPath == "Transform/position" || paramPath == "Transform/rotation")) {
        var balletName = unityBallet == null ? "Ballet" : unityBallet.niceName;
        local.send("/" + unityOSCName(balletName) + "/" + unityOSCName(managerName) +
            "/" + unityOSCName(itemName) + "/" + paramPath, value);
        return;
    }
    if (unityBallet == null) return;
    var manager = unityBallet.getChild(managerName);
    if (manager == null) return;
    var item = manager.getChild(itemName);
    if (item == null) return;
    // Resolve one segment at a time. Native compound-address lookup drops
    // the first segment without / and resolves the leaf case-sensitively;
    // single-name getChild preserves case-insensitive field matching.
    var resolvedParts = paramPath.split("/");
    var param = item;
    for (var p = 0; p < resolvedParts.length; p++) {
        param = param.getChild(resolvedParts[p]);
        if (param == null) return;
    }
    if (forceSend) {
        // The resolved OSCQuery control retains Unity's exact field spelling
        // (e.g. hdrMultiplier vs the bridge UI's hDRMultiplier).
        var parts = paramPath.split("/");
        if (param.name) parts[parts.length - 1] = param.name;
        var oscPath = parts.join("/");
        // OSCQuery's explicit send bypasses unchanged-value suppression in
        // Chataigne's local parameter cache. Arrays are OSC argument lists.
        local.send("/" + unityOSCName(unityBallet.niceName) + "/" + unityOSCName(managerName) +
            "/" + unityOSCName(itemName) + "/" + oscPath, value);
    } else param.set(value);
}

function findShowContainer(parent, name) {
    if (parent == null) return null;
    var children = parent.getContainers();
    if (children == null) return null;
    var wanted = name.toLowerCase();
    for (var i = 0; i < children.length; i++) {
        if (children[i].name.toLowerCase() == wanted) return children[i];
    }
    return null;
}

function getShowVariableValue(group, name) {
    if (typeof root == "undefined") return null;
    // Enumerate optional containers instead of getChild: a missing variable
    // must not print "Child not found" on every 10 Hz control poll. Native
    // getChild also requires a leading / for any multi-segment address.
    var customVariables = findShowContainer(root, "customVariables");
    var showGroup = findShowContainer(customVariables, group);
    var variables = findShowContainer(showGroup, "variables");
    var variable = findShowContainer(variables, name);
    if (variable == null && name == "twoHandForces") variable = findShowContainer(variables, "twoHandsForces");
    if (variable == null && name == "singleHandAtATime") variable = findShowContainer(variables, "singleHandOnly");
    if (variable == null) return null;
    // A Custom Variable's container short name is stable, but Chataigne
    // regenerates its value's short name from the displayed label on load.
    var controls = variable.getControllables();
    for (var i = 0; i < controls.length; i++) {
        if (controls[i].name == name || controls[i].niceName == variable.niceName)
            return controls[i].get();
    }
    return null;
}

function getKinectShowValue(name) {
    return getShowVariableValue("kinect", name);
}

function processTwoHandControls() {
    if (isUnityEditing() || util.getTime() < nextTwoHandControlPoll) return;
    nextTwoHandControlPoll = util.getTime() + 0.1;
    var names = ["twoHandForces", "singleHandAtATime"];
    for (var i = 0; i < names.length; i++) {
        var value = getKinectShowValue(names[i]);
        if (value != null && value != lastTwoHandControls[i]) {
            local.send("/Ballet/Optical_Flow/TwoHandForceBrush/" + names[i], value);
            lastTwoHandControls[i] = value;
        }
    }
}

function pushCameraToUnity() {
    if (isUnityEditing()) return;
    var fov = getShowVariableValue("camera", "fieldofview");
    var offset = getShowVariableValue("camera", "zOffset");
    // Camera values need the same unchanged-cache bypass as group values.
    // A restarted Unity otherwise keeps its prefab FoV (75) while the show
    // still displays the preset's FoV (25).
    if (fov != null && fov > 0 && fov < 180)
        local.send("/Cameras/Camera_Controller/CameraController/fov", fov);
    if (offset != null && offset >= 0)
        local.send("/Cameras/Camera_Controller/CameraController/followZOffset", offset);
}

function pushKinectToUnity() {
    if (isUnityEditing()) return;
    var prefix = "/Ballet/Optical_Flow/";
    var fields = [
        ["brushEnabled", "brushEnabled"], ["sendForcesPosition", "controlForcePosition"],
        ["sendOrbsPosition", "controlOrbPosition"], ["controlIntensityRadius", "controlBrushParameters"],
        ["controlOrientation", "controlForceOrientation"], ["controlOrbRadius", "controlOrbRadius"],
        ["controlOrbOrientation", "controlOrbOrientation"], ["strength", "strength"],
        ["radiusMultiplier", "radiusMultiplier"], ["sizeMultiplier", "sizeMultiplier"],
        ["orbRadiusMultiplier", "orbRadiusMultiplier"], ["minimumRadius", "minimumRadius"],
        ["maximumRadius", "maximumRadius"], ["smoothingSeconds", "smoothingSeconds"],
        ["activationFadeSeconds", "activationFadeSeconds"], ["forceGroupNumber", "forceGroupNumber"],
        ["orbGroupNumber", "orbGroupNumber"], ["unityBrushIndex", "selectedBrush"],
        ["interactionDepth", "interactionDepth"], ["useTargetDepth", "useTargetDepth"],
        ["minimumAxisDistance", "minimumAxisDistance"], ["showMonitor", "showMonitor"],
        ["showHandOverlay", "showHandOverlay"], ["invertGestureIntensity", "invertGestureIntensity"],
        ["twoHandOrbs", "twoHandOrbs"], ["monitorScale", "monitorScale"],
        ["twoHandForces", "twoHandForces"], ["singleHandAtATime", "singleHandAtATime"]
    ];
    for (var i = 0; i < fields.length; i++) {
        var value = getKinectShowValue(fields[i][0]);
        if (value != null) local.send(prefix + "TwoHandForceBrush/" + fields[i][1], value);
    }
    var x = getKinectShowValue("orientationOffsetX"), y = getKinectShowValue("orientationOffsetY"), z = getKinectShowValue("orientationOffsetZ");
    if (x != null && y != null && z != null) local.send(prefix + "TwoHandForceBrush/orientationOffset", [x, y, z]);
    var flow = [["debugOverlayOpacity", "OpticalFlowDebugView/overlayOpacity"],
        ["opticalFlowIntensity", "OpticalFlowManager/intensity"], ["opticalFlowStrength", "OpticalFlowManager/strength"],
        ["windDrag", "OpticalFlowManager/windDrag"], ["windBlend", "OpticalFlowManager/windBlend"],
        ["flowOutputGain", "OpticalFlowProcessor/outputGain"],
        ["minimumHandConfidence", "OpticalFlowAzureKinectInput/minimumHandConfidence"],
        ["trackingTimeout", "OpticalFlowAzureKinectInput/trackingTimeout"],
        ["maximumHandDepth", "OpticalFlowAzureKinectInput/maximumHandDepth"],
        ["filterHandDepth", "OpticalFlowAzureKinectInput/filterHandDepth"]];
    for (var j = 0; j < flow.length; j++) {
        var flowValue = getKinectShowValue(flow[j][0]);
        if (flowValue != null) local.send(prefix + flow[j][1], flowValue);
    }
    // Enable only after the independent switches and target group numbers.
    var enabled = getKinectShowValue("kinectEnabled");
    if (enabled != null) local.send(prefix + "TwoHandForceBrush/remoteControlEnabled", enabled);
}

function pushAllToUnity() {
    if (isUnityEditing()) return;
    // OnDisable restores owned group settings. Release before applying the
    // scene snapshot so it cannot overwrite the newly recalled preset.
    if (getKinectShowValue("kinectEnabled") != null)
        local.send("/Ballet/Optical_Flow/TwoHandForceBrush/remoteControlEnabled", false);
    linkArrays();
    pushAllParameters(forces, forceGroupParameters, true);
    pushAllParameters(orbGroups, orbGroupParameters, true);
    pushCameraToUnity();
    pushKinectToUnity();
}
