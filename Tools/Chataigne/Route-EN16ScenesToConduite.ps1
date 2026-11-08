param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Json($n){ConvertTo-Json -InputObject $n -Depth 100 -Compress}
function Clone($n){Json $n|ConvertFrom-Json}
function Value($n,$key){($n.parameters|Where-Object controlAddress -eq $key).value}
function Set-Value($n,$key,$value){$p=$n.parameters|Where-Object controlAddress -eq $key;if(!$p){throw "Missing $key"};$p.value=$value}
function P($key,$value){[pscustomobject]@{controlAddress=$key;value=$value}}
if([IO.Path]::GetFullPath($SourcePath) -eq [IO.Path]::GetFullPath($OutputPath)){throw 'Prepare a separate output file.'}
$p=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$presets=$p.states.items|Where-Object niceName -eq Presets
$conduite=$p.states.items|Where-Object niceName -eq Conduite
$conductor=$conduite.processors.items|Where-Object type -eq Conductor
if(!$presets -or !$conductor){throw 'Expected Presets and Conduite states.'}
$routes=@(@('Meduse','meduse',15),@('Chute','chute',14),@('Cascade','cascade',9),@('Tornade','tornade',5),@('Tourbillon','tourbillon',10),@('Circle','cercle',11))
$inputs=@();$sourceActions=@{}
foreach($spec in $routes){
    $name=$spec[0];$key=$spec[1];$slot=$spec[2]
    $cue=$conductor.containers.processors.items|Where-Object shortName -eq $key
    if(@($cue).Count -ne 1 -or (Value $cue.sequenceLinking '/linkedSequence') -ne "/$key"){throw "Missing sequence cue $key"}
    $source=$presets.processors.items|Where-Object niceName -eq $name
    if(@($source).Count -ne 1){throw "Missing source action $name"}
    $buttonAddress="/customVariables/kinect/variables/en16AbyssesButton$slot/en16AbyssesButton$slot"
    if(@($source.conditions.items|Where-Object {(Value $_ '/inputValue') -eq $buttonAddress}).Count -ne 1){throw "Expected routed EN16 condition for $name"}
    $inputs+=@($buttonAddress);$sourceActions[$key]=Clone $source
}
# Remove every old subscriber for these scene buttons, including the legacy
# Bulle/Circle, Cascade end and Descente variants sharing the same MIDI slots.
# Keep their recall commands available for deliberate manual preset authoring.
function Disconnect-SceneInputs($nodes){foreach($n in $nodes){
    if($n.type -eq 'Action' -and $n.conditions.items){
        $n.conditions.items=@($n.conditions.items|Where-Object {(Value $_ '/inputValue') -notin $inputs})
    }
    if($n.processors.items){Disconnect-SceneInputs $n.processors.items}
    if($n.containers.processors.items){Disconnect-SceneInputs $n.containers.processors.items}
    if($n.states.items){Disconnect-SceneInputs $n.states.items}
}}
Disconnect-SceneInputs $p.states.items
foreach($spec in $routes){
    $name=$spec[0];$key=$spec[1];$slot=$spec[2]
    $target="/states/conduite/processors/conductor/processors/$key/trigger"
    $action=[pscustomobject]@{
        niceName="EN16 - $key";shortName="en16$key";type='Action';editorIsCollapsed=$true
        conditions=(Clone $sourceActions[$key].conditions)
        consequences=[pscustomobject]@{items=@([pscustomobject]@{
            niceName="Lancer la sequence $key";type='Consequence';commandModule='generic';commandPath='';commandType='Trigger a Control'
            command=[pscustomobject]@{parameters=@((P '/target' $target));paramLinks=[pscustomobject]@{}}
        })}
    }
    if($conduite.processors.items|Where-Object shortName -eq $action.shortName){throw 'Scene routing is already installed.'}
    $conduite.processors.items+=@($action)
    $oldKey=$sourceActions[$key].shortName
    if(!$oldKey){$oldKey=($name -replace '[^\p{L}\p{Nd}_]','');$oldKey=$oldKey.Substring(0,1).ToLowerInvariant()+$oldKey.Substring(1)}
    $oldTarget="/states/presets/processors/$oldKey/trigger"
    foreach($dash in $p.dashboardManager.items){foreach($widget in $dash.itemManager.items){
        if((Value $widget '/target') -eq $oldTarget){
            Set-Value $widget '/target' $target
            $widget.ghostAddress=$target;$widget.controllable=$target
            if($key -eq 'cercle'){Set-Value $widget '/customText' 'Cercle'}
        }
    }}
}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),(Json $p),[Text.UTF8Encoding]::new($false))
'EN16_SCENES_ROUTED: six scene buttons and matching dashboards launch Conduite cues; direct preset/legacy duplicate input subscriptions removed.'
