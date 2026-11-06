param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$sourceFull=(Resolve-Path -LiteralPath $SourcePath).Path
$outputFull=[IO.Path]::GetFullPath($OutputPath)
if($sourceFull -eq $outputFull){throw 'Use a separate output file.'}
$p=[IO.File]::ReadAllText($sourceFull)|ConvertFrom-Json
function Copy-Node($n){$n|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json}
function Put($n,[string]$key,$value){$n|Add-Member -NotePropertyName $key -NotePropertyValue $value -Force}
function Param([string]$key,$value){[pscustomobject]@{controlAddress=$key;value=$value}}
function CV([string]$key){'/customVariables/kinect/variables/'+$key+'/'+$key}
function Set-Parameter($n,[string]$key,$value){
    $param=$n.parameters|Where-Object controlAddress -eq $key
    if($param){$param.value=$value}else{Put $n 'parameters' (@($n.parameters|Where-Object{$null -ne $_})+@((Param $key $value)))}
}
function Condition([string]$address,$reference,[string]$comparison='='){
    [pscustomobject]@{niceName='From Input Value';type='From Input Value';parameters=@((Param '/inputValue' $address));comparator=[pscustomobject]@{parameters=@((Param '/comparisonFunction' $comparison),(Param '/reference' $reference));hideInEditor=$true}}
}
function Command([string]$target,$value,[string]$operator='Equals'){
    [pscustomobject]@{niceName='Consequence';type='Consequence';commandModule='generic';commandPath='';commandType='Set Parameter Value';command=[pscustomobject]@{parameters=@((Param '/target' $target),(Param '/component' 'All'),(Param '/operator' $operator),(Param '/value' $value));paramLinks=[pscustomobject]@{}}}
}
function Select-Dashboard([string]$name){
    [pscustomobject]@{niceName='Show '+$name;type='Consequence';commandModule='generic';commandPath='';commandType='Select Dashboard';command=[pscustomobject]@{parameters=@((Param '/dashboard' ('/'+$name)),(Param '/setInClients' $true));paramLinks=[pscustomobject]@{}}}
}
$g=$p.customVariables.items|Where-Object niceName -eq Kinect
$bank=$p.states.items|Where-Object shortName -eq kinectEN16
$unity=$p.states.items|Where-Object shortName -eq kinectToUnity
$dash=$p.dashboardManager.items|Where-Object niceName -eq 'Abysses Kinect'
$abysses=$p.dashboardManager.items|Where-Object niceName -eq Abysses
if(!$g -or !$bank -or !$unity -or !$dash -or !$abysses){throw 'Expected both dashboards and Kinect control states.'}
if($g.variables.items|Where-Object niceName -eq 'Two Hand Orbs'){throw 'Performance controls already installed.'}
$bankAddress=CV 'en16KinectBank'
$brushRoot='/modules/oxipital/values/Ballet/Optical_Flow/TwoHandForceBrush/'
$newSpecs=@(@('twoHandOrbs','Two Hand Orbs','Bool Parameter',$false,0,1),@('monitorScale','Monitor Scale','Float Parameter',1.5,1,3))
foreach($spec in $newSpecs){
    $key=$spec[0]
    $v=Copy-Node ($g.variables.items|Where-Object shortName -eq $(if($spec[2] -eq 'Bool Parameter'){'controlOrbRadius'}else{'strength'}))
    $v.niceName=$spec[1];$v.shortName=$key;$v.type=$spec[2]
    $v.parameters[0].controlAddress='/'+$key;$v.parameters[0].niceName=$spec[1]
    Put $v.parameters[0] 'value' $spec[3];Put $v.parameters[0] 'default' $spec[3]
    Put $v.parameters[0] 'minValue' $spec[4];Put $v.parameters[0] 'maxValue' $spec[5]
    $g.variables.items+=@($v)
    foreach($preset in $g.presets.items){
        Put $preset.values.containers $key ([pscustomobject]@{niceName=$spec[1];owned=$true;parameters=@((Param ('/'+$key) $spec[3]))})
    }
    foreach($direction in @('out','in')){
        $templateName=if($direction -eq 'out'){'Strength -> Unity'}else{'Unity -> Strength'}
        $route=Copy-Node ($unity.processors.items|Where-Object niceName -eq $templateName)
        $route.niceName=if($direction -eq 'out'){$spec[1]+' -> Unity'}else{'Unity -> '+$spec[1]}
        $input=if($direction -eq 'out'){CV $key}else{$brushRoot+$key}
        $target=if($direction -eq 'out'){$brushRoot+$key}else{CV $key}
        Set-Parameter $route.im.items[0] '/inputValue' $input
        Set-Parameter $route.outputs.items[0].command '/target' $target
        $unity.processors.items+=@($route)
    }
    $ox=$p.modules.items|Where-Object niceName -eq Oxipital
    $cached=$ox.values.containers.Ballet.containers.Optical_Flow.containers.TwoHandForceBrush
    $cached.parameters+=@((Param ('/'+$key) $spec[3]))
    Put $ox.treeData.CONTENTS.Ballet.CONTENTS.Optical_Flow.CONTENTS.TwoHandForceBrush.CONTENTS $key ([pscustomobject]@{ACCESS=3;VALUE=@($spec[3]);TYPE=$(if($spec[2] -eq 'Bool Parameter'){'T'}else{'f'});RANGE=@([pscustomobject]@{MIN=$spec[4];MAX=$spec[5]});FULL_PATH='/Ballet/Optical_Flow/TwoHandForceBrush/'+$key;DESCRIPTION=$spec[1]})
}
# Chataigne owns the show presets; Unity stays in Current Group mode.
$index=$g.variables.items|Where-Object shortName -eq unityBrushIndex
Put $index.parameters[0] 'value' 0
Put $index.parameters[0] 'minValue' 0;Put $index.parameters[0] 'maxValue' 0
Put $index.parameters[0] 'hideInEditor' $true
foreach($preset in $g.presets.items){
    if($preset.values.containers.unityBrushIndex){$preset.values.containers.unityBrushIndex.parameters=@((Param '/unityBrushIndex' 0))}
}
$unity.processors.items=@($unity.processors.items|Where-Object{$_.niceName -notin @('Unity -> Unity Brush Index','Leap flags -> controlForcePosition','Leap flags -> controlOrbPosition')})
# Buttons and presets now write the Kinect flags directly, as corrected by the user.
foreach($number in @(2,3)){
    $key=if($number -eq 2){'sendForcesPosition'}else{'sendOrbsPosition'}
    $a=$bank.processors.items|Where-Object niceName -eq ('Push '+$number)
    Set-Parameter $a.consequences.items[0].command '/target' (CV $key)
    $widget=$dash.itemManager.items|Where-Object niceName -eq ('Push '+$number)
    Set-Parameter $widget '/target' (CV $key);$widget.controllable=CV $key;$widget.ghostAddress=CV $key
}
$mux=$bank.processors.items|Where-Object type -eq Multiplex
$physical=($mux.containers.lists.items|Where-Object niceName -eq 'EN16 Button Page 1').parameters.value
$reserved=$physical[15]
# Reserve physical 16 in both banks. Other actions must not react to the same
# held note when the bank changes; multiplex reset must also ignore this note.
function Reserve-Button($nodes){foreach($n in $nodes){
    if($n.type -eq 'Action' -and $n.conditions){
        $text=$n.conditions|ConvertTo-Json -Depth 40 -Compress
        if($text.Contains($reserved)){Set-Parameter $n '/enabled' $false}
        elseif($text.Contains('/en16ButtonPage1')){Put $n.conditions 'items' (@($n.conditions.items)+@((Condition $reserved 0)))}
    }
    if($n.processors.items){Reserve-Button $n.processors.items}
    if($n.containers.processors.items){Reserve-Button $n.containers.processors.items}
}}
Reserve-Button $p.states.items
$bank.processors.items=@($bank.processors.items|Where-Object niceName -ne 'Push 16')
$switch=[pscustomobject]@{niceName='Switch EN16 Bank';shortName='switchEN16Bank';type='Action';conditions=[pscustomobject]@{items=@((Condition $reserved 0 '>'))};consequences=[pscustomobject]@{items=@((Command $bankAddress $false 'Inverse'))};consequencesOff=[pscustomobject]@{items=@()}}
$bank.processors.items+=@($switch)
$select=[pscustomobject]@{niceName='Show Active EN16 Bank';type='Action';conditions=[pscustomobject]@{items=@((Condition $bankAddress $true))};consequences=[pscustomobject]@{items=@((Select-Dashboard 'abyssesKinect'))};consequencesOff=[pscustomobject]@{items=@((Select-Dashboard 'abysses'))}}
$bank.processors.items+=@($select)

