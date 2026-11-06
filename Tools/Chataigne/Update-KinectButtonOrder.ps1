param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$sourceFull=(Resolve-Path -LiteralPath $SourcePath).Path
$outputFull=[IO.Path]::GetFullPath($OutputPath)
if($sourceFull -eq $outputFull){throw 'Use a separate copy to keep the saved show.'}
$p=[IO.File]::ReadAllText($sourceFull)|ConvertFrom-Json
function Clone($node){$node|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json}
function Put-Field($node,$key,$value){$node|Add-Member -NotePropertyName $key -NotePropertyValue $value -Force}
function Param($node,$key,$value){$v=$node.parameters|Where-Object controlAddress -eq $key;if($v){$v.value=$value}else{$node.parameters+=@([pscustomobject]@{controlAddress=$key;value=$value})}}
function CV($key){'/customVariables/kinect/variables/'+$key+'/'+$key}
$group=$p.customVariables.items|Where-Object niceName -eq Kinect
$state=$p.states.items|Where-Object shortName -eq kinectEN16
$unity=$p.states.items|Where-Object shortName -eq kinectToUnity
$dash=$p.dashboardManager.items|Where-Object niceName -eq 'Abysses Kinect'
if(!$group -or !$state -or !$unity -or !$dash){throw 'Expected the Kinect Performance project.'}
if($group.variables.items|Where-Object shortName -eq controlOrbOrientation){throw 'Orb orientation is already installed.'}
$variable=Clone ($group.variables.items|Where-Object shortName -eq controlOrbRadius)
$variable.niceName='Control Orb Orientation';$variable.shortName='controlOrbOrientation'
$variable.parameters[0].niceName=$variable.niceName;$variable.parameters[0].controlAddress='/controlOrbOrientation'
$variable.parameters[0].value=$false;$variable.parameters[0].default=$false
$group.variables.items+=@($variable)
foreach($preset in $group.presets.items){
    if(!$preset.values.containers){continue}
    Put-Field $preset.values.containers controlOrbOrientation ([pscustomobject]@{
        parameters=@([pscustomobject]@{controlAddress='/controlOrbOrientation';value=$false})
        owned=$true;niceName='Control Orb Orientation'
    })
}
foreach($name in @('Control Orb Radius -> Unity','Unity -> Control Orb Radius')){
    $route=$unity.processors.items|Where-Object niceName -eq $name
    if(!$route){throw ('Missing route '+$name)}
    $new=$route|ConvertTo-Json -Depth 100 -Compress
    $unity.processors.items+=@(($new.Replace('controlOrbRadius','controlOrbOrientation').Replace('Control Orb Radius','Control Orb Orientation')|ConvertFrom-Json))
}
$ox=$p.modules.items|Where-Object niceName -eq Oxipital
$cache=$ox.values.containers.Ballet.containers.Optical_Flow.containers.TwoHandForceBrush
$cached=Clone ($cache.parameters|Where-Object controlAddress -eq '/controlOrbRadius')
$cached.controlAddress='/controlOrbOrientation';$cached.value=$false;$cache.parameters+=@($cached)
$contents=$ox.treeData.CONTENTS.Ballet.CONTENTS.Optical_Flow.CONTENTS.TwoHandForceBrush.CONTENTS
$tree=($contents.controlOrbRadius|ConvertTo-Json -Depth 20 -Compress).Replace('controlOrbRadius','controlOrbOrientation').Replace('Orb Radius','Orb Orientation')|ConvertFrom-Json
$tree.VALUE=@($false);Put-Field $contents controlOrbOrientation $tree

# New slot, old slot, label, exact target. Keep the existing bank event router,
# note addresses and button 16; only bank-local actions and widgets change.
$order=@(
    @(1,3,'Orb Position',(CV 'sendOrbsPosition')),
    @(2,6,'Orb Radius',(CV 'controlOrbRadius')),
    @(3,6,'Orb Orientation',(CV 'controlOrbOrientation')),
    @(4,11,'Two Hand Orbs',(CV 'twoHandOrbs')),
    @(5,2,'Force Position',(CV 'sendForcesPosition')),
    @(6,4,'Force Radius',(CV 'controlIntensityRadius')),
    @(7,5,'Force Orientation',(CV 'controlOrientation')),
    @(8,8,'Invert Gesture Intensity',(CV 'invertGestureIntensity')),
    @(9,14,'Reset','/states/initialisation/processors/resetCameraPosition/trigger'),
    @(10,13,'Sync','/states/initialisation/processors/syncData/trigger'),
    @(11,10,'Show Monitor',(CV 'showMonitor')),
    @(12,15,'Meduses','/states/presets/processors/meduse/trigger'),
    @(13,12,'Kinect Enabled',(CV 'kinectEnabled')),
    @(14,1,'Brush Enabled',(CV 'brushEnabled')),
    @(15,9,'Use Target Depth',(CV 'useTargetDepth')),
    @(16,16,'EN16 Kinect Bank',(CV 'en16KinectBank'))
)
$originalActions=@{};$originalWidgets=@{}
foreach($i in 1..16){
    $originalActions[$i]=Clone ($state.processors.items|Where-Object niceName -eq ('Push '+$i))
    $originalWidgets[$i]=Clone ($dash.itemManager.items|Where-Object niceName -eq ('Push '+$i))
}
foreach($spec in $order){
    $slot=[int]$spec[0];$oldSlot=[int]$spec[1];$label=[string]$spec[2];$target=[string]$spec[3]
    if($slot -ne 16){
        $action=Clone $originalActions[$oldSlot]
        if(!$action){throw ('Missing old button action '+$oldSlot)}
        $action.niceName='Push '+$slot
        if($action.PSObject.Properties['shortName']){$action.shortName='push'+$slot}
        $condition=$action.conditions.items|Where-Object {($_.parameters|Where-Object controlAddress -eq '/inputValue').value -eq (CV ('en16KinectButton'+$oldSlot))}
        if(!$condition){throw 'Expected bank-isolated virtual note input.'}
        Param $condition '/inputValue' (CV ('en16KinectButton'+$slot))
        Param $action.consequences.items[0].command '/target' $target
        $state.processors.items=@($state.processors.items|ForEach-Object {if($_.niceName -eq ('Push '+$slot)){$action}else{$_}})
    }
    $widget=Clone $originalWidgets[$oldSlot]
    if(!$widget){throw ('Missing old dashboard button '+$oldSlot)}
    $widget.niceName='Push '+$slot
    if($widget.PSObject.Properties['shortName']){$widget.shortName='push'+$slot}
    $position=($originalWidgets[$slot].parameters|Where-Object controlAddress -eq '/viewUIPosition').value
    Param $widget '/viewUIPosition' $position
    Param $widget '/target' $target
    Param $widget '/customText' ($slot.ToString()+' '+$label)
    Put-Field $widget ghostAddress $target;Put-Field $widget controllable $target
    $dash.itemManager.items=@($dash.itemManager.items|ForEach-Object {if($_.niceName -eq ('Push '+$slot)){$widget}else{$_}})
}
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFull))|Out-Null
[IO.File]::WriteAllText($outputFull,($p|ConvertTo-Json -Depth 100 -Compress),[Text.UTF8Encoding]::new($false))
'KINECT_BUTTON_ORDER_READY: 16 dashboard slots and 15 bank-isolated actions reordered; orb orientation routed and included in presets; bank switch unchanged.'
