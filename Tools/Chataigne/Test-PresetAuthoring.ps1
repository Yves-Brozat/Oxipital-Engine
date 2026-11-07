param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Assert($ok,$message){if(!$ok){throw $message}}
function Json($x){ConvertTo-Json -InputObject $x -Depth 100 -Compress}
function Short($name){$s=$name -replace '[^\p{L}\p{Nd}_]','';$s.Substring(0,1).ToLowerInvariant()+$s.Substring(1)}
function Name($x){if($x.shortName){$x.shortName}else{Short $x.niceName}}
$old=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $SourcePath).Path)|ConvertFrom-Json
$p=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $OutputPath).Path)|ConvertFrom-Json
$tools=@($p.customVariables.items|Where-Object shortName -eq presetTools)
$state=@($p.states.items|Where-Object shortName -eq savePresets)
Assert ($tools.Count -eq 1 -and $state.Count -eq 1) 'Missing authoring containers'
$options=($tools[0].variables.items|Where-Object shortName -eq selectedPreset).parameters[0].enumOptions
Assert (@($options.PSObject.Properties).Count -ge 11) 'Missing scene selector options'
foreach($option in $options.PSObject.Properties){
    $entry=$option.Value
    Assert ($entry.label -ceq $option.Name -and $entry.targets.Count -eq 3) 'Invalid catalog entry'
    foreach($i in 0..2){
        $parts=$entry.targets[$i].Split('/')
        Assert ($parts[2] -ceq @('force1','orb1','kinect')[$i]) 'Wrong group order'
        $g=$p.customVariables.items|Where-Object {(Name $_) -ceq $parts[2]}
        Assert (@($g.presets.items|Where-Object {(Name $_) -eq $parts[4]}).Count -eq 1) ('Broken target '+$entry.targets[$i])
    }
    $a=@($state[0].processors.items|Where-Object shortName -ceq ('update'+$entry.key))
    Assert ($a.Count -eq 1) 'Missing per-scene update action'
    $script=$a[0].consequences.items[0].command.script
    Assert (($script.parameters|Where-Object controlAddress -eq '/filePath').value -eq 'scripts/PresetAuthoring.js') 'Wrong script path'
    Assert (($script.scriptParams.parameters|Where-Object controlAddress -eq '/entryKey').value -ceq $entry.key) 'Wrong update key'
}
$session=$state[0].processors.items|Where-Object shortName -eq saveSession
Assert ($session.consequences.items[0].commandType -eq 'Save Session') 'Not using native Save Session'
$dash=$p.dashboardManager.items|Where-Object niceName -eq Abysses
$beforeDash=$old.dashboardManager.items|Where-Object niceName -eq Abysses
$save=@($dash.itemManager.items|Where-Object shortName -eq saveNewPreset)
Assert ($save.Count -eq 1 -and $save[0].type -eq 'DashboardTriggerItem') 'Missing Save button'
Assert (($save[0].parameters|Where-Object controlAddress -eq '/target').value -eq '/states/savePresets/processors/saveNewPreset/trigger') 'Save does not create presets'
Assert (@($dash.itemManager.items|Where-Object shortName -eq updateSelectedPreset).Count -eq 1) 'Missing Update button'
$oldButton=$beforeDash.itemManager.items|Where-Object {($_.parameters|Where-Object controlAddress -eq '/customText').value -eq 'Leap to force'}
Assert ((Json ($save[0].parameters|Where-Object controlAddress -eq '/viewUIPosition').value) -ceq (Json ($oldButton.parameters|Where-Object controlAddress -eq '/viewUIPosition').value)) 'Save moved away from the requested slot'
# Undo precisely the allowed additions/replacement, then compare the entire session.
$p.customVariables.items=@($p.customVariables.items|Where-Object shortName -ne presetTools)
$p.states.items=@($p.states.items|Where-Object shortName -ne savePresets)
$dash.itemManager.items=@($dash.itemManager.items|Where-Object {$_.shortName -notin @('newPresetName','updateSelectedPreset','selectedPreset','presetSaveStatus')}|ForEach-Object {if($_.shortName -eq 'saveNewPreset'){$oldButton}else{$_}})
Assert ((Json $p) -ceq (Json $old)) 'Unexpected edits to existing presets, actions, routes or dashboard controls'
'PRESET_AUTHORING_TEST_PASS: '+@($options.PSObject.Properties).Count+' complete trios, correct actions/dashboard; all existing session data retained.'
