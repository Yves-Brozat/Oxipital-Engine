param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$sourceFull=(Resolve-Path -LiteralPath $SourcePath).Path
$outputFull=[IO.Path]::GetFullPath($OutputPath)
if($sourceFull -eq $outputFull){throw 'Keep the saved show; use a separate output path.'}
$p=[IO.File]::ReadAllText($sourceFull)|ConvertFrom-Json
function Clone($n){$n|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json}
function Put($n,$k,$v){if($n.PSObject.Properties[$k]){$n.PSObject.Properties[$k].Value=$v}else{$n|Add-Member -NotePropertyName $k -NotePropertyValue $v}}
function Aspect($shape){if($shape -eq 'Plane'){@(1.0,.5625,1.0)}else{@(1.0,1.0,1.0)}}
$ox=$p.modules.items|Where-Object niceName -eq Oxipital
$state=$p.states.items|Where-Object niceName -eq 'CV Orb 1 -> OSC Oxipital'
if(!$ox -or !$state){throw 'Expected the preset-fixed Oxipital show.'}
foreach($number in 1..2){
    $key='orb'+$number
    $group=$p.customVariables.items|Where-Object {($_.niceName -replace ' ','') -eq $key}
    if(!$group){throw ('Missing '+$key)}
    if($group.variables.items|Where-Object shortName -eq emitterSize){throw 'Emitter Size already installed.'}
    $shape=($group.variables.items|Where-Object niceName -eq 'Emitter Shape').parameters[0].value
    $value=@(Aspect $shape)
    $variable=Clone ($group.variables.items|Where-Object niceName -eq 'Dancer Rotation')
    $variable.niceName='Emitter Size';Put $variable shortName emitterSize
    $param=$variable.parameters[0];$param.niceName='Emitter Size';$param.controlAddress='/emitterSize';$param.value=$value
    Put $param description 'Relative emitter dimensions; Unity normalizes the largest axis to 1. Dancer Size controls the overall radius.'
    $group.variables.items+=@($variable)
    foreach($preset in $group.presets.items){
        $aspect=@(Aspect $preset.values.containers.emitterShape.parameters[0].value)
        Put $preset.values.containers emitterSize ([pscustomobject]@{
            parameters=@([pscustomobject]@{controlAddress='/emitterSize';value=$aspect})
            owned=$true;niceName='Emitter Size'
        })
    }
    $dancer=$ox.params.containers.orbGroups.containers.('orbGroup'+$number).containers.dancer
    Put $dancer.containers emitterScale ([pscustomobject]@{
        parameters=@([pscustomobject]@{controlAddress='/baseValue';value=$value})
        owned=$true;niceName='Emitter Scale'
    })
    $target='/modules/oxipital/parameters/orbGroups/orbGroup'+$number+'/dancer/emitterScale/baseValue'
    $state.processors.items+=@([pscustomobject]@{
        niceName='Orb '+$number+' Emitter Size';shortName='orb'+$number+'EmitterSize';type='Mapping'
        im=[pscustomobject]@{items=@([pscustomobject]@{niceName='Input Value';type='Input Value';parameters=@([pscustomobject]@{controlAddress='/inputValue';value=('/customVariables/'+$key+'/variables/emitterSize/emitterSize')})})}
        params=[pscustomobject]@{parameters=@(
            [pscustomobject]@{controlAddress='/updateRate';value=30},
            [pscustomobject]@{controlAddress='/sendOnInputChangeOnly';value=$false},
            [pscustomobject]@{controlAddress='/sendOnOutputChangeOnly';value=$false},
            [pscustomobject]@{controlAddress='/sendOnActivate';value=$true}
        )}
        outputs=[pscustomobject]@{items=@([pscustomobject]@{
            niceName='MappingOutput';type='BaseItem';commandModule='generic';commandPath='';commandType='Set Parameter Value'
            command=[pscustomobject]@{parameters=@(
                [pscustomobject]@{controlAddress='/target';value=$target},
                [pscustomobject]@{controlAddress='/component';value='All'},
                [pscustomobject]@{controlAddress='/operator';value='Equals'}
            );paramLinks=[pscustomobject]@{value=[pscustomobject]@{linkType=1;mappingValueIndex=0}}}
        })}
    })
}
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFull))|Out-Null
[IO.File]::WriteAllText($outputFull,($p|ConvertTo-Json -Depth 100 -Compress),[Text.UTF8Encoding]::new($false))
'ORB_EMITTER_SIZE_READY: Orb1/Orb2 preset dimensions, round Sphere / normalized 16:9 Plane, existing Dancer Size retained.'
