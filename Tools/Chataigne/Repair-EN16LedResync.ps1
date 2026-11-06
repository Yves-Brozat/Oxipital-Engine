param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$sourceFull=(Resolve-Path -LiteralPath $SourcePath).Path
$outputFull=[IO.Path]::GetFullPath($OutputPath)
if($sourceFull -eq $outputFull){throw 'Use a separate output path to keep the saved session.'}
$p=[IO.File]::ReadAllText($sourceFull)|ConvertFrom-Json
$state=$p.states.items|Where-Object shortName -eq kinectEN16
$mapping=$state.processors.items|Where-Object shortName -eq en16LEDBankResync
$math=@($mapping.filters.items|Where-Object {$_.type -eq 'Math' -and $_.niceName -eq 'Bank to CC value'})
if($math.Count -ne 1){throw 'Expected exactly one bank LED resync Math filter.'}
$math=$math[0]
$operation=$math.filterParams.parameters|Where-Object controlAddress -eq '/operation'
if($operation.value -ne 'Multiply'){throw 'Unexpected bank conversion operation.'}
$before=$math|ConvertTo-Json -Depth 100 -Compress
$value=$math.filterParams.parameters|Where-Object controlAddress -eq '/value'
if(!$value){throw 'Expected the serialized multiplier parameter.'}
$value.value=127
# A dynamic Math operand is recreated on load from operationValue, not just
# filterParams.parameters. Set both representations to survive a save/reload.
$math|Add-Member -Force -NotePropertyName operationValue -NotePropertyValue ([pscustomobject]@{
    value=127
    controlAddress='/states/kinectEN16/processors/en16LEDBankResync/filters/bankToCCValue/filterParams/value'
})
$json=$p|ConvertTo-Json -Depth 100 -Compress
$loaded=$json|ConvertFrom-Json
$loadedMath=($loaded.states.items|Where-Object shortName -eq kinectEN16).processors.items|Where-Object shortName -eq en16LEDBankResync|ForEach-Object {$_.filters.items}|Where-Object type -eq Math
if($loadedMath.operationValue.value -ne 127 -or ($loadedMath.filterParams.parameters|Where-Object controlAddress -eq '/value').value -ne 127){throw 'Multiplier did not survive serialization.'}
foreach($bank in @(0,1)){
    $cc=$bank*$loadedMath.operationValue.value
    if($cc -ne @(0,127)[$bank]){throw 'Incorrect bank resync MIDI value.'}
}
# Restore the original filter and prove no other session data was changed.
$mapping.filters.items=@($mapping.filters.items|ForEach-Object {if($_ -eq $math){$before|ConvertFrom-Json}else{$_}})
$original=[IO.File]::ReadAllText($sourceFull)|ConvertFrom-Json|ConvertTo-Json -Depth 100 -Compress
if(($p|ConvertTo-Json -Depth 100 -Compress) -cne $original){throw 'Unexpected change outside the LED multiplier.'}
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFull))|Out-Null
[IO.File]::WriteAllText($outputFull,$json,[Text.UTF8Encoding]::new($false))
'EN16_LED_RESYNC_PASS: operationValue and filter parameter = 127; reload data valid; banks map to 0/127; no changes outside this filter.'
