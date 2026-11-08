param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$p=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
if($p.type -ne 'EN16' -or $p.configs.Count -ne 17){throw 'Expected a complete EN16 profile.'}
$p.name='EN16 Abysses - Three Banks v9';$p.id=[guid]::NewGuid().ToString()
foreach($key in @('cloudId','owner','localId','fileName','virtualPath')){$p.PSObject.Properties.Remove($key)}
$p.description='Single native page. Button 4 cycles Abysses / Kinect / AbyssesFluides. Channel 16 CC119 = bank 0/1/2; CC116..118 = Kinect RGB; CC112..114 = Fluides RGB. Independent persistent color caches. Element 15 (button 4) always orange. Side paging disabled.'
$system=$p.configs|Where-Object controlElementNumber -eq 255
$setup=$system.events|Where-Object event -eq 0
$lateral=$system.events|Where-Object event -eq 4
if(!$setup.config.Contains('oxipital_kinect_bank=false') -or !$lateral){throw 'Expected the v5 RGB profile.'}
# Native auto MIDI indices are 32 + element index: slot 4 is note 47 => element 15.
$lua=@'
--[[@cb]] oxipital_bank=0 oxipital_rgb={{255,210,0},{0,255,255}}
function oxipital_led(i)
 for l=1,2 do glf(i,l,0) gls(i,l,0) end
 if i==15 then
  for l=1,2 do glc(i,l,255,100,0) glp(i,l,255) end
 elseif oxipital_bank~=0 then
  glc(i,1,0,0,0) glc(i,2,table.unpack(oxipital_rgb[oxipital_bank])) glp(i,2,255)
 else
  for l=1,2 do glc(i,l,glr(),glg(),glb()) end
  glp(i,1,(ele[i]:bva()*255/127)//1) glp(i,2,(ele[i]:eva()*255/127)//1)
 end
end
self.midirx_cb=function(self,e,h)
 if e[1]==15 and e[2]==176 and e[3]>=112 and e[3]<=119 then
  if e[3]==119 then
   if e[4]>=0 and e[4]<=2 then oxipital_bank=e[4] end
  else
   local b=e[3]>=116 and 1 or 2
   local c=e[3]-(b==1 and 115 or 111)
   if c>3 then return end
   oxipital_rgb[b][c]=e[4]*255//127
   if b~=oxipital_bank then return end
  end
  for i=0,15 do oxipital_led(i) end
 end
end
for i=0,15 do oxipital_led(i) end
'@
# GridAction.parse removes line breaks without inserting token separators.
# Export one line with explicit spaces, and never use a trailing line comment:
# the firmware appends the closing `end` of its generated event function.
$setup.config=($lua -replace '[\r\n]+',' ' -replace '\s{2,}',' ').Trim()
$lateral.config='--[[@cb]] do end'
foreach($element in $p.configs){foreach($event in $element.events){
    # Firmware v1.5.0: GRID_PARAMETER_ACTIONSTRING_maxlength = 909;
    # transmitted script adds "<?lua " and " ?>" (nine bytes).
    if([Text.Encoding]::UTF8.GetByteCount($event.config)+9 -gt 909){throw "Event exceeds Grid firmware size limit: $($element.controlElementNumber)/$($event.event)"}
}}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),($p|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
'EN16_THREE_BANK_PROFILE_READY: three bank codes, per-bank RGB, always-orange element 15, disabled lateral paging; encoder/button MIDI settings preserved.'
