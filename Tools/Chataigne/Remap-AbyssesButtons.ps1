param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Json($n){ConvertTo-Json -InputObject $n -Depth 100 -Compress}
function Clone($n){Json $n|ConvertFrom-Json}
function Value($n,$key){($n.parameters|Where-Object controlAddress -eq $key).value}
function Set-Value($n,$key,$value){$a=$n.parameters|Where-Object controlAddress -eq $key;if($a){$a.value=$value}else{$n.parameters=@($n.parameters)+@([pscustomobject]@{controlAddress=$key;value=$value})}}
function P($key,$value){[pscustomobject]@{controlAddress=$key;value=$value}}
function Trigger-Command($label,$target){[pscustomobject]@{niceName=$label;type='Consequence';commandModule='generic';commandPath='';commandType='Trigger a Control';command=[pscustomobject]@{parameters=@((P '/target' $target));paramLinks=[pscustomobject]@{}}}}
if([IO.Path]::GetFullPath($SourcePath) -eq [IO.Path]::GetFullPath($OutputPath)){throw 'Use a separate output file.'}
$p=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$dashboard=$p.dashboardManager.items|Where-Object niceName -eq Abysses
$conduite=$p.states.items|Where-Object niceName -eq Conduite
if(!$dashboard -or !$conduite){throw 'Expected Abysses dashboard and Conduite.'}
$root='/states/conduite/processors/'
$cue=$root+'conductor/processors/'
$specs=@(
    @('Launch All','/states/initialisation/processors/launchStart/trigger'),
    @('Init conduite',($root+'init/trigger')),
    @('Previous',($root+'previous/trigger')),
    @('Bank Kinect','/customVariables/kinect/variables/en16KinectBank/en16KinectBank'),
    @('Meduse',($cue+'meduse/trigger')),
    @('Cascade',($cue+'cascade/trigger')),
    @('Tornade',($cue+'tornade/trigger')),
    @('Reset','/states/initialisation/processors/resetCameraPosition/trigger'),
    @('Chute',($cue+'chute/trigger')),
    @('Tourbillon',($cue+'tourbillon/trigger')),
    @('Cercle',($cue+'cercle/trigger')),
    @('Sync','/states/initialisation/processors/syncData/trigger'),
    @('Next',($root+'next/trigger')),
    @('In/out radial','/states/effects/processors/switchInOutRadial/trigger'),
    @('180Z','/states/effects/processors/180Z/trigger'),
    @('Explosion','/states/effects/processors/explosion/trigger')
)
if(!$conduite.processors.items.Where({$_.shortName -eq 'previous'}).Count){
    $conduite.processors.items+=@([pscustomobject]@{niceName='Previous';shortName='previous';type='Action';consequences=[pscustomobject]@{items=@((Trigger-Command 'Sequence precedente' ($root+'conductor/triggerPrevious')))}})
}
# Remove obsolete direct subscriptions as a whole: retaining only a Kinect
# gate from a two-condition Leap action could otherwise trigger on bank changes.
function Disconnect-Inputs($nodes){foreach($n in $nodes){
    if($n.type -eq 'Action' -and @($n.conditions.items|Where-Object {(Value $_ '/inputValue') -match '^/customVariables/kinect/variables/en16AbyssesButton\d+/'}).Count){$n.conditions.items=@()}
    if($n.processors.items){Disconnect-Inputs $n.processors.items}
    if($n.containers.processors.items){Disconnect-Inputs $n.containers.processors.items}
    if($n.states.items){Disconnect-Inputs $n.states.items}
}}
Disconnect-Inputs $p.states.items
$conduite.processors.items=@($conduite.processors.items|Where-Object {$_.shortName -notmatch '^en16(meduse|chute|cascade|tornade|tourbillon|cercle)$'})
$original=@($dashboard.itemManager.items)
$template=$original|Where-Object type -eq DashboardTriggerItem|Select-Object -First 1
$widgets=@()
for($i=0;$i -lt 16;$i++){
    $slot=$i+1;$label=$specs[$i][0];$target=$specs[$i][1]
    $widget=$original|Where-Object {(Value $_ '/target') -eq $target}
    if(@($widget).Count -gt 1){throw "Duplicate widget for $target"}
    if(!$widget){$widget=$template}
    $widget=Clone $widget
    $widget.niceName="Abysses Push $slot"
    $widget|Add-Member -NotePropertyName shortName -NotePropertyValue "abyssesPush$slot" -Force
    $widget.ghostAddress=$target;$widget.controllable=$target
    Set-Value $widget '/target' $target
    Set-Value $widget '/customText' ("$slot $label")
    ($widget.parameters|Where-Object controlAddress -eq '/customText')|Add-Member -NotePropertyName enabled -NotePropertyValue $true -Force
    Set-Value $widget '/viewUIPosition' @((160+100*($i%4)),(-360+100*[Math]::Floor($i/4)))
    Set-Value $widget '/viewUISize' @(80,80)
    $widgets+=@($widget)
    if($slot -eq 4){continue} # The bank selector keeps its existing raw note.
    $buttonAddress="/customVariables/kinect/variables/en16AbyssesButton$slot/en16AbyssesButton$slot"
    $conduite.processors.items+=@([pscustomobject]@{
        niceName="EN16 Abysses $slot - $label";shortName="en16Abysses$slot";type='Action';editorIsCollapsed=$true
        conditions=[pscustomobject]@{items=@([pscustomobject]@{
            niceName='From Input Value';type='From Input Value';parameters=@((P '/inputValue' $buttonAddress))
            comparator=[pscustomobject]@{parameters=@((P '/comparisonFunction' '>'),(P '/reference' 0));hideInEditor=$true}
        })}
        consequences=[pscustomobject]@{items=@((Trigger-Command $label $target))}
    })
}
$removed=@('/states/initialisation/processors/launchOxipital/trigger','/customVariables/leapMotion/variables/sendOrbsPosition/sendOrbsPosition','/states/presets/processors/monteeDesEaux/trigger')
$replaced=@($specs|ForEach-Object {$_[1]})
$dashboard.itemManager.items=@($original|Where-Object {(Value $_ '/target') -notin ($removed+$replaced)})+@($widgets)
$save=$dashboard.itemManager.items|Where-Object {(Value $_ '/target') -eq '/states/savePresets/processors/saveNewPreset/trigger'}
if(@($save).Count -ne 1){throw 'Expected exactly one independent Save widget.'}
Set-Value $save '/viewUIPosition' @(560,-360)
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),(Json $p),[Text.UTF8Encoding]::new($false))
'ABYSSES_BUTTONS_READY: 16 numbered widgets, 15 isolated hardware actions, native Previous, Save outside the grid.'
