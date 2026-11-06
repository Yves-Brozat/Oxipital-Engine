param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$before=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$after=Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8|ConvertFrom-Json
function Check($ok,$message){if(!$ok){throw $message}}
function Matches($mapping,$values){
    foreach($f in $mapping.filters.items|Where-Object type -eq Condition){
        foreach($c in $f.conditions.items){
            $path=($c.parameters|Where-Object controlAddress -eq '/inputValue').value
            $expected=($c.comparator.parameters|Where-Object controlAddress -eq '/reference').value
            Check ($values.ContainsKey($path)) "Unexpected route condition $path"
            if($values[$path] -ne $expected){return $false}
        }
    }
    return $true
}
foreach($kind in 'Orb','Force'){
    $state=$after.states.items|Where-Object niceName -eq "CV $kind 1 -> OSC Oxipital"
    $sum=$state.processors.items|Where-Object niceName -eq "Preset plus Quest $kind Offset"
    $direct=@($state.processors.items|Where-Object niceName -in "Preset $kind Position Kinect","Preset $kind Position Without Quest")
    Check ($direct.Count -eq 2) 'Missing non-Quest routes'
    foreach($mapping in $direct){
        Check (@($mapping.filters.items|Where-Object type -ne Condition).Count -eq 0) 'Direct position must bypass stale Math state'
        Check (($mapping.params.parameters|Where-Object controlAddress -eq '/sendOnInputChangeOnly').value -eq $false) 'Unchanged zero must still be processed'
        Check (($mapping.im|ConvertTo-Json -Depth 100 -Compress) -ceq ($sum.im|ConvertTo-Json -Depth 100 -Compress)) 'Position preset source changed'
        Check (($mapping.outputs|ConvertTo-Json -Depth 100 -Compress) -ceq ($sum.outputs|ConvertTo-Json -Depth 100 -Compress)) 'Position destination changed'
    }
    foreach($kinect in $false,$true){foreach($quest in $false,$true){foreach($editing in $false,$true){
        $values=@{'/customVariables/kinect/variables/kinectEnabled/kinectEnabled'=$kinect;'/states/metaQuestOSC__Oxipital/enabled'=$quest;'/modules/oxipital/parameters/setup/unityEditMode'=$editing}
        $active=@(@($sum)+$direct|Where-Object {Matches $_ $values})
        Check ($active.Count -eq $(if($editing){0}else{1})) 'Position writers overlap or are missing'
        if(!$editing){Check (($active[0].niceName -eq $sum.niceName) -eq (!$kinect -and $quest)) 'Stale Quest position wins with Quest disabled'}
    }}}
    $state.processors.items=@($state.processors.items|Where-Object niceName -notin "Preset $kind Position Kinect","Preset $kind Position Without Quest")
    $sum.filters.items=@($sum.filters.items|Where-Object niceName -notin 'Quest State Enabled','Kinect Position Route','Performance Mode')
    $oldState=$before.states.items|Where-Object niceName -eq $state.niceName
    $mux=$oldState.processors.items|Where-Object niceName -eq "$kind P3D"
    if($mux.containers.processors.items|Where-Object niceName -eq "$kind 1 Kinect Preset Values"){
        $mux.containers.processors.items=@($mux.containers.processors.items|Where-Object niceName -ne "$kind 1 Kinect Preset Values")
        $legacy=$mux.containers.processors.items|Where-Object {($_.im.items[0].parameters|Where-Object controlAddress -eq '/inputList').value -eq '/questFinalValues'}
        $legacy.filters.items=@($legacy.filters.items|Where-Object niceName -notin 'Quest Position Route','Performance Mode')
    }
}
Check (($before|ConvertTo-Json -Depth 100 -Compress) -ceq ($after|ConvertTo-Json -Depth 100 -Compress)) 'Unexpected changes to camera, presets, variables, rotations, LEDs or other routes'
'PRESET_POSITION_ROUTING_PASS: all tracking/authoring combinations, previous repair removed, only position writers changed; camera and other saved data preserved.'
