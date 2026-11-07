param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$sourceFull=(Resolve-Path -LiteralPath $SourcePath).Path
$outputFull=[IO.Path]::GetFullPath($OutputPath)
if($sourceFull -eq $outputFull){throw 'Prepare a separate output before replacing the saved session.'}
$p=[IO.File]::ReadAllText($sourceFull)|ConvertFrom-Json
$group=$p.customVariables.items|Where-Object niceName -eq Kinect
if(@($group.variables.items|Where-Object shortName -eq en16LEDColor).Count -ne 1){throw 'Expected one Kinect EN16 LED color variable.'}
$protected=0
foreach($preset in $group.presets.items){
    $color=$preset.values.containers.en16LEDColor
    if(!$color){throw ('Missing LED color in Kinect preset: '+$preset.niceName)}
    # Native ParameterPreset mode None ignores recall, including interpolation,
    # and survives Update Values. Keep the shared CV and dashboard/MIDI routes.
    $mode=@($color.parameters|Where-Object controlAddress -eq '/mode')
    if($mode.Count -gt 1){throw 'Duplicate preset mode.'}
    if($mode.Count){$mode[0].value='None'}else{
        $color.parameters+=@([pscustomobject]@{controlAddress='/mode';value='None'})
    }
    $protected++
}
if(!$protected){throw 'No Kinect presets found.'}
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFull))|Out-Null
[IO.File]::WriteAllText($outputFull,($p|ConvertTo-Json -Depth 100 -Compress),[Text.UTF8Encoding]::new($false))
'KINECT_LED_COLOR_GLOBAL: '+$protected+' presets ignore the shared LED color.'
