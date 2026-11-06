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
    var param = item.getChild(paramPath);
    if (param == null) return;
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

function getKinectShowValue(name) {
    if (typeof root == "undefined") return null;
    var control = root.getChild("customVariables/kinect/variables/" + name + "/" + name);
    return control == null ? null : control.get();
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
        ["twoHandOrbs", "twoHandOrbs"], ["monitorScale", "monitorScale"]
    ];
    for (var i = 0; i < fields.length; i++) {
        var value = getKinectShowValue(fields[i][0]);
        if (value != null) local.send(prefix + "TwoHandForceBrush/" + fields[i][1], value);
    }
    var x = getKinectShowValue("orientationOffsetX"), y = getKinectShowValue("orientationOffsetY"), z = getKinectShowValue("orientationOffsetZ");
    if (x != null && y != null && z != null) local.send(prefix + "TwoHandForceBrush/orientationOffset", [x, y, z]);
    var flow = [["debugOverlayOpacity", "OpticalFlowDebugView/overlayOpacity"],
        ["opticalFlowIntensity", "OpticalFlowManager/intensity"], ["opticalFlowStrength", "OpticalFlowManager/strength"]];
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
    pushKinectToUnity();
}
