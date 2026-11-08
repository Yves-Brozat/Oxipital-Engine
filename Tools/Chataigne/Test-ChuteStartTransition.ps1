param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Json($n){ConvertTo-Json -InputObject $n -Depth 100 -Compress}
function Assert($ok,$message){if(!$ok){throw $message}}
function Value($n,$key){($n.parameters|Where-Object controlAddress -eq $key).value}
$before=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$after=Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8|ConvertFrom-Json
foreach($spec in @(@('Force 1','intensity','/intensity'),@('Orb1','dancerIntensity','/dancerIntensity'),@('Kinect','',''))){
    $group=$after.customVariables.items|Where-Object niceName -eq $spec[0]
    $source=$group.presets.items|Where-Object niceName -eq Chute
    $start=$group.presets.items|Where-Object shortName -eq chuteStart
    Assert (@($start).Count -eq 1 -and $start.niceName -eq 'Chute - Start') 'Missing Chute Start preset'
    if($spec[1]){
        $intensity=$start.values.containers.PSObject.Properties[$spec[1]].Value.parameters|Where-Object controlAddress -eq $spec[2]
        Assert ($intensity.value -eq 0) 'Start intensity is nonzero'
        $intensity.value=($source.values.containers.PSObject.Properties[$spec[1]].Value.parameters|Where-Object controlAddress -eq $spec[2]).value
    }
    $start.niceName=$source.niceName
    if($source.PSObject.Properties['shortName']){$start.shortName=$source.shortName}else{$start.PSObject.Properties.Remove('shortName')}
    Assert ((Json $start) -ceq (Json $source)) "Start differs beyond intensity in $($spec[0])"
    $group.presets.items=@($group.presets.items|Where-Object {$_ -ne $start})
}
$seq=$after.sequences.items|Where-Object shortName -eq chute
$morph=$seq.layers.items|Where-Object shortName -eq chuteMorph
$keys=$morph.containers.automation.items
Assert ([Math]::Abs(((Value $keys[1] '/position')-(Value $keys[0] '/position'))-10) -lt 0.00001) 'Morph must last ten seconds'
$conduite=$after.states.items|Where-Object niceName -eq Conduite
$route=$conduite.processors.items|Where-Object shortName -eq en16Abysses9
Assert ((Value $route.consequences.items[0].command '/target') -eq '/states/conduite/processors/conductor/processors/chute/trigger') 'EN16 Chute must launch the sequence'
$tools=$after.customVariables.items|Where-Object shortName -eq presetTools
$selector=($tools.variables.items|Where-Object shortName -eq selectedPreset).parameters|Where-Object controlAddress -eq '/selectedPreset'
$entry=$selector.enumOptions.PSObject.Properties['Chute - Start'].Value
Assert ($entry.key -eq 'chuteStart' -and @($entry.targets).Count -eq 3) 'Missing authoring entry'
$selector.enumOptions.PSObject.Properties.Remove('Chute - Start')
foreach($spec in @(@('Presets','chuteStart'),@('Save Presets','updatechuteStart'))){
    $state=$after.states.items|Where-Object niceName -eq $spec[0]
    Assert (@($state.processors.items|Where-Object shortName -eq $spec[1]).Count -eq 1) 'Missing Start recall/update action'
    $state.processors.items=@($state.processors.items|Where-Object shortName -ne $spec[1])
}
$originalSequence=$before.sequences.items|Where-Object shortName -eq chute
$after.sequences.items=@($after.sequences.items|ForEach-Object {if($_.shortName -eq 'chute'){$originalSequence}else{$_}})
Assert ((Json $before) -ceq (Json $after)) 'Existing presets, positions, routes or other sequence data changed'
'CHUTE_START_TRANSITION_PASS: exact preset clones except zero intensity, 10-second timeline, EN16 route, authoring entries, and preservation of all original session data.'
