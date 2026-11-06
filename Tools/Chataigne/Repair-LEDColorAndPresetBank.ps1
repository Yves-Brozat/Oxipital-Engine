param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'EN16-ColorConversion.ps1')
$sourceFull=(Resolve-Path -LiteralPath $SourcePath).Path
$outputFull=[IO.Path]::GetFullPath($OutputPath)
if($sourceFull -eq $outputFull){throw 'Prepare a separate output before replacing the saved session.'}
$p=Get-Content -LiteralPath $sourceFull -Raw -Encoding UTF8|ConvertFrom-Json
$state=$p.states.items|Where-Object shortName -eq kinectEN16
foreach($i in 0..2){
    $name=@('Red','Green','Blue')[$i]
    $mapping=$state.processors.items|Where-Object shortName -eq ('en16LED'+$name)
    $math=@($mapping.filters.items|Where-Object type -eq Math)
    if(!$mapping -or $math.Count -ne 1 -or $mapping.filters.items.Count -gt 2){throw 'Unexpected LED mapping structure.'}
    # Accept the saved state after Chataigne discarded an unknown filter type.
    $mapping.filters.items=@((New-EN16ColorConversion $i)) + $math
}
$group=$p.customVariables.items|Where-Object niceName -eq Kinect
$protected=0
foreach($preset in $group.presets.items){
    $bank=$preset.values.containers.en16KinectBank
    if(!$bank){continue}
    # ParameterPreset's native "Mode=None" skips the variable on preset recall
    # and retains that behavior when the preset's values are updated later.
    $mode=$bank.parameters|Where-Object controlAddress -eq '/mode'
    if($mode){$mode.value='None'}else{$bank.parameters+=@([pscustomobject]@{controlAddress='/mode';value='None'})}
    $protected++
}
$meduse=($p.states.items|Where-Object niceName -eq Presets).processors.items|Where-Object niceName -eq Meduse
if(!$meduse){throw 'Missing Meduse show action.'}
# Keep the Meduse Orb/Force/Kinect presets, camera reset and internal sync.
# An unrelated Leap Motion mode preset is not part of this show cue.
$meduse.consequences.items=@($meduse.consequences.items|Where-Object {
    !( $_.commandType -eq 'Go to preset' -and ($_.command.parameters|Where-Object controlAddress -eq '/targetPreset').value -eq '/leapMotion/presets/orbOnly' )
})
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFull))|Out-Null
[IO.File]::WriteAllText($outputFull,($p|ConvertTo-Json -Depth 100 -Compress),[Text.UTF8Encoding]::new($false))
'LED_AND_BANK_REPAIR_READY: explicit RGB links; bank ignored by '+$protected+' Kinect presets; Meduse cue retains its own presets, camera reset and synchronization.'
