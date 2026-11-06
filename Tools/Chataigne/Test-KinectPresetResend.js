// cscript //nologo Test-KinectPresetResend.js <production Oxipital.js>
var fs = new ActiveXObject("Scripting.FileSystemObject");
var file = fs.OpenTextFile(WScript.Arguments(0), 1), source = file.ReadAll(); file.Close();
function check(ok, message) { if (!ok) throw new Error(message); }
function load(name) {
    var fn = new RegExp("^function " + name + "\\([^\\r\\n]*\\)\\s*\\{[\\s\\S]*?^\\}", "m").exec(source);
    check(fn != null, "Missing " + name); return fn[0];
}
eval(load("isUnityEditing"));
if (source.indexOf("function findShowContainer(") >= 0) eval(load("findShowContainer"));
eval(load("getShowVariableValue")); eval(load("getKinectShowValue")); eval(load("pushCameraToUnity")); eval(load("pushKinectToUnity")); eval(load("pushAllToUnity")); eval(load("processTwoHandControls"));
var editing = false, packets = [];
var values = { kinectEnabled: true, brushEnabled: true, sendForcesPosition: true,
    sendOrbsPosition: false, controlOrbRadius: false, forceGroupNumber: 1, orbGroupNumber: 1,
    orientationOffsetX: 0, orientationOffsetY: 0, orientationOffsetZ: 90,
    strength: 0, opticalFlowIntensity: 0, twoHandForces: true, singleHandAtATime: true,
    maximumHandDepth: 2, minimumHandConfidence: 2, trackingTimeout: .3,
    filterHandDepth: false, windDrag: 6.89, windBlend: .437, flowOutputGain: 1.5 };
var failedLookups = 0;
function variableNode(name) {
    var nativeName = name == "twoHandForces" ? "twoHandsForces" : name == "singleHandAtATime" ? "singleHandOnly" : name;
    var label = name == "twoHandForces" ? "Two Hands Forces" : name == "singleHandAtATime" ? "Single Hand Only" : name;
    return { name:nativeName, niceName: label, getControllables: function() { return [
        {name:"viewUIPosition",niceName:"Position",get:function(){return [20,20];}},
        {name:nativeName,niceName:label,get:function(){return values[name];}}
    ]; } };
}
function variableNodes(group) {
    var result = [];
    for (var name in values) {
        var isCamera = name == "fieldofview" || name == "zOffset";
        if (isCamera == (group == "camera")) result.push(variableNode(name));
    }
    return result;
}
function groupNode(name) { return {name:name, getContainers:function(){return [
    {name:"variables",getContainers:function(){return variableNodes(name);}}
];}}; }
var root = {
    // Native getChild logs and returns null for paths without the initial /.
    getChild:function(path){failedLookups++;return null;},
    getContainers:function(){return [{name:"customVariables",getContainers:function(){return [groupNode("kinect"),groupNode("camera")];}}];}
};
var now = 0, nextTwoHandControlPoll = 0, lastTwoHandControls = [null, null];
var util = {getTime:function(){return now;}};
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
check(unity.twoHandForces === true && unity.singleHandAtATime === true, "Two-hand force settings were omitted from preset resend");
check(unity.maximumHandDepth === 2 && unity.minimumHandConfidence === 2 && unity.trackingTimeout === .3 && unity.filterHandDepth === false, "Sensor tuning was omitted from preset resend");
check(unity.windDrag === 6.89 && unity.windBlend === .437 && unity.outputGain === 1.5, "Physical flow controls were omitted from preset resend");
values.kinectEnabled = false; pushAllToUnity();
check(unity.remoteControlEnabled === false, "Disabled Kinect was not explicitly sent");
values.fieldofview = 25; values.zOffset = 5;
unity.fov = 75; unity.followZOffset = 1.5;
pushCameraToUnity();
check(unity.fov == 25 && unity.followZOffset == 5, "Camera remained at the restarted Unity defaults");
processTwoHandControls();
var beforeIdle = packets.length;
now = .2; processTwoHandControls();
check(packets.length == beforeIdle, "Idle control polling sends continuous packets");
values.twoHandForces = false; now = .4; processTwoHandControls();
check(unity.twoHandForces === false && packets.length == beforeIdle + 1, "Native-named button change did not reach Unity");
var count = packets.length; editing = true; pushAllToUnity(); pushKinectToUnity();
check(packets.length == count, "Unity authoring mode was overwritten");
editing = false;
check(getKinectShowValue("missingOptionalVariable") == null, "Missing variable should be optional");
check(getShowVariableValue("missingGroup", "missingVariable") == null, "Missing group should be optional");
check(failedLookups == 0, "Optional variable polling invokes noisy failed getChild lookups");
WScript.Echo("KINECT_PRESET_RESEND_PASS: Play restart, independent switches, false/zero, vector offset, release/apply/enable order, editing isolation.");
