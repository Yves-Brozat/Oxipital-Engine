// cscript //nologo Test-ConduiteInit.js <ConduiteInit.js>
var fso = new ActiveXObject("Scripting.FileSystemObject");
var file = fso.OpenTextFile(WScript.Arguments(0), 1);
var source = file.ReadAll(); file.Close();
var calls = [], current = "", next = 1, restartSameCue = true;
var keys = ["meduse", "chute", "cascade", "tornade", "tourbillon", "cercle"];
var names = ["Meduse", "Chute", "Cascade", "Tornade", "Tourbillon", "Cercle"];
var playing = {}, positions = {}, starts = {};
function node(name, containers, controls) {
    return {name:name, getContainers:function(){return containers || [];},
        getControllables:function(){return controls || [];}};
}
function check(ok,message){if(!ok)throw new Error(message);}
function start(key){playing[key]=true;positions[key]=0;starts[key]++;calls.push(key+":play");}
function sequence(key){return node(key, [], [
    {name:"stop",trigger:function(){playing[key]=false;calls.push(key+":stop");}},
    {name:"play",trigger:function(){start(key);}},
    {name:"isPlaying",get:function(){return playing[key];}}
]);}
var conductor=node("conductor",[],[
    {name:"nextCue",set:function(v){next=v;}},
    {name:"trigger",trigger:function(){
        check(next===1,"Init did not select the first cue before triggering");
        var wasFirst=current==="Meduse";current="Meduse";next=2;
        if(!wasFirst || restartSameCue)start("meduse");
    }}
]);
var sequences=[];
for(var i=0;i<keys.length;i++)sequences.push(sequence(keys[i]));
var root=node("root",[node("states",[node("conduite",[node("processors",[conductor])])]),node("sequences",sequences)]);
eval(source);
check(calls.length===0,"Loading the script starts playback");
function scenario(cue,legacy){
    current=cue;next=6;restartSameCue=!legacy;calls=[];
    for(var i=0;i<keys.length;i++){playing[keys[i]]=true;positions[keys[i]]=35;starts[keys[i]]=0;}
    trigger();
    check(current==="Meduse" && next===2,"Init must restart the show and leave Chute next");
    for(var j=0;j<keys.length;j++){
        var key=keys[j];
        check(calls[j]===key+":stop","All show timelines must stop before starting the first cue");
        if(key==="meduse")check(positions[key]===0,"Meduse did not restart at time zero");
        check(playing[key]===(key==="meduse"),"A previous timeline remains active: "+key);
        check(starts[key]===(key==="meduse" ? 1 : 0),"Wrong or duplicate sequence start: "+key);
    }
}
scenario("",false);
for(var j=0;j<names.length;j++){scenario(names[j],false);scenario(names[j],true);}
scenario("unknown",false);
scenario("Meduse",true);scenario("Meduse",true);
WScript.Echo("PASS: no playback on load; cold, every scene, repeated and legacy Init restart Meduse once at time zero; Chute next; other timelines stopped.");