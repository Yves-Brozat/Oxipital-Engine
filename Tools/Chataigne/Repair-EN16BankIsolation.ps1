param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$sourceFull=(Resolve-Path -LiteralPath $SourcePath).Path
$outputFull=[IO.Path]::GetFullPath($OutputPath)
if($sourceFull -eq $outputFull){throw 'Use a separate output file.'}
$p=[IO.File]::ReadAllText($sourceFull)|ConvertFrom-Json
function Put($n,[string]$key,$value){$n|Add-Member -NotePropertyName $key -NotePropertyValue $value -Force}
function Set-Parameter($n,[string]$key,$value){
    $param=$n.parameters|Where-Object controlAddress -eq $key
    if($param){$param.value=$value}else{Put $n parameters (@($n.parameters|Where-Object{$null -ne $_})+@([pscustomobject]@{controlAddress=$key;value=$value}))}
}
$bankAddress='/customVariables/kinect/variables/en16KinectBank/en16KinectBank'
$script:fixedActions=0;$script:fixedRotaries=0
function Repair-Nodes($nodes){foreach($n in $nodes){
    if($n.type -eq 'Action'){
        $bankConditions=@($n.conditions.items|Where-Object{($_.parameters|Where-Object controlAddress -eq '/inputValue').value -eq $bankAddress})
        $op=$n.conditions.parameters|Where-Object controlAddress -eq '/operator'
        if($bankConditions.Count -gt 0 -and $op.value -eq 'OR'){
            $other=@($n.conditions.items|Where-Object{($_.parameters|Where-Object controlAddress -eq '/inputValue').value -ne $bankAddress})
            if($other.Count -ne 1){throw ('Manual grouping required for OR action: '+$n.niceName)}
            $op.value='AND';$script:fixedActions++
        }
    }
    if($n.type -eq 'Mapping' -and $n.niceName -eq 'Force1 MIDI Rotary'){
        Set-Parameter $n.params '/sendOnInputChangeOnly' $true
        Set-Parameter $n.params '/sendOnActivate' $false
        # Consecutive relative ticks may have identical values (e.g. 65,65).
        # The existing MIDI input keeps alwaysNotify=true; do not deduplicate output.
        Set-Parameter $n.params '/sendOnOutputChangeOnly' $false
        $script:fixedRotaries++
    }
    if($n.processors.items){Repair-Nodes $n.processors.items}
    if($n.containers.processors.items){Repair-Nodes $n.containers.processors.items}
    if($n.states.items){Repair-Nodes $n.states.items}
}}
Repair-Nodes $p.states.items
if($script:fixedRotaries -ne 2){throw "Expected two EN16 rotary mappings, got $script:fixedRotaries"}
[IO.File]::WriteAllText($outputFull,($p|ConvertTo-Json -Depth 100 -Compress),[Text.UTF8Encoding]::new($false))
"EN16_BANK_ISOLATION_REPAIRED: $script:fixedActions OR gate(s), $script:fixedRotaries event-driven rotary mappings."
