param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'EN16-ColorConversion.ps1')
$sourceFull=(Resolve-Path -LiteralPath $SourcePath).Path
$outputFull=[IO.Path]::GetFullPath($OutputPath)
if($sourceFull -eq $outputFull){throw 'Keep the saved session; use a separate output path.'}
$p=[IO.File]::ReadAllText($sourceFull)|ConvertFrom-Json
$group=$p.customVariables.items|Where-Object niceName -eq Kinect
$state=$p.states.items|Where-Object shortName -eq kinectEN16
$dash=$p.dashboardManager.items|Where-Object niceName -eq 'Abysses Kinect'
if(!$group -or !$state -or !$dash){throw 'Expected Kinect variables, EN16 state and dashboard.'}
if(@($group.variables.items|Where-Object shortName -eq en16LEDColor).Count){throw 'LED color is already installed.'}
$address='/customVariables/kinect/variables/en16LEDColor/en16LEDColor'
$group.variables.items+=@([pscustomobject]@{
    niceName='EN16 LED Color';shortName='en16LEDColor';type='Color Parameter'
    parameters=@([pscustomobject]@{
        controlAddress='/en16LEDColor';value=@(1.0,(210.0/255),0.0,1.0)
        type='Color';niceName='EN16 LED Color';customizable=$true;removable=$false
        feedbackOnly=$false;hideInEditor=$false
        description='Color of the EN16 LEDs in the Kinect software bank. Alpha is ignored.'
    })
})
# Reuse the exact firmware-confirmed MIDI output and refresh behavior.
$resync=$state.processors.items|Where-Object shortName -eq en16LEDBankResync
if(!$resync){throw 'Install the bank LED feedback first.'}
$bankMath=$resync.filters.items|Where-Object type -eq Math
($bankMath.filterParams.parameters|Where-Object controlAddress -eq '/value').value=127
$bankMath|Add-Member -Force -NotePropertyName operationValue -NotePropertyValue ([pscustomobject]@{
    value=127;controlAddress='/states/kinectEN16/processors/en16LEDBankResync/filters/bankToCCValue/filterParams/value'
})
foreach($component in 0..2){
    $name=@('Red','Green','Blue')[$component]
    $short='en16LED'+$name
    $mapping=$resync|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json
    $mapping.niceName='EN16 LED '+$name
    $mapping.shortName=$short
    ($mapping.im.items[0].parameters|Where-Object controlAddress -eq '/inputValue').value=$address
    $mapping.filters.items=@(
        (New-EN16ColorConversion $component),
        [pscustomobject]@{
            niceName='Color to MIDI';type='Math'
            filterParams=[pscustomobject]@{parameters=@(
                [pscustomobject]@{controlAddress='/operation';value='Multiply'},
                [pscustomobject]@{controlAddress='/value';value=127}
            );paramLinks=[pscustomobject]@{}}
            operationValue=[pscustomobject]@{value=127;controlAddress=('/states/kinectEN16/processors/'+$short+'/filters/colorToMIDI/filterParams/value')}
        }
    )
    ($mapping.outputs.items[0].command.parameters|Where-Object controlAddress -eq '/ccNumber').value=116+$component
    $state.processors.items+=@($mapping)
}
$dash.itemManager.items+=@([pscustomobject]@{
    niceName='Kinect LED Color';shortName='kinectLEDColor';type='DashboardParameterItem'
    hideInEditor=$true;ghostAddress=$address;controllable=$address
    parameters=@(
        [pscustomobject]@{controlAddress='/viewUIPosition';value=@(700,-40)},
        [pscustomobject]@{controlAddress='/viewUISize';value=@(190,85)},
        [pscustomobject]@{controlAddress='/target';value=$address},
        [pscustomobject]@{controlAddress='/showLabel';value=$true},
        [pscustomobject]@{controlAddress='/customText';value='Couleur LED Kinect';enabled=$true},
        [pscustomobject]@{controlAddress='/readOnly';value=$false}
    )
})
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFull))|Out-Null
[IO.File]::WriteAllText($outputFull,($p|ConvertTo-Json -Depth 100 -Compress),[Text.UTF8Encoding]::new($false))
'EN16_LED_COLOR_READY: Color variable + dashboard picker; RGB channel 16 CC116..118; 1 Hz reconnect sync; bank multiplier persisted at 127.'
