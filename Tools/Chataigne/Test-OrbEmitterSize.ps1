param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Assert($ok,$message){if(!$ok){throw $message}}
function Json($n){ConvertTo-Json -InputObject $n -Depth 100 -Compress}
$old=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$p=Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8|ConvertFrom-Json
$ox=$p.modules.items|Where-Object niceName -eq Oxipital
$state=$p.states.items|Where-Object niceName -eq 'CV Orb 1 -> OSC Oxipital'
foreach($number in 1..2){
    $key='orb'+$number
    $group=$p.customVariables.items|Where-Object {($_.niceName -replace ' ','') -eq $key}
    Assert (@($group.variables.items|Where-Object shortName -eq emitterSize).Count -eq 1) 'Missing size variable'
    foreach($preset in $group.presets.items){
        $size=$preset.values.containers.emitterSize.parameters[0].value
        Assert ($size.Count -eq 3 -and $size[0] -eq 1 -and $size[2] -eq 1) 'Invalid preset dimensions'
        $shape=$preset.values.containers.emitterShape.parameters[0].value
        $expected=if($shape -eq 'Plane'){.5625}else{1.0}
        Assert ($size[1] -eq $expected) ('Wrong preset aspect '+$preset.niceName)
        $preset.values.containers.PSObject.Properties.Remove('emitterSize')
    }
    $mapping=$state.processors.items|Where-Object shortName -eq ('orb'+$number+'EmitterSize')
    Assert ($mapping.outputs.items[0].command.paramLinks.value.mappingValueIndex -eq 0) 'Missing size mapping value'
    $target=($mapping.outputs.items[0].command.parameters|Where-Object controlAddress -eq '/target').value
    Assert ($target -eq ('/modules/oxipital/parameters/orbGroups/orbGroup'+$number+'/dancer/emitterScale/baseValue')) 'Wrong emitter target'
    $group.variables.items=@($group.variables.items|Where-Object shortName -ne emitterSize)
    $prior=($old.modules.items|Where-Object niceName -eq Oxipital).params.containers.orbGroups.containers.('orbGroup'+$number).containers.dancer.containers
    $container=$ox.params.containers.orbGroups.containers.('orbGroup'+$number).containers.dancer.containers
    if($prior.PSObject.Properties['emitterScale']){$container.emitterScale=$prior.emitterScale}
    else{$container.PSObject.Properties.Remove('emitterScale')}
}
$state.processors.items=@($state.processors.items|Where-Object shortName -notin @('orb1EmitterSize','orb2EmitterSize'))
Assert ((Json $p) -ceq (Json $old)) 'Existing show/preset/size values were modified'
'ORB_EMITTER_SIZE_PASS: both Orb groups, every preset, Sphere round / Plane 16:9, mapping values and all previous show data preserved.'
