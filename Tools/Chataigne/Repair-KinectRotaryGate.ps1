param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$sourceFull=(Resolve-Path -LiteralPath $SourcePath).Path
$outputFull=[IO.Path]::GetFullPath($OutputPath)
if($sourceFull -eq $outputFull){throw 'Use a separate output file.'}
$p=[IO.File]::ReadAllText($sourceFull)|ConvertFrom-Json
$state=$p.states.items|Where-Object shortName -eq kinectEN16
$mux=$state.processors.items|Where-Object type -eq Multiplex
$count=0
foreach($mapping in $mux.containers.processors.items|Where-Object type -eq Mapping){
    foreach($filter in $mapping.filters.items|Where-Object niceName -eq 'Kinect Mode Gate'){
        $condition=$filter.conditions.items[0]
        $address=($condition.parameters|Where-Object controlAddress -eq '/inputValue').value
        if($address -ne '/customVariables/kinect/variables/en16KinectBank/en16KinectBank'){throw 'Unexpected rotary bank address'}
        $condition.comparator.parameters=@(
            [pscustomobject]@{controlAddress='/comparisonFunction';value='='},
            [pscustomobject]@{controlAddress='/reference';value=$true}
        )
        $count++
    }
}
if($count -ne 2){throw "Expected rotary and feedback bank gates, got $count"}
[IO.File]::WriteAllText($outputFull,($p|ConvertTo-Json -Depth 100 -Compress),[Text.UTF8Encoding]::new($false))
"KINECT_ROTARY_GATE_FIXED: $count gates now require Kinect bank = true."
