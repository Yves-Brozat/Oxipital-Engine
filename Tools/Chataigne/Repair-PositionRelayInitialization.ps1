param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
if([IO.Path]::GetFullPath($SourcePath) -eq [IO.Path]::GetFullPath($OutputPath)){throw 'Use a separate output file.'}
$p=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$count=0
foreach($kind in 'Force','Orb'){
    $s=$p.states.items|Where-Object niceName -eq "CV $kind 1 -> OSC Oxipital"
    foreach($name in @("Preset plus Quest $kind Offset","Preset $kind Position Kinect","Preset $kind Position Without Quest")){
        $m=$s.processors.items|Where-Object niceName -eq $name
        if(!$m){throw "Missing route $name"}
        foreach($spec in @(@('/sendOnInputChangeOnly',$false),@('/sendOnOutputChangeOnly',$false),@('/sendOnActivate',$true),@('/sendAfterLoad',$true),@('/forceContinuousProcess',$true))){
            $v=$m.params.parameters|Where-Object controlAddress -eq $spec[0]
            if($v){$v.value=$spec[1]}else{$m.params.parameters+=@([pscustomobject]@{controlAddress=$spec[0];value=$spec[1]})}
        }
        $count++
    }
}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),($p|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
"POSITION_RELAY_INITIALIZATION_REPAIRED: $count routes refresh unchanged values and send on activation."
