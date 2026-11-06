param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$before=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$after=Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8|ConvertFrom-Json
$g=$after.customVariables.items|Where-Object niceName -eq 'Force 1'
$v=@($g.variables.items|Where-Object shortName -eq linearDirection)
if($v.Count -ne 1 -or $v[0].parameters[0].controlAddress -ne '/linearDirection'){throw 'Invalid CV'}
foreach($preset in $g.presets.items){
    $expected=if($preset.niceName -eq 'Cascade'){'0,1,0'}else{'0,0,0'}
    if(($preset.values.containers.linearDirection.parameters[0].value -join ',') -ne $expected){throw "Wrong direction: $($preset.niceName)"}
    $preset.values.containers.PSObject.Properties.Remove('linearDirection')
}
$g.variables.items=@($g.variables.items|Where-Object shortName -ne linearDirection)
$state=$after.states.items|Where-Object niceName -eq 'CV Force 1 -> OSC Oxipital'
$r=@($state.processors.items|Where-Object shortName -eq force1LinearDirection)
if($r.Count -ne 1 -or ($r[0].im.items[0].parameters|Where-Object controlAddress -eq '/inputValue').value -ne '/customVariables/force1/variables/linearDirection/linearDirection'){throw 'Missing direction input'}
if(($r[0].outputs.items[0].command.parameters|Where-Object controlAddress -eq '/target').value -ne '/modules/oxipital/parameters/forceGroups/forceGroup1/linear/linearDirection/baseValue'){throw 'Wrong Unity bridge target'}
if($r[0].filters.items[0].niceName -ne 'Performance Mode'){throw 'Authoring guard missing'}
$state.processors.items=@($state.processors.items|Where-Object shortName -ne force1LinearDirection)
if(($before|ConvertTo-Json -Depth 100 -Compress) -cne ($after|ConvertTo-Json -Depth 100 -Compress)){throw 'Unrelated project data changed'}
'FORCE_LINEAR_DIRECTION_PASS: Cascade world up, other presets legacy direction, dancer transforms and all other data unchanged.'
