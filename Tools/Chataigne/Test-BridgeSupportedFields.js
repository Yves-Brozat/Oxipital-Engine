// cscript //nologo Test-BridgeSupportedFields.js <Oxipital.js>
var fs = new ActiveXObject("Scripting.FileSystemObject");
var f = fs.OpenTextFile(WScript.Arguments(0), 1), source = f.ReadAll(); f.Close();
function check(ok, message) { if (!ok) throw new Error(message); }
function load(name) { return new RegExp("^function " + name + "\\([^\\r\\n]*\\)\\s*\\{[\\s\\S]*?^\\}", "m").exec(source)[0]; }
function schema(name) { return new RegExp("var " + name + " = \\{[\\s\\S]*?^\\};", "m").exec(source)[0].replace(/,\s*([}\]])/g,"$1"); }
eval(schema("danceGroupParameters")); eval(schema("forceGroupParameters")); eval(schema("orbGroupParameters"));
eval(load("updateParam")); eval(load("findControllable"));
var writes = [], reads = 0;
var numMacrosParam = {get:function(){return 0;}};
function updateUnityParam(manager, item, path, value) { writes.push([path,value]); }
var forceItem = {niceName:"Force Group 1", getParent:function(){return {niceName:"Force Groups"};},getChild:child};
var orbItem = {niceName:"Orb Group 1", getParent:function(){return {niceName:"Orb Groups"};},getChild:child};
function child(name) { reads++; return {name:name.charAt(0).toLowerCase()+name.substring(1).split(" ").join(""),getChild:child,getControllables:function(){return [{name:"baseValue",get:function(){return [1,1,1];}}];}}; }
updateParam(0,"Dancer","Emitter Scale",null,forceGroupParameters,[forceItem],true);
updateParam(0,"Turbulence Curl","Curl Drag",null,forceGroupParameters,[forceItem],true);
check(reads == 0 && writes.length == 0, "Unsupported force fields reached Unity lookup");
updateParam(0,"Dancer","Emitter Scale",null,orbGroupParameters,[orbItem],true);
check(writes.length == 1 && writes[0][0] == "OrbGroup/emitterScale", "Orb emitter scale was lost");
updateParam(0,"Linear","Linear Direction",null,forceGroupParameters,[forceItem],true);
check(writes.length == 2 && writes[1][0] == "StandardForceGroup/linearDirection", "Force direction was incorrectly skipped");
WScript.Echo("SUPPORTED_BRIDGE_FIELDS_PASS: unsupported force fields skipped, orb scale and force direction preserved.");
