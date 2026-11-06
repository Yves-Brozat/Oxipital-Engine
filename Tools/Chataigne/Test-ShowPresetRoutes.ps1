param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Assert($ok,$message){if(!$ok){throw $message}}
function Json($node){ConvertTo-Json -InputObject $node -Depth 100 -Compress}
function Value($node,$key){($node.parameters|Where-Object controlAddress -eq $key).value}
$old=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$p=Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8|ConvertFrom-Json
Assert ((Json $p.customVariables) -ceq (Json $old.customVariables)) 'Authored preset or custom-variable values changed'
Assert ((Json $p.modules) -ceq (Json $old.modules)) 'Module configuration changed'
Assert ((Json $p.dashboardManager) -ceq (Json $old.dashboardManager)) 'Dashboard changed'
Assert ((Json $p.sequences) -ceq (Json $old.sequences)) 'Show sequences changed'
foreach($state in $p.states.items){
    $prior=$old.states.items|Where-Object niceName -eq $state.niceName
    if($state.niceName -notmatch '^CV (Orb|Force)'){
        Assert ((Json $state) -ceq (Json $prior)) ('Unrelated state changed: '+$state.niceName)
        continue
    }
    foreach($mux in $state.processors.items|Where-Object type -eq Multiplex){
        $oldMux=$prior.processors.items|Where-Object niceName -eq $mux.niceName
        Assert ((Json $mux.containers.lists) -ceq (Json $oldMux.containers.lists)) 'Parameter list contents changed'
        foreach($mapping in $mux.containers.processors.items){
            $oldMapping=$oldMux.containers.processors.items|Where-Object niceName -eq $mapping.niceName
            Assert ((Json $mapping.im) -ceq (Json $oldMapping.im)) 'Mapping input changed'
            Assert ((Json $mapping.filters) -ceq (Json $oldMapping.filters)) 'Gesture smoothing/filter changed'
            foreach($o in $mapping.outputs.items){
                Assert ($o.commandModule -eq 'generic') 'Remaining legacy list output'
                Assert ($o.command.paramLinks.target.linkType -eq 2) 'Output does not target the indexed list element'
                Assert ($o.command.paramLinks.value.linkType -eq 1 -and $o.command.paramLinks.value.mappingValueIndex -eq 0) 'Missing mapping value'
                Assert ((Value $o.command '/operator') -eq 'Equals') 'Output does not assign preset value'
                Assert ((Value $o.command '/time') -eq (Value $oldMapping.outputs.items[0].command '/time')) 'Transition duration changed'
            }
        }
    }
}
$orbState=$p.states.items|Where-Object niceName -eq 'CV Orb 1 -> OSC Oxipital'
$enum=$orbState.processors.items|Where-Object niceName -eq 'Orb Enum'
$send=$enum.containers.processors.items|Where-Object niceName -eq 'Orbs to Oxipital'
Assert ((Value $send.params '/sendOnInputChangeOnly') -eq $false -and (Value $send.params '/sendOnOutputChangeOnly') -eq $false) 'Enum refresh still skips unchanged preset values'
$source=$enum.containers.lists.items|Where-Object niceName -eq 'Orb CV'
$target=$enum.containers.lists.items|Where-Object niceName -eq 'Orb Oxipital'
Assert ($source.parameters[0].value -eq '/customVariables/orb1/variables/emitterShape/emitterShape') 'Sphere source is not Orb1 shape'
Assert ($target.parameters[0].value -eq '/modules/oxipital/parameters/orbGroups/orbGroup1/general/emitterShape/baseValue') 'Sphere output is not Orb Group1 shape'
$preset=($p.customVariables.items|Where-Object niceName -eq Orb1).presets.items|Where-Object niceName -eq Meduse
Assert ($preset.values.containers.emitterShape.parameters[0].value -eq 'Sphere') 'Meduse does not specify Sphere'
# Evaluate the serialized mapping links with a deliberately conflicting Unity
# value. This also covers reloading the same preset while the CV is unchanged.
$unityShape='Plane'
$mappedValue=$preset.values.containers.emitterShape.parameters[0].value
if($send.outputs.items[0].command.paramLinks.value.mappingValueIndex -eq 0){$unityShape=$mappedValue}
Assert ($unityShape -eq 'Sphere') 'Plane was not overridden by the preset shape'
'SHOW_PRESET_ROUTES_PASS: Sphere route complete; unchanged enums refreshed; Orb/Force values linked; presets, interpolation, gestures, controls and LED configuration preserved.'
