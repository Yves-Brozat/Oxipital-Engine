param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Assert($ok,[string]$message){if(!$ok){throw $message}}
function Json($n){ConvertTo-Json -InputObject $n -Depth 100 -Compress}
function Value($n,$key){($n.parameters|Where-Object controlAddress -eq $key).value}
function CV($key){'/customVariables/kinect/variables/'+$key+'/'+$key}
$old=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $SourcePath))|ConvertFrom-Json
$p=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $OutputPath))|ConvertFrom-Json
$g=$p.customVariables.items|Where-Object niceName -eq Kinect
$oldGroup=$old.customVariables.items|Where-Object niceName -eq Kinect
Assert ((Json $g.presets) -ceq (Json $oldGroup.presets)) 'Kinect show presets changed'
foreach($group in $old.customVariables.items|Where-Object niceName -ne Kinect){
    Assert ((Json $group) -ceq (Json ($p.customVariables.items|Where-Object niceName -eq $group.niceName))) ('Unrelated CV group changed: '+$group.niceName)
}
foreach($v in $oldGroup.variables.items){
    Assert ((Json $v) -ceq (Json ($g.variables.items|Where-Object shortName -eq $v.shortName))) ('Existing variable changed: '+$v.niceName)
}
foreach($state in $old.states.items|Where-Object shortName -notin @('kinectEN16','kinectToUnity')){
    Assert ((Json $state) -ceq (Json ($p.states.items|Where-Object niceName -eq $state.niceName))) ('Show state changed: '+$state.niceName)
}
$unity=$p.states.items|Where-Object shortName -eq kinectToUnity
$oldUnity=$old.states.items|Where-Object shortName -eq kinectToUnity
foreach($route in $oldUnity.processors.items){
    Assert ((Json $route) -ceq (Json ($unity.processors.items|Where-Object niceName -eq $route.niceName))) ('Existing Unity route changed: '+$route.niceName)
}
$bank=$p.states.items|Where-Object shortName -eq kinectEN16
$oldBank=$old.states.items|Where-Object shortName -eq kinectEN16
Assert ((Json @($bank.processors.items|Where-Object type -ne Multiplex)) -ceq (Json @($oldBank.processors.items|Where-Object type -ne Multiplex))) 'Bank buttons or LED feedback changed'
$mux=$bank.processors.items|Where-Object type -eq Multiplex
$oldMux=$oldBank.processors.items|Where-Object type -eq Multiplex
Assert ((Json $mux.containers.processors) -ceq (Json $oldMux.containers.processors)) 'Rotary bank conditions or physical mappings changed'
foreach($list in $oldMux.containers.lists.items){
    $newList=$mux.containers.lists.items|Where-Object niceName -eq $list.niceName
    foreach($i in 0..15){
        if($i -in @(4,5,6) -and $list.niceName -in @('Target Kinect Parameters','Increment Value','Range','Reset Value')){continue}
        Assert ((Json $list.parameters[$i]) -ceq (Json $newList.parameters[$i])) ('Unexpected EN16 list change: '+$list.niceName+' slot '+($i+1))
    }
}
$dash=$p.dashboardManager.items|Where-Object niceName -eq 'Abysses Kinect'
$oldDash=$old.dashboardManager.items|Where-Object niceName -eq 'Abysses Kinect'
Assert ($dash.itemManager.items.Count -eq $oldDash.itemManager.items.Count+3) 'Expected three extra mouse controls'
foreach($i in 0..2){
    $key=@('debugOverlayOpacity','opticalFlowIntensity','opticalFlowStrength')[$i]
    $unityPath=@('OpticalFlowDebugView/overlayOpacity','OpticalFlowManager/intensity','OpticalFlowManager/strength')[$i]
    $v=$g.variables.items|Where-Object shortName -eq $key
    Assert ($null -ne $v) ('Missing CV: '+$key)
    # Chataigne rebuilds the inner CV container from niceName when loading.
    # A matching serialized shortName alone does not make its target resolvable.
    $derived=$v.niceName -replace '[^\p{L}\p{Nd}_]',''
    $derived=$derived.Substring(0,1).ToLowerInvariant()+$derived.Substring(1)
    Assert ($derived -ceq $key -and $v.parameters[0].controlAddress -ceq ('/'+$key)) ('CV address changes on Chataigne load: '+$v.niceName)
    $widget=$dash.itemManager.items|Where-Object niceName -eq ('Rotary '+($i+5))
    Assert ((Value $widget '/target') -ceq (CV $key) -and $widget.controllable -ceq (CV $key) -and $widget.ghostAddress -ceq (CV $key)) 'Flow widget addresses disagree'
    $list=$mux.containers.lists.items|Where-Object niceName -eq 'Target Kinect Parameters'
    Assert ($list.parameters[$i+4].value -ceq (CV $key)) 'Physical EN16 target mismatch'
    $forward=$unity.processors.items|Where-Object niceName -eq ($v.niceName+' -> Unity')
    $reverse=$unity.processors.items|Where-Object niceName -eq ('Unity -> '+$v.niceName)
    $address='/modules/oxipital/values/Ballet/Optical_Flow/'+$unityPath
    Assert ((Value $forward.im.items[0] '/inputValue') -ceq (CV $key)) 'Wrong outbound input'
    Assert ((Value $forward.outputs.items[0].command '/target') -ceq $address) 'Wrong Unity OSCQuery target'
    Assert ((Value $reverse.im.items[0] '/inputValue') -ceq $address) 'Wrong return route input'
    Assert ((Value $reverse.outputs.items[0].command '/target') -ceq (CV $key)) 'Wrong return route target'
    Assert ($forward.filters.items.Count -eq 0 -and $reverse.filters.items.Count -eq 0) 'Optical flow incorrectly depends on hand brush activation'
    $rotation=$dash.itemManager.items|Where-Object niceName -eq ('Mouse Orientation '+@('X','Y','Z')[$i])
    $original=$oldDash.itemManager.items|Where-Object niceName -eq ('Rotary '+($i+5))
    Assert ($rotation.controllable -ceq $original.controllable -and (Value $rotation '/target') -ceq (Value $original '/target')) 'Mouse rotation lost original variable'
    $pos=Value $rotation '/viewUIPosition'
    Assert ($pos[0] -eq 700 -and $pos[1] -eq (-340+100*$i)) 'Mouse rotation is not in sidebar'
}
foreach($widget in $oldDash.itemManager.items){
    $newWidget=$dash.itemManager.items|Where-Object niceName -eq $widget.niceName
    Assert ((Json (Value $widget '/viewUIPosition')) -ceq (Json (Value $newWidget '/viewUIPosition'))) ('Original dashboard control moved: '+$widget.niceName)
}
foreach($i in 1..16){
    $text=Value ($dash.itemManager.items|Where-Object niceName -eq ('Push '+$i)) '/customText'
    Assert ($text -notmatch 'Pinceau|Profondeur|Groupe|Banque|orbes|geste|actif|Moniteur') 'French button label remains'
}
Assert ((Value ($dash.itemManager.items|Where-Object niceName -eq 'Push 9') '/customText') -ceq '9 Use Target Depth') 'Use Target Depth label mismatch'
'KINECT_OPTICAL_FLOW_PASS: English labels, EN16 5/6/7, bidirectional flow routes, mouse rotations, preserved presets, bank actions and LED feedback.'
