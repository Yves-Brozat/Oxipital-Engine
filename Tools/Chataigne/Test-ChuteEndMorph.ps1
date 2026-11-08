param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Assert($ok,$message){if(!$ok){throw $message}}
function Json($n){ConvertTo-Json -InputObject $n -Depth 100 -Compress}
function Value($n,$key){($n.parameters|Where-Object controlAddress -eq $key).value}
$before=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$after=Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8|ConvertFrom-Json
$force=$after.customVariables.items|Where-Object niceName -eq 'Force 2'
Assert (@($force.variables.items|Where-Object shortName -eq linearDirection).Count -eq 1) 'Missing Force2 direction CV'
foreach($preset in $force.presets.items){
    Assert (@(Value $preset.values.containers.linearDirection '/linearDirection').Count -eq 3) "Missing direction: $($preset.niceName)"
    if($preset.niceName -in @('Chute','Chute - Start','Chute - End')){
        $direction=Value $preset.values.containers.linearDirection '/linearDirection'
        Assert ($direction[0] -eq 0 -and $direction[1] -eq 1 -and $direction[2] -eq 0) 'Chute direction must match Force1'
    }
    if($preset.shortName -eq 'transitionRelease'){Assert ((Value $preset.values.containers.linearDirection '/mode') -eq 'None') 'Release must preserve direction'}
}
foreach($label in @('Force 2','Orb2','Kinect')){
    $g=$after.customVariables.items|Where-Object niceName -eq $label
    $source=$g.presets.items|Where-Object niceName -eq Chute
    $end=$g.presets.items|Where-Object shortName -eq chuteEnd
    Assert (@($end).Count -eq 1 -and $end.niceName -eq 'Chute - End') "Missing End in $label"
    if($label -eq 'Force 2'){
        Assert ((Value $end.values.containers.linearIntensity '/linearIntensity') -eq 1) 'End linear intensity must be one'
        ($end.values.containers.linearIntensity.parameters|Where-Object controlAddress -eq /linearIntensity).value=Value $source.values.containers.linearIntensity '/linearIntensity'
    }
    $end.niceName=$source.niceName
    $expected=Json $source|ConvertFrom-Json
    $expected.PSObject.Properties.Remove('shortName');$end.PSObject.Properties.Remove('shortName')
    Assert ((Json $end) -ceq (Json $expected)) "End differs beyond linear intensity: $label"
    $g.presets.items=@($g.presets.items|Where-Object {$_ -ne $end})
}
$sequence=$after.sequences.items|Where-Object shortName -eq chute
$first=$sequence.layers.items|Where-Object shortName -eq chuteMorph
$end=$sequence.layers.items|Where-Object shortName -eq chuteEndMorph
Assert (@($end).Count -eq 1) 'Missing editable End curve'
$split=Value $first.containers.automation.items[-1] '/position'
$a=Value $end.containers.automation.items[0] '/position'
$b=Value $end.containers.automation.items[-1] '/position'
Assert ($a -eq $split -and $b-$a -eq 5) 'End must start after Chute and last five seconds'
Assert ((Value $end.containers.automation.items[0] '/value') -eq 0 -and (Value $end.containers.automation.items[-1] '/value') -eq 1) 'Curve must interpolate 0 to 1'
foreach($layer in @($first,$end)){
    $condition=$layer.containers.mapping.filters.items[0].conditions.items[0]
    Assert ((Value $condition '/inputValue') -eq '/sequences/chute/currentTime') 'Phase must use timeline time'
    Assert ((Value $condition.comparator '/reference') -eq $split) 'Phase boundary differs from Chute completion'
    foreach($key in @('/sendOnPlay','/sendOnSeek','/sendOnStop')){Assert ((Value $layer $key) -eq $true) "Missing transport support: $key"}
}
Assert ((Value $first.containers.mapping.filters.items[0].conditions.items[0].comparator '/comparisonFunction') -eq '<') 'First morph would overwrite End'
Assert ((Value $end.containers.mapping.filters.items[0].conditions.items[0].comparator '/comparisonFunction') -eq '>=') 'End morph would overwrite Start'
foreach($group in @('force2','orb2','kinect')){
    $output=$end.containers.mapping.outputs.items|Where-Object {(Value $_.command '/targetPreset2') -eq "/$group/presets/chuteEnd"}
    Assert (@($output).Count -eq 1 -and $output.commandType -eq 'Interpolate presets') "Missing End output $group"
    Assert ($output.command.paramLinks.value.mappingValueIndex -eq 0) 'Morph does not follow curve'
}
$state=$after.states.items|Where-Object niceName -eq 'CV Force 1 -> OSC Oxipital'
$route=$state.processors.items|Where-Object shortName -eq force2LinearDirection
Assert (@($route).Count -eq 1) 'Missing Force2 direction mapping'
Assert ((Value $route.im.items[0] '/inputValue') -eq '/customVariables/force2/variables/linearDirection/linearDirection') 'Wrong direction input'
Assert ((Value $route.outputs.items[0].command '/target') -eq '/modules/oxipital/parameters/forceGroups/forceGroup2/linear/linearDirection/baseValue') 'Wrong direction target'
Assert (@($route.filters.items|Where-Object niceName -eq 'Performance Mode').Count -eq 1) 'Direction must respect Unity edit mode'
$edit=$after.states.items|Where-Object shortName -eq unityAuthoring
$read=$edit.processors.items|Where-Object niceName -eq 'Read Force_Group_2 linearDirection'
Assert ((Value $read.im.items[0] '/inputValue') -eq '/modules/oxipital/values/Ballet/Force_Groups/Force_Group_2/StandardForceGroup/linearDirection') 'Missing reverse Unity edit route'
$tools=$after.customVariables.items|Where-Object shortName -eq presetTools
$selector=($tools.variables.items|Where-Object shortName -eq selectedPreset).parameters|Where-Object controlAddress -eq /selectedPreset
Assert (($selector.enumOptions.'Chute - End'.targets -join ',') -eq '/customVariables/force2/presets/chuteEnd,/customVariables/orb2/presets/chuteEnd,/customVariables/kinect/presets/chuteEnd') 'Wrong End authoring entry'
$load=$after.states.items|Where-Object niceName -eq Presets
$recall=$load.processors.items|Where-Object shortName -eq chuteEnd
foreach($target in $selector.enumOptions.'Chute - End'.targets){
    Assert (@($recall.consequences.items|Where-Object {(Value $_.command '/targetPreset') -eq $target.Substring(16)}).Count -eq 1) "Missing End recall $target"
}
$save=$after.states.items|Where-Object niceName -eq 'Save Presets'
$update=$save.processors.items|Where-Object shortName -eq updatechuteEnd
Assert ((Value $update.consequences.items[0].command.script.scriptParams '/entryKey') -eq 'chuteEnd') 'Missing End update'
# Undo the exact allowed changes, then compare the complete saved document.
$oldForce=$before.customVariables.items|Where-Object niceName -eq 'Force 2'
$force.variables=$oldForce.variables
foreach($preset in $force.presets.items){
    $old=$oldForce.presets.items|Where-Object niceName -eq $preset.niceName
    if($old.values.containers.PSObject.Properties['linearDirection']){$preset.values.containers.linearDirection=$old.values.containers.linearDirection}
    else{$preset.values.containers.PSObject.Properties.Remove('linearDirection')}
}
$state.processors.items=@($state.processors.items|Where-Object shortName -ne force2LinearDirection)
$edit.processors.items=@($edit.processors.items|Where-Object niceName -ne 'Read Force_Group_2 linearDirection')
$load.processors.items=@($load.processors.items|Where-Object shortName -ne chuteEnd)
$save.processors.items=@($save.processors.items|Where-Object shortName -ne updatechuteEnd)
$selector.enumOptions.PSObject.Properties.Remove('Chute - End')
$original=$before.sequences.items|Where-Object shortName -eq chute
$after.sequences.items=@($after.sequences.items|ForEach-Object {if($_.shortName -eq 'chute'){$original}else{$_}})
Assert ((Json $before) -ceq (Json $after)) 'Unexpected change to existing session data'
'CHUTE_END_PASS: direction CV/presets/Unity routes, exact End clones except linear intensity 1, exclusive timeline phases 10.1-15.1, recall/update entries and preservation of all other session data.'
