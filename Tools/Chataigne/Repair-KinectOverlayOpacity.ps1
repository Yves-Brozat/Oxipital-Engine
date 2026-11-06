param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$sourceFull=(Resolve-Path -LiteralPath $SourcePath).Path
$outputFull=[IO.Path]::GetFullPath($OutputPath)
if($sourceFull -eq $outputFull){throw 'Use a separate output file.'}
$p=[IO.File]::ReadAllText($sourceFull)|ConvertFrom-Json
$g=$p.customVariables.items|Where-Object niceName -eq Kinect
$v=$g.variables.items|Where-Object { $_.shortName -eq 'debugOverlayOpacity' -or $_.niceName -eq 'Overlay Opacity' }
if(@($v).Count -ne 1){throw 'Expected exactly one dashboard opacity variable.'}
$v.niceName='Debug Overlay Opacity'
$v.shortName='debugOverlayOpacity'
$v.parameters[0].niceName='Debug Overlay Opacity'
$v.parameters[0].controlAddress='/debugOverlayOpacity'
$unity=$p.states.items|Where-Object shortName -eq kinectToUnity
foreach($pair in @(@('Overlay Opacity -> Unity','Debug Overlay Opacity -> Unity'),@('Unity -> Overlay Opacity','Unity -> Debug Overlay Opacity'))){
    $route=$unity.processors.items|Where-Object niceName -eq $pair[0]
    if($route){$route.niceName=$pair[1]}
}
# Handle projects saved after Chataigne has normalized the old CV item.
$json=$p|ConvertTo-Json -Depth 100 -Compress
$json=$json.Replace('/customVariables/kinect/variables/overlayOpacity/overlayOpacity','/customVariables/kinect/variables/debugOverlayOpacity/debugOverlayOpacity')
[IO.File]::WriteAllText($outputFull,$json,[Text.UTF8Encoding]::new($false))
'KINECT_OVERLAY_OPACITY_REPAIRED: display name, inner parameter name and dashboard/encoder/Unity addresses agree.'
