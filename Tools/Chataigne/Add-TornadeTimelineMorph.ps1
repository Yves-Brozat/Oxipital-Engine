param(
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [double]$MorphDuration=70,
    [ValidateSet('Tornade','Cascade','Chute')][string]$Scene='Tornade'
)
$ErrorActionPreference='Stop'
if($MorphDuration -le 0 -or [double]::IsNaN($MorphDuration) -or [double]::IsInfinity($MorphDuration)){throw 'MorphDuration must be finite and positive.'}
if([IO.Path]::GetFullPath($SourcePath) -eq [IO.Path]::GetFullPath($OutputPath)){throw 'Prepare a separate output file.'}
function Json($x){ConvertTo-Json -InputObject $x -Depth 100 -Compress}
function P($key,$value){[pscustomobject]@{controlAddress=$key;value=$value}}
function Value($n,$key){($n.parameters|Where-Object controlAddress -eq $key).value}
function Set-Value($n,$key,$value){$a=$n.parameters|Where-Object controlAddress -eq $key;if($a){$a.value=$value}else{$n.parameters=@($n.parameters)+@((P $key $value))}}
function Command($label,$type,$parameters){[pscustomobject]@{niceName=$label;type='Consequence';commandModule='customVariables';commandPath='';commandType=$type;command=[pscustomobject]@{parameters=@($parameters);paramLinks=[pscustomobject]@{}}}}
$p=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$sceneKey=$Scene.ToLowerInvariant();$startKey=$sceneKey+'Start';$layerKey=$sceneKey+'Morph'
$kinectEndKey=switch($Scene){'Cascade'{'scene07'}'Chute'{'scene02'}default{'scene09'}}
$sequence=$p.sequences.items|Where-Object shortName -eq $sceneKey
if(@($sequence).Count -ne 1){throw "Expected one $Scene sequence."}
if($sequence.layers.items|Where-Object shortName -eq $layerKey){throw 'Timeline morph already installed.'}
$init=$sequence.layers.items.triggers.items|Where-Object niceName -eq 'Init - preset actuel'
if(@($init).Count -ne 1){throw "Expected the existing $Scene initialization event."}
$targets=@(@('force1','Force 1',$sceneKey),@('orb1','Orb1',$sceneKey),@('kinect','Kinect',$kinectEndKey))
$outputs=@();$stops=@();$starts=@()
foreach($spec in $targets){
    $key=$spec[0];$label=$spec[1];$endKey=$spec[2]
    $group=$p.customVariables.items|Where-Object niceName -eq $label
    $start=$group.presets.items|Where-Object shortName -eq $startKey
    $end=$group.presets.items|Where-Object {($_.shortName -eq $endKey) -or ($_.niceName -eq $Scene -and !$_.shortName)}
    if(@($start).Count -ne 1 -or @($end).Count -ne 1){throw "Missing preset pair in $label"}
    $startAddress="/$key/presets/$startKey";$endAddress="/$key/presets/$endKey"
    $stops+=@(Command ("Stop previous morph - $label") 'Kill Go to preset' @((P '/targetGroup' "/$key")))
    $starts+=@(Command ("Start - $label") 'Set Preset' @((P '/targetPreset' $startAddress)))
    $outputs+=@([pscustomobject]@{
        niceName="$label - Start vers $Scene";type='BaseItem';commandModule='customVariables';commandPath='';commandType='Interpolate presets'
        command=[pscustomobject]@{
            parameters=@((P '/targetPreset' $startAddress),(P '/targetPreset2' $endAddress),(P '/value' 0))
            paramLinks=[pscustomobject]@{value=[pscustomobject]@{linkType=1;mappingValueIndex=0}}
        }
    })
}
# Keep the background-off and other scene setup commands; replace only the
# three preset pairs previously recalled by independent wall-clock timers.
$addresses=@($targets|ForEach-Object {"/$($_[0])/presets/$startKey";"/$($_[0])/presets/$($_[2])"})
$remaining=@($init.consequences.items|Where-Object {
    !($_.commandModule -eq 'customVariables' -and $_.commandType -in @('Set Preset','Go to preset') -and (Value $_.command '/targetPreset') -in $addresses)
})
foreach($c in $remaining){
    # This bridge setting schedules final resends; the timeline supplies the
    # evolving values, so no separate four-second preset recall is needed.
    if((Value $c.command '/target') -eq '/modules/oxipital/parameters/setup/presetApplyDuration'){Set-Value $c.command '/value' 0}
}
$init.consequences.items=@($stops)+@($starts)+@($remaining)
$init.niceName="Init - $Scene Start"
$morphStart=0.1;$morphEnd=$morphStart+$MorphDuration
$length=[Math]::Max([double](Value $sequence '/totalTime'),[Math]::Ceiling($morphEnd+4))
Set-Value $sequence '/totalTime' $length
Set-Value $sequence '/viewEndTime' $length
$layer=[pscustomobject]@{
    niceName="Morph $Scene - Start vers $Scene";shortName=$layerKey;type='Mapping'
    parameters=@((P '/uiHeight' 180),(P '/listSize' 180),(P '/sendOnSeek' $true),(P '/sendOnPlay' $true),(P '/sendOnStop' $true))
    containers=[pscustomobject]@{
        automation=[pscustomobject]@{
            parameters=@((P '/length' $length),(P '/viewValueRange' @(0,1)),[pscustomobject]@{controlAddress='/range';value=@(0,1);enabled=$true})
            hideInEditor=$true;hideInRemoteControl=$false
            items=@(
                [pscustomobject]@{niceName='Start - 0 pour cent';type='Key';parameters=@((P '/position' $morphStart),(P '/value' 0),(P '/easingType' 'Linear'))},
                [pscustomobject]@{niceName="$Scene - 100 pour cent";type='Key';parameters=@((P '/position' $morphEnd),(P '/value' 1),(P '/easingType' 'Linear'))}
            )
        }
        mapping=[pscustomobject]@{
            niceName='Mapping';type='Mapping'
            im=[pscustomobject]@{hideInEditor=$true;items=@([pscustomobject]@{niceName='Input Value';type='Input Value';parameters=@((P '/inputValue' ''))})}
            params=[pscustomobject]@{parameters=@((P '/updateRate' 50))}
            filters=[pscustomobject]@{}
            outputs=[pscustomobject]@{items=@($outputs)}
        }
    }
}
$sequence.layers.items+=@($layer)
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),(Json $p),[Text.UTF8Encoding]::new($false))
Write-Output "$($Scene.ToUpperInvariant())_TIMELINE_MORPH_READY: $MorphDuration seconds, one 0..1 curve for Force 1 / Orb1 / Kinect, sequence length $length seconds."
