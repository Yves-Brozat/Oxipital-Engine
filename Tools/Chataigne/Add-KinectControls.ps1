param(
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
$sourceFull = (Resolve-Path -LiteralPath $SourcePath).Path
$outputFull = [IO.Path]::GetFullPath($OutputPath)
if ($sourceFull -eq $outputFull) { throw 'Use a separate output path to preserve the live session.' }
$p = [IO.File]::ReadAllText($sourceFull) | ConvertFrom-Json
if (@($p.customVariables.items | Where-Object niceName -eq 'Kinect').Count) { throw 'Kinect group already exists; refusing to duplicate routes.' }
function Copy-Node($node) { $node | ConvertTo-Json -Depth 100 -Compress | ConvertFrom-Json }
function Set-Field($node,[string]$name,$value) { $node | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force }
function Param([string]$address,$value) { [pscustomobject]@{ value=$value; controlAddress=$address } }
function CV([string]$name) { '/customVariables/kinect/variables/' + $name + '/' + $name }
function Bool-Condition([string]$address,[bool]$expected) {
    [pscustomobject]@{ niceName='From Input Value'; type='From Input Value'; parameters=@((Param '/inputValue' $address)); comparator=[pscustomobject]@{ parameters=@((Param '/reference' $expected)); hideInEditor=$true } }
}
function Gate([bool]$expected,[string]$control='kinectEnabled') {
    [pscustomobject]@{niceName='Kinect Mode Gate';type='Condition';filterParams=[pscustomobject]@{paramLinks=[pscustomobject]@{}};conditions=[pscustomobject]@{items=@((Bool-Condition (CV $control) $expected));viewOffset=@(0,0);viewZoom=1.0}}
}
function Add-Gate($mapping,[bool]$expected,[string]$control='kinectEnabled') {
    if (!$mapping.filters) { Set-Field $mapping 'filters' ([pscustomobject]@{}) }
    Set-Field $mapping.filters 'items' (@($mapping.filters.items | Where-Object { $null -ne $_ }) + @((Gate $expected $control)))
}
function Set-Command([string]$target,$value,[string]$operator='Equals',[string]$component='All') {
    [pscustomobject]@{niceName='Consequence';type='Consequence';commandModule='generic';commandPath='';commandType='Set Parameter Value';command=[pscustomobject]@{parameters=@((Param '/target' $target),(Param '/component' $component),(Param '/operator' $operator),(Param '/value' $value));paramLinks=[pscustomobject]@{}}}
}
function Map([string]$name,[string]$inputPath,[string]$targetPath,[string]$component='All') {
    $output=Set-Command $targetPath 0 'Equals' $component
    $output.type='BaseItem'
    $output.niceName='MappingOutput'
    $output.command.parameters=@($output.command.parameters|Where-Object controlAddress -ne '/value')
    $output.command.paramLinks=[pscustomobject]@{value=[pscustomobject]@{linkType=1;mappingValueIndex=0}}
    [pscustomobject]@{niceName=$name;type='Mapping';editorIsCollapsed=$true;im=[pscustomobject]@{items=@([pscustomobject]@{niceName='Input Value';type='Input Value';parameters=@((Param '/inputValue' $inputPath))});viewOffset=@(0,0);viewZoom=1.0};params=[pscustomobject]@{parameters=@((Param '/updateRate' 30),(Param '/sendOnInputChangeOnly' $true));editorIsCollapsed=$true};filters=[pscustomobject]@{items=@();viewOffset=@(0,0);viewZoom=1.0};outputs=[pscustomobject]@{items=@($output);viewOffset=@(0,0);viewZoom=1.0}}
}
$ox = @($p.modules.items | Where-Object niceName -eq 'Oxipital')
$leap = @($p.customVariables.items | Where-Object niceName -eq 'Leap Motion')
$presets = @($p.states.items | Where-Object niceName -eq 'Preset')
$encState = @($p.states.items | Where-Object niceName -eq 'EN16 -> CV')
if ($ox.Count -ne 1 -or $leap.Count -ne 1 -or $presets.Count -ne 1 -or $encState.Count -ne 1) { throw 'Expected live Oxipital, Leap Motion, Preset and EN16 -> CV objects.' }
$ox=$ox[0];$leap=$leap[0];$presets=$presets[0];$encState=$encState[0]
$unityRoot='/modules/oxipital/values/Ballet/Optical_Flow/'
$brushRoot=$unityRoot+'TwoHandForceBrush/'
$specs=@(
    @('kinectEnabled','Kinect Enabled','Boolean',$true,0,1,'', 'All'),
    @('en16Kinect','EN16 Kinect Bank','Boolean',$false,0,1,'','All'),
    @('brushEnabled','Brush Enabled','Boolean',$true,0,1,'brushEnabled','All'),
    @('controlForcePosition','Send Forces Position','Boolean',$false,0,1,'controlForcePosition','All'),
    @('controlOrbPosition','Send Orbs Position','Boolean',$true,0,1,'controlOrbPosition','All'),
    @('controlBrushParameters','Control Intensity Radius','Boolean',$true,0,1,'controlBrushParameters','All'),
    @('controlForceOrientation','Control Orientation','Boolean',$false,0,1,'controlForceOrientation','All'),
    @('controlOrbRadius','Control Orb Radius','Boolean',$false,0,1,'controlOrbRadius','All'),
    @('strength','Strength','Float',1,0,1,'strength','All'),
    @('radiusMultiplier','Radius Multiplier','Float',.5,.01,5,'radiusMultiplier','All'),
    @('sizeMultiplier','Size Multiplier','Float',1,.01,20,'sizeMultiplier','All'),
    @('orbRadiusMultiplier','Orb Radius Multiplier','Float',1,.01,20,'orbRadiusMultiplier','All'),
    @('minimumRadius','Minimum Radius','Float',.05,.01,10,'minimumRadius','All'),
    @('maximumRadius','Maximum Radius','Float',3,.01,30,'maximumRadius','All'),
    @('smoothingSeconds','Smoothing Seconds','Float',.08,0,.5,'smoothingSeconds','All'),
    @('activationFadeSeconds','Activation Fade Seconds','Float',.12,.01,1,'activationFadeSeconds','All'),
    @('forceGroupNumber','Force Group Number','Integer',1,1,16,'forceGroupNumber','All'),
    @('orbGroupNumber','Orb Group Number','Integer',1,1,16,'orbGroupNumber','All'),
    @('selectedBrush','Unity Brush Index','Integer',0,0,3,'selectedBrush','All'),
    @('orientationX','Orientation Offset X','Float',0,-180,180,'orientationOffset','X'),
    @('orientationY','Orientation Offset Y','Float',0,-180,180,'orientationOffset','Y'),
    @('orientationZ','Orientation Offset Z','Float',90,-180,180,'orientationOffset','Z'),
    @('interactionDepth','Interaction Depth','Float',10,.1,100,'interactionDepth','All'),
    @('useTargetDepth','Use Target Depth','Boolean',$true,0,1,'useTargetDepth','All'),
    @('minimumAxisDistance','Minimum Axis Distance','Float',.08,.01,1,'minimumAxisDistance','All'),
    @('showMonitor','Show Monitor','Boolean',$true,0,1,'showMonitor','All'),
    @('showHandOverlay','Show Hand Overlay','Boolean',$true,0,1,'showHandOverlay','All'),
    @('gestureIntensity','Intensity From Hand Distance','Boolean',$false,0,1,'','All'),
    @('invertGestureIntensity','Invert Gesture Intensity','Boolean',$false,0,1,'invertGestureIntensity','All')
)
$variables=@();$baseValues=@{}
foreach($spec in $specs) {
    $key=$spec[0];$name=$spec[1];$kind=$spec[2];$value=$spec[3]
    if($key -eq 'controlForcePosition') { $value=($leap.variables.items|Where-Object niceName -eq 'Send Forces Position').parameters[0].value }
    if($key -eq 'controlOrbPosition') { $value=($leap.variables.items|Where-Object niceName -eq 'Send Orbs Position').parameters[0].value }
    $baseValues[$key]=$value
    $param=[pscustomobject]@{value=$value;minValue=$spec[4];maxValue=$spec[5];default=$value;controlAddress='/'+$key;feedbackOnly=$false;type=$kind;niceName=$name;customizable=$true;removable=$false;description='Azure Kinect / TwoHandForceBrush';hideInEditor=$false}
    $type=switch($kind){'Boolean'{'Bool Parameter'}'Integer'{'Int Parameter'}default{'Float Parameter'}}
    $variables += [pscustomobject]@{niceName=$name;shortName=$key;editorIsCollapsed=$true;type=$type;parameters=@($param)}
}
$group=[pscustomobject]@{niceName='Kinect';shortName='kinect';type='CVGroup';params=[pscustomobject]@{};variables=[pscustomobject]@{items=$variables;viewOffset=@(0,0);viewZoom=1.0};presets=[pscustomobject]@{items=@();viewOffset=@(0,0);viewZoom=1.0}}
$p.customVariables.items=@($p.customVariables.items)+@($group)

# Cache the new OSCQuery component so all targets resolve before the next Sync Data.
$cached=@();$treeContents=[pscustomobject]@{}
foreach($spec in $specs|Where-Object{ $_[6] -and $_[6] -ne 'orientationOffset' }) {
    $key=$spec[6];$value=$baseValues[$spec[0]]
    $cached+=Param ('/'+$key) $value
    $type=switch($spec[2]){'Boolean'{'T'}'Integer'{'i'}default{'f'}}
    Set-Field $treeContents $key ([pscustomobject]@{ACCESS=3;VALUE=@($value);TYPE=$type;RANGE=@([pscustomobject]@{MIN=$spec[4];MAX=$spec[5]});FULL_PATH='/Ballet/Optical_Flow/TwoHandForceBrush/'+$key;DESCRIPTION=$spec[1]})
}
$cached+=Param '/orientationOffset' @(0,0,90)
$cached+=Param '/intensityMapping' 'Manual'
$cached+=Param '/remoteControlEnabled' $true
Set-Field $treeContents 'remoteControlEnabled' ([pscustomobject]@{ACCESS=3;VALUE=@($true);TYPE='T';RANGE=@($null);FULL_PATH='/Ballet/Optical_Flow/TwoHandForceBrush/remoteControlEnabled';DESCRIPTION='Remote Control Enabled'})
Set-Field $treeContents 'orientationOffset' ([pscustomobject]@{ACCESS=3;VALUE=@(0,0,90);TYPE='fff';RANGE=@($null,$null,$null);FULL_PATH='/Ballet/Optical_Flow/TwoHandForceBrush/orientationOffset';DESCRIPTION='Orientation Offset'})
Set-Field $treeContents 'intensityMapping' ([pscustomobject]@{ACCESS=3;VALUE=@('Manual');TYPE='s';RANGE=@([pscustomobject]@{VALS=@('Manual','HandDistance')});FULL_PATH='/Ballet/Optical_Flow/TwoHandForceBrush/intensityMapping';DESCRIPTION='Intensity Mapping'})
Set-Field $ox.values.containers.Ballet.containers.Optical_Flow.containers 'TwoHandForceBrush' ([pscustomobject]@{parameters=$cached;editorIsCollapsed=$true;owned=$true;niceName='TwoHandForceBrush'})
Set-Field $ox.treeData.CONTENTS.Ballet.CONTENTS.Optical_Flow.CONTENTS 'TwoHandForceBrush' ([pscustomobject]@{ACCESS=0;CONTENTS=$treeContents})

$routes=@((Map 'Kinect Enabled -> Unity component' (CV 'kinectEnabled') ($brushRoot+'remoteControlEnabled')))
($routes[0].params.parameters|Where-Object controlAddress -eq '/sendOnInputChangeOnly').value=$false
$routes[0].params.parameters+=@(Param '/sendOnOutputChangeOnly' $false)
foreach($spec in $specs|Where-Object{$_[6]}) {
    $route=Map ($spec[1]+' -> Unity') (CV $spec[0]) ($brushRoot+$spec[6]) $spec[7]
    Add-Gate $route $true
    # Poll while enabled: reconnecting Unity receives the current controls again.
    ($route.params.parameters|Where-Object controlAddress -eq '/sendOnInputChangeOnly').value=$false
    $route.params.parameters+=@(Param '/sendOnOutputChangeOnly' $false)
    $routes+=@($route)
    if($spec[7] -eq 'All' -and $spec[0] -notin @('controlForcePosition','controlOrbPosition','brushEnabled')) {
        $feedback=Map ('Unity -> '+$spec[1]) ($brushRoot+$spec[6]) (CV $spec[0])
        Add-Gate $feedback $true
        $routes+=@($feedback)
    }
}
foreach($pair in @(@('sendForcesPosition','controlForcePosition'),@('sendOrbsPosition','controlOrbPosition'))) {
    $address='/customVariables/leapMotion/variables/'+$pair[0]+'/'+$pair[0]
    $routes+=@(Map ('Leap flags -> '+$pair[1]) $address (CV $pair[1]))
}
$intensity=[pscustomobject]@{niceName='Intensity Mapping Mode';type='Action';conditions=[pscustomobject]@{items=@((Bool-Condition (CV 'gestureIntensity') $true),(Bool-Condition (CV 'kinectEnabled') $true))};consequences=[pscustomobject]@{items=@((Set-Command ($brushRoot+'intensityMapping') 'HandDistance'))};consequencesOff=[pscustomobject]@{items=@((Set-Command ($brushRoot+'intensityMapping') 'Manual'))}}
$routes+=@($intensity)
$state=[pscustomobject]@{niceName='Kinect -> Unity';shortName='kinectToUnity';type='State';parameters=@((Param '/active' $true),(Param '/viewUIPosition' @(-400,-1200)),(Param '/viewUISize' @(390,300)));processors=[pscustomobject]@{items=$routes;viewOffset=@(0,0);viewZoom=1.0}}
$p.states.items=@($p.states.items)+@($state)

# One Kinect preset per show preset. Positions inherit the existing Leap preset.
$index=0
foreach($action in $presets.processors.items) {
    if(!$action.consequences.items) { continue }
    $leapCommand=@($action.consequences.items|Where-Object{ @($_.command.parameters|Where-Object{ $_.controlAddress -eq '/targetPreset' -and $_.value -is [string] -and $_.value.StartsWith('/leapMotion/presets/') }).Count })
    if(!$leapCommand.Count) { continue }
    $command=$leapCommand[-1]
    $leapPath=($command.command.parameters|Where-Object controlAddress -eq '/targetPreset').value
    $leapKey=$leapPath.Split('/')[-1]
    $known=@{forceOrb='Force & Orb';forceOnly='Force only';orbOnly='Orb only';off='Off'}
    $leapPreset=$leap.presets.items|Where-Object niceName -eq $known[$leapKey]
    if(!$leapPreset) { throw ('Unknown Leap preset: '+$leapPath) }
    $forceFlag=[bool]$leapPreset.values.containers.sendForcesPosition.parameters[0].value
    $orbFlag=[bool]$leapPreset.values.containers.sendOrbsPosition.parameters[0].value
    $containers=[pscustomobject]@{}
    foreach($spec in $specs|Where-Object{$_[0] -notin @('kinectEnabled','en16Kinect')}) {
        $key=$spec[0];$value=$baseValues[$key]
        if($key -eq 'controlForcePosition'){$value=$forceFlag}
        if($key -eq 'controlOrbPosition'){$value=$orbFlag}
        Set-Field $containers $key ([pscustomobject]@{niceName=$spec[1];owned=$true;parameters=@((Param ('/'+$key) $value))})
    }
    $index++;$presetKey='scene'+$index.ToString('00')
    $group.presets.items+=@([pscustomobject]@{niceName=$action.niceName;shortName=$presetKey;type='MorphTarget';values=[pscustomobject]@{containers=$containers}})
    $consequence=Copy-Node $command
    $consequence.niceName='Kinect Brush Preset'
    ($consequence.command.parameters|Where-Object controlAddress -eq '/targetPreset').value='/kinect/presets/'+$presetKey
    $action.consequences.items=@($action.consequences.items)+@($consequence)
}

# Dedicated EN16 bank, copied from the existing relative rotary implementation.
$mux=$encState.processors.items|Where-Object type -eq 'Multiplex'|Select-Object -First 1
$kinectMux=Copy-Node $mux
$bankKeys=@('strength','radiusMultiplier','sizeMultiplier','orbRadiusMultiplier','orientationX','orientationY','orientationZ','smoothingSeconds','interactionDepth','maximumRadius','minimumRadius','activationFadeSeconds','forceGroupNumber','orbGroupNumber','selectedBrush','minimumAxisDistance')
$steps=@(.01,.01,.05,.05,5,5,5,.005,.1,.05,.01,.01,1,1,1,.005)
$targetList=$kinectMux.containers.lists.items|Where-Object niceName -eq 'Target Force 1'
$increments=$kinectMux.containers.lists.items|Where-Object niceName -eq 'Increment Value'
$range=$kinectMux.containers.lists.items|Where-Object niceName -eq 'Range'
$resets=$kinectMux.containers.lists.items|Where-Object niceName -eq 'Reset Value'
$resets.parameters=@()
for($i=0;$i -lt 16;$i++) {
    $key=$bankKeys[$i];$spec=$specs|Where-Object{$_[0] -eq $key}|Select-Object -First 1
    $targetList.parameters[$i].value=CV $key
    $increments.parameters[$i].value=$steps[$i]
    $range.parameters[$i].value=@($spec[4],$spec[5])
    $resets.parameters+=@(Param ('/#'+($i+1)) $baseValues[$key])
}
$kinectMux.containers.processors.items=@($kinectMux.containers.processors.items|Where-Object type -eq 'Mapping') # Push buttons keep their show/Leap actions.
foreach($mapping in $kinectMux.containers.processors.items){Add-Gate $mapping $true 'en16Kinect'}
$bankText=$kinectMux|ConvertTo-Json -Depth 100 -Compress
$bankText=$bankText.Replace('/states/en16__CV/','/states/kinectEN16/')
$kinectMux=$bankText|ConvertFrom-Json
$p.states.items+=@([pscustomobject]@{niceName='Kinect EN16';shortName='kinectEN16';type='State';parameters=@((Param '/active' $true));processors=[pscustomobject]@{items=@($kinectMux);viewOffset=@(0,0);viewZoom=1.0}})
foreach($mapping in $mux.containers.processors.items) {
    if($mapping.type -eq 'Mapping'){Add-Gate $mapping $false 'en16Kinect'}
    elseif($mapping.type -eq 'Action'){Set-Field $mapping.conditions 'items' (@($mapping.conditions.items)+@((Bool-Condition (CV 'en16Kinect') $false)))}
}

# Prevent legacy hand position writers from competing with the native Kinect controller.
foreach($legacy in $p.states.items|Where-Object{ $_.niceName -in @('Leap Motion','Leap Motion to Force1','Leap Motion to Force2','Leap OSC','Meta Quest OSC -> Oxipital') }) {
    foreach($processor in $legacy.processors.items) {
        if($processor.niceName -match 'Position|Pos to|to Pos') {
            if($processor.type -eq 'Mapping'){Add-Gate $processor $false}
            elseif($processor.type -eq 'Action' -and $processor.conditions){Set-Field $processor.conditions 'items' (@($processor.conditions.items)+@((Bool-Condition (CV 'kinectEnabled') $false)))}
        }
    }
}
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFull))|Out-Null
[IO.File]::WriteAllText($outputFull,($p|ConvertTo-Json -Depth 100 -Compress),[Text.UTF8Encoding]::new($false))
"KINECT_PROJECT_CREATED: $($variables.Count) variables, $index scene presets, $($routes.Count) OSCQuery routes, 16 encoder controls."
