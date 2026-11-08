param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Assert($ok,$message){if(!$ok){throw $message}}
function Json($n){ConvertTo-Json -InputObject $n -Depth 100 -Compress}
function Value($n,$key){($n.parameters|Where-Object controlAddress -eq $key).value}
$before=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$after=Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8|ConvertFrom-Json
$sequence=$after.sequences.items|Where-Object niceName -eq Chute
$first=$sequence.layers.items|Where-Object shortName -eq chuteMorph
$end=$sequence.layers.items|Where-Object shortName -eq chuteEndMorph
$key=$end.containers.automation.items|Where-Object shortName -eq phaseStart
Assert (@($key).Count -eq 1) 'Missing stable first-key address'
foreach($layer in @($first,$end)){
    $original=($before.sequences.items|Where-Object niceName -eq Chute).layers.items|Where-Object niceName -eq $layer.niceName
    # User edits to timing/easing must survive exactly (ignore added address).
    $keys=$layer.containers.automation.items
    foreach($k in $keys){if($k.shortName -eq 'phaseStart'){$k.PSObject.Properties.Remove('shortName')}}
    Assert ((Json $keys) -ceq (Json $original.containers.automation.items)) 'User curve edits changed'
    if($layer -eq $end){$key|Add-Member -NotePropertyName shortName -NotePropertyValue phaseStart -Force}
    Assert ((Value $layer '/sendOnStop') -eq $false) 'Stopping Chute must preserve current force values'
    $gate=$layer.containers.mapping.filters.items|Where-Object niceName -eq 'Follow Chute End first key'
    Assert (@($gate).Count -eq 1) 'Missing dynamic phase gate'
    $ref=$gate.conditions.items[0].comparator.parameters|Where-Object controlAddress -eq /reference
    Assert ($ref.controlMode -eq 2) 'Phase boundary is still a fixed number'
    Assert ($ref.reference.value -eq '/sequences/chute/layers/chuteEndMorph/automation/phaseStart/position') 'Phase boundary is not linked to End first key'
}
# Exercise the declarative phase handoff after moving the key repeatedly,
# including backwards seeks and an overlapping pair of curves.
$originalPosition=Value $key '/position'
foreach($position in @(2,5.3,8,12)){
    ($key.parameters|Where-Object controlAddress -eq /position).value=$position
    foreach($time in @(0,1.9,2,5.3,8,12,15,30,4,0)){
        $boundary=Value $key '/position'
        $writers=0
        foreach($layer in @($first,$end)){
            $comparator=$layer.containers.mapping.filters.items[0].conditions.items[0].comparator
            $op=Value $comparator '/comparisonFunction'
            if(($op -eq '<' -and $time -lt $boundary) -or ($op -eq '>=' -and $time -ge $boundary)){$writers++}
        }
        Assert ($writers -eq 1) "Conflicting or missing morph phase at $time with moved key $position"
    }
}
($key.parameters|Where-Object controlAddress -eq /position).value=$originalPosition
$force=$after.customVariables.items|Where-Object niceName -eq 'Force 2'
$release=$force.presets.items|Where-Object niceName -eq 'Transition Release'
foreach($field in @('intensity','linearIntensity')){
    Assert ((Value $release.values.containers.$field '/mode') -eq 'Interpolate') "Missing release of $field"
    Assert ((Value $release.values.containers.$field ('/'+$field)) -eq 0) "Release must end at zero: $field"
}
foreach($field in @('count','rotation','linearDirection')){Assert ((Value $release.values.containers.$field '/mode') -eq 'None') "Release changes $field"}
$actions=@(($after.states.items|Where-Object niceName -eq Presets).processors.items)+@($after.sequences.items.layers.items.triggers.items)
$releases=0
foreach($action in $actions){
    foreach($c in $action.consequences.items|Where-Object {(Value $_.command '/targetPreset') -eq '/force2/presets/transitionRelease'}){
        $releases++
        Assert ((Value $c.command.containers.interpolationCurve '/enabled') -eq $true) 'Force2 release lacks eased curve'
        $easing=$c.command.containers.interpolationCurve.items[0].containers.easing
        Assert ((Value $easing '/anchor1')[1] -eq 0 -and (Value $easing '/anchor2')[1] -eq 0) 'Release endpoints have nonzero slope'
    }
}
Assert ($releases -gt 3) 'Missing release routes'
foreach($action in @((($after.states.items|Where-Object niceName -eq Presets).processors.items|Where-Object niceName -eq Tourbillon),($after.sequences.items|Where-Object niceName -eq Tourbillon).layers.items.triggers.items[0])){
    Assert (@($action.consequences.items|Where-Object {(Value $_.command '/targetPreset') -eq '/force2/presets/tourbillon'}).Count -eq 0) 'Tourbillon still cuts dancer count'
    Assert (@($action.consequences.items|Where-Object {(Value $_.command '/targetPreset') -eq '/force2/presets/transitionRelease'}).Count -eq 1) 'Tourbillon must release outgoing Force2'
}
# All stored scene presets stay exactly as saved; only Force2 release changes.
foreach($group in $before.customVariables.items){
    $g=$after.customVariables.items|Where-Object niceName -eq $group.niceName
    foreach($preset in $group.presets.items){
        if($group.niceName -eq 'Force 2' -and $preset.niceName -eq 'Transition Release'){continue}
        Assert ((Json $preset) -ceq (Json ($g.presets.items|Where-Object niceName -eq $preset.niceName))) "Stored scene preset changed: $($group.niceName) / $($preset.niceName)"
    }
}
foreach($name in @('modules','dashboardManager')){Assert ((Json $before.$name) -ceq (Json $after.$name)) "Unrelated $name changed"}
'CHUTE_FLEXIBLE_PASS: saved timing/easing preserved; movable first-key boundary; one writer across moved boundaries/seeks; no stop resend; global/linear eased release; no Tourbillon count cut; scene presets/modules/dashboards preserved.'
