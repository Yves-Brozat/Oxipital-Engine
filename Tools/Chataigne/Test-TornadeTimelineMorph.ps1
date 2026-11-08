param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath,[ValidateSet('Tornade','Cascade','Chute')][string]$Scene='Tornade')
$ErrorActionPreference='Stop'
function Assert($ok,$message){if(!$ok){throw $message}}
function Json($x){ConvertTo-Json -InputObject $x -Depth 100 -Compress}
function Value($n,$key){($n.parameters|Where-Object controlAddress -eq $key).value}
$before=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$after=Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8|ConvertFrom-Json
$sceneKey=$Scene.ToLowerInvariant();$startKey=$sceneKey+'Start';$layerKey=$sceneKey+'Morph'
$kinectEndKey=switch($Scene){'Cascade'{'scene07'}'Chute'{'scene02'}default{'scene09'}}
$seq=$after.sequences.items|Where-Object shortName -eq $sceneKey
$layer=$seq.layers.items|Where-Object shortName -eq $layerKey
Assert (@($layer).Count -eq 1) 'Expected one shared timeline morph layer'
Assert ($layer.type -eq 'Mapping') 'Expected native mapping layer'
Assert ((Value $layer '/sendOnSeek') -eq $true) 'Seeking must apply the timeline value'
$keys=@($layer.containers.automation.items)
Assert ($keys.Count -eq 2) 'Expected editable start/end keys'
Assert ((Value $keys[0] '/value') -eq 0 -and (Value $keys[1] '/value') -eq 1) 'Curve endpoints must be 0 and 1'
Assert ((Value $keys[1] '/position') -gt (Value $keys[0] '/position')) 'Morph duration must be positive'
Assert ((Value $seq '/totalTime') -ge (Value $keys[1] '/position')) 'Morph must finish within the sequence'
Assert ((Value $layer.containers.automation '/length') -eq (Value $seq '/totalTime')) 'Automation length must match sequence'
$outputs=@($layer.containers.mapping.outputs.items)
Assert ($outputs.Count -eq 3) 'Expected Force 1, Orb1 and Kinect morph outputs'
foreach($spec in @(@('force1',$sceneKey),@('orb1',$sceneKey),@('kinect',$kinectEndKey))){
    $start='/'+$spec[0]+'/presets/'+$startKey;$end='/'+$spec[0]+'/presets/'+$spec[1]
    $output=@($outputs|Where-Object {(Value $_.command '/targetPreset') -eq $start})
    Assert ($output.Count -eq 1) "Missing source $start"
    Assert ($output[0].commandType -ceq 'Interpolate presets') 'Expected native interpolation command'
    Assert ((Value $output[0].command '/targetPreset2') -eq $end) "Wrong destination for $start"
    Assert ($output[0].command.paramLinks.value.linkType -eq 1 -and $output[0].command.paramLinks.value.mappingValueIndex -eq 0) 'All groups must follow the same automation value'
    $init=$seq.layers.items.triggers.items|Where-Object niceName -eq "Init - $Scene Start"
    Assert (@($init).Count -eq 1) 'Missing initialization'
    Assert ((Value $init '/time') -lt (Value $keys[0] '/position')) 'Start presets must be loaded before the ramp'
    Assert (@($init.consequences.items|Where-Object {$_.commandType -eq 'Set Preset' -and (Value $_.command '/targetPreset') -eq $start}).Count -eq 1) 'Start preset must be recalled once'
    Assert (@($init.consequences.items|Where-Object {$_.commandType -eq 'Kill Go to preset' -and (Value $_.command '/targetGroup') -eq ('/'+$spec[0])}).Count -eq 1) 'Prior wall-clock transitions must be stopped'
    Assert (@($init.consequences.items|Where-Object {$_.commandType -eq 'Go to preset' -and (Value $_.command '/targetPreset') -eq $end}).Count -eq 0) 'Independent preset timer conflicts with the timeline'
}
# Remove only the intentionally edited sequence from both parsed documents.
# Everything else, including all Start/target presets and dashboards, must match.
$before.sequences.items=@($before.sequences.items|Where-Object shortName -ne $sceneKey)
$after.sequences.items=@($after.sequences.items|Where-Object shortName -ne $sceneKey)
Assert ((Json $before) -ceq (Json $after)) "Data outside the $Scene sequence changed"
"$($Scene.ToUpperInvariant())_TIMELINE_MORPH_PASS: native commands, shared factor, initialization, seeking, duration and preservation of all other session data."
