param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Assert($ok,$message){if(!$ok){throw $message}}
function Json($node){ConvertTo-Json -InputObject $node -Depth 100 -Compress}
function Value($node,$key){($node.parameters|Where-Object controlAddress -eq $key).value}
function CV($key){'/customVariables/kinect/variables/'+$key+'/'+$key}
$old=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$p=Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8|ConvertFrom-Json
$targets=@('sendOrbsPosition','controlOrbRadius','controlOrbOrientation','twoHandOrbs','sendForcesPosition','controlIntensityRadius','controlOrientation','invertGestureIntensity',
    '/states/initialisation/processors/resetCameraPosition/trigger','/states/initialisation/processors/syncData/trigger','showMonitor','/states/presets/processors/meduse/trigger','kinectEnabled','brushEnabled','useTargetDepth','en16KinectBank')
$state=$p.states.items|Where-Object shortName -eq kinectEN16
$oldState=$old.states.items|Where-Object shortName -eq kinectEN16
$dashboard=$p.dashboardManager.items|Where-Object niceName -eq 'Abysses Kinect'
$oldDashboard=$old.dashboardManager.items|Where-Object niceName -eq 'Abysses Kinect'
foreach($i in 1..16){
    $target=if($targets[$i-1].StartsWith('/')){$targets[$i-1]}else{CV $targets[$i-1]}
    $widget=$dashboard.itemManager.items|Where-Object niceName -eq ('Push '+$i)
    Assert ((Value $widget '/target') -eq $target) ('Dashboard target '+$i)
    $oldWidget=$oldDashboard.itemManager.items|Where-Object niceName -eq ('Push '+$i)
    Assert ((Json (Value $widget '/viewUIPosition')) -ceq (Json (Value $oldWidget '/viewUIPosition'))) ('Dashboard position '+$i)
    if($i -eq 16){continue}
    $action=$state.processors.items|Where-Object niceName -eq ('Push '+$i)
    Assert ((Value $action.conditions.items[0] '/inputValue') -eq (CV ('en16KinectButton'+$i))) ('Physical virtual note '+$i)
    Assert ((Value $action.consequences.items[0].command '/target') -eq $target) ('Physical target '+$i)
    $command=if($i -in @(9,10,12)){'Trigger a Control'}else{'Set Parameter Value'}
    Assert ($action.consequences.items[0].commandType -eq $command) ('Physical command type '+$i)
    if($command -eq 'Set Parameter Value'){Assert ((Value $action.consequences.items[0].command '/operator') -eq 'Inverse') ('Toggle operation '+$i)}
}
# The bank router, LED RGB/resync, bank-switch reset logic and rotary mappings
# must remain unchanged by the new push-button layout.
$remaining=@($state.processors.items|Where-Object niceName -notmatch '^Push \d+$')
$prior=@($oldState.processors.items|Where-Object niceName -notmatch '^Push \d+$')
Assert ((Json $remaining) -ceq (Json $prior)) 'Bank routing or LED logic changed'
foreach($oldStateItem in $old.states.items|Where-Object shortName -notin @('kinectEN16','kinectToUnity')){
    $newState=$p.states.items|Where-Object shortName -eq $oldStateItem.shortName
    if(!$oldStateItem.shortName){$newState=$p.states.items|Where-Object niceName -eq $oldStateItem.niceName}
    Assert ((Json $newState) -ceq (Json $oldStateItem)) ('Unrelated state changed: '+$oldStateItem.niceName)
}
Assert ((Json $p.sequences) -ceq (Json $old.sequences)) 'Show sequences changed'
Assert ((Json ($p.dashboardManager.items|Where-Object niceName -eq Abysses)) -ceq (Json ($old.dashboardManager.items|Where-Object niceName -eq Abysses))) 'Abysses dashboard changed'
$group=$p.customVariables.items|Where-Object niceName -eq Kinect
$oldGroup=$old.customVariables.items|Where-Object niceName -eq Kinect
Assert (@($group.variables.items|Where-Object shortName -eq controlOrbOrientation).Count -eq 1) 'Missing orb orientation variable'
foreach($preset in $group.presets.items){
    Assert ($preset.values.containers.controlOrbOrientation.parameters[0].value -eq $false) 'New orientation must default off in saved presets'
    $preset.values.containers.PSObject.Properties.Remove('controlOrbOrientation')
}
Assert ((Json $group.presets) -ceq (Json $oldGroup.presets)) 'Existing show preset values changed'
$routes=($p.states.items|Where-Object shortName -eq kinectToUnity).processors.items
Assert (@($routes|Where-Object niceName -eq 'Control Orb Orientation -> Unity').Count -eq 1) 'Missing orb orientation route'
Assert (@($routes|Where-Object niceName -eq 'Unity -> Control Orb Orientation').Count -eq 1) 'Missing orb orientation feedback'
'KINECT_BUTTON_ORDER_PASS: all 16 visual slots, 15 physical actions, isolation, LED/rotary logic, presets, sequences, Abysses bank and orientation routes.'
