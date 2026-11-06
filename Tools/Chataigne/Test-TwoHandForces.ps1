param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$before=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$after=Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8|ConvertFrom-Json
function Check($ok,$message){if(!$ok){throw $message}}
$g=$after.customVariables.items|Where-Object shortName -eq kinect
$nativeLeaves=@{twoHandForces='twoHandsForces';singleHandAtATime='singleHandOnly'}
foreach($key in 'twoHandForces','singleHandAtATime'){
    $cv=@($g.variables.items|Where-Object shortName -eq $key)
    Check ($cv.Count -eq 1 -and $cv[0].parameters[0].value -eq $false) "Missing default-off $key"
    $leaf=$nativeLeaves[$key]
    Check ($cv[0].parameters[0].controlAddress -eq ('/'+$leaf)) "Leaf control address differs from native $leaf"
    foreach($preset in $g.presets.items){
        Check ($preset.values.containers.$leaf.parameters[0].value -eq $false) "Missing preset default $key"
        $preset.values.containers.PSObject.Properties.Remove($leaf)
    }
    $g.variables.items=@($g.variables.items|Where-Object shortName -ne $key)
    $routes=$after.states.items|Where-Object shortName -eq kinectToUnity
    $route=@($routes.processors.items|Where-Object shortName -eq ($key+'ToUnity'))
    Check ($route.Count -eq 1) "Missing $key OSC mapping"
    $input=($route[0].im.items[0].parameters|Where-Object controlAddress -eq '/inputValue').value
    $target=($route[0].outputs.items[0].command.parameters|Where-Object controlAddress -eq '/target').value
    Check ($input -eq "/customVariables/kinect/variables/$key/$leaf" -and $target -eq "/modules/oxipital/values/Ballet/Optical_Flow/TwoHandForceBrush/$key") "Wrong $key route"
    $routes.processors.items=@($routes.processors.items|Where-Object shortName -ne ($key+'ToUnity'))
}
foreach($spec in @(@(12,'singleHandAtATime'),@(14,'twoHandForces'))){
    $index=$spec[0];$key=$spec[1];$leaf=$nativeLeaves[$key];$path="/customVariables/kinect/variables/$key/$leaf"
    $dash=$after.dashboardManager.items|Where-Object niceName -eq 'Abysses Kinect'
    $oldDash=$before.dashboardManager.items|Where-Object niceName -eq 'Abysses Kinect'
    $button=$dash.itemManager.items|Where-Object niceName -eq "Push $index"
    Check ($button.type -eq 'DashboardParameterItem' -and $button.controllable -eq $path -and $button.ghostAddress -eq $path) 'Wrong dashboard target/type'
    $bank=$after.states.items|Where-Object shortName -eq kinectEN16
    $action=$bank.processors.items|Where-Object niceName -eq "Push $index"
    Check (($action.consequences.items[0].command.parameters|Where-Object controlAddress -eq '/target').value -eq $path) 'Wrong physical button target'
    Check (($action.consequences.items[0].command.parameters|Where-Object controlAddress -eq '/operator').value -eq 'Inverse') 'Physical button must toggle'
    $oldBank=$before.states.items|Where-Object shortName -eq kinectEN16
    $action.consequences.items=($oldBank.processors.items|Where-Object niceName -eq "Push $index").consequences.items
    $dash.itemManager.items=@($dash.itemManager.items|ForEach-Object {if($_.niceName -eq "Push $index"){$oldDash.itemManager.items|Where-Object niceName -eq "Push $index"}else{$_}})
}
Check (($after|ConvertTo-Json -Depth 100 -Compress) -ceq ($before|ConvertTo-Json -Depth 100 -Compress)) 'Other preset values, camera, Abysses dashboard, LED config or routes changed'
'TWO_HAND_FORCES_PROJECT_PASS: buttons 12/14, OSC paths, defaults in every Kinect preset, all unrelated project data preserved.'
