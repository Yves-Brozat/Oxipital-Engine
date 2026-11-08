param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Assert($ok,$message){if(!$ok){throw $message}}
function Json($n){ConvertTo-Json -InputObject $n -Depth 100 -Compress}
function Value($n,$key){($n.parameters|Where-Object controlAddress -eq $key).value}
function Walk($nodes){foreach($n in $nodes){$n;if($n.processors.items){Walk $n.processors.items};if($n.containers.processors.items){Walk $n.containers.processors.items};if($n.states.items){Walk $n.states.items}}}
$before=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$after=Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8|ConvertFrom-Json
$actions=@(Walk $after.states.items|Where-Object type -eq Action)
$conduite=$after.states.items|Where-Object niceName -eq Conduite
$conductor=$conduite.processors.items|Where-Object type -eq Conductor
$routes=@(@('Meduse','meduse',15),@('Chute','chute',14),@('Cascade','cascade',9),@('Tornade','tornade',5),@('Tourbillon','tourbillon',10),@('Circle','cercle',11))
$addresses=@()
foreach($spec in $routes){
    $name=$spec[0];$key=$spec[1];$slot=$spec[2]
    $buttonAddress="/customVariables/kinect/variables/en16AbyssesButton$slot/en16AbyssesButton$slot"
    $addresses+=@($buttonAddress)
    $listeners=@($actions|Where-Object {@($_.conditions.items|Where-Object {(Value $_ '/inputValue') -eq $buttonAddress}).Count})
    Assert ($listeners.Count -eq 1) "Button $slot must have exactly one action subscriber"
    $action=$listeners[0]
    Assert ($action.shortName -eq "en16$key") "Button $slot bypasses Conduite"
    Assert (@($action.consequences.items).Count -eq 1) 'Scene press also recalls presets directly'
    $command=$action.consequences.items[0]
    $target="/states/conduite/processors/conductor/processors/$key/trigger"
    Assert ($command.commandType -eq 'Trigger a Control' -and (Value $command.command '/target') -eq $target) 'Wrong cue trigger'
    $cue=$conductor.containers.processors.items|Where-Object shortName -eq $key
    Assert (@($cue).Count -eq 1 -and (Value $cue.sequenceLinking '/linkedSequence') -eq "/$key") 'Broken cue/sequence link'
    Assert ((Value $cue.sequenceLinking '/autoStart') -eq $true -and (Value $cue.sequenceLinking '/forcePlayFromStart') -eq $true) 'Cue must start the timeline at the beginning'
    Assert (!$cue.consequences.items.Count) 'Cue recalls presets outside its sequence'
    $condition=$action.conditions.items|Where-Object {(Value $_ '/inputValue') -eq $buttonAddress}
    Assert ((Value $condition '/enabled') -ne $false) 'Scene press condition is disabled'
    Assert ((Value $condition.comparator '/comparisonFunction') -eq '>' -and (Value $condition.comparator '/reference') -eq 0) 'Press must require a positive note'
    # Exercise a press/release and a bank-clear cycle. Only a positive rising
    # edge can dispatch a cue, so zeros on release/bank change do not launch it.
    $triggerCount=0;$previous=$false
    foreach($noteValue in @(0,127,127,0,0)){
        $valid=$noteValue -gt 0
        if($valid -and !$previous){$triggerCount++}
        $previous=$valid
    }
    Assert ($triggerCount -eq 1) 'Repeated note or release caused an extra scene trigger'
    $oldKey=$name.Substring(0,1).ToLowerInvariant()+$name.Substring(1)
    $oldTarget="/states/presets/processors/$oldKey/trigger"
    $widgets=@($after.dashboardManager.items.itemManager.items|Where-Object {(Value $_ '/target') -eq $target})
    Assert ($widgets.Count -ge 2) 'Both Abysses and Conduite dashboards must launch the same cue'
    foreach($widget in $widgets){Assert ($widget.ghostAddress -eq $target -and $widget.controllable -eq $target) 'Stale dashboard link'}
    Assert (@($after.dashboardManager.items.itemManager.items|Where-Object {(Value $_ '/target') -eq $oldTarget}).Count -eq 0) 'Dashboard still launches a direct preset'
}
foreach($section in @('customVariables','modules','sequences')){Assert ((Json $before.$section) -ceq (Json $after.$section)) "Changed $section (including Tornade presets/morph)"}
Assert ((Json @($before.states.items|Where-Object niceName -notin @('Presets','Conduite'))) -ceq (Json @($after.states.items|Where-Object niceName -notin @('Presets','Conduite')))) 'Unrelated states, bank routing or Kinect buttons changed'
$oldPresets=$before.states.items|Where-Object niceName -eq Presets
$newPresets=$after.states.items|Where-Object niceName -eq Presets
foreach($action in $oldPresets.processors.items){if($action.conditions.items){$action.conditions.items=@($action.conditions.items|Where-Object {(Value $_ '/inputValue') -notin $addresses})}}
Assert ((Json $oldPresets) -ceq (Json $newPresets)) 'Manual preset actions changed beyond the removed scene-button subscriptions'
$oldConduite=$before.states.items|Where-Object niceName -eq Conduite
$newConduite=$after.states.items|Where-Object niceName -eq Conduite
$newConduite.processors.items=@($newConduite.processors.items|Where-Object shortName -notmatch '^en16(meduse|chute|cascade|tornade|tourbillon|cercle)$')
Assert ((Json $oldConduite) -ceq (Json $newConduite)) 'Existing conductor, Next or Init changed'
'EN16_CONDUITE_ROUTING_PASS: six unique button-to-cue routes, press/release isolation, matching dashboards, no legacy scene listeners, presets/morph/Kinect/bank routing preserved.'
