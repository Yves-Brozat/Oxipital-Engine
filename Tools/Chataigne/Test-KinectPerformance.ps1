param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Assert($ok,[string]$message){if(!$ok){throw $message}}
$old=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $SourcePath))|ConvertFrom-Json
$p=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $OutputPath))|ConvertFrom-Json
$g=$p.customVariables.items|Where-Object niceName -eq Kinect
$bank=$p.states.items|Where-Object shortName -eq kinectEN16
$unity=$p.states.items|Where-Object shortName -eq kinectToUnity
$dash=$p.dashboardManager.items|Where-Object niceName -eq 'Abysses Kinect'
$abysses=$p.dashboardManager.items|Where-Object niceName -eq Abysses
Assert ($g.presets.items.Count -eq ($old.customVariables.items|Where-Object niceName -eq Kinect).presets.items.Count) 'Show preset list changed'
foreach($name in @('Presets','Preset','Conduite')){
    $a=$old.states.items|Where-Object niceName -eq $name
    if($a){$b=$p.states.items|Where-Object niceName -eq $name;Assert (($a|ConvertTo-Json -Depth 100 -Compress) -ceq ($b|ConvertTo-Json -Depth 100 -Compress)) ('Show sequence/preset actions changed: '+$name)}
}
$bankAddress='/customVariables/kinect/variables/en16KinectBank/en16KinectBank'
foreach($pair in @(@($dash,'Push 16',540,-40),@($abysses,'EN16 Bank Switch',620,-40))){
    $w=$pair[0].itemManager.items|Where-Object niceName -eq $pair[1]
    Assert (($w.parameters|Where-Object controlAddress -eq '/target').value -ceq $bankAddress) 'Dashboard bank switch target mismatch'
    $pos=($w.parameters|Where-Object controlAddress -eq '/viewUIPosition').value
    Assert ($pos[0] -eq $pair[2] -and $pos[1] -eq $pair[3]) 'Bank switch is not at slot 16'
}
$switch=$bank.processors.items|Where-Object shortName -eq switchEN16Bank
Assert ($switch.conditions.items.Count -eq 1) 'Switch must work in both banks'
$reserved=$switch.conditions.items[0].parameters[0].value
Assert ($reserved -eq '/modules/en16/values/_1_G#1') 'Wrong physical button 16'
Assert (($switch.consequences.items[0].command.parameters|Where-Object controlAddress -eq '/operator').value -eq 'Inverse') 'Bank must toggle once per press'
Assert (!$switch.consequencesOff.items.Count) 'Button release must not toggle again'
function Check-Reserved($nodes){foreach($n in $nodes){
    if($n.type -eq 'Action' -and $n.niceName -ne 'Switch EN16 Bank'){
        $text=$n.conditions|ConvertTo-Json -Depth 50 -Compress
        if($text.Contains($reserved)){
            $enabled=$n.parameters|Where-Object controlAddress -eq '/enabled'
            $excludes=$n.conditions.items|Where-Object{ ($_.parameters|Where-Object controlAddress -eq '/inputValue').value -eq $reserved -and ($_.comparator.parameters|Where-Object controlAddress -eq '/reference').value -eq 0 }
            Assert (($enabled -and $enabled.value -eq $false) -or $excludes) ('Competing button 16 action: '+$n.niceName)
        }
    }
    if($n.processors.items){Check-Reserved $n.processors.items}
    if($n.containers.processors.items){Check-Reserved $n.containers.processors.items}
}}
Check-Reserved $p.states.items
Assert (@($unity.processors.items|Where-Object niceName -like 'Leap flags ->*').Count -eq 0) 'Leap still overwrites Kinect flags'
foreach($i in @(2,3,11)){
    $key=switch($i){2{'sendForcesPosition'}3{'sendOrbsPosition'}11{'twoHandOrbs'}}
    $expected='/customVariables/kinect/variables/'+$key+'/'+$key
    $action=$bank.processors.items|Where-Object niceName -eq ('Push '+$i)
    $w=$dash.itemManager.items|Where-Object niceName -eq ('Push '+$i)
    Assert (($action.consequences.items[0].command.parameters|Where-Object controlAddress -eq '/target').value -ceq $expected) 'Physical toggle target mismatch'
    Assert ($w.controllable -ceq $expected) 'Dashboard toggle target mismatch'
}
foreach($preset in $g.presets.items){
    Assert ($null -ne $preset.values.containers.twoHandOrbs) 'Missing orb mode in existing preset'
    Assert ($preset.values.containers.unityBrushIndex.parameters[0].value -eq 0) 'Preset must keep Chataigne force parameters'
}
$show=$bank.processors.items|Where-Object niceName -eq 'Show Active EN16 Bank'
Assert ($show.consequences.items.Count -eq 17 -and $show.consequencesOff.items.Count -eq 17) 'Missing dashboard selection/color consequences'
foreach($direction in @('consequences','consequencesOff')){
    $colors=$show.PSObject.Properties[$direction].Value.items|Where-Object commandType -eq 'Set Parameter Value'
    foreach($cmd in $colors){
        $target=($cmd.command.parameters|Where-Object controlAddress -eq '/target').value
        Assert ($target -match '^/dashboards/abyssesKinect/dashboard/rotary(\d+)/foregroundColor$') 'Unknown dynamic color target'
        Assert ([int]$Matches[1] -ge 1 -and [int]$Matches[1] -le 16) 'Color targets a missing widget'
    }
}
$oldOrb=$old.customVariables.items|Where-Object niceName -eq Orb1
$newOrb=$p.customVariables.items|Where-Object niceName -eq Orb1
Assert (($oldOrb|ConvertTo-Json -Depth 100 -Compress) -ceq ($newOrb|ConvertTo-Json -Depth 100 -Compress)) 'Orb appearance presets changed'
'KINECT_PERFORMANCE_PASS: exclusive button 16, matching dashboards, Kinect-only toggles, dynamic colors, preserved show/orb presets and per-preset two-orb mode.'
