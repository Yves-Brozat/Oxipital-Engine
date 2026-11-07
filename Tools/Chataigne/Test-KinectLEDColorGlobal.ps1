param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Json($value){ConvertTo-Json -InputObject $value -Depth 100 -Compress}
$old=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $SourcePath).Path)|ConvertFrom-Json
$p=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $OutputPath).Path)|ConvertFrom-Json
$group=$p.customVariables.items|Where-Object niceName -eq Kinect
$oldGroup=$old.customVariables.items|Where-Object niceName -eq Kinect
$count=0
foreach($preset in $group.presets.items){
    $color=$preset.values.containers.en16LEDColor
    $modes=@($color.parameters|Where-Object controlAddress -eq '/mode')
    if($modes.Count -ne 1 -or $modes[0].value -ne 'None'){throw ('LED color still recalled by '+$preset.niceName)}
    $original=@($oldGroup.presets.items|Where-Object shortName -eq $preset.shortName)
    if($original.Count -ne 1){throw 'Preset identity changed.'}
    $color.parameters=$original[0].values.containers.en16LEDColor.parameters
    $count++
}
if(!$count){throw 'No Kinect presets checked.'}
# Restoring only the allowed mode edits must recover the entire source project:
# current color, stored colors, all scene settings, dashboard and MIDI routes.
if((Json $p) -cne (Json $old)){throw 'Unexpected edit outside Kinect LED preset modes.'}
'KINECT_LED_COLOR_GLOBAL_TEST_PASS: '+$count+' presets excluded; all other session data preserved.'
