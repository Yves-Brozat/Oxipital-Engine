param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$before=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$after=Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8|ConvertFrom-Json
function Check($ok,$message){if(!$ok){throw $message}}
$g=$after.customVariables.items|Where-Object shortName -eq kinect
$d=$after.dashboardManager.items|Where-Object niceName -eq 'Abysses Kinect'
$oldDash=$before.dashboardManager.items|Where-Object niceName -eq 'Abysses Kinect'
$mux=($after.states.items|Where-Object shortName -eq kinectEN16).processors.items|Where-Object type -eq Multiplex
$oldMux=($before.states.items|Where-Object shortName -eq kinectEN16).processors.items|Where-Object type -eq Multiplex
$keys=@('smoothingSeconds','orbRadiusMultiplier','maximumHandDepth','minimumHandConfidence','strength','radiusMultiplier','trackingTimeout','windDrag','sizeMultiplier','windBlend','flowOutputGain','opticalFlowStrength','debugOverlayOpacity','monitorScale','interactionDepth','opticalFlowIntensity')
foreach($i in 1..16){
    $key=$keys[$i-1];$path="/customVariables/kinect/variables/$key/$key"
    $target=($mux.containers.lists.items|Where-Object niceName -eq 'Target Kinect Parameters').parameters|Where-Object controlAddress -eq ('/#'+$i)
    $item=$d.itemManager.items|Where-Object niceName -eq "Rotary $i"
    Check ($target.value -eq $path -and $item.controllable -eq $path -and $item.ghostAddress -eq $path) "Dashboard/EN16 mismatch at $i"
    $cv=$g.variables.items|Where-Object shortName -eq $key
    Check (($cv.parameters|Where-Object type -in 'Float','Integer').controlAddress -eq ('/'+$key)) "Native leaf mismatch $key"
}
$newKeys=@('maximumHandDepth','minimumHandConfidence','trackingTimeout','windDrag','windBlend','flowOutputGain','filterHandDepth')
$routes=$after.states.items|Where-Object shortName -eq kinectToUnity
foreach($key in $newKeys){
    $route=$routes.processors.items|Where-Object shortName -eq ($key+'ToUnity')
    Check ($null -ne $route) "Missing OSC route $key"
    Check ($route.outputs.items[0].command.paramLinks.value.mappingValueIndex -eq 0) "Missing output binding $key"
    foreach($preset in $g.presets.items){
        Check ($null -ne $preset.values.containers.$key) "Missing $key in preset $($preset.niceName)"
        $preset.values.containers.PSObject.Properties.Remove($key)
    }
}
$gain=$routes.processors.items|Where-Object shortName -eq flowOutputGainToUnity
Check (($gain.outputs.items[0].command.parameters|Where-Object controlAddress -eq '/target').value -match '/OpticalFlowProcessor/outputGain$') 'Flow gain points to a display-only parameter'
$filter=$d.itemManager.items|Where-Object shortName -eq handDepthFilter
Check ($filter.controllable -eq '/customVariables/kinect/variables/filterHandDepth/filterHandDepth') 'Depth filter toggle is missing'
$g.variables.items=@($g.variables.items|Where-Object shortName -notin $newKeys)
$routes.processors.items=@($routes.processors.items|Where-Object {$_.shortName -notin @($newKeys|ForEach-Object {$_+'ToUnity'})})
$d.itemManager.items=@($d.itemManager.items|Where-Object shortName -ne handDepthFilter|ForEach-Object {if($_.niceName -match '^Rotary \d+$'){$name=$_.niceName;$oldDash.itemManager.items|Where-Object niceName -eq $name}else{$_}})
foreach($name in 'Target Kinect Parameters','Increment Value','Range','Reset Value'){
    ($mux.containers.lists.items|Where-Object niceName -eq $name).parameters=($oldMux.containers.lists.items|Where-Object niceName -eq $name).parameters
}
Check (($after|ConvertTo-Json -Depth 100 -Compress) -ceq ($before|ConvertTo-Json -Depth 100 -Compress)) 'Other preset values, buttons, camera, LED configuration or Abysses bank changed'
'KINECT_KNOBS_PASS: all 16 positions, native addresses, OSC bindings, physical/dashboard agreement, preset additions and unchanged existing show data.'
