param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Json($n){ConvertTo-Json -InputObject $n -Depth 100 -Compress}
function P($key,$value){[pscustomobject]@{controlAddress=$key;value=$value}}
function Value($n,$key){($n.parameters|Where-Object controlAddress -eq $key).value}
function Set-Value($n,$key,$value){$v=$n.parameters|Where-Object controlAddress -eq $key;if($v){$v.value=$value}else{$n.parameters=@($n.parameters)+@((P $key $value))}}
if([IO.Path]::GetFullPath($SourcePath) -eq [IO.Path]::GetFullPath($OutputPath)){throw 'Use a separate output file.'}
$p=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$chute=$p.sequences.items|Where-Object niceName -eq Chute
$first=$chute.layers.items|Where-Object niceName -eq 'Morph Chute - Start vers Chute'
$second=$chute.layers.items|Where-Object niceName -eq 'Morph Chute vers Chute - End'
if(@($first).Count -ne 1 -or @($second).Count -ne 1){throw 'Expected both Chute morph curves.'}
$first|Add-Member -NotePropertyName shortName -NotePropertyValue chuteMorph -Force
$second|Add-Member -NotePropertyName shortName -NotePropertyValue chuteEndMorph -Force
$key=$second.containers.automation.items|Sort-Object {Value $_ '/position'}|Select-Object -First 1
$key|Add-Member -NotePropertyName shortName -NotePropertyValue phaseStart -Force
$boundary='/sequences/chute/layers/chuteEndMorph/automation/phaseStart/position'
foreach($spec in @(@($first,'<'),@($second,'>='))){
    $layer=$spec[0];$comparison=$spec[1]
    # Stop hands the currently applied values to the outgoing fade. A final
    # automation send during stop/rewind must not reapply a lower curve value.
    Set-Value $layer '/sendOnStop' $false
    $condition=[pscustomobject]@{
        niceName='Follow Chute End first key';type='Condition'
        filterParams=[pscustomobject]@{paramLinks=[pscustomobject]@{}}
        conditions=[pscustomobject]@{items=@([pscustomobject]@{
            niceName='From Input Value';type='From Input Value';parameters=@((P '/inputValue' '/sequences/chute/currentTime'))
            comparator=[pscustomobject]@{hideInEditor=$true;parameters=@(
                (P '/comparisonFunction' $comparison),
                [pscustomobject]@{controlAddress='/reference';value=(Value $key '/position');controlMode=2;reference=[pscustomobject]@{value=$boundary;controlAddress='/reference'}}
            )}
        })}
    }
    # Replace only the old phase filter, keeping other user-authored filters.
    $remaining=@($layer.containers.mapping.filters.items|Where-Object {$_.niceName -notin @('Before Chute End morph','Chute End morph active','Follow Chute End first key')})
    $layer.containers.mapping.filters|Add-Member -NotePropertyName items -NotePropertyValue (@($condition)+$remaining) -Force
}
$force2=$p.customVariables.items|Where-Object niceName -eq 'Force 2'
$release=$force2.presets.items|Where-Object shortName -eq transitionRelease
if(!$release){$release=$force2.presets.items|Where-Object niceName -eq 'Transition Release'}
if(@($release).Count -ne 1){throw 'Missing Force2 release preset.'}
Set-Value $release.values.containers.linearIntensity '/mode' 'Interpolate'
Set-Value $release.values.containers.linearIntensity '/linearIntensity' 0
# Keep count, orientation and normalized direction until the force is silent.
foreach($field in @('count','linearDirection','rotation')){Set-Value $release.values.containers.$field '/mode' 'None'}
$tourbillon=$force2.presets.items|Where-Object niceName -eq Tourbillon
if((Value $tourbillon.values.containers.count '/count') -ne 0){throw 'Tourbillon has a live Force2 background; do not replace it with a release.'}
$changed=0
$actions=@(($p.states.items|Where-Object niceName -eq Presets).processors.items)
$actions+=@(($p.sequences.items|Where-Object niceName -eq Tourbillon).layers.items.triggers.items)
foreach($action in $actions){
    $items=@($action.consequences.items)
    $usesOrb1=@($items|Where-Object {(Value $_.command '/targetPreset') -like '/orb1/presets/*'}).Count -gt 0
    if(!$usesOrb1){continue}
    foreach($c in $items|Where-Object {(Value $_.command '/targetPreset') -eq '/force2/presets/tourbillon'}){
        $c.niceName='Crossfade - release Force2 without removing dancers'
        $c.commandType='Go to preset'
        Set-Value $c.command '/targetPreset' '/force2/presets/transitionRelease'
        Set-Value $c.command '/interpolationTime' 10
        ($c.command.parameters|Where-Object controlAddress -eq '/interpolationTime')|Add-Member -NotePropertyName enabled -NotePropertyValue $true -Force
        $changed++
    }
}
if($changed -lt 2){throw 'Expected Tourbillon recall and timeline release routes.'}
# A zero slope at both ends softens the release instead of ending a linear
# ramp with an abrupt derivative change. Use the native Bezier schema.
foreach($action in @($actions)+@($p.sequences.items.layers.items.triggers.items)){
    foreach($c in $action.consequences.items|Where-Object {(Value $_.command '/targetPreset') -eq '/force2/presets/transitionRelease'}){
        $curve=[pscustomobject]@{niceName='Interpolation Curve';owned=$true;parameters=@((P '/length' 1),(P '/viewValueRange' @(0,1)),[pscustomobject]@{controlAddress='/range';value=@(0,1);enabled=$true},(P '/enabled' $true));items=@(
            [pscustomobject]@{niceName='Key';type='Key';parameters=@((P '/position' 0),(P '/value' 0),(P '/easingType' 'Bezier'));containers=[pscustomobject]@{easing=[pscustomobject]@{parameters=@((P '/anchor1' @(0.3,0)),(P '/anchor2' @(-0.3,0)))}}},
            [pscustomobject]@{niceName='Key 1';type='Key';parameters=@((P '/position' 1),(P '/value' 1),(P '/easingType' 'Linear'))}
        )}
        if(!$c.command.containers){$c.command|Add-Member -NotePropertyName containers -NotePropertyValue ([pscustomobject]@{})}
        $c.command.containers|Add-Member -NotePropertyName interpolationCurve -NotePropertyValue $curve -Force
    }
}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),(Json $p),[Text.UTF8Encoding]::new($false))
'CHUTE_FLEXIBLE_READY: phase boundary follows End first key; edited curve times preserved; linear/global Force2 release with smooth endpoints; no zero-count Tourbillon recall.'
