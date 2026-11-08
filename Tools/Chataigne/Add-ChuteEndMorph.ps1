param(
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [ValidateRange(0.1,120)][double]$MorphDuration=5
)
$ErrorActionPreference='Stop'
function Json($n){ConvertTo-Json -InputObject $n -Depth 100 -Compress}
function Clone($n){Json $n|ConvertFrom-Json}
function P($key,$value){[pscustomobject]@{controlAddress=$key;value=$value}}
function Value($n,$key){($n.parameters|Where-Object controlAddress -eq $key).value}
function Set-Value($n,$key,$value){
    $field=$n.parameters|Where-Object controlAddress -eq $key
    if($field){$field.value=$value}else{$n.parameters=@($n.parameters)+@((P $key $value))}
}
if([IO.Path]::GetFullPath($SourcePath) -eq [IO.Path]::GetFullPath($OutputPath)){throw 'Use a separate output file.'}
$p=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$force1=$p.customVariables.items|Where-Object niceName -eq 'Force 1'
$force2=$p.customVariables.items|Where-Object niceName -eq 'Force 2'
$direction=$force1.variables.items|Where-Object niceName -eq 'Linear Direction'
if(@($direction).Count -ne 1){throw 'Missing Force1 direction template.'}
if(!($force2.variables.items|Where-Object niceName -eq 'Linear Direction')){
    $force2.variables.items+=@((Clone $direction))
}
foreach($preset in $force2.presets.items){
    $entry=$preset.values.containers.linearDirection
    if(!(Value $entry '/linearDirection')){
        $source=($force1.presets.items|Where-Object niceName -eq $preset.niceName).values.containers.linearDirection
        if($source -and (Value $source '/linearDirection')){$entry=Clone $source}
        else{$entry=[pscustomobject]@{niceName='Linear Direction';owned=$true;parameters=@((P '/linearDirection' @(0.0,0.0,0.0)))}}
        $preset.values.containers|Add-Member -NotePropertyName linearDirection -NotePropertyValue $entry -Force
    }
    if($preset.shortName -eq 'transitionRelease'){Set-Value $entry '/mode' 'None'}
}
$forceState=$p.states.items|Where-Object niceName -eq 'CV Force 1 -> OSC Oxipital'
if(!($forceState.processors.items|Where-Object shortName -eq force2LinearDirection)){
    $template=$forceState.processors.items|Where-Object shortName -eq force1LinearDirection
    if(@($template).Count -ne 1){throw 'Missing Force1 direction mapping.'}
    $route=(Json $template).Replace('force1','force2').Replace('forceGroup1','forceGroup2').Replace('Force 1','Force 2')|ConvertFrom-Json
    $forceState.processors.items+=@($route)
}
$editing=$p.states.items|Where-Object shortName -eq unityAuthoring
if($editing -and !($editing.processors.items|Where-Object niceName -eq 'Read Force_Group_2 linearDirection')){
    $template=$editing.processors.items|Where-Object niceName -eq 'Read Force_Group_2 linearIntensity'
    if(@($template).Count -ne 1){throw 'Missing Force2 Unity edit mapping template.'}
    $editing.processors.items+=@(((Json $template).Replace('linearIntensity','linearDirection')|ConvertFrom-Json))
}
foreach($label in @('Force 2','Orb2','Kinect')){
    $group=$p.customVariables.items|Where-Object niceName -eq $label
    if($group.presets.items|Where-Object shortName -eq chuteEnd){throw "Chute - End already exists in $label"}
    $source=$group.presets.items|Where-Object niceName -eq Chute
    if(@($source).Count -ne 1){throw "Missing Chute in $label"}
    $end=Clone $source
    $end.niceName='Chute - End'
    $end|Add-Member -NotePropertyName shortName -NotePropertyValue chuteEnd -Force
    if($label -eq 'Force 2'){Set-Value $end.values.containers.linearIntensity '/linearIntensity' 1}
    $group.presets.items+=@($end)
}
$tools=$p.customVariables.items|Where-Object shortName -eq presetTools
$selector=($tools.variables.items|Where-Object shortName -eq selectedPreset).parameters|Where-Object controlAddress -eq /selectedPreset
$entry=Clone $selector.enumOptions.Chute
$entry.key='chuteEnd';$entry.label='Chute - End'
$entry.targets=@('/customVariables/force2/presets/chuteEnd','/customVariables/orb2/presets/chuteEnd','/customVariables/kinect/presets/chuteEnd')
$selector.enumOptions|Add-Member -NotePropertyName 'Chute - End' -NotePropertyValue $entry
$presets=$p.states.items|Where-Object niceName -eq Presets
$recall=Clone ($presets.processors.items|Where-Object niceName -eq Chute)
$recall.niceName='Chute - End';$recall|Add-Member -NotePropertyName shortName -NotePropertyValue chuteEnd -Force
foreach($consequence in $recall.consequences.items){
    $target=Value $consequence.command '/targetPreset'
    if($target -in @('/force2/presets/chute','/orb2/presets/chute','/kinect/presets/scene02')){
        $group=$target.Split('/')[1];Set-Value $consequence.command '/targetPreset' "/$group/presets/chuteEnd"
    }
}
$presets.processors.items+=@($recall)
$save=$p.states.items|Where-Object niceName -eq 'Save Presets'
$update=Clone ($save.processors.items|Where-Object shortName -eq updatechute)
$update.niceName='Update Chute - End';$update.shortName='updatechuteEnd'
Set-Value $update.consequences.items[0].command.script.scriptParams '/entryKey' 'chuteEnd'
$save.processors.items+=@($update)
$sequence=$p.sequences.items|Where-Object shortName -eq chute
$start=$sequence.layers.items|Where-Object shortName -eq chuteMorph
if(@($start).Count -ne 1){throw 'Missing Chute timeline morph.'}
$split=[double](Value ($start.containers.automation.items|Sort-Object {Value $_ '/position'}|Select-Object -Last 1) '/position')
$endTime=$split+$MorphDuration
if($endTime -gt [double](Value $sequence '/totalTime')){
    $length=[Math]::Ceiling($endTime+1)
    Set-Value $sequence '/totalTime' $length;Set-Value $sequence '/viewEndTime' $length
    foreach($layer in $sequence.layers.items|Where-Object type -eq Mapping){Set-Value $layer.containers.automation '/length' $length}
}
$end=Clone $start
$end.niceName='Morph Chute vers Chute - End';$end.shortName='chuteEndMorph'
$end.containers.automation.items=@(
    [pscustomobject]@{niceName='Chute - etablie';type='Key';parameters=@((P '/position' $split),(P '/value' 0),(P '/easingType' 'Linear'))},
    [pscustomobject]@{niceName='Chute - End';type='Key';parameters=@((P '/position' $endTime),(P '/value' 1),(P '/easingType' 'Linear'))}
)
Set-Value $end.containers.automation '/position' 0
foreach($output in $end.containers.mapping.outputs.items){
    $target=Value $output.command '/targetPreset2'
    $group=$target.Split('/')[1]
    $output.niceName="$group - Chute vers Chute - End"
    Set-Value $output.command '/targetPreset' $target
    Set-Value $output.command '/targetPreset2' "/$group/presets/chuteEnd"
}
function Phase-Gate($label,$comparison){
    [pscustomobject]@{niceName=$label;type='Condition';filterParams=[pscustomobject]@{paramLinks=[pscustomobject]@{}};conditions=[pscustomobject]@{items=@(
        [pscustomobject]@{niceName='From Input Value';type='From Input Value';parameters=@((P '/inputValue' '/sequences/chute/currentTime'));comparator=[pscustomobject]@{hideInEditor=$true;parameters=@((P '/comparisonFunction' $comparison),(P '/reference' $split))}}
    )}}
}
# Two complete-preset morphs need exclusive phases. Otherwise the first
# mapping keeps writing Chute while the second tries to apply Chute - End.
$start.containers.mapping.filters|Add-Member -NotePropertyName items -NotePropertyValue @((Phase-Gate 'Before Chute End morph' '<')) -Force
$end.containers.mapping.filters|Add-Member -NotePropertyName items -NotePropertyValue @((Phase-Gate 'Chute End morph active' '>=')) -Force
$sequence.layers.items+=@($end)
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),(Json $p),[Text.UTF8Encoding]::new($false))
"CHUTE_END_READY: Force2 direction repaired; Chute - End linear intensity 1; timeline morph $split to $endTime seconds."
