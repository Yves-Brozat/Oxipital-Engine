param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Assert($value,[string]$message){if(!$value){throw $message}}
$source=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $SourcePath))|ConvertFrom-Json
$p=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $OutputPath))|ConvertFrom-Json
Assert ($p.modules.items.Count -eq $source.modules.items.Count) 'Module count changed'
Assert ($p.states.items.Count -eq $source.states.items.Count+2) 'Expected two new Kinect states'
Assert ($p.customVariables.items.Count -eq $source.customVariables.items.Count+1) 'Expected one Kinect group'
$group=@($p.customVariables.items|Where-Object shortName -eq kinect)
Assert ($group.Count -eq 1 -and $group[0].variables.items.Count -eq 29) 'Missing/duplicate Kinect variables'
$group=$group[0]
$keys=@($group.variables.items|ForEach-Object{$_.shortName})
Assert (@($keys|Sort-Object -Unique).Count -eq $keys.Count) 'Duplicate CV addresses'
$state=$p.states.items|Where-Object niceName -eq 'Kinect -> Unity'
$ox=$p.modules.items|Where-Object niceName -eq Oxipital
$brush=$ox.values.containers.Ballet.containers.Optical_Flow.containers.TwoHandForceBrush
foreach($route in $state.processors.items|Where-Object type -eq Mapping){
    $input=($route.im.items[0].parameters|Where-Object controlAddress -eq '/inputValue').value
    $target=($route.outputs.items[0].command.parameters|Where-Object controlAddress -eq '/target').value
    foreach($address in @($input,$target)){
        if($address -like '/customVariables/kinect/*'){
            $parts=$address.Split('/'); Assert ($keys -contains $parts[4]) ('Missing CV: '+$address)
            Assert ($parts[4] -eq $parts[5]) 'CV parameter address mismatch'
        }elseif($address -like '/modules/oxipital/*/TwoHandForceBrush/*'){
            $field=$address.Split('/')[-1]
            Assert (@($brush.parameters|Where-Object controlAddress -eq ('/'+$field)).Count -eq 1) ('Missing OSCQuery cache: '+$field)
        }
    }
}
$oldPreset=$source.states.items|Where-Object niceName -eq Preset
$newPreset=$p.states.items|Where-Object niceName -eq Preset
Assert ($oldPreset.processors.items.Count -eq $newPreset.processors.items.Count) 'Preset actions changed'
Assert ($group.presets.items.Count -eq $oldPreset.processors.items.Count) 'Missing Kinect scene preset'
foreach($oldAction in $oldPreset.processors.items){
    $action=$newPreset.processors.items|Where-Object niceName -eq $oldAction.niceName
    Assert ($action.consequences.items.Count -eq $oldAction.consequences.items.Count+1) ('Missing Kinect consequence: '+$oldAction.niceName)
    for($i=0;$i -lt $oldAction.consequences.items.Count;$i++){
        Assert (($oldAction.consequences.items[$i]|ConvertTo-Json -Depth 100 -Compress) -ceq ($action.consequences.items[$i]|ConvertTo-Json -Depth 100 -Compress)) 'Original consequence altered'
    }
    $target=($action.consequences.items[-1].command.parameters|Where-Object controlAddress -eq '/targetPreset').value
    $preset=$group.presets.items|Where-Object shortName -eq $target.Split('/')[-1]
    Assert ($null -ne $preset) 'Kinect preset reference does not resolve'
    $leapTargets=@($oldAction.consequences.items|ForEach-Object{($_.command.parameters|Where-Object controlAddress -eq '/targetPreset').value}|Where-Object{$_ -is [string] -and $_.StartsWith('/leapMotion/presets/')})
    $expected=@{forceOrb=@($true,$true);forceOnly=@($true,$false);orbOnly=@($false,$true);off=@($false,$false)}[$leapTargets[-1].Split('/')[-1]]
    Assert ($preset.values.containers.controlForcePosition.parameters[0].value -eq $expected[0]) 'Force position preset differs from Leap flags'
    Assert ($preset.values.containers.controlOrbPosition.parameters[0].value -eq $expected[1]) 'Orb position preset differs from Leap flags'
    Assert (!$preset.values.containers.en16Kinect -and !$preset.values.containers.kinectEnabled) 'Scene preset would change the input bank/source selection'
}
$oldMux=($source.states.items|Where-Object niceName -eq 'EN16 -> CV').processors.items|Where-Object type -eq Multiplex|Select-Object -First 1
$normalMux=($p.states.items|Where-Object niceName -eq 'EN16 -> CV').processors.items|Where-Object type -eq Multiplex|Select-Object -First 1
$newMux=($p.states.items|Where-Object niceName -eq 'Kinect EN16').processors.items[0]
foreach($listName in @('EN16 Rotary Page 1','EN16 Button Page 1')){
    $before=($oldMux.containers.lists.items|Where-Object niceName -eq $listName).parameters
    $normal=($normalMux.containers.lists.items|Where-Object niceName -eq $listName).parameters
    $kinect=($newMux.containers.lists.items|Where-Object niceName -eq $listName).parameters
    Assert ($before.Count -eq 16 -and $kinect.Count -eq 16) 'EN16 channel count changed'
    for($i=0;$i -lt 16;$i++){
        Assert ($before[$i].value -ceq $normal[$i].value -and $before[$i].value -ceq $kinect[$i].value) 'Physical encoder/button order changed'
    }
}
$targets=($newMux.containers.lists.items|Where-Object niceName -eq 'Target Force 1').parameters
foreach($target in $targets){Assert ($keys -contains $target.value.Split('/')[4]) 'Encoder points to a missing Kinect control'}
$relative=($newMux.containers.processors.items|Where-Object niceName -eq 'Force1 MIDI Rotary').filters.items|Where-Object niceName -eq 'Math 1'
Assert (($relative.filterParams.parameters|Where-Object controlAddress -eq '/value').value -eq -64) 'EN16 relative decoding changed'
Assert (@($newMux.containers.processors.items|Where-Object type -eq Action).Count -eq 0) 'Kinect bank would steal show preset push buttons'
'KINECT_CONTROLS_PASS: 29 CVs, 11 inherited preset flags/consequences, OSCQuery targets, 16-bank routing and original hardware bindings.'
