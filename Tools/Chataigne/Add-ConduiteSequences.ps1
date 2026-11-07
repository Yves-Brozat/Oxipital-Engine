param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath,[switch]$IncludeChutePreset)
$ErrorActionPreference='Stop'
function Json($x){ConvertTo-Json -InputObject $x -Depth 100 -Compress}
function P($key,$value){[pscustomobject]@{controlAddress=$key;value=$value}}
function Short($x){if($x.shortName){return $x.shortName};$s=$x.niceName -replace '[^\p{L}\p{Nd}_]','';$s.Substring(0,1).ToLowerInvariant()+$s.Substring(1)}
function Command($label,$module,$type,$parameters){[pscustomobject]@{niceName=$label;type='Consequence';commandModule=$module;commandPath='';commandType=$type;command=[pscustomobject]@{parameters=@($parameters);paramLinks=[pscustomobject]@{}}}}
function Trigger($label,$target){Command $label 'generic' 'Trigger a Control' @((P '/target' $target))}
function TimeEvent($label,$time,$commands){[pscustomobject]@{niceName=$label;type='TimeTrigger';parameters=@((P '/time' $time),(P '/length' 0));consequences=[pscustomobject]@{items=@($commands)};untriggerConsequences=[pscustomobject]@{};conditions=[pscustomobject]@{}}}
function DashboardButton($label,$key,$target,$x,$y,$width=180){[pscustomobject]@{niceName=$label;shortName=$key;type='DashboardTriggerItem';hideInEditor=$true;ghostAddress=$target;controllable=$target;parameters=@((P '/target' $target),(P '/viewUIPosition' @($x,$y)),(P '/viewUISize' @($width,65)),[pscustomobject]@{controlAddress='/customText';value=$label;enabled=$true})}}
$sourceFull=(Resolve-Path -LiteralPath $SourcePath).Path
if($sourceFull -eq [IO.Path]::GetFullPath($OutputPath)){throw 'Prepare a separate output before replacing the session.'}
$project=[IO.File]::ReadAllText($sourceFull)|ConvertFrom-Json
$state=@($project.states.items|Where-Object niceName -eq Conduite)
if($state.Count -ne 1){throw 'Expected one Conduite state.'}
$state=$state[0]
$rootPath='/states/'+(Short $state)+'/processors/'
if((Short $state) -ne 'conduite'){throw 'Init script requires the Conduite state address.'}
$presetState=@($project.states.items|Where-Object niceName -eq Presets)
if($presetState.Count -ne 1){throw 'Expected one Presets state.'}
$specs=@(
    @('Meduse','meduse','Meduse'),
    @('Chute','chute','Chute'),
    @('Cascade','cascade','Cascade'),
    @('Tornade','tornade','Tornade'),
    @('Tourbillon','tourbillon','Tourbillon'),
    @('Cercle','cercle','Circle')
)
$newSequences=@();$cues=@();$buttons=@()
foreach($spec in $specs){
    $label=$spec[0];$key=$spec[1]
    if($project.sequences.items|Where-Object {(Short $_) -eq $key}){throw "Sequence already exists: $key"}
    $events=@()
    if($key -ne 'chute' -or $IncludeChutePreset){
        $action=@($presetState[0].processors.items|Where-Object niceName -eq $spec[2])
        if($action.Count -ne 1){throw "Missing or ambiguous current scene: $($spec[2])"}
        # Keep the complete current recall bundle, including Force 2, camera,
        # Kinect and Unity's presetApplyDuration/applyCurrentValues handshake.
        $event=TimeEvent 'Init - preset actuel' 0.05 @()
        $event.consequences=(Json $action[0].consequences)|ConvertFrom-Json
        $events=@($event)
    }
    $newSequences+=@([pscustomobject]@{niceName=$label;shortName=$key;type='Sequence';parameters=@((P '/totalTime' 60),(P '/viewEndTime' 60),(P '/loop' $false),(P '/saveCurrentTime' $false));layers=[pscustomobject]@{hideInEditor=$true;items=@([pscustomobject]@{niceName='Presets et morphs';shortName='presetsEtMorphs';type='Trigger';triggers=[pscustomobject]@{hideInEditor=$true;items=$events}})};cues=[pscustomobject]@{hideInEditor=$true}})
    # Linked Sequence is rooted at ChataigneSequenceManager, not the engine.
    $cues+=@([pscustomobject]@{niceName=$label;shortName=$key;type='Cue';consequences=[pscustomobject]@{};consequencesOff=[pscustomobject]@{};sequenceLinking=[pscustomobject]@{parameters=@((P '/linkedSequence' ('/'+$key)),(P '/autoStart' $true),(P '/forcePlayFromStart' $true),(P '/autoStop' $true),(P '/autoNextOnFinish' $false))}})
    $buttons+=@(DashboardButton $label $key ($rootPath+'conductor/processors/'+$key+'/trigger') 0 (100+$buttons.Count*75) 380)
}
$conductor=[pscustomobject]@{niceName='Conductor';shortName='conductor';type='Conductor';parameters=@((P '/nextCue' 1),(P '/loop' $false),(P '/cueTriggerSetCurrent' $true));containers=[pscustomobject]@{processors=[pscustomobject]@{hideInEditor=$true;items=$cues}}}
$next=[pscustomobject]@{niceName='Next';shortName='next';type='Action';consequences=[pscustomobject]@{items=@((Trigger 'Sequence suivante' ($rootPath+'conductor/trigger')))}}
$init=[pscustomobject]@{niceName='Init';shortName='init';type='Action';consequences=[pscustomobject]@{items=@([pscustomobject]@{niceName='Relancer la sequence courante';type='Consequence';commandModule='generic';commandPath='';commandType='Script';command=[pscustomobject]@{script=[pscustomobject]@{parameters=@((P '/filePath' 'scripts/ConduiteInit.js'))}}})}}
$state.processors.items=@($conductor,$next,$init)
$project.sequences.items+=@($newSequences)
if($project.dashboardManager.items|Where-Object niceName -eq Conduite){throw 'Conduite dashboard already exists.'}
$project.dashboardManager.items+=@([pscustomobject]@{niceName='Conduite';shortName='conduite';type='BaseItem';itemManager=[pscustomobject]@{parameters=@((P '/canvasSize' @(420,620)));items=@((DashboardButton 'Next' 'next' ($rootPath+'next/trigger') 0 0),(DashboardButton 'Init' 'init' ($rootPath+'init/trigger') 200 0))+$buttons}})
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),(Json $project),(New-Object Text.UTF8Encoding($false)))
Write-Output "Created six sequences and Conduite dashboard: $OutputPath"
