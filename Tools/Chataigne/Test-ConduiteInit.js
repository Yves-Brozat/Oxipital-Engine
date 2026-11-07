// Run with Windows Script Host: cscript //nologo Test-ConduiteInit.js <script>
var fso = new ActiveXObject("Scripting.FileSystemObject");
var file = fso.OpenTextFile(WScript.Arguments(0), 1);
var source = file.ReadAll(); file.Close();
var calls = [], current = "", next = 1;
function node(name, containers, controls) {
    return {name: name, getContainers: function () { return containers || []; },
        getControllables: function () { return controls || []; }};
}
function button(name, label) { return {name:name, trigger:function(){calls.push(label);}}; }
var conductor = node("conductor", [], [
    {name:"currentCueName", get:function(){return current;}},
    {name:"nextCue", set:function(v){next=v;}}, button("trigger", "first")]);
var keys = ["meduse", "chute", "cascade", "tornade", "tourbillon", "cercle"];
var names = ["Meduse", "Chute", "Cascade", "Tornade", "Tourbillon", "Cercle"];
var sequences=[];
for(var i=0;i<keys.length;i++) sequences.push(node(keys[i], [], [button("stop",keys[i]+":stop"),button("play",keys[i]+":play")]));
var root=node("root",[node("states",[node("conduite",[node("processors",[conductor])])]),node("sequences",sequences)]);
var script={logWarning:function(message){calls.push("warning");}};
function check(ok,message){if(!ok)throw new Error(message);}
eval(source);
check(calls.length===0,"Loading starts playback");
next=4; trigger(); check(next===1 && calls.join(",")==="first","Cold Init must start Meduse");
for(var j=0;j<names.length;j++){
    calls=[];current=names[j];next=j+2;trigger();
    check(calls.join(",")===keys[j]+":stop,"+keys[j]+":play","Wrong restart: "+names[j]);
    check(next===j+2,"Init advances cue");
    calls=[];trigger();check(calls.length===2,"Repeated Init must restart again");
}
current="unknown";calls=[];trigger();check(calls.join(",")==="warning","Unknown cue must not restart another scene");
WScript.Echo("PASS: no playback on load, cold Init, all six restarts, repeated Init and unchanged Next index.");
