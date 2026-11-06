param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Assert($ok,$message){if(!$ok){throw $message}}
function Json($n){ConvertTo-Json -InputObject $n -Depth 100 -Compress}
function Value($n,$key){($n.parameters|Where-Object controlAddress -eq $key).value}
$old=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$p=Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8|ConvertFrom-Json
Assert ((Json $p.customVariables) -ceq (Json $old.customVariables)) 'Authored variables or presets changed'
Assert ((Json $p.sequences) -ceq (Json $old.sequences)) 'Show sequences changed'
$reverse=$p.states.items|Where-Object shortName -eq unityAuthoring
Assert ((Value $reverse '/active') -eq $false) 'Live imports run outside editing mode'
Assert ($reverse.processors.items.Count -ge 100) 'Incomplete Unity feedback coverage'
$targets=@{}
foreach($mapping in $reverse.processors.items){
    $input=Value $mapping.im.items[0] '/inputValue'
    $target=Value $mapping.outputs.items[0].command '/target'
    Assert ($input.StartsWith('/modules/oxipital/values/Ballet/')) 'Feedback input is not live Unity data'
    Assert ($target -match '^/customVariables/(orb[12]|force[12])/') 'Feedback overwrites unrelated controls'
    Assert (!$targets.ContainsKey($target)) 'Duplicate import destination'
    $targets[$target]=$input
    Assert ((Value $mapping.params '/updateRate') -eq 5) 'Import rate is too high'
    Assert ($mapping.outputs.items[0].command.paramLinks.value.mappingValueIndex -eq 0) 'Missing live mapping value'
}
Assert ($targets['/customVariables/force1/variables/position/position'] -eq '/modules/oxipital/values/Ballet/Force_Groups/Force_Group_1/Transform/position') 'Missing world force position import'
Assert ($targets['/customVariables/orb1/variables/emitterShape/emitterShape'] -eq '/modules/oxipital/values/Ballet/Orb_Groups/Orb_Group_1/OrbGroup/emitterShape') 'Missing shape import'
Assert ($targets['/customVariables/orb1/variables/emitterSize/emitterSize'] -eq '/modules/oxipital/values/Ballet/Orb_Groups/Orb_Group_1/OrbGroup/emitterScale') 'Missing emitter aspect import'
foreach($action in ($p.states.items|Where-Object niceName -eq Presets).processors.items){
    $recalls=@($action.consequences.items|Where-Object {$_.commandType -eq 'Go to preset' -and (Value $_.command '/targetPreset') -match '^/(orb|force)'})
    if(!$recalls.Count){continue}
    Assert ($action.consequences.items[-1].niceName -eq 'Reapply Show Values') 'Preset does not reapply after recall'
    Assert ((Value $action.consequences.items[-1].command '/target') -eq '/modules/oxipital/parameters/setup/applyCurrentValues') 'Wrong preset resend control'
    $expected=0
    foreach($c in $recalls){$v=Value $c.command '/interpolationTime';if($v -gt $expected){$expected=$v}}
    Assert ((Value $action.consequences.items[-2].command '/value') -eq $expected) 'Final resend occurs before interpolation completes'
}
$bank=$p.states.items|Where-Object shortName -eq kinectEN16
$oldBank=$old.states.items|Where-Object shortName -eq kinectEN16
Assert ((Json @($bank.processors.items|Where-Object shortName -ne unityEditingMode)) -ceq (Json @($oldBank.processors.items))) 'Bank buttons or LED routes changed'
$unity=$p.states.items|Where-Object shortName -eq kinectToUnity
foreach($mapping in $unity.processors.items|Where-Object type -eq Mapping){
    Assert (@($mapping.filters.items|Where-Object niceName -eq 'Performance Mode').Count -eq 1) 'Kinect writes remain active during Unity editing'
}
$setup=($p.modules.items|Where-Object niceName -eq Oxipital).params.containers.setup
Assert ((Value $setup '/unityEditMode') -eq $false) 'Project defaults to authoring mode'
'SHOW_SYNC_PROJECT_PASS: live Orb/Force capture, dormant 5Hz authoring, all preset resend schedules, original presets/buttons/LEDs retained.'
