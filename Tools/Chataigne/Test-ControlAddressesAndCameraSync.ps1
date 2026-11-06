param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$before=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$after=Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8|ConvertFrom-Json
function Check($ok,$message){if(!$ok){throw $message}}
$group=$after.customVariables.items|Where-Object shortName -eq kinect
$routes=$after.states.items|Where-Object shortName -eq kinectToUnity
foreach($spec in @(@('twoHandForces',8),@('singleHandAtATime',12))){
    $key=$spec[0];$index=$spec[1]
    $cv=$group.variables.items|Where-Object shortName -eq $key
    $leaf=($cv.parameters|Where-Object type -eq Boolean).controlAddress
    $path='/customVariables/kinect/variables/'+$key+$leaf
    $mapping=$routes.processors.items|Where-Object shortName -eq ($key+'ToUnity')
    Check (($mapping.im.items[0].parameters|Where-Object controlAddress -eq '/inputValue').value -eq $path) 'Mapping does not use native-saved variable address'
    Check (($mapping.outputs.items[0].command.parameters|Where-Object controlAddress -eq '/operator').value -eq 'Equals') 'Missing output operator'
    Check ($mapping.outputs.items[0].command.paramLinks.value.mappingValueIndex -eq 0) 'Missing mapping value link'
    $dash=($after.dashboardManager.items|Where-Object niceName -eq 'Abysses Kinect').itemManager.items|Where-Object niceName -eq "Push $index"
    Check (($dash.parameters|Where-Object controlAddress -eq '/target').value -eq $path -and $dash.ghostAddress -eq $path) 'Dashboard address is stale'
    $action=($after.states.items|Where-Object shortName -eq kinectEN16).processors.items|Where-Object niceName -eq "Push $index"
    Check (($action.consequences.items[0].command.parameters|Where-Object controlAddress -eq '/operator').value -eq 'Inverse') 'Physical button does not toggle'
}
$camera=$after.customVariables.items|Where-Object niceName -eq Camera
Check (($camera.presets.items|Where-Object niceName -eq Reset).values.containers.zOffset.parameters[0].value -eq 5) 'Reference Zoffset was not restored'
# Compare the entire Orb/Force/Kinect preset groups: no visual compensation,
# noise changes or emitter changes are permitted as part of this repair.
foreach($name in 'Orb1','Orb2','Force 1','Force 2','Kinect'){
    $old=$before.customVariables.items|Where-Object niceName -eq $name
    $new=$after.customVariables.items|Where-Object niceName -eq $name
    Check (($old|ConvertTo-Json -Depth 100 -Compress) -ceq ($new|ConvertTo-Json -Depth 100 -Compress)) "Visual settings changed in $name"
}
Check (($before.dashboardManager.items|Where-Object niceName -eq Abysses|ConvertTo-Json -Depth 100 -Compress) -ceq ($after.dashboardManager.items|Where-Object niceName -eq Abysses|ConvertTo-Json -Depth 100 -Compress)) 'Abysses dashboard changed'
'CONTROL_CAMERA_REPAIR_PASS: native address compatibility, output value links, physical buttons, original Zoffset and visual presets preserved.'
