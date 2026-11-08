// cscript //nologo Test-EN16Dashboard.js <EN16Dashboard.js>
var fso=new ActiveXObject("Scripting.FileSystemObject"),file=fso.OpenTextFile(WScript.Arguments(0),1);
var source=file.ReadAll();file.Close();
var page=0,bank=false,calls=[];
function node(name,containers,controls){return {name:name,getContainers:function(){return containers||[];},getControllables:function(){return controls||[];}};}
function value(name,get){return {name:name,get:get};}
function action(name){return node(name,[],[{name:"trigger",trigger:function(){calls.push(name);}}]);}
var root=node("root",[
    node("modules",[node("en16",[node("values",[],[value("_16_CC115",function(){return page;})])])]),
    node("customVariables",[node("kinect",[node("variables",[node("en16KinectBank",[],[value("en16KinectBank",function(){return bank;})])])])]),
    node("states",[node("dashboard",[node("processors",[action("showEN16Abysses"),action("showEN16Kinect"),action("showEN16Fluides")])])])
]);
function check(ok,message){if(!ok)throw new Error(message);}
eval(source);check(calls.length===0,"Script loading changes the UI");
var cases=[[0,false,"showEN16Abysses"],[0,true,"showEN16Kinect"],[1,true,"showEN16Fluides"],[1,false,"showEN16Fluides"],[0,false,"showEN16Abysses"],[0,true,"showEN16Kinect"]];
for(var i=0;i<cases.length;i++){page=cases[i][0];bank=cases[i][1];calls=[];trigger();check(calls.join(",")===cases[i][2],"Wrong page/bank selection "+i);}
for(var p=2;p<4;p++){page=p;calls=[];trigger();check(calls.length===0,"Unconfigured hardware page steals focus");}
WScript.Echo("PASS: native page 2 selects Fluides regardless of Kinect bank; page 1 restores Abysses/Kinect; other pages ignored; no action on load.");
