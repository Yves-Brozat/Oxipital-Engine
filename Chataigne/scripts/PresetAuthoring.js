// Generic Script consequences; compatible with the JUCE Javascript subset.
// Loading this script never captures or recalls values.
var operation = script.addStringParameter("Operation", "create, update or updateEntry", "update");
var entryKey = script.addStringParameter("Entry Key", "Stable scene key", "");
function child(parent, name) {
    if (parent == null) return null;
    var items = parent.getContainers();
    for (var i = 0; i < items.length; i++) if (lower(items[i].name) == lower(name)) return items[i];
    var controls = parent.getControllables();
    for (var j = 0; j < controls.length; j++) if (lower(controls[j].name) == lower(name)) return controls[j];
    return null;
}
function resolve(path) {
    var parts = path.split("/"), node = root;
    for (var i = 0; i < parts.length; i++) if (parts[i] != "") node = child(node, parts[i]);
    return node;
}
function control(name) { return resolve("/customVariables/presetTools/variables/" + name + "/" + name); }
function fail(message) {
    var status = control("status");
    if (status != null) status.set("Not saved: " + message);
    script.logWarning("Preset authoring: " + message);
    return false;
}
function lower(text) {
    var upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ", lowerCase = "abcdefghijklmnopqrstuvwxyz", result = "";
    for (var i = 0; i < text.length; i++) {
        var c = text.charAt(i), index = upper.indexOf(c);
        result += index < 0 ? c : lowerCase.charAt(index);
    }
    return result;
}
function trim(text) {
    var start = 0, end = text.length;
    while (start < end && text.charCodeAt(start) <= 32) start++;
    while (end > start && text.charCodeAt(end - 1) <= 32) end--;
    return text.substring(start, end);
}
function shortNameFor(text) {
    var valid = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_", result = "";
    for (var i = 0; i < text.length; i++) if (valid.indexOf(text.charAt(i)) >= 0) result += text.charAt(i);
    return lower(result.charAt(0)) + result.substring(1, result.length);
}
function parameter(address, value) { return {controlAddress: address, value: value}; }
function consequence(type, params, module) {
    return {niceName: type, type: "Consequence", commandModule: module,
        commandPath: "", commandType: type, command: {parameters: params, paramLinks: {}}};
}
function triggerConsequence(target) { return consequence("Trigger a Control", [parameter("/target", target)], "generic"); }
function scriptAction(label, key, shortName) {
    return {niceName: label, shortName: shortName, type: "Action", consequences: {items: [{
        niceName: "Update three presets", type: "Consequence", commandModule: "generic", commandPath: "", commandType: "Script",
        command: {script: {parameters: [parameter("/filePath", "scripts/PresetAuthoring.js")], scriptParams: {
            parameters: [parameter("/operation", "updateEntry"), parameter("/entryKey", key)]}}}
    }]}};
}
function kinectModes(preset) {
    var values = child(preset, "values");
    if (values == null) return null;
    var containers = values.getContainers(), modes = [];
    for (var i = 0; i < containers.length; i++) {
        // Bank, color and physical MIDI input states must never be recalled.
        if (containers[i].name.indexOf("en16") != 0) continue;
        var mode = child(containers[i], "mode");
        if (mode == null) return null;
        modes.push(mode);
    }
    return modes;
}
function protectModes(modes) { for (var i = 0; i < modes.length; i++) modes[i].set("None"); }
function preflightGroups(names) {
    if (names == null) names = ["force1", "orb1", "kinect"];
    var groups = [];
    for (var i = 0; i < names.length; i++) {
        var group = resolve("/customVariables/" + names[i]);
        if (group == null || child(group, "presets") == null) { fail("Missing group " + names[i]); return null; }
        var progress = child(group, "interpolationProgress");
        if (progress != null && progress.get() > 0) { fail("Wait until the transition has finished."); return null; }
        groups.push(group);
    }
    return groups;
}
function updateEntry(entry) {
    if (entry == null || entry.targets == null || entry.targets.length != 3) return fail("Choose a preset to update.");
    var second = entry.targets[0].indexOf("/customVariables/force2/presets/") == 0;
    var groupNames = [second ? "force2" : "force1", second ? "orb2" : "orb1", "kinect"];
    if (preflightGroups(groupNames) == null) return false;
    var presets = [], updates = [];
    // Resolve all three targets before changing any stored values.
    for (var i = 0; i < 3; i++) {
        if (entry.targets[i].indexOf("/customVariables/" + groupNames[i] + "/presets/") != 0) return fail("Invalid group target.");
        var preset = resolve(entry.targets[i]);
        if (preset == null || child(preset, "update") == null) return fail("Missing target: " + entry.targets[i]);
        presets.push(preset); updates.push(child(preset, "update"));
    }
    var modes = kinectModes(presets[2]);
    if (modes == null) return fail("Missing Kinect exclusion modes.");
    for (var j = 0; j < 3; j++) updates[j].trigger();
    protectModes(modes);
    control("selectedPreset").set(entry.label);
    control("status").set("Updated: " + entry.label + " (" + groupNames[0] + " / " + groupNames[1] + " / Kinect). Session save requested.");
    return true;
}
function rollback(created) {
    for (var i = created.length - 1; i >= 0; i--) created[i].manager.removeItem(created[i].item);
    return false;
}
function createEntry() {
    var name = trim(control("newPresetName").get()), shortName = shortNameFor(name);
    if (name == "" || shortName == "") return fail("Enter a name with at least one letter A-Z or digit.");
    var groups = preflightGroups();
    if (groups == null) return false;
    var loadManager = resolve("/states/presets/processors"), saveManager = resolve("/states/savePresets/processors");
    if (loadManager == null || saveManager == null) return fail("Missing preset action states.");
    var selector = control("selectedPreset"), options = selector.getAllOptions();
    for (var e = 0; e < options.length; e++) if (lower(options[e].key) == lower(name)) return fail("This name already exists. Use Update.");
    var managers = [];
    for (var i = 0; i < groups.length; i++) {
        var manager = child(groups[i], "presets"), existing = manager.getItems();
        managers.push(manager);
        for (var n = 0; n < existing.length; n++) {
            if (lower(existing[n].name) == lower(shortName) || lower(existing[n].niceName) == lower(name))
                return fail("A preset with this name/address already exists. Use Update.");
        }
    }
    if (child(loadManager, shortName) != null || child(saveManager, "update" + shortName) != null)
        return fail("A scene action already uses this address. Choose another name.");
    var entry = {key: shortName, label: name, targets: []}, created = [], groupNames = ["force1", "orb1", "kinect"];
    for (var g = 0; g < 3; g++) {
        var added = managers[g].addItem("MorphTarget", {niceName: name, shortName: shortName});
        if (added == null) { fail("Could not create preset in " + groupNames[g]); return rollback(created); }
        created.push({manager: managers[g], item: added});
        if (added.name != shortName || child(added, "update") == null) { fail("Unexpected preset structure."); return rollback(created); }
        child(added, "update").trigger();
        entry.targets.push("/customVariables/" + groupNames[g] + "/presets/" + shortName);
    }
    var modes = kinectModes(created[2].item);
    if (modes == null) { fail("Missing Kinect exclusion modes."); return rollback(created); }
    protectModes(modes);
    var recalls = [];
    // Sessions with the crossfade release presets also give newly created
    // Orb1 scenes the same outgoing fade as the installed show actions.
    if (resolve("/customVariables/orb2/presets/transitionRelease") != null &&
        resolve("/customVariables/force2/presets/transitionRelease") != null) {
        var timelines = ["meduse", "chute", "cascade", "tornade", "tourbillon", "cercle"];
        for (var q = 0; q < timelines.length; q++) recalls.push(triggerConsequence("/sequences/" + timelines[q] + "/stop"));
        var cancelGroups = ["orb1", "orb2", "force1", "force2", "kinect"];
        for (var c = 0; c < cancelGroups.length; c++) recalls.push(consequence("Kill Go to preset", [
            parameter("/targetGroup", "/" + cancelGroups[c])], "customVariables"));
        var releaseGroups = ["orb2", "force2"];
        for (var r = 0; r < releaseGroups.length; r++) recalls.push(consequence("Go to preset", [
            parameter("/targetPreset", "/" + releaseGroups[r] + "/presets/transitionRelease"),
            {controlAddress: "/interpolationTime", value: 10, enabled: true}], "customVariables"));
    }
    for (var t = 0; t < 3; t++) recalls.push(consequence("Go to preset", [
        parameter("/targetPreset", entry.targets[t].substring(16, entry.targets[t].length)),
        {controlAddress: "/interpolationTime", value: 4, enabled: true}], "customVariables"));
    recalls.push(consequence("Set Parameter Value", [parameter("/target", "/modules/oxipital/parameters/setup/presetApplyDuration"),
        parameter("/component", "All"), parameter("/operator", "Equals"), parameter("/value", 4)], "generic"));
    recalls.push(triggerConsequence("/modules/oxipital/parameters/setup/applyCurrentValues"));
    recalls.push(consequence("Set Parameter Value", [parameter("/target", "/customVariables/presetTools/variables/selectedPreset/selectedPreset"),
        parameter("/component", "All"), parameter("/operator", "Equals"), parameter("/value", name)], "generic"));
    var recall = loadManager.addItem("Action", {niceName: name, shortName: shortName, type: "Action", consequences: {items: recalls}});
    if (recall == null) { fail("Could not create recall action."); return rollback(created); }
    created.push({manager: loadManager, item: recall});
    if (recall.name != shortName) { fail("Recall action address was renamed."); return rollback(created); }
    var save = saveManager.addItem("Action", scriptAction("Update " + name, entry.key, "update" + shortName));
    if (save == null) { fail("Could not create update action."); return rollback(created); }
    created.push({manager: saveManager, item: save});
    if (save.name != "update" + shortName) { fail("Update action address was renamed."); return rollback(created); }
    selector.addOption(name, entry); selector.set(name);
    control("status").set("Created: " + name + " (3 presets + recall/update actions). Session save requested.");
    return true;
}
function trigger() {
    if (control("newPresetName") == null || control("selectedPreset") == null || control("status") == null) { fail("Missing dashboard controls."); return; }
    var save = resolve("/states/savePresets/processors/saveSession/trigger");
    if (save == null) { fail("Missing Save Session action."); return; }
    var success = false;
    if (operation.get() == "create") success = createEntry();
    else if (operation.get() == "update" || operation.get() == "updateEntry") {
        var entry = control("selectedPreset").get();
        if (operation.get() == "updateEntry") {
            entry = null;
            var options = control("selectedPreset").getAllOptions();
            for (var i = 0; i < options.length; i++) if (options[i].value.key == entryKey.get()) entry = options[i].value;
        }
        success = updateEntry(entry);
    } else { fail("Unknown operation."); return; }
    if (success) save.trigger();
}
