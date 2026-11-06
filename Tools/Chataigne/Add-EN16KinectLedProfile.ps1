param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$sourceFull=(Resolve-Path -LiteralPath $SourcePath).Path
$outputFull=[IO.Path]::GetFullPath($OutputPath)
if($sourceFull -eq $outputFull){throw 'Keep the original profile; use a separate output path.'}
$original=[IO.File]::ReadAllText($sourceFull)|ConvertFrom-Json
$profile=$original|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json
if($profile.type -ne 'EN16' -or $profile.configType -ne 'profile' -or $profile.configs.Count -ne 17){throw 'Expected a complete EN16 profile with 16 encoders and system events.'}
$profile.name='EN16 Abysses - Kinect LEDs v5 RGB'
$profile.id=[guid]::NewGuid().ToString()
foreach($field in @('cloudId','owner','localId','fileName','virtualPath')){$profile.PSObject.Properties.Remove($field)}
$profile|Add-Member -NotePropertyName description -NotePropertyValue 'Original encoder/button MIDI settings. Channel 16: CC116/117/118 = Kinect RGB (0..127); CC119 = bank (127 Kinect, 0 original automatic colors).' -Force

# Only the color action is replaced. Mode, sensitivity, relative encoder
# output and automatic MIDI addressing stay byte-for-byte identical.
$oldColor='--[[@sglc]] self:glc(-1,{{-1,-1,-1,1}}) self:glp(-1,-1)'
$changed=0
foreach($element in $profile.configs|Where-Object controlElementNumber -ne 255){
    $newColor='--[[@cb]] oxipital_led('+$element.controlElementNumber+')'
    foreach($event in $element.events|Where-Object event -in @(2,3)){
        if(!$event.config.Contains($oldColor)){throw ('Unexpected color settings on element '+$element.controlElementNumber+'; do not overwrite a custom palette.')}
        $event.config=$event.config.Replace($oldColor,$newColor)
        $changed++
    }
}
if($changed -ne 32){throw 'Expected one color action per encoder and button.'}
# Verified against grid-fw tag v1.5.0, lua_src/decode.lua: event first,
# header second. The firmware's element table is named ele, not element.
$init='--[[@cb]] oxipital_kinect_bank=false oxipital_rgb={255,210,0} function oxipital_led(i) for l=1,2 do glf(i,l,0) gls(i,l,0) end if oxipital_kinect_bank then glc(i,1,0,0,0) glc(i,2,table.unpack(oxipital_rgb)) glp(i,2,255) else for l=1,2 do glc(i,l,glr(),glg(),glb()) end glp(i,1,(ele[i]:bva()*255/127)//1) glp(i,2,(ele[i]:eva()*255/127)//1) end end self.midirx_cb=function(self,e,h) if e[1]==15 and e[2]==176 and e[3]>=116 and e[3]<=119 then if e[3]==119 then local b=e[4]>=64 if b~=oxipital_kinect_bank then print("Oxipital LEDs v5: "..e[4]) end oxipital_kinect_bank=b else oxipital_rgb[e[3]-115]=e[4]*255//127 end for i=0,15 do oxipital_led(i) end end end print("Oxipital LEDs: init v5 RGB")'
$system=$profile.configs|Where-Object controlElementNumber -eq 255
$setup=$system.events|Where-Object event -eq 0
$receive=$system.events|Where-Object event -eq 5
if(!$setup -or !$receive){throw 'System Init and MIDI RX events are required.'}
if($setup.config.Contains('midirx_cb')){throw 'Existing callback requires a manual merge; do not replace it.'}
# These phase formulas match the original profile's 0..127 ranges. Refreshing
# phase controls the displayed intensity. Kinect uses a fixed bright yellow,
# matching the native-command test confirmed on the physical EN16. Abysses
# restores the original automatic palette and value-dependent intensity.
foreach($element in $profile.configs|Where-Object controlElementNumber -ne 255){
    $button=($element.events|Where-Object event -eq 3).config
    $encoder=($element.events|Where-Object event -eq 2).config
    if(!$button.Contains('self:bmi(0) self:bma(127)') -or !$encoder.Contains('self:emi(0) self:ema(127)')){throw 'Unexpected element ranges; review LED phase normalization.'}
}
$setup.config+=' '+$init

# Verify all events against the actual backup, allowing only these LED edits.
foreach($before in $original.configs){
    $newColor='--[[@cb]] oxipital_led('+$before.controlElementNumber+')'
    $after=$profile.configs|Where-Object controlElementNumber -eq $before.controlElementNumber
    if($after.events.Count -ne $before.events.Count){throw 'Event count changed'}
    foreach($event in $before.events){
        $modified=$after.events|Where-Object event -eq $event.event
        $restored=$modified.config.Replace($newColor,$oldColor)
        if($before.controlElementNumber -eq 255 -and $event.event -eq 0){$restored=$restored.Substring(0,$restored.Length-$init.Length-1)}
        if($restored -cne $event.config){throw 'Unexpected non-LED event modification'}
        if($modified.config.Length -gt 908){throw 'Script exceeds the device character limit'}
    }
}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFull))
[IO.File]::WriteAllText($outputFull,($profile|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
'EN16_LED_PROFILE_PASS: 16 encoders + system; Setup midirx_cb registered; color phase refreshed; MIDI/mode/sensitivity unchanged; scripts below 908 characters.'
