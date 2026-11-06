param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$sourceFull=(Resolve-Path -LiteralPath $SourcePath).Path
$outputFull=[IO.Path]::GetFullPath($OutputPath)
if($sourceFull -eq $outputFull){throw 'Use a separate output path.'}
$p=[IO.File]::ReadAllText($sourceFull)|ConvertFrom-Json
$module=$p.modules.items|Where-Object niceName -eq EN16
$state=$p.states.items|Where-Object shortName -eq kinectEN16
$bank=$state.processors.items|Where-Object niceName -eq 'Show Active EN16 Bank'
if(!$module -or !$bank){throw 'Expected EN16 MIDI module and existing bank action.'}
$device=$module.params.parameters|Where-Object controlAddress -eq '/devices'
if(!$device.outputName){throw 'EN16 MIDI output is not selected.'}
if(@($module.values.parameters|Where-Object{ $_.channel -eq 16 -and $_.pitchOrNumber -eq 119 }).Count){throw 'Reserved feedback channel/CC is already in use.'}
foreach($side in @('consequences','consequencesOff')){
    $list=$bank.PSObject.Properties[$side].Value
    if(@($list.items|Where-Object niceName -eq 'EN16 Bank LED Feedback').Count){throw 'LED feedback already installed.'}
    $value=if($side -eq 'consequences'){127}else{0}
    $command=[pscustomobject]@{
        niceName='EN16 Bank LED Feedback';type='Consequence'
        commandModule='en16';commandPath='';commandType='Control Change'
        command=[pscustomobject]@{
            parameters=@(
                [pscustomobject]@{controlAddress='/channel';value=16},
                [pscustomobject]@{controlAddress='/ccNumber';value=119},
                [pscustomobject]@{controlAddress='/ccValue';value=$value}
            )
            paramLinks=[pscustomobject]@{}
        }
    }
    $list.items=@($list.items)+@($command)
}
# Reapply the state after a controller reconnect or profile/page load. The
# dedicated feedback channel is never used by the encoder input mappings.
$state.processors.items+=@([pscustomobject]@{
    niceName='EN16 LED Bank Resync';shortName='en16LEDBankResync';type='Mapping'
    im=[pscustomobject]@{items=@([pscustomobject]@{niceName='Input Value';type='Input Value';parameters=@([pscustomobject]@{controlAddress='/inputValue';value='/customVariables/kinect/variables/en16KinectBank/en16KinectBank'})})}
    params=[pscustomobject]@{parameters=@(
        [pscustomobject]@{controlAddress='/updateRate';value=1},
        [pscustomobject]@{controlAddress='/sendOnInputChangeOnly';value=$false},
        [pscustomobject]@{controlAddress='/sendOnOutputChangeOnly';value=$false},
        [pscustomobject]@{controlAddress='/sendOnActivate';value=$true}
    )}
    filters=[pscustomobject]@{items=@(
        [pscustomobject]@{niceName='Convert To Float';type='Convert To Float';filterParams=[pscustomobject]@{paramLinks=[pscustomobject]@{}}},
        # Math restores its dynamic operand from operationValue after loading
        # filterParams. Without this property the multiplier becomes zero.
        [pscustomobject]@{niceName='Bank to CC value';type='Math';filterParams=[pscustomobject]@{parameters=@([pscustomobject]@{controlAddress='/operation';value='Multiply'},[pscustomobject]@{controlAddress='/value';value=127});paramLinks=[pscustomobject]@{}};operationValue=[pscustomobject]@{value=127;controlAddress='/states/kinectEN16/processors/en16LEDBankResync/filters/bankToCCValue/filterParams/value'}}
    )}
    outputs=[pscustomobject]@{items=@([pscustomobject]@{
        niceName='MappingOutput';type='BaseItem';commandModule='en16';commandPath='';commandType='Control Change'
        command=[pscustomobject]@{parameters=@([pscustomobject]@{controlAddress='/channel';value=16},[pscustomobject]@{controlAddress='/ccNumber';value=119});paramLinks=[pscustomobject]@{ccValue=[pscustomobject]@{linkType=1;mappingValueIndex=0}}}
    })}
})
[IO.File]::WriteAllText($outputFull,($p|ConvertTo-Json -Depth 100 -Compress),[Text.UTF8Encoding]::new($false))
'EN16_LED_FEEDBACK_PREPARED: channel 16 / CC119, Kinect=127 / Abysses=0, transition + 1 Hz reconnect sync. Requires the matching Grid receiver profile.'
