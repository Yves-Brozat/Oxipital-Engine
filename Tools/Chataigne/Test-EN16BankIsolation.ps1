param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Assert($ok,[string]$message){if(!$ok){throw $message}}
function Value($n,$key){($n.parameters|Where-Object controlAddress -eq $key).value}
function Json($n){ConvertTo-Json -InputObject $n -Depth 100 -Compress}
$old=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $SourcePath))|ConvertFrom-Json
$p=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $OutputPath))|ConvertFrom-Json
$bankAddress='/customVariables/kinect/variables/en16KinectBank/en16KinectBank'
$start=($p.states.items|Where-Object niceName -eq Initialisation).processors.items|Where-Object niceName -eq 'Launch Start'
function Evaluate-Start($pressed,$bank){
    $results=@(foreach($c in $start.conditions.items){
        $address=Value $c '/inputValue'
        $input=if($address -eq $bankAddress){$bank}elseif($address -eq '/modules/en16/values/_1_B0'){$pressed}else{throw ('Unexpected start input: '+$address)}
        $reference=Value $c.comparator '/reference'
        switch(Value $c.comparator '/comparisonFunction'){
            '>' {$input -gt $reference}
            '=' {$input -eq $reference}
            default {throw 'Unknown start comparator'}
        }
    })
    if((Value $start.conditions '/operator') -eq 'OR'){return $results -contains $true}
    return $results -notcontains $false
}
# Replay toggling from both dashboards and pressing/releasing physical 16,
# keeping the start button released. No start/preset/camera chain may fire.
foreach($bank in @($true,$false,$true,$false)){
    Assert (!(Evaluate-Start 0 $bank)) 'Bank change triggers Launch Start without its physical button'
}
Assert (Evaluate-Start 127 $false) 'Abysses start button no longer works'
Assert (!(Evaluate-Start 127 $true)) 'Abysses start button is not blocked in Kinect bank'
function Walk($nodes){foreach($n in $nodes){
    $n
    if($n.processors.items){Walk $n.processors.items}
    if($n.containers.processors.items){Walk $n.containers.processors.items}
    if($n.states.items){Walk $n.states.items}
}}
$nodes=@(Walk $p.states.items)
$rotaries=@($nodes|Where-Object{ $_.type -eq 'Mapping' -and $_.niceName -eq 'Force1 MIDI Rotary' })
Assert ($rotaries.Count -eq 2) 'Both rotary banks must be protected'
foreach($r in $rotaries){
    Assert ((Value $r.params '/sendOnInputChangeOnly') -eq $true) 'Old rotary delta can be replayed on bank change'
    Assert ((Value $r.params '/sendOnActivate') -eq $false) 'Activating rotary mapping sends a stored delta'
    Assert ((Value $r.params '/sendOnOutputChangeOnly') -eq $false) 'Identical consecutive MIDI ticks would be dropped'
    Assert ((Value $r.im.items[0] '/inputList') -eq '/en16RotaryPage1') 'Rotary MIDI input changed'
    Assert (($r.im.items[0].parameters|Where-Object controlAddress -eq '/inputList').alwaysNotify -eq $true) 'Repeated relative ticks lost alwaysNotify'
}
$switch=$nodes|Where-Object shortName -eq switchEN16Bank
Assert ((Value $switch.consequences.items[0].command '/target') -eq $bankAddress) 'Bank switch writes something other than the bank selector'
Assert ($switch.consequences.items.Count -eq 1 -and !$switch.consequencesOff.items.Count) 'Extra actions on bank button press/release'
$show=$nodes|Where-Object niceName -eq 'Show Active EN16 Bank'
foreach($cmd in @($show.consequences.items)+@($show.consequencesOff.items)){
    if($cmd.commandType -eq 'Select Dashboard'){continue}
    if($cmd.commandType -eq 'Control Change'){
        Assert ((Value $cmd.command '/channel') -eq 16 -and (Value $cmd.command '/ccNumber') -eq 119) 'Bank MIDI feedback targets show controls'
        continue
    }
    Assert ($cmd.commandType -eq 'Set Parameter Value' -and (Value $cmd.command '/target') -match '^/dashboards/abyssesKinect/dashboard/rotary\d+/foregroundColor$') 'Bank change writes a particle/show parameter'
}
# Limit edits to the broken start gate and rotary event scheduling. This
# preserves all authored values, presets, consequences, dashboard and LEDs.
foreach($n in @(Walk $old.states.items)){
    if($n.type -eq 'Action' -and $n.niceName -eq 'Launch Start'){
        ($n.conditions.parameters|Where-Object controlAddress -eq '/operator').value='AND'
    }
    if($n.type -eq 'Mapping' -and $n.niceName -eq 'Force1 MIDI Rotary'){
        foreach($pair in @(@('/sendOnInputChangeOnly',$true),@('/sendOnActivate',$false),@('/sendOnOutputChangeOnly',$false))){
            $param=$n.params.parameters|Where-Object controlAddress -eq $pair[0]
            if($param){$param.value=$pair[1]}else{
                $n.params|Add-Member -NotePropertyName parameters -NotePropertyValue (@($n.params.parameters)+@([pscustomobject]@{controlAddress=$pair[0];value=$pair[1]})) -Force
            }
        }
    }
}
Assert ((Json $old) -ceq (Json $p)) 'Unexpected changes to presets, values or unrelated actions'
'EN16_BANK_ISOLATION_PASS: bank-only truth table, explicit start press, both rotary banks, UI-only bank consequences, preserved live configuration.'