$toggleTemplate=Copy-Node ($dash.itemManager.items|Where-Object niceName -eq 'Push 11')
function Toggle-Widget($template,[string]$name,[string]$text,[string]$target,$pos){
    $w=Copy-Node $template;$w.niceName=$name
    Set-Parameter $w '/customText' $text;Set-Parameter $w '/target' $target
    Set-Parameter $w '/viewUIPosition' $pos
    $w.ghostAddress=$target;$w.controllable=$target
    return $w
}
# Overlay remains available in CV/Unity; slot 11 now switches one/two orbs.
$push11=$bank.processors.items|Where-Object niceName -eq 'Push 11'
Set-Parameter $push11.consequences.items[0].command '/target' (CV 'twoHandOrbs')
$dash.itemManager.items=@($dash.itemManager.items|Where-Object niceName -notin @('Push 11','Push 16','Kinect Bank'))
$dash.itemManager.items+=@((Toggle-Widget $toggleTemplate 'Push 11' '11 Deux orbes' (CV 'twoHandOrbs') @(410,-140)),(Toggle-Widget $toggleTemplate 'Push 16' '16 Banque Kinect' $bankAddress @(540,-40)))
# Replace the old Leap launcher with the same switch, at physical slot 16.
$launcher=$abysses.itemManager.items|Where-Object{ @($_.parameters|Where-Object{ $_.controlAddress -eq '/customText' -and $_.value -eq 'Leap' }).Count }
if(!$launcher){throw 'Expected Leap launcher on Abysses dashboard'}
$occupied=$abysses.itemManager.items|Where-Object{ @($_.parameters|Where-Object{ $_.controlAddress -eq '/viewUIPosition' -and $_.value.Count -eq 2 -and $_.value[0] -eq 620 -and $_.value[1] -eq -40 }).Count }
foreach($w in $occupied){Set-Parameter $w '/viewUIPosition' @(520,-340)}
$abysses.itemManager.items=@($abysses.itemManager.items|Where-Object{$_.niceName -ne $launcher.niceName})
$abysses.itemManager.items+=@((Toggle-Widget $toggleTemplate 'EN16 Bank Switch' '16 Banque Kinect' $bankAddress @(620,-40)))
# Yellow controls identify the Kinect bank; the other dashboard keeps its colors.
foreach($w in $dash.itemManager.items|Where-Object niceName -like 'Rotary *'){
    $key=($w.niceName -replace ' ','').ToLowerInvariant()
    $colorTarget='/dashboards/abyssesKinect/dashboard/'+$key+'/foregroundColor'
    $select.consequences.items+=@((Command $colorTarget @(1,.82,.05,1)))
    $select.consequencesOff.items+=@((Command $colorTarget @(.45,.45,.45,1)))
    $bankValue=($g.variables.items|Where-Object shortName -eq en16KinectBank).parameters[0].value
    Set-Parameter $w '/foregroundColor' $(if($bankValue){@(1,.82,.05,1)}else{@(.45,.45,.45,1)})
    ($w.parameters|Where-Object controlAddress -eq '/foregroundColor')|ForEach-Object{Put $_ 'enabled' $true}
}
# No native Unity brush selection from the EN16: use slot 15 for monitor size.
$targetList=$mux.containers.lists.items|Where-Object niceName -eq 'Target Kinect Parameters'
$targetList.parameters[14].value=CV 'monitorScale'
($mux.containers.lists.items|Where-Object niceName -eq 'Increment Value').parameters[14].value=.05
($mux.containers.lists.items|Where-Object niceName -eq 'Range').parameters[14].value=@(1,3)
($mux.containers.lists.items|Where-Object niceName -eq 'Reset Value').parameters[14].value=1.5
$w=$dash.itemManager.items|Where-Object niceName -eq 'Rotary 15'
Set-Parameter $w '/target' (CV 'monitorScale');Set-Parameter $w '/customText' '15 Zoom moniteur'
$w.controllable=CV 'monitorScale';$w.ghostAddress=CV 'monitorScale'
[IO.File]::WriteAllText($outputFull,($p|ConvertTo-Json -Depth 100 -Compress),[Text.UTF8Encoding]::new($false))
'KINECT_PERFORMANCE_UPDATED: shared button 16, yellow bank, direct Kinect toggles, two-hand orbs and existing Chataigne show presets.'
