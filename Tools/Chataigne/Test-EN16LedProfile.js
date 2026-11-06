// Execute the generated Lua with the actual decode.lua and simplecolor.lua
// from grid-fw v1.5.0. Native hardware functions are stubbed at the LED/MIDI
// boundary; callback argument order and color processing are firmware code.
// Usage: node Test-EN16LedProfile.js fengari-web.js firmwareDir profile.json
// Append --expect-broken to reproduce the v2 reception failure.
const fs = require('fs');
const path = require('path');
global.window = globalThis;
const fengari = require(path.resolve(process.argv[2]));
const dir = path.resolve(process.argv[3]);
const profile = JSON.parse(fs.readFileSync(process.argv[4], 'utf8'));
const expectBroken = process.argv.includes('--expect-broken');
const rgbProfile = profile.name.includes('v5 RGB');
const nativeProfile = profile.name.includes('v4 Native') || rgbProfile;
const quote = s => {
  if (s.includes(']====]')) throw Error('Unexpected Lua string delimiter');
  return '[====[' + s + ']====]';
};
const system = profile.configs.find(x => x.controlElementNumber === 255);
const setup = system.events.find(x => x.event === 0).config;
const event = (element, type) => profile.configs.find(x => x.controlElementNumber === element).events.find(x => x.event === type).config;
const syntaxChecks = profile.configs.flatMap(x => x.events).map(x => `assert(load(${quote(x.config)}))`).join('\n');
const test = `
local nativePrint=print
local messages={}
print=function(...) messages[#messages+1]=table.concat({...},' ') end
local curves,phases,midi,rates,shapes={}, {}, {}, {}, {}
ele={}
-- Intentionally no global "element": firmware only registers "ele".
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
function gln(i,l,...) end
function gld(i,l,...) end
function glx(i,l,r,g,b,a) curves[i..':'..l]={r,g,b,a} end
function glc(i,l,r,g,b)
 assert(i>=0 and i<=15 and (l==1 or l==2),'Invalid native LED address')
 gln(i,l,r//20,g//20,b//20);gld(i,l,r//2,g//2,b//2);glx(i,l,r,g,b)
end
function glf(i,l,v) rates[i..':'..l]=v end
function gls(i,l,v) shapes[i..':'..l]=v end
function glp(i,l,v) assert(type(v)=='number' and v>=0 and v<=255) phases[i..':'..l]=v end
function gmaps(x,a,b,c,d) return (x-a)*(d-c)/(b-a)+c end
function event_function_name() return EFN end
${fs.readFileSync(path.join(dir, 'simplecolor.lua'), 'utf8')}
${fs.readFileSync(path.join(dir, 'decode.lua'), 'utf8')}
init_simple_color()
${nativeProfile ? `
-- Do not allow the v4 regression to hide a dependency on element wrappers.
for i=0,15 do
 ele[i].glc=function() error('v4 must use native global glc') end
 ele[i].glp=function() error('v4 must use native global glp') end
end
` : ''}
${syntaxChecks}
self=ele[16]
assert(load(${quote(setup)}))()
assert(type(ele[16].midirx_cb)=='function','Setup did not register MIDI receiver')
local function receive(ch,cmd,cc,value)
 _decoded_order={1};_decoded_midi={{ch,cmd,cc,value,13,127,127}};_decoded_sysex={};_decoded_eview={}
 _decode_process(_decoded_midi,_decoded_sysex,_decoded_eview)
end
receive(15,176,119,127)
${expectBroken ? `
assert(oxipital_kinect_bank==false,'Expected the v2 ABI mismatch to reject the bank message')
assert(next(curves)==nil,'Broken callback unexpectedly updated LEDs')
nativePrint('REPRODUCED: v2 ignores MIDI with the real firmware 1.5.0 callback order')
` : `
assert(oxipital_kinect_bank==true,'Kinect bank message was ignored')
local function checkColors(r,g,b)
 for i=0,15 do for l=1,2 do
  local c=curves[i..':'..l]
  local black=${nativeProfile ? 'true' : 'false'} and oxipital_kinect_bank and l==1
  assert(c and c[1]==(black and 0 or r) and c[2]==(black and 0 or g) and c[3]==(black and 0 or b),'Unexpected LED color '..i..':'..l)
  if not black then assert(phases[i..':'..l]~=nil,'LED phase not refreshed') end
  ${nativeProfile ? `
  assert(rates[i..':'..l]==0 and shapes[i..':'..l]==0,'LED animation not reset')
  if oxipital_kinect_bank and l==2 then assert(phases[i..':'..l]==255,'Custom color must be visible even with value zero') end
  ` : ''}
 end end
