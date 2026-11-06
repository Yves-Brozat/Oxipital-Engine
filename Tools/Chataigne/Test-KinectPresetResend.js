// cscript //nologo Test-KinectPresetResend.js <production Oxipital.js>
var fs = new ActiveXObject("Scripting.FileSystemObject");
var file = fs.OpenTextFile(WScript.Arguments(0), 1), source = file.ReadAll(); file.Close();
function check(ok, message) { if (!ok) throw new Error(message); }
function load(name) {
    var fn = new RegExp("^function " + name + "\\([^\\r\\n]*\\)\\s*\\{[\\s\\S]*?^\\}", "m").exec(source);
    check(fn != null, "Missing " + name); return fn[0];
}
eval(load("isUnityEditing")); eval(load("getKinectShowValue")); eval(load("pushKinectToUnity")); eval(load("pushAllToUnity"));
var editing = false, packets = [];
var values = { kinectEnabled: true, brushEnabled: true, sendForcesPosition: true,
    sendOrbsPosition: false, controlOrbRadius: false, forceGroupNumber: 1, orbGroupNumber: 1,
    orientationOffsetX: 0, orientationOffsetY: 0, orientationOffsetZ: 90,
    strength: 0, opticalFlowIntensity: 0 };
var root = { getChild: function(path) {
    var name = path.split("/").pop();
    return typeof values[name] == "undefined" ? null : { get: function() { return values[name]; } };
}};
// The saved OSCQuery cache agrees with Chataigne, but Unity has restarted
// with component=false and orb tracking=true. Normal setters do not send.
var unity = { remoteControlEnabled: false, controlOrbPosition: true, controlForcePosition: false };
var local = { parameters: { setup: { unityEditMode: { get: function() { return editing; } } } },
    send: function(path, value) { packets.push([path, value]); unity[path.split("/").pop()] = value; } };
var forces = [], orbGroups = [], forceGroupParameters = {}, orbGroupParameters = {};
function linkArrays() {}
function pushAllParameters(items, defs, force) { packets.push(["scene", force]); }
pushAllToUnity();
check(unity.remoteControlEnabled === true && unity.controlForcePosition === true && unity.controlOrbPosition === false,
    "Tourbillon's independent switches were not restored after Play restart");
check(packets[0][0].split("/").pop() == "remoteControlEnabled" && packets[0][1] === false, "Brush must release before scene settings");
check(packets[1][0] == "scene" && packets[2][0] == "scene", "Scene snapshot order changed");
check(packets[packets.length - 1][1] === true && packets[packets.length - 1][0].split("/").pop() == "remoteControlEnabled", "Component enabled before switches");
check(unity.strength === 0 && unity.intensity === 0 && unity.controlOrbRadius === false, "Zero or false was omitted");
check(unity.orientationOffset.join(",") == "0,0,90", "Orientation was sent as partial axes");
values.kinectEnabled = false; pushAllToUnity();
check(unity.remoteControlEnabled === false, "Disabled Kinect was not explicitly sent");
var count = packets.length; editing = true; pushAllToUnity(); pushKinectToUnity();
check(packets.length == count, "Unity authoring mode was overwritten");
WScript.Echo("KINECT_PRESET_RESEND_PASS: Play restart, independent switches, false/zero, vector offset, release/apply/enable order, editing isolation.");
