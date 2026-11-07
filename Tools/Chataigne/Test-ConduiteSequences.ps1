param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Json($x){ConvertTo-Json -InputObject $x -Depth 100 -Compress}
function Assert($ok,$message){if(!$ok){throw $message}}
function Short($x){if($x.shortName){return $x.shortName};$s=$x.niceName -replace '[^\p{L}\p{Nd}_]','';$s.Substring(0,1).ToLowerInvariant()+$s.Substring(1)}
function Value($x,$key){($x.parameters|Where-Object controlAddress -eq $key).value}
$before=[IO.File]::ReadAllText((Resolve-Path $SourcePath))|ConvertFrom-Json
$after=[IO.File]::ReadAllText((Resolve-Path $OutputPath))|ConvertFrom-Json
foreach($prop in $before.PSObject.Properties.Name){
    if($prop -in @('states','sequences','dashboardManager')){continue}
    Assert ((Json $before.$prop) -ceq (Json $after.$prop)) "Unrelated section changed: $prop"
}
Assert ((Json @($before.states.items|Where-Object niceName -ne Conduite)) -ceq (Json @($after.states.items|Where-Object niceName -ne Conduite))) 'Unrelated states changed'
Assert ((Json $before.sequences.items) -ceq (Json @($after.sequences.items|Select-Object -First $before.sequences.items.Count))) 'Existing sequences changed'
Assert ((Json $before.dashboardManager.items) -ceq (Json @($after.dashboardManager.items|Select-Object -First $before.dashboardManager.items.Count))) 'Existing dashboards changed'
$state=$after.states.items|Where-Object niceName -eq Conduite
$conductor=$state.processors.items|Where-Object type -eq Conductor
$cues=@($conductor.containers.processors.items)
Assert (($cues.niceName -join ',') -ceq 'Meduse,Chute,Cascade,Tornade,Tourbillon,Cercle') 'Wrong cue order'
Assert ((Value $conductor '/nextCue') -eq 1) 'First Next must launch Meduse'
Assert ((Value $conductor '/loop') -eq $false) 'Manual end of show expected'
$targets=@{}
foreach($group in $after.customVariables.items){foreach($preset in $group.presets.items){$targets['/'+(Short $group)+'/presets/'+(Short $preset)]=$true}}
$count=0
foreach($cue in $cues){
    Assert (!$cue.consequences.items.Count) 'Conductor still recalls presets directly'
    $link=$cue.sequenceLinking
    foreach($key in @('/autoStart','/autoStop','/forcePlayFromStart')){Assert ((Value $link $key) -eq $true) "Missing $key"}
    Assert ((Value $link '/autoNextOnFinish') -eq $false) 'Unexpected automatic Next'
    $address=Value $link '/linkedSequence'
    Assert ($address -match '^/[^/]+$') 'Sequence link must be relative to the sequences manager (no /sequences prefix)'
    $sequence=@($after.sequences.items|Where-Object {('/'+(Short $_)) -eq $address})
    Assert ($sequence.Count -eq 1) 'Broken sequence link'
    $events=$sequence[0].layers.items[0].triggers.items
    if($cue.niceName -eq 'Chute' -and !$events.Count){continue}
    Assert ($events.Count -eq 1) 'Unexpected extra event using obsolete end presets'
    $sceneName=if($cue.niceName -eq 'Cercle'){'Circle'}else{$cue.niceName}
    $scene=($before.states.items|Where-Object niceName -eq Presets).processors.items|Where-Object niceName -eq $sceneName
    Assert ((Json $events[0].consequences) -ceq (Json $scene.consequences)) "Current synchronized recall bundle changed: $sceneName"
    foreach($event in $events){
        $time=Value $event '/time'
        foreach($command in $event.consequences.items){
            $target=Value $command.command '/targetPreset'
            if(!$target){continue}
            Assert ($target -notmatch '/(cascadeEnd|descenteInit|descenteEnd)$') 'Obsolete preset used'
            Assert ($targets.ContainsKey($target)) "Unresolved preset: $target"
            $duration=Value $command.command '/interpolationTime'
            Assert (($time+$duration) -lt (Value $sequence[0] '/totalTime')) 'Morph exceeds sequence duration'
            $count++
        }
    }
}
$next=$state.processors.items|Where-Object niceName -eq Next
Assert ((Value $next.consequences.items[0].command '/target') -eq '/states/conduite/processors/conductor/trigger') 'Next targets obsolete conductor'
$init=$state.processors.items|Where-Object niceName -eq Init
Assert ((Value $init.consequences.items[0].command.script '/filePath') -eq 'scripts/ConduiteInit.js') 'Missing Init script'
Assert (!$next.conditions -and !$init.conditions) 'Legacy button conditions still active'
Write-Output "PASS: six manager-relative sequence links, $count preset references, current synchronized recall bundles, no obsolete end morphs, Next/Init routes, unrelated content preserved."
