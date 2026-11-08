// cscript //nologo Test-EN16Banks.js <EN16Banks.js>
var fso=new ActiveXObject("Scripting.FileSystemObject"),file=fso.OpenTextFile(WScript.Arguments(0),1);
var source=file.ReadAll();file.Close();
var bank=0,operationValue="apply",compat=false,calls=[],held={};
function node(name,containers,controls){return {name:name,getContainers:function(){return containers||[];},getControllables:function(){return controls||[];}};}
function value(name,get,set){return {name:name,get:get,set:set};}
function heldVariable(name){held[name]=127;return node(name,[],[value(name,function(){return held[name];},function(v){held[name]=v;})]);}
var kinect=[node("en16KinectBank",[],[value("en16KinectBank",function(){return compat;},function(v){compat=v;})])];
var banks=[node("bank",[],[value("bank",function(){return bank;},function(v){bank=v;})])];
for(var i=1;i<=16;i++){kinect.push(heldVariable("en16AbyssesButton"+i));kinect.push(heldVariable("en16KinectButton"+i));banks.push(heldVariable("fluidButton"+i));}
function action(name){return node(name,[],[{name:"trigger",trigger:function(){calls.push(name);}}]);}
var root=node("root",[
 node("customVariables",[node("kinect",[node("variables",kinect)]),node("en16Banks",[node("variables",banks)])]),
 node("states",[node("dashboard",[node("processors",[action("showEN16Abysses"),action("showEN16Kinect"),action("showEN16Fluides")])])])
]);
var script={addStringParameter:function(){return {get:function(){return operationValue;}};}};
function check(ok,message){if(!ok)throw new Error(message);}
eval(source);check(calls.length===0,"Loading changes dashboards");
var names=["showEN16Abysses","showEN16Kinect","showEN16Fluides"];
for(var run=0;run<9;run++){
 var previous=bank;operationValue="cycle";trigger();check(bank===(previous+1)%3,"Wrong cycle order");
 for(var key in held)held[key]=127;
 operationValue="apply";calls=[];trigger();
 check(calls.join(",")===names[bank],"Wrong dashboard for bank "+bank);
 check(compat===(bank===1),"Compatibility Boolean disagrees with bank");
 for(var address in held)check(held[address]===0,"Held input survived bank transition: "+address);
}
WScript.Echo("PASS: three complete cycles, correct dashboards/Kinect compatibility, all 48 inputs cleared, no playback or UI change on script load.");
