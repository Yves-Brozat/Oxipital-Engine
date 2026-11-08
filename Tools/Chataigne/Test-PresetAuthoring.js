// cscript //nologo Test-PresetAuthoring.js <PresetAuthoring.js> <prepared.noisette>
// Model the native manager, enum (get returns data) and preset Update contracts.
function read(path) { var s = new ActiveXObject("ADODB.Stream"); s.Type = 2; s.Charset = "utf-8"; s.Open(); s.LoadFromFile(path); var v = s.ReadText(); s.Close(); return v; }
function check(ok, message) { if (!ok) throw new Error(message); }
var document = eval("(" + read(WScript.Arguments(1)) + ")");
var source = read(WScript.Arguments(0));
check(!/\b(try|catch|throw)\b|JSON\.parse|\.replace\(|\.toLowerCase\(/.test(source), "Unsupported JUCE syntax/API");
function clone(x) { if (x == null || typeof x != "object") return x; var y = x instanceof Array ? [] : {}; for (var k in x) y[k] = clone(x[k]); return y; }
function same(a,b) { if (typeof a != typeof b) return false; if (a == null || typeof a != "object") return a === b; for (var k in a) if (!same(a[k],b[k])) return false; for (var j in b) if (!(j in a)) return false; return true; }
function nativeShort(name) { var words=name.split(" "), result=""; for(var i=0;i<words.length;i++){var w=words[i]; if(!w)continue; result+=i ? w.charAt(0).toUpperCase()+w.substr(1) : w.charAt(0).toLowerCase()+w.substr(1);}return result.replace(/[^a-zA-Z0-9_]/g,""); }
function Node(name) { this.name=name; this.niceName=name; this.nodes=[]; this.controls=[]; }
Node.prototype.getContainers=function(){return this.nodes;};
Node.prototype.getControllables=function(){return this.controls;};
Node.prototype.add=function(node){this.nodes.push(node);return node;};
function Value(name,value,options){this.name=name;this.value=clone(value);this.options=clone(options);}
Value.prototype.get=function(){return this.options ? this.options[this.value] : this.value;};
Value.prototype.getKey=function(){return this.value;};
Value.prototype.set=function(v){this.value=clone(v);};
Value.prototype.addOption=function(k,v){check(!(k in this.options),"Duplicate enum option");this.options[k]=clone(v);};
Value.prototype.getAllOptions=function(){var a=[];for(var k in this.options)a.push({key:k,value:clone(this.options[k])});return a;};
function Preset(name,group){
    Node.call(this,name);this.group=group;this.captures=0;this.stored={};
    var values=this.add(new Node("values")), self=this;
    for(var k in group.live){var c=values.add(new Node(k)); c.controls.push(new Value("mode",k=="brushEnabled"?"Change at end":"Interpolate"));}
    this.controls.push({name:"update",trigger:function(){self.captures++;self.stored=clone(group.live);}});
}
Preset.prototype=new Node("");
function Manager(name,group){Node.call(this,name);this.group=group;this.refuse=false;}
Manager.prototype=new Node("");
Manager.prototype.getItems=function(){return this.nodes;};
Manager.prototype.addItem=function(type,data){
    if(this.refuse)return null;
    var n=this.group ? new Preset(data.shortName,this.group) : new Node(data.shortName);
    n.niceName=data.niceName;n.data=clone(data);this.nodes.push(n);return n;
};
Manager.prototype.removeItem=function(item){for(var i=0;i<this.nodes.length;i++)if(this.nodes[i]===item){this.nodes.splice(i,1);return;}};
var root, saves, warnings, groupNodes, fixtureOptions, fixtureName, fixtureSelector, fixtureStatus, scriptValues;
function setup(){
    root=new Node("root");saves=0;warnings=[];scriptValues={};groupNodes={};
    var cv=root.add(new Node("customVariables"));
    for(var i=0;i<document.customVariables.items.length;i++){
        var g=document.customVariables.items[i], key=g.shortName||nativeShort(g.niceName);
        if(key=="presetTools"){
            var tools=cv.add(new Node(key)).add(new Node("variables"));
            for(var v=0;v<g.variables.items.length;v++){
                var item=g.variables.items[v],p=item.parameters[0],c=new Value(item.shortName,p.value,p.enumOptions);
                tools.add(new Node(item.shortName)).controls.push(c);
                if(item.shortName=="selectedPreset")fixtureSelector=c;
                if(item.shortName=="newPresetName")fixtureName=c;
                if(item.shortName=="status")fixtureStatus=c;
            }
        } else if(key=="force1"||key=="orb1"||key=="force2"||key=="orb2"||key=="kinect"){
            var node=cv.add(new Node(key));groupNodes[key]=node;
            node.live={position:[1,2,3],intensity:17};
            if(key=="kinect")node.live={strength:2,brushEnabled:true,en16KinectBank:true,en16LEDColor:[0,0,1,1],en16Button1:false};
            node.controls.push(new Value("interpolationProgress",0));
            var manager=node.add(new Manager("presets",node));
            for(var t=0;t<g.presets.items.length;t++){
                var original=g.presets.items[t],preset=new Preset(original.shortName||nativeShort(original.niceName),node);
                preset.niceName=original.niceName;manager.nodes.push(preset);
            }
        }
    }
    var states=root.add(new Node("states"));
    for(var s=0;s<document.states.items.length;s++){
        var state=document.states.items[s],key=state.shortName||nativeShort(state.niceName);
        if(key!="presets"&&key!="savePresets")continue;
        var manager=states.add(new Node(key)).add(new Manager("processors",null));
        for(var a=0;a<state.processors.items.length;a++){
            var action=state.processors.items[a],node=manager.add(new Node(action.shortName||nativeShort(action.niceName)));
            if(node.name=="saveSession")node.controls.push({name:"trigger",trigger:function(){saves++;}});
        }
    }
    eval(source);
}
var script={addStringParameter:function(name,desc,value){var key=name=="Operation"?"operation":"entryKey";var p=new Value(key,value);scriptValues[key]=p;return p;},
    getScriptPath:function(){return "scripts/PresetAuthoring.js";},logWarning:function(x){warnings.push(x);}};
// eval globally: functions must see the same operation/entryKey bindings as JUCE.
function load(){eval(source);}
// Execute the source once at global scope; setup only resets its parameters.
setup();
eval(source);
function reset(){setup();operation=scriptValues.operation;entryKey=scriptValues.entryKey;}
function run(op,key){operation.set(op);entryKey.set(key||"");trigger();}
function stored(entry){var result=[];for(var i=0;i<3;i++)result.push(clone(resolve(entry.targets[i]).stored));return result;}
function counts(){var result={};for(var g in groupNodes){var items=child(groupNodes[g],"presets").nodes;for(var i=0;i<items.length;i++)result[g+"/"+items[i].name]=items[i].captures;}return result;}
check(saves==0&&warnings.length==0,"Script load performed work");
var entries=fixtureSelector.getAllOptions();
for(var i=0;i<entries.length;i++){
    reset();var entry=entries[i].value;run("updateEntry",entry.key);
    check(saves==1,"Scene update did not save: "+entry.label);
    for(var t=0;t<3;t++)check(resolve(entry.targets[t]).captures==1,"Wrong trio target: "+entry.label);
    var c=counts(),total=0;for(var k in c)total+=c[k];check(total==3,"Updated unrelated presets");
    var modes=kinectModes(resolve(entry.targets[2]));for(var m=0;m<modes.length;m++)check(modes[m].get()=="None","Lost global MIDI exclusion");
    check(child(child(resolve(entry.targets[2]),"values"),"brushEnabled").controls[0].get()=="Change at end","Changed artistic interpolation mode");
}
reset();fixtureName.set("  Essai live  ");run("create");
check(saves==1&&warnings.length==0,"Creation failed");var created=fixtureSelector.get();
check(created.label=="Essai live"&&created.key=="essailive","Name normalization failed");
for(var i=0;i<3;i++)check(same(resolve(created.targets[i]).stored,groupNodes[["force1","orb1","kinect"][i]].live),"Creation lost current CV values");
check(resolve("/states/presets/processors/essailive")!=null,"No recall action");
check(resolve("/states/savePresets/processors/updateessailive")!=null,"No update action");
var recall=resolve("/states/presets/processors/essailive").data.consequences.items;
var hasRecall=false,hasRelease=false;
for(var r=0;r<recall.length;r++){
    var params=recall[r].command.parameters;
    for(var v=0;v<params.length;v++){
        if(params[v].value=="/force1/presets/essailive")hasRecall=true;
        if(params[v].value=="/orb2/presets/transitionRelease")hasRelease=true;
    }
}
check(hasRecall,"Wrong native recall address");
if(resolve("/customVariables/orb2/presets/transitionRelease")!=null)check(hasRelease,"New scene lacks outgoing crossfade");
groupNodes.force1.live.intensity=99;run("update");check(saves==2&&resolve(created.targets[0]).stored.intensity==99,"Update selected failed");
fixtureName.set("Essai-live");var before=counts();run("create");check(saves==2&&same(before,counts()),"Address collision wrote data");
fixtureName.set("Essai live");run("create");check(saves==2,"Duplicate name was accepted");
// Snapshot serialization/reload of enum options retains the complete new trio.
var persisted=clone(fixtureSelector.options);fixtureSelector.options=clone(persisted);run("update");check(saves==3,"Reloaded selection lost new trio");
reset();fixtureName.set(" ");run("create");check(saves==0,"Blank name accepted");
reset();fixtureName.set("Partial");child(groupNodes.orb1,"presets").refuse=true;before=counts();run("create");check(saves==0&&same(before,counts()),"Partial preset creation was not rolled back");
reset();fixtureName.set("Partial");resolve("/states/savePresets/processors").refuse=true;before=counts();run("create");check(saves==0&&same(before,counts())&&resolve("/states/presets/processors/partial")==null,"Action creation failure left partial data");
reset();var entry=fixtureSelector.get();var missing=resolve(entry.targets[2]);child(groupNodes.kinect,"presets").removeItem(missing);before=counts();run("update");check(saves==0&&same(before,counts()),"Missing third preset caused partial update");
reset();fixtureSelector.set("Meduse");groupNodes.force1.controls[0].set(.5);before=counts();run("update");check(saves==0&&same(before,counts()),"Saved during interpolation");
reset();entryKey.set("notFound");run("updateEntry","notFound");check(saves==0,"Missing scene key accepted");
if(resolve("/customVariables/orb2/presets/chute")!=null){
    reset();groupNodes.orb2.controls[0].set(.5);run("updateEntry","chute");
    check(saves==0,"Saved Chute during Orb2 interpolation");
    reset();groupNodes.orb1.controls[0].set(.5);run("updateEntry","chute");
    check(saves==1,"Unrelated Orb1 interpolation blocked Chute update");
}
WScript.Echo("PRESET_AUTHORING_JS_PASS: "+entries.length+" real scene trios; create/update/persistence, global LED/bank, collisions, rollback and preflight failures.");
