param(
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [ValidateRange(0.1,120)][double]$FadeDuration=10
)
$ErrorActionPreference='Stop'
function Json($n){ConvertTo-Json -InputObject $n -Depth 100 -Compress}
function Clone($n){Json $n|ConvertFrom-Json}
function P($key,$value){[pscustomobject]@{controlAddress=$key;value=$value}}
function Value($n,$key){($n.parameters|Where-Object controlAddress -eq $key).value}
function Command($label,$type,$parameters,$module='customVariables'){
    [pscustomobject]@{niceName=$label;type='Consequence';commandModule=$module;commandPath='';commandType=$type;command=[pscustomobject]@{parameters=@($parameters);paramLinks=[pscustomobject]@{}}}
}
if([IO.Path]::GetFullPath($SourcePath) -eq [IO.Path]::GetFullPath($OutputPath)){throw 'Use a separate output file.'}
$p=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$show=@('meduse','chute','cascade','tornade','tourbillon','cercle')
foreach($spec in @(@('Orb1','Orb2','dancerIntensity'),@('Force 1','Force 2','intensity'))){
    $from=$p.customVariables.items|Where-Object niceName -eq $spec[0]
    $to=$p.customVariables.items|Where-Object niceName -eq $spec[1]
    foreach($name in @('Chute','Chute - Start')){
        $source=$from.presets.items|Where-Object niceName -eq $name
        if(@($source).Count -ne 1){throw "Missing $name in $($spec[0])"}
        if($to.presets.items|Where-Object niceName -eq $name){throw "Already installed: $name in $($spec[1])"}
        $to.presets.items+=@((Clone $source))
    }
}
# Explicit None modes protect all other values, including after Chataigne
# reconstructs its preset containers on load. Only intensity interpolates.
foreach($spec in @(@('Orb1','dancerIntensity'),@('Orb2','dancerIntensity'),@('Force 1','intensity'),@('Force 2','intensity'))){
    $g=$p.customVariables.items|Where-Object niceName -eq $spec[0]
    if($g.presets.items|Where-Object shortName -eq transitionRelease){throw 'Crossfade already installed.'}
    $containers=Clone $g.presets.items[0].values.containers
    foreach($field in $containers.PSObject.Properties){
        $field.Value.parameters=@($field.Value.parameters|Where-Object controlAddress -ne '/mode')
        $mode=if($field.Name -eq $spec[1]){'Interpolate'}else{'None'}
        $field.Value.parameters+=@((P '/mode' $mode))
    }
    ($containers.($spec[1]).parameters|Where-Object controlAddress -eq ('/'+$spec[1])).value=0
    $g.presets.items+=@([pscustomobject]@{niceName='Transition Release';shortName='transitionRelease';type='MorphTarget';values=[pscustomobject]@{containers=$containers}})
}
function Remap-Chute($node){
    # Scoped to Chute actions/layers: keep the original Orb1/Force1 presets as
    # archival data, and leave all unrelated scene values alone.
    (Json $node).Replace('/orb1','/orb2').Replace('/force1','/force2').Replace('Orb1','Orb2').Replace('Force 1','Force 2')|ConvertFrom-Json
}
$presets=$p.states.items|Where-Object niceName -eq Presets
foreach($state in $p.states.items|Where-Object niceName -in @('Presets','Save Presets')){
    $state.processors.items=@($state.processors.items|ForEach-Object {
        if($_.niceName -in @('Chute','Chute - Start','Update Chute','Update Chute - Start') -or $_.shortName -in @('chute','chuteStart','updatechute','updatechuteStart')){Remap-Chute $_}else{$_}
    })
}
$chute=$p.sequences.items|Where-Object shortName -eq chute
if(@($chute).Count -ne 1){throw 'Missing Chute sequence.'}
$chute.layers.items=@($chute.layers.items|ForEach-Object {Remap-Chute $_})
$init=$chute.layers.items.triggers.items|Select-Object -First 1
($init.parameters|Where-Object controlAddress -eq /time).value=0.05
foreach($preset in ($p.customVariables.items|Where-Object niceName -eq Kinect).presets.items|Where-Object niceName -in @('Chute','Chute - Start')){
    foreach($key in @('orbGroupNumber','forceGroupNumber')){($preset.values.containers.$key.parameters|Where-Object controlAddress -eq ('/'+$key)).value=2}
}
$tools=$p.customVariables.items|Where-Object shortName -eq presetTools
$selector=($tools.variables.items|Where-Object shortName -eq selectedPreset).parameters|Where-Object controlAddress -eq /selectedPreset
foreach($name in @('Chute','Chute - Start')){
    $selector.enumOptions.$name.targets=@($selector.enumOptions.$name.targets|ForEach-Object {$_.Replace('/orb1/','/orb2/').Replace('/force1/','/force2/')})
}
function Add-Crossfade($action,$currentSequence=''){
    $items=@($action.consequences.items)
    $orbTargets=@($items|Where-Object commandModule -eq customVariables|ForEach-Object {Value $_.command '/targetPreset'}|Where-Object {$_ -match '^/orb[12]/presets/'})
    if(!$orbTargets.Count){return}
    $groups=@($orbTargets|ForEach-Object {$_.Split('/')[1]}|Select-Object -Unique)
    if($groups.Count -ne 1){return} # Deliberately simultaneous authored scenes.
    $incoming=if($groups[0] -eq 'orb1'){1}else{2};$outgoing=3-$incoming
    # The old immediate background-off preset would cut Chute's Force2.
    $items=@($items|Where-Object {(Value $_.command '/targetPreset') -ne '/force2/presets/tourbillonBackgroundOff'})
    $prefix=@()
    foreach($key in $show|Where-Object {$_ -ne $currentSequence}){
        $prefix+=@(Command "Crossfade - stop $key timeline" 'Trigger a Control' @((P '/target' "/sequences/$key/stop")) 'generic')
    }
    foreach($group in @('orb1','orb2','force1','force2','kinect')){
        $prefix+=@(Command "Crossfade - cancel $group interpolation" 'Kill Go to preset' @((P '/targetGroup' "/$group")))
    }
    $releaseGroups=@("orb$outgoing")
    # Tourbillon has an intentional Force2 background; keep its recall.
    $hasOutgoingForce=@($items|Where-Object {(Value $_.command '/targetPreset') -like "/force$outgoing/presets/*"}).Count -gt 0
    if(!$hasOutgoingForce){$releaseGroups+=@("force$outgoing")}
    foreach($group in $releaseGroups){
        $prefix+=@(Command "Crossfade - release $group" 'Go to preset' @((P '/targetPreset' "/$group/presets/transitionRelease"),[pscustomobject]@{controlAddress='/interpolationTime';value=$FadeDuration;enabled=$true}))
    }
    $action.consequences.items=@($prefix)+@($items)
}
foreach($action in $presets.processors.items){Add-Crossfade $action}
foreach($sequence in $p.sequences.items|Where-Object shortName -in $show){
    foreach($event in $sequence.layers.items.triggers.items){Add-Crossfade $event $sequence.shortName}
}
# Chataigne otherwise renames duplicate cue addresses at load. Preserve the
# first /chute address used by the EN16, and give repetitions stable names.
$conductor=($p.states.items|Where-Object niceName -eq Conduite).processors.items|Where-Object type -eq Conductor
$index=0
foreach($cue in $conductor.containers.processors.items|Where-Object {(Value $_.sequenceLinking '/linkedSequence') -eq '/chute'}){
    $index++;if($index -gt 1){$cue.shortName='chute'+$index}
}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),(Json $p),[Text.UTF8Encoding]::new($false))
"ORB_CROSSFADE_READY: Chute on Orb2/Force2; $FadeDuration second outgoing release; recall, timeline, Kinect and authoring routes updated."
