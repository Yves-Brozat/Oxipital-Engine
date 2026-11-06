param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Assert($value,[string]$message){if(!$value){throw $message}}
$source=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $SourcePath))|ConvertFrom-Json
$p=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $OutputPath))|ConvertFrom-Json
$old=$source.dashboardManager.items|Where-Object niceName -eq Abysses
$preserved=$p.dashboardManager.items|Where-Object niceName -eq Abysses
Assert (($old|ConvertTo-Json -Depth 100 -Compress) -ceq ($preserved|ConvertTo-Json -Depth 100 -Compress)) 'Original dashboard changed'
Assert ($p.dashboardManager.items.Count -eq $source.dashboardManager.items.Count+1) 'Expected one dashboard copy'
$d=$p.dashboardManager.items|Where-Object niceName -eq 'Abysses Kinect'
Assert ($d.itemManager.items.Count -eq 35) 'Expected 32 controls, two selectors and camera preview'
$g=$p.customVariables.items|Where-Object niceName -eq Kinect
$addresses=@{}
foreach($v in $g.variables.items){
    $key=$v.parameters[0].controlAddress.TrimStart('/')
    Assert ($v.shortName -ceq $key) ('CV item and parameter names differ: '+$v.niceName)
    $addresses['/customVariables/kinect/variables/'+$key+'/'+$key]=$true
}
$bank=$p.states.items|Where-Object shortName -eq kinectEN16
$mux=$bank.processors.items|Where-Object type -eq Multiplex
$rotaryList=$mux.containers.lists.items|Where-Object niceName -in @('Target Kinect Parameters','Target Force 1')
$pushList=$mux.containers.lists.items|Where-Object niceName -eq 'EN16 Button Page 1'
$baselineMux=($source.states.items|Where-Object shortName -eq kinectEN16).processors.items|Where-Object type -eq Multiplex
$baselinePush=$baselineMux.containers.lists.items|Where-Object niceName -eq 'EN16 Button Page 1'
$rotaryMapping=$mux.containers.processors.items|Where-Object niceName -eq 'Force1 MIDI Rotary'
$rotaryGate=$rotaryMapping.filters.items|Where-Object niceName -eq 'Kinect Mode Gate'
Assert ($null -ne $rotaryGate) 'Rotaries missing bank gate'
Assert (($rotaryGate.conditions.items[0].parameters|Where-Object controlAddress -eq '/inputValue').value -ceq '/customVariables/kinect/variables/en16KinectBank/en16KinectBank') 'Wrong rotary bank control'
$reference=($rotaryGate.conditions.items[0].comparator.parameters|Where-Object controlAddress -eq '/reference').value
Assert ($reference -is [bool] -and $reference -eq $true) 'Rotaries must run when Kinect bank is true'
Assert ($rotaryList.parameters.Count -eq 16 -and $pushList.parameters.Count -eq 16) 'Missing EN16 channels'
for($i=0;$i -lt 16;$i++){
    $rotary=$d.itemManager.items|Where-Object niceName -eq ('Rotary '+($i+1))
    $target=($rotary.parameters|Where-Object controlAddress -eq '/target').value
    Assert ($addresses.ContainsKey($target)) ('Dashboard target missing: '+$target)
    Assert ($target -ceq $rotaryList.parameters[$i].value) 'Rotary dashboard/hardware mismatch'
    Assert ($rotary.controllable -ceq $target -and $rotary.ghostAddress -ceq $target) 'Stale widget target'
    $push=$d.itemManager.items|Where-Object niceName -eq ('Push '+($i+1))
    $target=($push.parameters|Where-Object controlAddress -eq '/target').value
    $action=$bank.processors.items|Where-Object niceName -eq ('Push '+($i+1))
    Assert ($action.type -eq 'Action') 'Missing physical push action'
    Assert ($action.conditions.items[0].parameters[0].value -ceq $pushList.parameters[$i].value) 'Wrong physical push channel'
    Assert ($pushList.parameters[$i].value -ceq $baselinePush.parameters[$i].value) 'MIDI channel order changed'
    Assert ($action.conditions.items[1].parameters[0].value -ceq '/customVariables/kinect/variables/en16KinectBank/en16KinectBank') 'Physical push missing bank gate'
    Assert (($action.consequences.items[0].command.parameters|Where-Object controlAddress -eq '/target').value -ceq $target) 'Push dashboard/hardware mismatch'
    if($i -lt 12){Assert ($addresses.ContainsKey($target) -or $target -match '^/customVariables/leapMotion/variables/send(Forces|Orbs)Position/') 'Unknown toggle target'}
    else{Assert ($action.consequences.items[0].commandType -eq 'Trigger a Control') 'Invalid native trigger command'}
}
# All Kinect reference strings must resolve after Chataigne regenerates CV names.
$json=$p|ConvertTo-Json -Depth 100 -Compress
foreach($match in [regex]::Matches($json,'"(/customVariables/kinect/variables/[^" ]+)"')){
    Assert ($addresses.ContainsKey($match.Groups[1].Value)) ('Unresolved Kinect reference: '+$match.Groups[1].Value)
}
foreach($preset in $g.presets.items){
    Assert (!$preset.values.containers.kinectEnabled -and !$preset.values.containers.en16KinectBank) 'Show presets must not switch bank/source'
    foreach($property in $preset.values.containers.PSObject.Properties){
        Assert ($property.Value.parameters.Count -eq 1) ('Missing preset value: '+$property.Name)
        Assert ($property.Value.parameters[0].controlAddress -ceq ('/'+$property.Name)) 'Preset parameter/container mismatch'
    }
}
Assert (($g.variables.items|Where-Object shortName -eq orientationOffsetZ).parameters[0].value -eq 90) 'Initial orientation offset was lost'
Assert (($g.variables.items|Where-Object shortName -eq controlIntensityRadius).parameters[0].value -eq $true) 'Initial brush parameter switch was lost'
'KINECT_DASHBOARD_PASS: original dashboard preserved; 16 rotary and 16 push bindings, native commands, canonical CV targets and preset values validated.'
