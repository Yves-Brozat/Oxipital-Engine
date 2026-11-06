param(
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$BaselinePath,
    [Parameter(Mandatory=$true)][string]$TargetPath,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference='Stop'
function Json($n){ConvertTo-Json -InputObject $n -Depth 100 -Compress}
function Same($a,$b){(Json $a) -ceq (Json $b)}
function Clone($n){if($null -eq $n){return $null};ConvertFrom-Json -InputObject (Json $n)}
function Object($n){$null -ne $n -and $n -is [pscustomobject]}
$sourceFull=(Resolve-Path -LiteralPath $SourcePath).Path
$baseFull=(Resolve-Path -LiteralPath $BaselinePath).Path
$targetFull=(Resolve-Path -LiteralPath $TargetPath).Path
$outputFull=[IO.Path]::GetFullPath($OutputPath)
if($outputFull -in @($sourceFull,$baseFull,$targetFull)){throw 'Write the merge to a separate file.'}
$source=Get-Content -LiteralPath $sourceFull -Raw -Encoding UTF8|ConvertFrom-Json
$baseline=Get-Content -LiteralPath $baseFull -Raw -Encoding UTF8|ConvertFrom-Json
$target=Get-Content -LiteralPath $targetFull -Raw -Encoding UTF8|ConvertFrom-Json
$before=Clone $target
$script:edits=0
function Merge-Node($destination,$edited,$original,[string]$path){
    # Walk only changes since the older session's baseline. New properties in
    # the target (e.g. Emitter Size) are not present in that delta and survive.
    $keys=@(@($edited.PSObject.Properties.Name)+@($original.PSObject.Properties.Name)|Select-Object -Unique)
    foreach($key in $keys){
        $s=$edited.PSObject.Properties[$key];$b=$original.PSObject.Properties[$key];$d=$destination.PSObject.Properties[$key]
        if(($null -eq $s) -eq ($null -eq $b) -and (Same $s.Value $b.Value)){continue}
        $where=$path+'/'+$key
        if($s -and $b -and $d -and (Object $s.Value) -and (Object $b.Value) -and (Object $d.Value)){
            Merge-Node $d.Value $s.Value $b.Value $where
            continue
        }
        if(!(Same $d.Value $b.Value) -and !(Same $d.Value $s.Value)){throw ('Conflicting preset edit: '+$where)}
        if($s){
            if($d){$d.Value=Clone $s.Value}
            else{$destination|Add-Member -NotePropertyName $key -NotePropertyValue (Clone $s.Value)}
            if(!(Same $destination.PSObject.Properties[$key].Value $s.Value)){throw ('Merge verification failed: '+$where)}
        }else{$destination.PSObject.Properties.Remove($key)}
        $script:edits++
    }
}
$merged=0
foreach($group in $source.customVariables.items){
    $bg=$baseline.customVariables.items|Where-Object niceName -eq $group.niceName
    $tg=$target.customVariables.items|Where-Object niceName -eq $group.niceName
    foreach($preset in $group.presets.items){
        $bp=$bg.presets.items|Where-Object niceName -eq $preset.niceName
        if(Same $preset $bp){continue}
        if($preset.niceName -notmatch '^(Meduse|Cascade|Cascade end)$'){throw ('Unexpected edited preset: '+$group.niceName+' / '+$preset.niceName)}
        $tp=$tg.presets.items|Where-Object niceName -eq $preset.niceName
        if(!$bp -or !$tp){throw 'Missing baseline/target preset; review new or renamed presets separately.'}
        Merge-Node $tp $preset $bp ($group.niceName+'/'+$preset.niceName)
        $merged++
        'MERGED: '+$group.niceName+' / '+$preset.niceName
    }
}
if(!$merged){throw 'No saved preset edits found.'}
$result=Json $target
# Restoring just the preset collections must reproduce the complete target:
# no changes to current CV values, OSC routes, dashboards, or LED controls.
foreach($group in $target.customVariables.items){
    $prior=$before.customVariables.items|Where-Object niceName -eq $group.niceName
    if($group.PSObject.Properties['presets']){$group.presets=Clone $prior.presets}
}
if(!(Same $target $before)){throw 'Unexpected changes outside preset collections.'}
$checked=$result|ConvertFrom-Json
foreach($name in @('Orb1','Orb2')){
    $presets=($checked.customVariables.items|Where-Object niceName -eq $name).presets.items
    foreach($preset in $presets){if(!$preset.values.containers.emitterSize){throw 'New Emitter Size data was lost.'}}
}
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFull))|Out-Null
[IO.File]::WriteAllText($outputFull,$result,[Text.UTF8Encoding]::new($false))
'PRESET_MERGE_PASS: '+$merged+' presets / '+$script:edits+' changed fields; no conflicts; Emitter Size and all non-preset show data preserved.'
