param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$sourceFull=(Resolve-Path -LiteralPath $SourcePath).Path
$outputFull=[IO.Path]::GetFullPath($OutputPath)
if($sourceFull -eq $outputFull){throw 'Use a separate output file.'}
$p=[IO.File]::ReadAllText($sourceFull)|ConvertFrom-Json
function Copy-Node($n){$n|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json}
function Put($n,[string]$key,$value){$n|Add-Member -NotePropertyName $key -NotePropertyValue $value -Force}
function Set-Parameter($n,[string]$key,$value){
    $param=$n.parameters|Where-Object controlAddress -eq $key
    if($param){$param.value=$value}else{Put $n 'parameters' (@($n.parameters)+@([pscustomobject]@{controlAddress=$key;value=$value}))}
}
function CV([string]$key){'/customVariables/kinect/variables/'+$key+'/'+$key}
$g=$p.customVariables.items|Where-Object niceName -eq Kinect
$bank=$p.states.items|Where-Object shortName -eq kinectEN16
$unity=$p.states.items|Where-Object shortName -eq kinectToUnity
$dash=$p.dashboardManager.items|Where-Object niceName -eq 'Abysses Kinect'
$ox=$p.modules.items|Where-Object niceName -eq Oxipital
if(!$g -or !$bank -or !$unity -or !$dash -or !$ox){throw 'Expected Kinect Performance controls and dashboard.'}
if($g.variables.items|Where-Object shortName -eq debugOverlayOpacity){throw 'Optical flow dashboard already installed.'}
$mux=$bank.processors.items|Where-Object type -eq Multiplex
$specs=@(
    @('debugOverlayOpacity','Debug Overlay Opacity','OpticalFlowDebugView','overlayOpacity',0,1,.01,.25),
    @('opticalFlowIntensity','Optical Flow Intensity','OpticalFlowManager','intensity',0,1,.01,1),
    @('opticalFlowStrength','Optical Flow Strength','OpticalFlowManager','strength',0,50,.5,10)
)
foreach($i in 0..2){
    $spec=$specs[$i];$key=$spec[0];$slot=5+$i
    $node=$ox.treeData.CONTENTS.Ballet.CONTENTS.Optical_Flow.CONTENTS.PSObject.Properties[$spec[2]].Value.CONTENTS.PSObject.Properties[$spec[3]].Value
    if(!$node){throw ('Sync Data first: missing Unity OSCQuery property '+$spec[2]+'/'+$spec[3])}
    $initial=$node.VALUE[0]
    $variable=Copy-Node ($g.variables.items|Where-Object shortName -eq strength)
    $variable.niceName=$spec[1];$variable.shortName=$key
    $param=$variable.parameters[0];$param.controlAddress='/'+$key;$param.niceName=$spec[1]
    Put $param value $initial;Put $param default $spec[7];Put $param minValue $spec[4];Put $param maxValue $spec[5]
    Put $param description ('Optical Flow / '+$spec[2]+' / '+$spec[3]+' (global, outside show presets)')
    $g.variables.items+=@($variable)
    $unityAddress='/modules/oxipital/values/Ballet/Optical_Flow/'+$spec[2]+'/'+$spec[3]
    foreach($direction in @('out','in')){
        $template=if($direction -eq 'out'){'Strength -> Unity'}else{'Unity -> Strength'}
        $route=Copy-Node ($unity.processors.items|Where-Object niceName -eq $template)
        $route.niceName=if($direction -eq 'out'){$spec[1]+' -> Unity'}else{'Unity -> '+$spec[1]}
        # Flow and debug image can be used even when the hand brush is disabled.
        $route.filters.items=@()
        $input=if($direction -eq 'out'){CV $key}else{$unityAddress}
        $target=if($direction -eq 'out'){$unityAddress}else{CV $key}
        Set-Parameter $route.im.items[0] '/inputValue' $input
        Set-Parameter $route.outputs.items[0].command '/target' $target
        $unity.processors.items+=@($route)
    }
    # Keep the saved OSCQuery value cache consistent with its existing tree.
    $cache=$ox.values.containers.Ballet.containers.Optical_Flow.containers.PSObject.Properties[$spec[2]].Value
    Set-Parameter $cache ('/'+$spec[3]) $initial
    ($mux.containers.lists.items|Where-Object niceName -eq 'Target Kinect Parameters').parameters[$slot-1].value=CV $key
    ($mux.containers.lists.items|Where-Object niceName -eq 'Increment Value').parameters[$slot-1].value=$spec[6]
    ($mux.containers.lists.items|Where-Object niceName -eq 'Range').parameters[$slot-1].value=@($spec[4],$spec[5])
    ($mux.containers.lists.items|Where-Object niceName -eq 'Reset Value').parameters[$slot-1].value=$spec[7]
    $widget=$dash.itemManager.items|Where-Object niceName -eq ('Rotary '+$slot)
    $rotation=Copy-Node $widget
    $rotation.niceName='Mouse Orientation '+@('X','Y','Z')[$i]
    Put $rotation shortName ('mouseOrientation'+@('X','Y','Z')[$i])
    Set-Parameter $rotation '/customText' ('Orientation Offset '+@('X','Y','Z')[$i])
    Set-Parameter $rotation '/viewUIPosition' @(700,(-340+100*$i))
    Set-Parameter $rotation '/viewUISize' @(190,85)
    Set-Parameter $rotation '/textSize' 13
    $dash.itemManager.items+=@($rotation)
    Set-Parameter $widget '/target' (CV $key)
    $widget.controllable=CV $key;$widget.ghostAddress=CV $key
}
$rotaryNames=@('Strength','Radius Multiplier','Size Multiplier','Orb Radius Multiplier',
    'Debug: Overlay Opacity','Flow: Intensity','Flow: Strength','Smoothing Seconds',
    'Interaction Depth','Maximum Radius','Minimum Radius','Activation Fade Seconds',
    'Force Group Number','Orb Group Number','Monitor Scale','Minimum Axis Distance')
$buttonNames=@('Brush Enabled','Control Force Position','Control Orb Position','Control Brush Parameters',
    'Control Force Orientation','Control Orb Radius','Intensity Mapping: Hand Distance','Invert Gesture Intensity',
    'Use Target Depth','Show Monitor','Two Hand Orbs','Remote Control Enabled','Sync Data','Reset Camera','Universe','EN16 Kinect Bank')
foreach($i in 1..16){
    foreach($pair in @(@('Rotary ',$rotaryNames),@('Push ',$buttonNames))){
        $widget=$dash.itemManager.items|Where-Object niceName -eq ($pair[0]+$i)
        if(!$widget){throw ('Missing dashboard control '+$pair[0]+$i)}
        Set-Parameter $widget '/customText' ($i.ToString()+' '+$pair[1][$i-1])
        Set-Parameter $widget '/textSize' 12
    }
}
Set-Parameter ($dash.itemManager.items|Where-Object niceName -eq 'Kinect Source') '/customText' 'Remote Control Enabled'
$abysses=$p.dashboardManager.items|Where-Object niceName -eq Abysses
Set-Parameter ($abysses.itemManager.items|Where-Object niceName -eq 'EN16 Bank Switch') '/customText' '16 EN16 Kinect Bank'
[IO.File]::WriteAllText($outputFull,($p|ConvertTo-Json -Depth 100 -Compress),[Text.UTF8Encoding]::new($false))
'KINECT_OPTICAL_FLOW_UPDATED: English labels, mouse orientation sidebar, EN16 5/6/7 = debug opacity / flow intensity / flow strength.'
