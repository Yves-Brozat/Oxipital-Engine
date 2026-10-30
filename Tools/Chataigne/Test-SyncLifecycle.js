// Run with cscript //nologo Test-SyncLifecycle.js <Oxipital.js>
var fs = new ActiveXObject("Scripting.FileSystemObject");
var input = fs.OpenTextFile(WScript.Arguments(0), 1);
var source = input.ReadAll();
input.Close();
function loadFunction(name) {
    var match = new RegExp("^function " + name + "\\([^\\r\\n]*\\)\\s*\\{[\\s\\S]*?^\\}", "m").exec(source);
    if (!match) throw new Error("Missing " + name);
    return match[0];
}
eval(loadFunction("update"));
eval(loadFunction("moduleParameterChanged"));
eval(loadFunction("dataStructureEvent"));
eval(loadFunction("onConnected"));
eval(loadFunction("requestSync"));
var now, syncs, pushes, countsChanged, warnings;
var structureReceived, syncRequestTime, pushOnNextStructure, countResyncRequested;
var util = { getTime: function () { return now; } };
var script = { logWarning: function () { warnings++; } };
var local = { parameters: {
    syncData: { trigger: function () { syncs++; moduleParameterChanged(parameter(this, true)); } },
    isConnected: {}
} };
function parameter(target, value) {
    return { is: function (other) { return target === other; }, get: function () { return value; } };
}
function linkUnity() { return countsChanged; }
function pushAllToUnity() { pushes++; }
function reset() {
    now = 0; syncs = 0; pushes = 0; warnings = 0; countsChanged = false;
    structureReceived = false; syncRequestTime = -1;
    pushOnNextStructure = false; countResyncRequested = false;
}
function require(condition, message) { if (!condition) throw new Error(message); }
function settle() { now += 2; update(.01); }

reset();
onConnected();
dataStructureEvent();
update(.01);
settle();
require(syncs == 0 && pushes == 1, "Socket-before-structure caused a redundant sync or double push");

reset();
dataStructureEvent();
update(.01);
onConnected();
settle();
require(syncs == 0 && pushes == 1, "Structure-before-socket caused a redundant sync or double push");

reset();
countsChanged = true;
dataStructureEvent();
onConnected();
update(.01);
require(pushes == 0, "Pushed to groups before Unity created them");
settle();
require(syncs == 1 && pushes == 0, "Group count change did not request exactly one new tree");
countsChanged = false;
dataStructureEvent();
onConnected();
update(.01);
settle();
require(syncs == 1 && pushes == 1, "Group count sync looped or pushed twice");

// Existing connection drops without a new HTTP structure response.
moduleParameterChanged(parameter(local.parameters.isConnected, false));
onConnected();
settle();
require(syncs == 2, "Genuine reconnect did not refresh the tree");
dataStructureEvent();
update(.01);
settle();
require(syncs == 2 && pushes == 2, "Reconnect did not recover exactly once");

reset();
countsChanged = true;
dataStructureEvent();
settle();
dataStructureEvent();
update(.01);
settle();
require(syncs == 1 && pushes == 0 && warnings == 1, "Unapplied group counts caused a sync loop or stale push");
WScript.Echo("SYNC_LIFECYCLE_PASS: both callback orders, one push per tree, group creation, reconnect recovery and bounded retries.");
