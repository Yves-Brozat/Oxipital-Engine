param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Assert($ok,$message){if(!$ok){throw $message}}
function Json($n){ConvertTo-Json -InputObject $n -Depth 100 -Compress}
function Clone($n){ConvertFrom-Json -InputObject (Json $n)}
$old=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$p=Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8|ConvertFrom-Json
$state=$p.states.items|Where-Object shortName -eq kinectEN16
$prior=$old.states.items|Where-Object shortName -eq kinectEN16
$channels=@()
foreach($i in 0..2){
    $name=@('Red','Green','Blue')[$i]
    $m=$state.processors.items|Where-Object shortName -eq ('en16LED'+$name)
    $f=$m.filters.items[0]
    Assert ($f.type -eq 'Mega Converter') 'Extractor is not a registered Chataigne filter type'
    Assert ($f.convertedParameters.items.Count -eq 1 -and $f.convertedParameters.items[0].type -eq 'Float') 'Wrong conversion output type'
    Assert ($f.links[0].sourceIndex -eq 0 -and $f.links[0].sourceValueIndex -eq $i -and $f.links[0].out -eq 'channelValue' -and $f.links[0].outValueIndex -eq 0) 'Wrong RGB link'
    Assert ($m.filters.items[1].operationValue.value -eq 127) 'Lost MIDI multiplier'
    Assert (($m.outputs.items[0].command.parameters|Where-Object controlAddress -eq '/ccNumber').value -eq 116+$i) 'Wrong MIDI color channel'
    $channels+=@($f.links[0].sourceValueIndex)
    $original=$prior.processors.items|Where-Object shortName -eq ('en16LED'+$name)
    $m.filters.items=$original.filters.items
}
foreach($case in @(@(@(1,0,0,1),@(127,0,0)),@(@(0,1,0,1),@(0,127,0)),@(@(0,0,1,1),@(0,0,127)),@(@(1,1,1,1),@(127,127,127)),@(@(0,0,0,1),@(0,0,0)))){
    $actual=@($channels|ForEach-Object {$case[0][$_]*127})
    Assert ((Json $actual) -ceq (Json $case[1])) 'RGB colors collapsed to grayscale'
}
$group=$p.customVariables.items|Where-Object niceName -eq Kinect
$oldGroup=$old.customVariables.items|Where-Object niceName -eq Kinect
foreach($preset in $group.presets.items){
    $bank=$preset.values.containers.en16KinectBank
    if(!$bank){continue}
    Assert (($bank.parameters|Where-Object controlAddress -eq '/mode').value -eq 'None') 'Show preset can still switch bank'
    foreach($currentBank in @($false,$true)){
        $after=$currentBank
        if(($bank.parameters|Where-Object controlAddress -eq '/mode').value -ne 'None'){$after=($bank.parameters|Where-Object controlAddress -eq '/en16KinectBank').value}
        Assert ($after -eq $currentBank) 'Preset changed selected bank'
    }
    $original=$oldGroup.presets.items|Where-Object niceName -eq $preset.niceName
    $bank.parameters=$original.values.containers.en16KinectBank.parameters
}
$show=$p.states.items|Where-Object niceName -eq Presets
$meduse=$show.processors.items|Where-Object niceName -eq Meduse
$presets=@($meduse.consequences.items|Where-Object commandType -eq 'Go to preset'|ForEach-Object {($_.command.parameters|Where-Object controlAddress -eq '/targetPreset').value})
Assert ($presets -contains '/orb1/presets/meduse' -and $presets -contains '/force1/presets/meduse' -and $presets -contains '/kinect/presets/scene01' -and $presets -contains '/camera/presets/reset') 'Meduse cue lost a required preset'
Assert ($presets.Count -eq 4) 'Meduse cue recalls an unrelated preset'
$oldMeduse=($old.states.items|Where-Object niceName -eq Presets).processors.items|Where-Object niceName -eq Meduse
$meduse.consequences.items=$oldMeduse.consequences.items
Assert ((Json $p) -ceq (Json $old)) 'Unexpected edit outside RGB extraction, preset-bank mode and Meduse consequence'
'LED_AND_BANK_TEST_PASS: independent R/G/B, primary colors and grayscale, bank preserved in both directions, Meduse-only recalls, all other show data retained.'
