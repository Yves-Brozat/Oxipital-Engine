param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$p=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
function Clone($n){ConvertTo-Json -InputObject $n -Depth 100 -Compress|ConvertFrom-Json}
function Value($n,$key){($n.parameters|Where-Object controlAddress -eq $key).value}
function Set-Value($n,$key,$value){$a=$n.parameters|Where-Object controlAddress -eq $key;if(!$a){throw "Missing $key"};$a.value=$value}
function CV($key){'/customVariables/kinect/variables/'+$key+'/'+$key}
$dash=$p.dashboardManager.items|Where-Object niceName -eq 'Abysses Kinect'
$abysses=$p.dashboardManager.items|Where-Object niceName -eq Abysses
$state=$p.states.items|Where-Object shortName -eq kinectEN16
$widgets=@{};$actions=@{}
foreach($i in 1..16){$widgets[$i]=Clone ($dash.itemManager.items|Where-Object niceName -eq "Push $i");$actions[$i]=Clone ($state.processors.items|Where-Object niceName -eq "Push $i")}
# Move the six existing controls, preserving the other ten slots.
$moves=@(@(4,16,'Bank'),@(8,9,'Reset'),@(9,4,'Two hands orbs'),@(10,8,'Two hands forces'),@(12,10,'Sync'),@(16,12,'Single Hand only'))
foreach($spec in $moves){
    $slot=[int]$spec[0];$old=[int]$spec[1]
    $widget=Clone $widgets[$old]
    if(!$widget){throw "Missing widget $old"}
    $widget.niceName="Push $slot"
    if($widget.PSObject.Properties['shortName']){$widget.shortName="push$slot"}
    Set-Value $widget '/viewUIPosition' (Value $widgets[$slot] '/viewUIPosition')
    Set-Value $widget '/customText' ("$slot "+$spec[2])
    $dash.itemManager.items=@($dash.itemManager.items|ForEach-Object {if($_.niceName -eq "Push $slot"){$widget}else{$_}})
    if($slot -eq 4){continue}
    $action=Clone $actions[$old]
    if(!$action){throw "Missing action $old"}
    $action.niceName="Push $slot"
    if($action.PSObject.Properties['shortName']){$action.shortName="push$slot"}
    $condition=$action.conditions.items|Where-Object {(Value $_ '/inputValue') -eq (CV "en16KinectButton$old")}
    Set-Value $condition '/inputValue' (CV "en16KinectButton$slot")
    $state.processors.items=@($state.processors.items|Where-Object niceName -ne "Push $slot")+@($action)
}
$state.processors.items=@($state.processors.items|Where-Object niceName -ne 'Push 4')
$explosion=$abysses.itemManager.items|Where-Object {(Value $_ '/target') -eq '/states/effects/processors/explosion/trigger'}
$bankWidget=$abysses.itemManager.items|Where-Object {(Value $_ '/target') -eq (CV en16KinectBank)}
$pos=Value $explosion '/viewUIPosition'
Set-Value $explosion '/viewUIPosition' (Value $bankWidget '/viewUIPosition')
Set-Value $bankWidget '/viewUIPosition' $pos
Set-Value $bankWidget '/customText' '4 EN16 Kinect Bank'
# Reserve physical slot 4 for the bank selector and release slot 16 to each bank.
$switch=$state.processors.items|Where-Object niceName -eq 'Switch EN16 Bank'
$oldPhysical=Value $switch.conditions.items[0] '/inputValue'
$mux=$state.processors.items|Where-Object type -eq Multiplex
$physical=$mux.containers.lists.items|Where-Object shortName -eq en16PhysicalButtons
$newPhysical=$physical.parameters[3].value
if($newPhysical -notlike '/modules/en16/*'){throw 'Expected original physical slot 4'}
Set-Value $switch.conditions.items[0] '/inputValue' $newPhysical
foreach($side in @('Abysses','Kinect')){
    $owner=if($side -eq 'Kinect'){$state}else{$p.states.items|Where-Object niceName -eq 'EN16 -> Oxipital CV'}
    $m=$owner.processors.items|Where-Object type -eq Multiplex
    $list=$m.containers.lists.items|Where-Object shortName -eq en16PhysicalButtons
    $list.parameters[3].value=CV "en16${side}Button4"
    $list.parameters[15].value=$oldPhysical
}
function Move-Explosion($nodes){foreach($n in $nodes){
    if($n.type -eq 'Action' -and $n.niceName -eq 'Explosion'){
        foreach($c in $n.conditions.items){if((Value $c '/inputValue') -eq (CV en16AbyssesButton4)){Set-Value $c '/inputValue' (CV en16AbyssesButton16)}}
    }
    if($n.processors.items){Move-Explosion $n.processors.items}
    if($n.containers.processors.items){Move-Explosion $n.containers.processors.items}
    if($n.states.items){Move-Explosion $n.states.items}
}}
Move-Explosion $p.states.items
# Ensure show data and the exact requested targets survive the transformation.
foreach($spec in $moves){
    $w=$dash.itemManager.items|Where-Object niceName -eq ('Push '+$spec[0])
    if((Value $w '/target') -ne (Value $widgets[[int]$spec[1]] '/target')){throw 'Dashboard target mismatch'}
    if($spec[0] -ne 4){$a=$state.processors.items|Where-Object niceName -eq ('Push '+$spec[0]);if((Value $a.consequences.items[0].command '/target') -ne (Value $w '/target')){throw 'Hardware target mismatch'}}
}
$original=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
foreach($key in @('customVariables','modules','sequences')){if((ConvertTo-Json -InputObject $p.$key -Depth 100 -Compress) -cne (ConvertTo-Json -InputObject $original.$key -Depth 100 -Compress)){throw "Unrelated data changed: $key"}}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),($p|ConvertTo-Json -Depth 100 -Compress),[Text.UTF8Encoding]::new($false))
'DASHBOARD_ORDER_PASS: requested dashboard targets and hardware actions agree; presets, modules and sequences preserved.'
