// cscript //nologo Test-ShowSynchronization.js patched/Oxipital.js
var fs = new ActiveXObject("Scripting.FileSystemObject");
var input = fs.OpenTextFile(WScript.Arguments(0), 1);
var source = input.ReadAll(); input.Close();
// JUCE's StringClass has indexOf/split/join, but no lastIndexOf.
String.prototype.lastIndexOf = undefined;
function check(ok, message) { if (!ok) throw new Error(message); }
function load(name) {
    var result = new RegExp("^function " + name + "\\([^\\r\\n]*\\)\\s*\\{[\\s\\S]*?^\\}", "m").exec(source);
    check(result != null, "Missing production function " + name); return result[0];
}
eval(load("isUnityEditing")); eval(load("processPresetPushes")); eval(load("handleShowSyncControl"));
eval(load("unityOSCName")); eval(load("updateUnityParam"));
eval(load("getKinectShowValue")); eval(load("pushKinectToUnity")); eval(load("pushAllToUnity"));
var now = 0, editing = false, messages = [], normalWrites = 0;
var presetPushAt = -1, presetFinalAt = -1;
var cachedZero = { set: function(value) {
    // Reproduce a local OSCQuery cache already at zero while Unity differs.
    if (value[0] != 0 || value[1] != 0 || value[2] != 0) normalWrites++;
}};
var unityBallet = { niceName: "Ballet", getChild: function(manager) {
    return { getChild: function(group) { return { getChild: function(path) { return cachedZero; } }; } };
}};
var util = { getTime: function() { return now; } };
var local = { parameters: { setup: {
    unityEditMode: { get: function() { return editing; } },
    applyCurrentValues: {}, presetApplyDuration: { get: function() { return 4; } }
}}, send: function(address, value) { messages.push([address, value]); } };
var forces = [1], orbGroups = [], forceGroupParameters = {}, orbGroupParameters = {};
function linkArrays() {}
function pushAllParameters(items, parameters, forceSend) {
    if (items.length) updateUnityParam("Force Groups", "Force Group 1", "Transform/position", [0,0,0], forceSend);
}
function parameter(target) { return { is: function(other) { return target === other; } }; }
updateUnityParam("Force Groups", "Force Group 1", "Transform/position", [0,0,0]);
check(normalWrites == 0 && messages.length == 0, "Did not reproduce unchanged-cache suppression");
check(handleShowSyncControl(parameter(local.parameters.setup.applyCurrentValues)), "Recall not handled");
now = .11; processPresetPushes();
check(messages.length == 1, "Missing initial preset resend");
check(messages[0][0] == "/Ballet/Force_Groups/Force_Group_1/Transform/position", "Wrong OSC address");
check(messages[0][1].join(",") == "0,0,0", "Zero vector was lost");
now = 4.21; processPresetPushes(); check(messages.length == 2, "Missing final preset resend");
processPresetPushes(); check(messages.length == 2, "Resend repeats continuously");
now = 5; handleShowSyncControl(parameter(local.parameters.setup.applyCurrentValues));
editing = true; handleShowSyncControl(parameter(local.parameters.setup.unityEditMode));
now = 10; processPresetPushes(); pushAllToUnity();
updateUnityParam("Force Groups", "Force Group 1", "Transform/position", [1,2,3]);
check(messages.length == 2 && normalWrites == 0, "Editing mode echoes values into Unity");
editing = false; handleShowSyncControl(parameter(local.parameters.setup.unityEditMode));
now = 10.21; processPresetPushes(); check(messages.length == 3, "Editing exit did not apply captured values");
check(source.indexOf("forceUnitySend") < 0, "A persistent resend flag remains in production");
var countBeforeNormal = messages.length;
updateUnityParam("Force Groups", "Force Group 1", "Transform/position", [1,2,3]);
check(normalWrites == 1 && messages.length == countBeforeNormal, "Forced sending leaked into regular updates");
cachedZero.name = "hdrMultiplier";
updateUnityParam("Orb Groups", "Orb Group 1", "OrbGroup/hDRMultiplier", 0, true);
check(messages[messages.length - 1][0] == "/Ballet/Orb_Groups/Orb_Group_1/OrbGroup/hdrMultiplier", "Unity field case was not preserved");
var savedBallet = unityBallet;
unityBallet = null;
var beforeMissingTree = messages.length;
pushAllToUnity();
check(messages.length == beforeMissingTree + 1, "Missing OSCQuery tree prevented preset position resend");
check(messages[messages.length - 1][1].join(",") == "0,0,0", "Missing-tree resend lost zero position");
unityBallet = { niceName: "Ballet", getChild: function() { return null; } };
updateUnityParam("Orb Groups", "Orb Group 1", "Transform/position", [0,0,0], true);
check(messages[messages.length - 1][0] == "/Ballet/Orb_Groups/Orb_Group_1/Transform/position", "Stale tree blocked orb position");
unityBallet = savedBallet;
WScript.Echo("SHOW_SYNC_BRIDGE_PASS: unchanged zero resend, canonical OSC path, initial/final snapshots, no continuous resend, editing isolation, exit sync.");
