// node Test-EN16ThreeBankProfile.js fengari-web.js firmwareDir original.json prepared.json
const fs=require('fs'),path=require('path');global.window=globalThis;
const fengari=require(path.resolve(process.argv[2])),dir=process.argv[3];
const original=JSON.parse(fs.readFileSync(process.argv[4],'utf8'));
const prepared=JSON.parse(fs.readFileSync(process.argv[5],'utf8'));
function check(ok,message){if(!ok)throw Error(message);}
for(const element of original.configs){
 const after=prepared.configs.find(e=>e.controlElementNumber===element.controlElementNumber);
 for(const event of element.events){
  if(element.controlElementNumber===255 && [0,4].includes(event.event))continue;
  check(event.config===after.events.find(e=>e.event===event.event).config,'Non-system control changed');
 }
}
const event=(element,type)=>prepared.configs.find(e=>e.controlElementNumber===element).events.find(e=>e.event===type).config;
const quote=s=>'[====['+s+']====]';
// GridAction.parse in the installed Grid Editor removes CR/LF, then collapses
// spaces. grid_ui_event_register_actionstring wraps the transmitted body in
// an event function. Raw Lua alone misses merged tokens and trailing comments.
const transported=code=>code.replace(/[\n\r]+/g,'').replace(/\s{2,10}/g,' ');
const wrap=(code,index,event)=>`ele[${index}].event${event} = function (self) local _efn = EFN; EFN = "event${event}"; ${transported(code)} end EFN = _efn`;
if(process.argv.includes('--expect-broken')){
 for(const type of [0,4]){
  const L=fengari.lauxlib.luaL_newstate();
  const status=fengari.lauxlib.luaL_loadstring(L,fengari.to_luastring(wrap(event(255,type),16,type)));
  check(status!==fengari.lua.LUA_OK,'Expected v7 transport error in event '+type);
  console.log('REPRODUCED: Grid event '+type+' fails after editor transport: '+fengari.to_jsstring(fengari.lua.lua_tostring(L,-1)));
 }
 process.exit(0);
}
for(const element of prepared.configs)for(const e of element.events){
 const L=fengari.lauxlib.luaL_newstate();
 const status=fengari.lauxlib.luaL_loadstring(L,fengari.to_luastring(wrap(e.config,element.controlElementNumber===255?16:element.controlElementNumber,e.event)));
 check(status===fengari.lua.LUA_OK,'Grid event fails after transport: element '+element.controlElementNumber+', event '+e.event);
}
const lua=`
local nativePrint=print
print=function(...) end
local curves,phases,midi,rates,shapes={},{},{},{},{}
ele={}
for i=0,15 do
 local k={index=i,type='encoder',button=0,value=64,min=0,max=127,bmin=0,bmax=127}
 function k:ind() return self.index end
 function k:bva() return self.button end
 function k:eva() return self.value end
 function k:bmi(v) if v~=nil then self.bmin=v end return self.bmin end
 function k:bma(v) if v~=nil then self.bmax=v end return self.bmax end
 function k:emi(v) if v~=nil then self.min=v end return self.min end
 function k:ema(v) if v~=nil then self.max=v end return self.max end
 function k:bmo(v) self.buttonMode=v end
 function k:emo(v) self.mode=v end
 function k:ev0(v) self.neutral=v end
 function k:ese(v) self.sensitivity=v end
 function k:gms(...) midi[#midi+1]={...} end
 ele[i]=k
end
ele[16]={type='system'}
function glr() return 12 end
function glg() return 34 end
function glb() return 210 end
function glag(i,sub) assert(sub==0) return i end
function gln(...) end
function gld(...) end
function glx(i,l,r,g,b,a) curves[i..':'..l]={r,g,b,a} end
function glc(i,l,r,g,b) assert(i>=0 and i<=15) glx(i,l,r,g,b) end
function glf(i,l,v) rates[i..':'..l]=v end
function gls(i,l,v) shapes[i..':'..l]=v end
function glp(i,l,v) assert(v>=0 and v<=255) phases[i..':'..l]=v end
function gmaps(x,a,b,c,d) return (x-a)*(d-c)/(b-a)+c end
function event_function_name() return EFN end
function gpl(...) error('Lateral button must not load a native page') end
${fs.readFileSync(path.join(dir,'simplecolor.lua'),'utf8')}
${fs.readFileSync(path.join(dir,'decode.lua'),'utf8')}
init_simple_color()
${prepared.configs.flatMap(e=>e.events).map(e=>`assert(load(${quote(transported(e.config))}))`).join('\n')}
self=ele[16]
assert(load(${quote(wrap(event(255,0),16,0))}))()
ele[16]:event0()
local function receive(ch,cmd,cc,value)
 _decoded_order={1};_decoded_midi={{ch,cmd,cc,value,13,127,127}};_decoded_sysex={};_decoded_eview={}
 _decode_process(_decoded_midi,_decoded_sysex,_decoded_eview)
end
local function orange()
 for l=1,2 do local c=curves['15:'..l] assert(c[1]==255 and c[2]==100 and c[3]==0,'Bank LED not orange') assert(phases['15:'..l]==255,'Bank LED must remain visible') end
end
local function colors(r,g,b,custom)
 orange()
 for i=0,14 do for l=1,2 do
  local c=curves[i..':'..l]
  local black=custom and l==1
  assert(c[1]==(black and 0 or r) and c[2]==(black and 0 or g) and c[3]==(black and 0 or b),'Wrong bank color')
  if custom and l==2 then assert(phases[i..':'..l]==255) end
 end end
end
assert(oxipital_bank==0) colors(12,34,210,false)
receive(15,176,119,1) assert(oxipital_bank==1) colors(255,210,0,true)
receive(15,176,116,0) receive(15,176,117,64) receive(15,176,118,127) colors(0,128,255,true)
-- Updating inactive Fluides must neither recolor Kinect nor lose its own RGB.
receive(15,176,112,127) receive(15,176,113,0) receive(15,176,114,0) colors(0,128,255,true)
receive(15,176,119,2) assert(oxipital_bank==2) colors(255,0,0,true)
-- Updating inactive Kinect must leave Fluides unchanged.
receive(15,176,116,127) receive(15,176,117,0) receive(15,176,118,127) colors(255,0,0,true)
receive(15,176,112,0) receive(15,176,113,127) receive(15,176,114,64) colors(0,255,128,true)
receive(15,176,119,1) colors(255,0,255,true)
receive(15,176,119,2) colors(0,255,128,true)
for n=1,3 do
 receive(15,176,119,0) colors(12,34,210,false)
 receive(15,176,119,1) colors(255,0,255,true)
 receive(15,176,119,2) colors(0,255,128,true)
end
self=ele[15] EFN='bc' assert(load(${quote(event(15,3))}))() orange()
self=ele[15] EFN='ec' assert(load(${quote(event(15,2))}))() orange()
assert(self.mode==1 and self.sensitivity==100 and self.neutral==50,'Relative encoder changed')
assert(self.buttonMode==0,'Momentary button changed')
receive(0,176,119,0) receive(15,144,119,0) receive(15,176,115,0) receive(15,176,119,127)
assert(oxipital_bank==2,'Unrelated or obsolete bank MIDI changed bank')
receive(15,176,119,0) colors(12,34,210,false)
self=ele[16] assert(load(${quote(wrap(event(255,4),16,4))}))() ele[16]:event4()
assert(#midi==2,'LED callbacks emitted extra MIDI')
for _,message in ipairs(midi) do for _,v in ipairs(message) do assert(v==-1,'Automatic MIDI addressing changed') end end
nativePrint('PASS: editor transport + firmware wrappers/decoder; independent Kinect and Fluides RGB caches during inactive edits and repeated cycles; orange Bank; disabled lateral paging; unchanged MIDI controls.')
`;
const L=fengari.lauxlib.luaL_newstate();
fengari.lualib.luaL_openlibs(L);
const status=fengari.lauxlib.luaL_dostring(L,fengari.to_luastring(lua));
if(status!==fengari.lua.LUA_OK)throw Error(fengari.to_jsstring(fengari.lua.lua_tostring(L,-1)));
