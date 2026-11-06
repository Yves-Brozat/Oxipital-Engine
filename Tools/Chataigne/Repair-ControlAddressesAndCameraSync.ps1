param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
if([IO.Path]::GetFullPath($SourcePath) -eq [IO.Path]::GetFullPath($OutputPath)){throw 'Use a separate output file.'}
$p=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
function Clone($n){$n|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json}
function Param($n,$key,$v){$a=$n.parameters|Where-Object controlAddress -eq $key;if(!$a){throw "Missing parameter $key"};$a.value=$v}
$group=$p.customVariables.items|Where-Object shortName -eq kinect
$routes=$p.states.items|Where-Object shortName -eq kinectToUnity
$template=$routes.processors.items|Where-Object niceName -eq 'Two Hand Orbs -> Unity'
$bank=$p.states.items|Where-Object shortName -eq kinectEN16
$replacements=@{}
foreach($spec in @(@('twoHandForces',8),@('singleHandAtATime',12))){
    $key=$spec[0];$index=$spec[1]
    $variable=$group.variables.items|Where-Object shortName -eq $key
    $leaf=($variable.parameters|Where-Object type -eq Boolean).controlAddress
    if(!$leaf){throw "Missing native Boolean for $key"}
    $old='/customVariables/kinect/variables/'+$key+'/'+$key
    $address='/customVariables/kinect/variables/'+$key+$leaf
    $replacements[$old]=$address
    $mapping=$routes.processors.items|Where-Object shortName -eq ($key+'ToUnity')
    if(!$mapping){throw "Missing forward mapping $key"}
    Param $mapping.im.items[0] '/inputValue' $address
    # An unresolved Unity target caused Chataigne to save an empty operator
    # and discard the mapping-value link. Rebuild from a loaded native route.
    $mapping.outputs=Clone $template.outputs
    Param $mapping.outputs.items[0].command '/target' ('/modules/oxipital/values/Ballet/Optical_Flow/TwoHandForceBrush/'+$key)
    $action=$bank.processors.items|Where-Object niceName -eq "Push $index"
    Param $action.consequences.items[0].command '/target' $address
    Param $action.consequences.items[0].command '/operator' 'Inverse'
}
# Replace only complete address strings, including dashboard ghost links.
$json=$p|ConvertTo-Json -Depth 100
foreach($old in $replacements.Keys){$json=$json.Replace(('"'+$old+'"'),('"'+$replacements[$old]+'"'))}
$p=$json|ConvertFrom-Json
$camera=$p.customVariables.items|Where-Object niceName -eq Camera
$z=$camera.variables.items|Where-Object niceName -eq 'Z Offset'
Param $z '/zOffset' 5.0
$reset=$camera.presets.items|Where-Object niceName -eq Reset
Param $reset.values.containers.zOffset '/zOffset' 5.0
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),($p|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
'REPAIRED: native control addresses, mapping links, physical toggles and camera Reset Zoffset=5.'
