param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
if([IO.Path]::GetFullPath($SourcePath) -eq [IO.Path]::GetFullPath($OutputPath)){throw 'Use a separate output file.'}
$p=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
function Clone($n){$n|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json}
function Put($n,$key,$value){$n|Add-Member -NotePropertyName $key -NotePropertyValue $value -Force}
function Param($n,$key,$value){
    $a=$n.parameters|Where-Object controlAddress -eq $key
    if($a){$a.value=$value}else{Put $n parameters (@($n.parameters)+@([pscustomobject]@{controlAddress=$key;value=$value}))}
}
function Gate($name,$address,$expected){
    [pscustomobject]@{niceName=$name;type='Condition';filterParams=[pscustomobject]@{paramLinks=[pscustomobject]@{}};conditions=[pscustomobject]@{items=@([pscustomobject]@{niceName='From Input Value';type='From Input Value';parameters=@([pscustomobject]@{controlAddress='/inputValue';value=$address});comparator=[pscustomobject]@{parameters=@([pscustomobject]@{controlAddress='/reference';value=$expected})}})}}
}
$kinect='/customVariables/kinect/variables/kinectEnabled/kinectEnabled'
$editing='/modules/oxipital/parameters/setup/unityEditMode'
$quest='/states/metaQuestOSC__Oxipital/enabled'
foreach($kind in 'Orb','Force'){
    $state=$p.states.items|Where-Object niceName -eq "CV $kind 1 -> OSC Oxipital"
    $mux=$state.processors.items|Where-Object niceName -eq "$kind P3D"
    $original=$mux.containers.processors.items|Where-Object {($_.im.items[0].parameters|Where-Object controlAddress -eq '/inputList').value -eq '/questFinalValues'}
    if(!$original -or @($original).Count -ne 1){throw "Missing legacy $kind position route"}
    # Undo the preceding repair: it changed all four P3D channels and missed
    # the important case where both Kinect and the Quest state are disabled.
    if($mux.containers.processors.items|Where-Object niceName -eq "$kind 1 Kinect Preset Values"){
        $mux.containers.processors.items=@($mux.containers.processors.items|Where-Object niceName -ne "$kind 1 Kinect Preset Values")
        $original.filters.items=@($original.filters.items|Where-Object niceName -notin 'Quest Position Route','Performance Mode')
    }
    $sum=$state.processors.items|Where-Object niceName -eq "Preset plus Quest $kind Offset"
    if(!$sum){throw "Missing $kind offset calculation"}
    if($state.processors.items|Where-Object niceName -eq "Preset $kind Position Without Quest"){throw 'Position repair v2 already installed.'}
    foreach($branch in 'Kinect','Without Quest'){
        $direct=Clone $sum
        $direct.niceName="Preset $kind Position $branch"
        Put $direct shortName ('preset'+$kind+'Position'+($branch -replace ' ',''))
        Param $direct.params '/sendOnInputChangeOnly' $false
        $direct.filters.items=@((Gate 'Performance Mode' $editing $false),(Gate 'Kinect Position Route' $kinect ($branch -eq 'Kinect')))
        if($branch -eq 'Without Quest'){$direct.filters.items+=@((Gate 'Quest State Disabled' $quest $false))}
        $state.processors.items+=@($direct)
    }
    # Only an explicitly enabled Quest state may add its hand displacement.
    $sum.filters.items=@($sum.filters.items)+@((Gate 'Quest State Enabled' $quest $true),(Gate 'Kinect Position Route' $kinect $false),(Gate 'Performance Mode' $editing $false))
}
$json=$p|ConvertTo-Json -Depth 100
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),$json,[Text.UTF8Encoding]::new($false))
Write-Output 'KINECT_PRESET_POSITION_ROUTING_REPAIRED'
