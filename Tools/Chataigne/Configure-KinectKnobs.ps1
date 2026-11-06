param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath,[Parameter(Mandatory=$true)][string]$SeedValuesPath)
$ErrorActionPreference='Stop'
if([IO.Path]::GetFullPath($SourcePath) -eq [IO.Path]::GetFullPath($OutputPath)){throw 'Use a separate output file.'}
$p=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$seeds=Get-Content -LiteralPath $SeedValuesPath -Raw|ConvertFrom-Json
function Clone($n){$n|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json}
function Put($n,$k,$v){$n|Add-Member -NotePropertyName $k -NotePropertyValue $v -Force}
function Param($n,$k,$v){$a=$n.parameters|Where-Object controlAddress -eq $k;if($a){$a.value=$v}else{Put $n parameters (@($n.parameters)+@([pscustomobject]@{controlAddress=$k;value=$v}))}}
function Address($key){'/customVariables/kinect/variables/'+$key+'/'+$key}
$g=$p.customVariables.items|Where-Object shortName -eq kinect
$routes=$p.states.items|Where-Object shortName -eq kinectToUnity
$dash=$p.dashboardManager.items|Where-Object niceName -eq 'Abysses Kinect'
$mux=($p.states.items|Where-Object shortName -eq kinectEN16).processors.items|Where-Object type -eq Multiplex
$mappingTemplate=$routes.processors.items|Where-Object niceName -eq 'Two Hand Orbs -> Unity'
if(!$g -or !$dash -or !$mux -or !$mappingTemplate){throw 'Missing Kinect configuration.'}
$specs=@(
    @('maximumHandDepth','Maximum Hand Depth','smoothingSeconds',.5,8,'OpticalFlowAzureKinectInput/maximumHandDepth'),
    @('minimumHandConfidence','Minimum Hand Confidence','forceGroupNumber',1,2,'OpticalFlowAzureKinectInput/minimumHandConfidence'),
    @('trackingTimeout','Tracking Timeout','smoothingSeconds',.1,1,'OpticalFlowAzureKinectInput/trackingTimeout'),
    @('windDrag','Wind Drag','smoothingSeconds',0,20,'OpticalFlowManager/windDrag'),
    @('windBlend','Wind Blend','smoothingSeconds',0,1,'OpticalFlowManager/windBlend'),
    @('flowOutputGain','Flow Output Gain','smoothingSeconds',0,5,'OpticalFlowProcessor/outputGain'),
    @('filterHandDepth','Filter Hand Depth','useTargetDepth',0,1,'OpticalFlowAzureKinectInput/filterHandDepth')
)
foreach($spec in $specs){
    $key=$spec[0];$label=$spec[1];$value=$seeds.$key
    if($null -eq $value){throw "Missing current Unity value $key"}
    if($g.variables.items|Where-Object shortName -eq $key){throw "Already configured: $key"}
    $cv=Clone ($g.variables.items|Where-Object shortName -eq $spec[2])
    $cv.niceName=$label;$cv.shortName=$key
    $a=$cv.parameters|Where-Object type -in 'Float','Integer','Boolean'
    $a.controlAddress='/'+$key;$a.niceName=$label;$a.value=$value;$a.default=$value
    $a.minValue=$spec[3];$a.maxValue=$spec[4]
    $g.variables.items+=@($cv)
    foreach($preset in $g.presets.items){
        $v=Clone $preset.values.containers.($spec[2])
        $v.niceName=$label;$v.parameters[0].controlAddress='/'+$key;$v.parameters[0].value=$value
        Put $preset.values.containers $key $v
    }
    $map=Clone $mappingTemplate;$map.niceName=$label+' -> Unity';Put $map shortName ($key+'ToUnity')
    Param $map.im.items[0] '/inputValue' (Address $key)
    Param $map.outputs.items[0].command '/target' ('/modules/oxipital/values/Ballet/Optical_Flow/'+$spec[5])
    # Sensor tuning remains usable when gesture interaction itself is disabled.
    $map.filters.items=@($map.filters.items|Where-Object niceName -ne 'Kinect Mode Gate')
    $routes.processors.items+=@($map)
}
$layout=@(
    @('smoothingSeconds','Smoothing Seconds',.005),@('orbRadiusMultiplier','Orb Radius Multiplier',.05),
    @('maximumHandDepth','Max Hand Depth (m)',.05),@('minimumHandConfidence','Minimum Hand Confidence',1),
    @('strength','Strength',.01),@('radiusMultiplier','Force Radius Multiplier',.01),
    @('trackingTimeout','Tracking Timeout (s)',.01),@('windDrag','Wind Intensity',.1),
    @('sizeMultiplier','Size Multiplier',.05),@('windBlend','Wind Blend',.01),
    @('flowOutputGain','Flow Output Gain',.05),@('opticalFlowStrength','Flow Strength',.5),
    @('debugOverlayOpacity','Debug Overlay Opacity',.01),@('monitorScale','Monitor Scale',.05),
    @('interactionDepth','Interaction Depth',.1),@('opticalFlowIntensity','Flow Intensity',.01)
)
foreach($i in 1..16){
    $key=$layout[$i-1][0];$label=$layout[$i-1][1];$address=Address $key
    $control=($g.variables.items|Where-Object shortName -eq $key).parameters|Where-Object type -in 'Float','Integer'
    if(@($control).Count -ne 1){throw "Ambiguous control $key"}
    foreach($listSpec in @(@('Target Kinect Parameters',$address),@('Increment Value',$layout[$i-1][2]),@('Range',@($control.minValue,$control.maxValue)),@('Reset Value',$control.default))){
        $list=$mux.containers.lists.items|Where-Object niceName -eq $listSpec[0]
        $entry=$list.parameters|Where-Object controlAddress -eq ('/#'+$i)
        if(!$entry){$entry=[pscustomobject]@{controlAddress=('/#'+$i);value=$listSpec[1]};$list.parameters+=@($entry)}else{$entry.value=$listSpec[1]}
    }
    $item=$dash.itemManager.items|Where-Object niceName -eq "Rotary $i"
    if(@($item).Count -ne 1){throw "Missing rotary $i"}
    $item.ghostAddress=$address;$item.controllable=$address
    Param $item '/target' $address;Param $item '/customText' "$i $label"
}
$toggle=Clone ($dash.itemManager.items|Where-Object niceName -eq 'Push 15')
$toggle.niceName='Hand Depth Filter';Put $toggle shortName 'handDepthFilter'
$toggle.ghostAddress=Address filterHandDepth;$toggle.controllable=Address filterHandDepth
Param $toggle '/target' (Address filterHandDepth);Param $toggle '/customText' 'Hand Depth Filter'
Param $toggle '/viewUIPosition' @(560,250);Param $toggle '/viewUISize' @(190,60)
$dash.itemManager.items+=@($toggle)
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),($p|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
'KINECT_KNOBS_CONFIGURED: requested positions, six new rotary controls, depth-filter toggle and preset values.'
