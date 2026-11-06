param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$before=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$after=Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8|ConvertFrom-Json
function ShowGroup($p,$name){$p.customVariables.items|Where-Object niceName -eq $name}
function V($pr,$k){$pr.values.containers.$k.parameters[0].value}
$old1=ShowGroup $before 'Force 1';$old2=ShowGroup $before 'Force 2'
$g1=ShowGroup $after 'Force 1';$g2=ShowGroup $after 'Force 2'
$original=$old1.presets.items|Where-Object niceName -eq Tourbillon
$one=$g1.presets.items|Where-Object niceName -eq Tourbillon
$two=$g2.presets.items|Where-Object niceName -eq Tourbillon
foreach($k in 'curlIntensity','perlinIntensity'){if((V $one $k) -ne 0){throw 'Noise remains on brush force'}}
foreach($entry in $original.values.containers.PSObject.Properties|Where-Object Name -match '^(curl|perlin)'){
    if(($entry.Value|ConvertTo-Json -Depth 100 -Compress) -cne ($two.values.containers.($entry.Name)|ConvertTo-Json -Depth 100 -Compress)){throw "Noise setting changed: $($entry.Name)"}
}
foreach($k in 'radialIntensity','axialIntensity','linearIntensity','orthoradialIntensity','orthoaxialIntensity'){if((V $two $k) -ne 0){throw "Unexpected background component $k"}}
foreach($k in 'intensity','size','position','forceFactorInside','forceFactorOutside'){
    if((V $two $k|ConvertTo-Json -Compress) -cne (V $original $k|ConvertTo-Json -Compress)){throw "Background baseline changed: $k"}
}
$off=$g2.presets.items|Where-Object shortName -eq tourbillonBackgroundOff
if((V $off intensity) -ne 0){throw 'Background off preset is not silent'}
foreach($a in ($after.states.items|Where-Object niceName -eq Presets).processors.items){
    $load=$a.consequences.items[0]
    $target=($load.command.parameters|Where-Object controlAddress -eq '/targetPreset').value
    if($a.niceName -eq 'Tourbillon'){
        if($target -ne '/force2/presets/tourbillon'){throw 'Background recall missing'}
        $f1=$a.consequences.items|Where-Object {($_.command.parameters|Where-Object controlAddress -eq '/targetPreset').value -eq '/force1/presets/tourbillon'}
        if(($f1.command.parameters|Where-Object controlAddress -eq '/interpolationTime').value -ne ($load.command.parameters|Where-Object controlAddress -eq '/interpolationTime').value){throw 'Transition durations differ'}
    }elseif($target -ne '/force2/presets/tourbillonBackgroundOff' -or $load.commandType -ne 'Set Preset'){throw "Background persists on $($a.niceName)"}
    $a.consequences.items=@($a.consequences.items|Select-Object -Skip 1)
}
$one.values.containers.curlIntensity=$original.values.containers.curlIntensity
$one.values.containers.perlinIntensity=$original.values.containers.perlinIntensity
$g2.presets.items=$old2.presets.items
if(($before|ConvertTo-Json -Depth 100 -Compress) -cne ($after|ConvertTo-Json -Depth 100 -Compress)){throw 'Unrelated data changed (including Kinect brush binding)'}
'TOURBILLON_FORCES_PASS: noise settings preserved, separated intensities, coordinated recall, scene exit mute, all unrelated data preserved.'
