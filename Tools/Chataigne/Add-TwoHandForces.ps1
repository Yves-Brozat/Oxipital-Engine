param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
if([IO.Path]::GetFullPath($SourcePath) -eq [IO.Path]::GetFullPath($OutputPath)){throw 'Use a separate output file.'}
$p=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
function Clone($n){$n|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json}
function Put($n,$k,$v){$n|Add-Member -NotePropertyName $k -NotePropertyValue $v -Force}
function Param($n,$k,$v){$a=$n.parameters|Where-Object controlAddress -eq $k;if($a){$a.value=$v}else{Put $n parameters (@($n.parameters)+@([pscustomobject]@{controlAddress=$k;value=$v}))}}
$nativeLeaves=@{twoHandForces='twoHandsForces';singleHandAtATime='singleHandOnly'}
function Address($key){'/customVariables/kinect/variables/'+$key+'/'+$nativeLeaves[$key]}
$g=$p.customVariables.items|Where-Object shortName -eq kinect
$template=$g.variables.items|Where-Object shortName -eq twoHandOrbs
$toUnity=$p.states.items|Where-Object shortName -eq kinectToUnity
$forward=$toUnity.processors.items|Where-Object niceName -eq 'Two Hand Orbs -> Unity'
$bank=$p.states.items|Where-Object shortName -eq kinectEN16
$dash=$p.dashboardManager.items|Where-Object niceName -eq 'Abysses Kinect'
if(!$template -or !$forward -or !$bank -or !$dash){throw 'Expected Kinect variables, OSC mapping, bank and dashboard.'}
foreach($spec in @(@('twoHandForces','Two Hands Forces'),@('singleHandAtATime','Single Hand Only'))){
    $key=$spec[0];$label=$spec[1]
    if($g.variables.items|Where-Object shortName -eq $key){throw 'Two-hand force controls already installed.'}
    $cv=Clone $template;$cv.niceName=$label;$cv.shortName=$key
    $param=$cv.parameters|Where-Object controlAddress -eq '/twoHandOrbs'
    $param.controlAddress='/'+$nativeLeaves[$key];$param.niceName=$label;$param.value=$false
    if($param.PSObject.Properties['default']){$param.default=$false}
    $g.variables.items+=@($cv)
    foreach($preset in $g.presets.items){
        $value=Clone $preset.values.containers.twoHandOrbs
        if(!$value){throw 'Missing two-hand value in preset'}
        $value.niceName=$label;$value.parameters[0].controlAddress='/'+$nativeLeaves[$key];$value.parameters[0].value=$false
        Put $preset.values.containers $nativeLeaves[$key] $value
    }
    $map=Clone $forward;$map.niceName=$label+' -> Unity';Put $map shortName ($key+'ToUnity')
    Param $map.im.items[0] '/inputValue' (Address $key)
    Param $map.outputs.items[0].command '/target' ('/modules/oxipital/values/Ballet/Optical_Flow/TwoHandForceBrush/'+$key)
    $toUnity.processors.items+=@($map)
}
foreach($spec in @(@(12,'singleHandAtATime','12 Single Hand Only'),@(14,'twoHandForces','14 Two Hands Forces'))){
    $index=$spec[0];$key=$spec[1];$label=$spec[2]
    $button=$dash.itemManager.items|Where-Object niceName -eq "Push $index"
    if(@($button).Count -ne 1){throw "Missing dashboard button $index"}
    $button.type='DashboardParameterItem';$button.ghostAddress=Address $key;$button.controllable=Address $key
    Param $button '/target' (Address $key);Param $button '/customText' $label;Param $button '/style' 'Toggle Button'
    $action=$bank.processors.items|Where-Object niceName -eq "Push $index"
    $toggle=Clone ($bank.processors.items|Where-Object niceName -eq 'Push 4').consequences.items[0]
    Param $toggle.command '/target' (Address $key)
    $action.consequences.items=@($toggle)
}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),($p|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
'TWO_HAND_FORCES_CONFIGURED: buttons 12/14, independent OSC controls, preset defaults off.'
