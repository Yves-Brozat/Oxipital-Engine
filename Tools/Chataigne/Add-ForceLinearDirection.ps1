param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
if([IO.Path]::GetFullPath($SourcePath) -eq [IO.Path]::GetFullPath($OutputPath)){throw 'Use a separate output file.'}
$p=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
function Clone($n){$n|ConvertTo-Json -Depth 100|ConvertFrom-Json}
$g=$p.customVariables.items|Where-Object niceName -eq 'Force 1'
if($g.variables.items|Where-Object niceName -eq 'Linear Direction'){throw 'Linear Direction already exists'}
$cv=Clone ($g.variables.items|Where-Object niceName -eq Rotation)
$cv.niceName='Linear Direction'
$cv|Add-Member -NotePropertyName shortName -NotePropertyValue linearDirection -Force
$value=$cv.parameters|Where-Object controlAddress -eq '/rotation'
$value.controlAddress='/linearDirection';$value.niceName='Linear Direction';$value.value=@(0.0,0.0,0.0)
$value.description='World-space linear force direction. Zero uses the dancer forward direction.'
$g.variables.items+=@($cv)
$cascadeFound=$false
foreach($preset in $g.presets.items){
    $entry=Clone $preset.values.containers.rotation
    $entry.niceName='Linear Direction'
    $entry.parameters=@([pscustomobject]@{controlAddress='/linearDirection';value=@(0.0,0.0,0.0)})
    if($preset.niceName -eq 'Cascade'){$entry.parameters[0].value=@(0.0,1.0,0.0);$cascadeFound=$true}
    $preset.values.containers|Add-Member -NotePropertyName linearDirection -NotePropertyValue $entry -Force
}
if(!$cascadeFound){throw 'Cascade preset missing'}
$orb=$p.states.items|Where-Object niceName -eq 'CV Orb 1 -> OSC Oxipital'
$route=Clone ($orb.processors.items|Where-Object niceName -eq 'Orb 1 Emitter Size')
$route.niceName='Force 1 Linear Direction';$route.shortName='force1LinearDirection'
($route.im.items[0].parameters|Where-Object controlAddress -eq '/inputValue').value='/customVariables/force1/variables/linearDirection/linearDirection'
($route.outputs.items[0].command.parameters|Where-Object controlAddress -eq '/target').value='/modules/oxipital/parameters/forceGroups/forceGroup1/linear/linearDirection/baseValue'
$state=$p.states.items|Where-Object niceName -eq 'CV Force 1 -> OSC Oxipital'
$gate=($state.processors.items|Where-Object niceName -eq 'Preset Force Position Kinect').filters.items|Where-Object niceName -eq 'Performance Mode'
if(!$gate){throw 'Performance mode gate missing'}
$route.filters|Add-Member -NotePropertyName items -NotePropertyValue @((Clone $gate)) -Force
$state.processors.items+=@($route)
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),($p|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
'FORCE_LINEAR_DIRECTION_ADDED: Cascade (0,1,0), other presets (0,0,0).'
