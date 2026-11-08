// node Test-EN16BankColorDashboardRepair.js prepared.noisette EN16Banks.js
const fs=require('fs'),vm=require('vm');
const p=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const scriptSource=fs.readFileSync(process.argv[3],'utf8');
const value=(n,k)=>n?.parameters?.find(a=>a.controlAddress===k)?.value;
const bankAddress='/customVariables/en16Banks/variables/bank/bank';
const bankState=p.states.items.find(s=>s.shortName==='en16Banks');
const dashboardState=p.states.items.find(s=>s.niceName==='Dashboard');
const expected=['/abysses','/abyssesKinect','/abyssesFluides'];
const values={},held=[];let selected=[],focused=0;
function check(ok,message){if(!ok)throw Error(message);}
for(let i=1;i<=16;i++){
 for(const side of ['Abysses','Kinect'])held.push(`/customVariables/kinect/variables/en16${side}Button${i}/en16${side}Button${i}`);
 held.push(`/customVariables/en16Banks/variables/fluidButton${i}/fluidButton${i}`);
}
const kColor='/customVariables/kinect/variables/en16LEDColor/en16LEDColor';
const fColor='/customVariables/en16Banks/variables/fluidLEDColor/fluidLEDColor';
values[kColor]=[1,0,0,1];values[fColor]=[0,0,1,1];values[bankAddress]=0;
function execute(items){for(const c of items){
 if(c.commandType==='Set Parameter Value')values[value(c.command,'/target')]=value(c.command,'/value');
 else if(c.commandType==='Trigger a Control'){
  const target=value(c.command,'/target');
  const key=target.split('/').slice(-2)[0];
  const action=dashboardState.processors.items.find(a=>a.shortName===key);
  check(!!action,'Unresolved native dashboard action '+target);execute(action.consequences.items);
 }else if(c.commandType==='Select Dashboard')selected.push(value(c.command,'/dashboard'));
 else if(c.commandType==='Launch App'){
  throw Error('Bank must not launch a foreground helper');
 }
 else if(c.commandType==='Set Window Parameters'){
  throw Error('Bank must not change the window');
 }else throw Error('Unexpected bank/window command '+c.commandType);
}}
function changeBank(next){
 values[bankAddress]=next;
 const matching=bankState.processors.items.filter(a=>a.type==='Action'&&a.conditions?.items?.some(c=>value(c,'/inputValue')===bankAddress&&value(c.comparator,'/reference')===next));
 check(matching.length===1,'Bank change must match exactly one apply action');
 check(!matching[0].consequences.items.some(c=>c.commandType==='Script'),'Apply still depends on script traversal');
 execute(matching[0].consequences.items);
}
function node(name,containers=[],controls=[]){return {name,getContainers:()=>containers,getControllables:()=>controls};}
const bankControl={name:'bank',get:()=>values[bankAddress],set:changeBank};
const root=node('root',[node('customVariables',[node('en16Banks',[node('variables',[node('bank',[],[bankControl])])])])]);
const context={root,script:{addStringParameter:()=>({get:()=> 'cycle'})}};
vm.createContext(context);vm.runInContext(scriptSource,context);
check(selected.length===0,'Script loading changed dashboards');
for(let i=0;i<9;i++){
 held.forEach(a=>values[a]=127);selected=[];focused=0;
 const next=(values[bankAddress]+1)%3;
 context.trigger();
 check(values[bankAddress]===next,'Cycle did not select next bank');
 check(selected.length===1&&selected[0]===expected[next],'Bank press failed to open the matching dashboard');
 check(focused===0,'Bank press changed the foreground window');
 check(held.every(a=>values[a]===0),'A held input survived a bank change');
 check(values['/customVariables/kinect/variables/en16KinectBank/en16KinectBank']===(next===1),'Compatibility bank incorrect');
 check(JSON.stringify(values[kColor])==='[1,0,0,1]'&&JSON.stringify(values[fColor])==='[0,0,1,1]','Bank change overwrote an independent LED color');
}
console.log('PASS: actual saved action graph + cycle script: nine presses select the matching dashboard without window/focus commands, clear 48 held inputs, and preserve separate Kinect/Fluides colors.');