end
checkColors(255,210,0)
receive(0,176,119,0);receive(15,176,115,0);receive(15,144,119,0)
assert(oxipital_kinect_bank==true,'Unrelated MIDI changed the bank')
self=ele[5];EFN='ec'
assert(load(${quote(event(5,2))}))()
assert(self.mode==1 and self.sensitivity==100 and self.neutral==50,'Relative encoder settings changed')
self=ele[6];EFN='bc';self.button=127
assert(load(${quote(event(6,3))}))()
assert(self.buttonMode==0,'Momentary button mode changed')
checkColors(255,210,0)
assert(#midi==2,'LED receiver emitted extra MIDI')
for _,message in ipairs(midi) do assert(#message==4) for _,v in ipairs(message) do assert(v==-1,'Automatic MIDI addressing changed') end end
receive(15,176,119,0)
assert(oxipital_kinect_bank==false,'Abysses bank message was ignored')
checkColors(12,34,210)
${nativeProfile ? `
for i=0,15 do
 assert(phases[i..':1']==(ele[i]:bva()*255/127)//1,'Original button brightness not restored')
 assert(phases[i..':2']==(ele[i]:eva()*255/127)//1,'Original encoder brightness not restored')
 ele[i].value=0
end
receive(15,176,119,127);checkColors(255,210,0)
receive(15,176,119,127);checkColors(255,210,0)
` : ''}
${rgbProfile ? `
receive(0,176,116,0);receive(15,144,116,0);checkColors(255,210,0)
receive(15,176,116,0);receive(15,176,117,0);receive(15,176,118,127)
checkColors(0,0,255)
receive(15,176,119,127);checkColors(0,0,255)
self=ele[5];EFN='ec';assert(load(${quote(event(5,2))}))();checkColors(0,0,255)
self=ele[6];EFN='bc';assert(load(${quote(event(6,3))}))();checkColors(0,0,255)
receive(15,176,119,0);checkColors(12,34,210)
receive(15,176,117,127);receive(15,176,118,0);checkColors(12,34,210)
receive(15,176,119,127);checkColors(0,255,0)
receive(15,176,116,0);receive(15,176,117,0);receive(15,176,118,0);checkColors(0,0,0)
receive(15,176,116,127);receive(15,176,117,127);receive(15,176,118,127);checkColors(255,255,255)
assert(#midi==4,'Color updates must not echo MIDI')
-- The following reset/resync checks expect the original two test interactions.
midi={midi[1],midi[2]}
` : ''}
receive(15,176,119,127)
self=ele[16];assert(load(${quote(setup)}))()
assert(oxipital_kinect_bank==false,'Setup did not reset the bank')
receive(15,176,119,127);checkColors(255,210,0)
assert(#midi==2,'Resynchronization must not echo MIDI')
nativePrint('PASS: real FW1.5.0 decoder/color Lua; 16 LEDs, both layers, phase refresh, turns/presses, MIDI filtering, reset/resync and original MIDI settings')
`}
`;
const L = fengari.lauxlib.luaL_newstate();
fengari.lualib.luaL_openlibs(L);
const status = fengari.lauxlib.luaL_dostring(L, fengari.to_luastring(test));
if (status !== fengari.lua.LUA_OK) {
  console.error('Lua test failed:', fengari.to_jsstring(fengari.lua.lua_tostring(L, -1)));
  process.exitCode = 1;
}
fengari.lua.lua_close(L);
