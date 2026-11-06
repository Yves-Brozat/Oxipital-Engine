param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$before=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$after=Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8|ConvertFrom-Json
foreach($kind in 'Force','Orb'){
    $old=$before.states.items|Where-Object niceName -eq "CV $kind 1 -> OSC Oxipital"
    $new=$after.states.items|Where-Object niceName -eq "CV $kind 1 -> OSC Oxipital"
    foreach($name in @("Preset plus Quest $kind Offset","Preset $kind Position Kinect","Preset $kind Position Without Quest")){
        $m=$new.processors.items|Where-Object niceName -eq $name
        foreach($spec in @(@('/sendOnInputChangeOnly',$false),@('/sendOnOutputChangeOnly',$false),@('/sendOnActivate',$true),@('/sendAfterLoad',$true),@('/forceContinuousProcess',$true))){
            $v=@($m.params.parameters|Where-Object controlAddress -eq $spec[0])
            if($v.Count -ne 1 -or $v[0].value -ne $spec[1]){throw "Relay can retain stale position: $name $($spec[0])"}
        }
        $m.params.parameters=($old.processors.items|Where-Object niceName -eq $name).params.parameters
    }
}
if(($before|ConvertTo-Json -Depth 100 -Compress) -cne ($after|ConvertTo-Json -Depth 100 -Compress)){throw 'Unrelated settings, routing conditions or presets changed'}
'POSITION_RELAY_INITIALIZATION_PASS: input/output refresh and activation enabled on six routes; all other data preserved.'
