param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Assert($ok,$message){if(!$ok){throw $message}}
function Json($n){ConvertTo-Json -InputObject $n -Depth 100 -Compress}
function Value($n,$key){($n.parameters|Where-Object controlAddress -eq $key).value}
$before=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$after=Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8|ConvertFrom-Json
foreach($g in $before.customVariables.items){
    $new=$after.customVariables.items|Where-Object niceName -eq $g.niceName
    foreach($preset in $g.presets.items){
        $saved=$new.presets.items|Where-Object niceName -eq $preset.niceName
        if($g.niceName -eq 'Kinect' -and $preset.niceName -in @('Chute','Chute - Start')){
            foreach($key in @('orbGroupNumber','forceGroupNumber')){
                Assert ((Value $saved.values.containers.$key ('/'+$key)) -eq 2) "Chute must target Kinect group 2: $key"
                ($saved.values.containers.$key.parameters|Where-Object controlAddress -eq ('/'+$key)).value=Value $preset.values.containers.$key ('/'+$key)
            }
        }
        Assert ((Json $preset) -ceq (Json $saved)) "Existing preset changed: $($g.niceName) / $($preset.niceName)"
    }
}
foreach($spec in @(@('Orb1','Orb2','dancerIntensity'),@('Force 1','Force 2','intensity'))){
    $from=$before.customVariables.items|Where-Object niceName -eq $spec[0]
    $to=$after.customVariables.items|Where-Object niceName -eq $spec[1]
    foreach($name in @('Chute','Chute - Start')){
        Assert ((Json ($from.presets.items|Where-Object niceName -eq $name)) -ceq (Json ($to.presets.items|Where-Object niceName -eq $name))) "Chute clone differs: $($spec[1]) / $name"
    }
    foreach($label in @($spec[0],$spec[1])){
        $release=($after.customVariables.items|Where-Object niceName -eq $label).presets.items|Where-Object shortName -eq transitionRelease
        foreach($field in $release.values.containers.PSObject.Properties){
            $expected=if($field.Name -eq $spec[2]){'Interpolate'}else{'None'}
            Assert ((Value $field.Value '/mode') -eq $expected) "Release must only change intensity: $label / $($field.Name)"
        }
        Assert ((Value $release.values.containers.($spec[2]) ('/'+$spec[2])) -eq 0) 'Release target must be zero'
    }
}
$show=@('meduse','chute','cascade','tornade','tourbillon','cercle')
foreach($sequence in $after.sequences.items|Where-Object shortName -in $show){
    $init=$sequence.layers.items.triggers.items|Select-Object -First 1
    $items=$init.consequences.items
    $other=if($sequence.shortName -eq 'chute'){1}else{2}
    $release=$items|Where-Object {(Value $_.command '/targetPreset') -eq "/orb$other/presets/transitionRelease"}
    Assert (@($release).Count -eq 1 -and (Value $release.command '/interpolationTime') -eq 10) "Missing outgoing fade in $($sequence.niceName)"
    $stops=@($items|Where-Object niceName -like 'Crossfade - stop *')
    Assert ($stops.Count -eq 5) 'Every other show timeline must stop before fading'
    Assert (!($stops|Where-Object {(Value $_.command '/target') -eq "/sequences/$($sequence.shortName)/stop"})) 'Sequence stops itself'
    Assert (@($items|Where-Object commandType -eq 'Kill Go to preset').Count -ge 5) 'Rapid recall must cancel old preset interpolations'
    Assert (!($items|Where-Object {(Value $_.command '/targetPreset') -eq '/force2/presets/tourbillonBackgroundOff'})) 'Immediate background-off cuts the outgoing Force2'
}
$chute=$after.sequences.items|Where-Object shortName -eq chute
$morph=$chute.layers.items|Where-Object shortName -eq chuteMorph
$outputs=$morph.containers.mapping.outputs.items
Assert ((Json $outputs) -notmatch '/orb1|/force1') 'Chute morph still overwrites the outgoing scene'
Assert ((Json $outputs) -match '/orb2/presets/chute' -and (Json $outputs) -match '/force2/presets/chute') 'Chute morph missing group 2'
Assert ((Value ($chute.layers.items.triggers.items|Select-Object -First 1) '/time') -lt (Value $morph.containers.automation.items[0] '/position')) 'Chute initialization must precede its morph'
Assert (((Value $morph.containers.automation.items[1] '/position')-(Value $morph.containers.automation.items[0] '/position')) -eq 10) 'Chute fade-in timing changed'
$tools=$after.customVariables.items|Where-Object shortName -eq presetTools
$selector=($tools.variables.items|Where-Object shortName -eq selectedPreset).parameters|Where-Object controlAddress -eq /selectedPreset
foreach($name in @('Chute','Chute - Start')){
    Assert ($selector.enumOptions.$name.targets[0] -like '/customVariables/force2/*' -and $selector.enumOptions.$name.targets[1] -like '/customVariables/orb2/*') 'Update points at old groups'
}
$conductor=($after.states.items|Where-Object niceName -eq Conduite).processors.items|Where-Object type -eq Conductor
Assert (@($conductor.containers.processors.items.shortName|Select-Object -Unique).Count -eq @($conductor.containers.processors.items).Count) 'Duplicate cue addresses'
Assert (@($conductor.containers.processors.items|Where-Object {(Value $_.sequenceLinking '/linkedSequence') -eq '/chute'}).Count -eq 3) 'Repeated Chute cues lost'
foreach($key in @('modules','dashboardManager')){Assert ((Json $before.$key) -ceq (Json $after.$key)) "Unrelated $key data changed"}
'ORB_CROSSFADE_PASS: original presets preserved; intensity-only releases; Chute Orb2/Force2/Kinect/authoring; interrupted timeline cancellation; three distinct Chute cues; dashboards and modules preserved.'
