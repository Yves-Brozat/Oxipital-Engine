param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Json($x){ConvertTo-Json -InputObject $x -Depth 100 -Compress}
function Clone($x){ConvertFrom-Json -InputObject (Json $x)}
function Short($name){$s=$name -replace '[^\p{L}\p{Nd}_]',''; $s.Substring(0,1).ToLowerInvariant()+$s.Substring(1)}
function Name($x){if($x.shortName){$x.shortName}else{Short $x.niceName}}
function Param($key,$value){[pscustomobject]@{controlAddress=$key;value=$value}}
function Action($label,$key,$operation,$short){[pscustomobject]@{
    niceName=$label;shortName=$short;type='Action';editorIsCollapsed=$true
    consequences=[pscustomobject]@{items=@([pscustomobject]@{
        niceName='Capture three presets';type='Consequence';commandModule='generic';commandPath='';commandType='Script'
        command=[pscustomobject]@{script=[pscustomobject]@{
            parameters=@((Param '/filePath' 'scripts/PresetAuthoring.js'))
            scriptParams=[pscustomobject]@{parameters=@((Param '/operation' $operation),(Param '/entryKey' $key))}
        }}
    })}
}}
function Variable($name,$label,$type,$value,$extra){
    $p=[pscustomobject]@{controlAddress=('/'+$name);value=$value;type=$type;niceName=$label;customizable=$true;removable=$false;feedbackOnly=$false}
    if($extra){foreach($prop in $extra.Keys){$p|Add-Member -NotePropertyName $prop -NotePropertyValue $extra[$prop] -Force}}
    [pscustomobject]@{niceName=$label;shortName=$name;type=($type+' Parameter');parameters=@($p)}
}
function DashboardItem($label,$short,$type,$target,$position,$size){[pscustomobject]@{
    niceName=$label;shortName=$short;type=$type;hideInEditor=$true;ghostAddress=$target;controllable=$target
    parameters=@((Param '/viewUIPosition' $position),(Param '/viewUISize' $size),(Param '/target' $target),
        [pscustomobject]@{controlAddress='/customText';value=$label;enabled=$true},
        [pscustomobject]@{controlAddress='/textSize';value=14;enabled=$true})
}}
$sourceFull=(Resolve-Path -LiteralPath $SourcePath).Path
$outputFull=[IO.Path]::GetFullPath($OutputPath)
if($sourceFull -eq $outputFull){throw 'Prepare a separate output before replacing the saved session.'}
$p=[IO.File]::ReadAllText($sourceFull)|ConvertFrom-Json
if($p.customVariables.items|Where-Object {(Name $_) -eq 'presetTools'}){throw 'Preset authoring already installed.'}
$groups=@{}
foreach($g in $p.customVariables.items){$groups[(Name $g)]=$g}
foreach($g in @('force1','orb1','kinect')){if(!$groups[$g]){throw ('Missing '+$g)}}
$show=$p.states.items|Where-Object {(Name $_) -eq 'presets'}
$dash=$p.dashboardManager.items|Where-Object niceName -eq Abysses
if(!$show -or !$dash){throw 'Missing Presets state or Abysses dashboard.'}
if($p.states.items|Where-Object {(Name $_) -eq 'savePresets'}){throw 'Save Presets state already exists.'}
$entries=@(); $options=[ordered]@{}
foreach($cue in $show.processors.items){
    $refs=@{}
    foreach($g in @('force1','orb1','kinect')){
        $refs[$g]=@($cue.consequences.items|Where-Object {$_.commandType -in @('Go to preset','Set Preset')}|ForEach-Object {
            ($_.command.parameters|Where-Object controlAddress -eq '/targetPreset').value
        }|Where-Object {$_ -like ('/'+$g+'/presets/*')}|Select-Object -Unique)
    }
    if(!$refs.kinect.Count){continue}
    if($refs.kinect.Count -ne 1){throw 'Ambiguous Kinect cue.'}
    $kp=$groups.kinect.presets.items|Where-Object {('/kinect/presets/'+(Name $_)) -eq $refs.kinect[0]}
    if(!$kp){throw 'Missing Kinect preset.'}
    # Legacy Cascade End recalls Force twice; use the existing Orb preset of the same name.
    foreach($g in @('force1','orb1')){
        if(!$refs[$g].Count){
            $fallback=$groups[$g].presets.items|Where-Object niceName -eq $kp.niceName
            if(@($fallback).Count -ne 1){throw ('No unambiguous '+$g+' preset for '+$cue.niceName)}
            $refs[$g]=@('/'+$g+'/presets/'+(Name $fallback))
        }
    }
    $steps=[Math]::Max($refs.force1.Count,$refs.orb1.Count)
    if($refs.force1.Count -ne $steps -or $refs.orb1.Count -ne $steps){throw ('Unmatched scene stages: '+$cue.niceName)}
    for($i=0;$i -lt $steps;$i++){
        $key=(Name $cue)+$(if($steps -gt 1){[string]($i+1)}else{''})
        $fp=$groups.force1.presets.items|Where-Object {('/force1/presets/'+(Name $_)) -eq $refs.force1[$i]}
        $label=if($steps -gt 1){$fp.niceName}else{$kp.niceName}
        # Make the shared Montee End values explicit in the selector.
        if($cue.niceName -eq 'Descente'){$label='Descente (Montee des eaux End)'}
        if($options.Contains($label)){throw ('Duplicate catalog label: '+$label)}
        $entry=[pscustomobject]@{key=$key;label=$label;targets=@(('/customVariables'+$refs.force1[$i]),('/customVariables'+$refs.orb1[$i]),('/customVariables'+$refs.kinect[0]))}
        foreach($target in $entry.targets){
            $parts=$target.Split('/'); $match=@($groups[$parts[2]].presets.items|Where-Object {(Name $_) -eq $parts[4]})
            if($match.Count -ne 1){throw ('Unresolved preset: '+$target)}
        }
        $entries+=@($entry); $options[$label]=$entry
    }
}
if($entries.Count -lt 11){throw 'Too few complete scene trios.'}
$tools=[pscustomobject]@{niceName='Preset Tools';shortName='presetTools';type='CVGroup';variables=[pscustomobject]@{items=@(
    (Variable 'newPresetName' 'New Preset Name' 'String' '' $null),
    (Variable 'selectedPreset' 'Selected Preset' 'Enum' $entries[0].label @{enumOptions=$options}),
    (Variable 'status' 'Status' 'String' 'Choose a preset to Update, or enter a new name and Save.' @{feedbackOnly=$true})
)};presets=[pscustomobject]@{items=@()}}
$p.customVariables.items+=@($tools)
$save=[pscustomobject]@{niceName='Save Presets';shortName='savePresets';type='State';processors=[pscustomobject]@{items=@(
    (Action 'Save New Preset' '' 'create' 'saveNewPreset'),
    (Action 'Update Selected Preset' '' 'update' 'updateSelectedPreset'),
    [pscustomobject]@{niceName='Save Session';shortName='saveSession';type='Action';consequences=[pscustomobject]@{items=@(
        [pscustomobject]@{niceName='Save Session';type='Consequence';commandModule='generic';commandPath='';commandType='Save Session';command=[pscustomobject]@{}}
    )}}
)}}
foreach($entry in $entries){$save.processors.items+=@((Action ('Update '+$entry.label) $entry.key 'updateEntry' ('update'+$entry.key)))}
$p.states.items+=@($save)
$button=@($dash.itemManager.items|Where-Object {($_.parameters|Where-Object controlAddress -eq '/customText').value -eq 'Leap to force'})
if($button.Count -ne 1){throw 'Expected exactly one Leap to force dashboard button.'}
$position=($button[0].parameters|Where-Object controlAddress -eq '/viewUIPosition').value
$size=($button[0].parameters|Where-Object controlAddress -eq '/viewUISize').value
$replacement=DashboardItem 'Save' 'saveNewPreset' 'DashboardTriggerItem' '/states/savePresets/processors/saveNewPreset/trigger' $position $size
$dash.itemManager.items=@($dash.itemManager.items|ForEach-Object {if($_ -eq $button[0]){$replacement}else{$_}})
$root='/customVariables/presetTools/variables/'
$dash.itemManager.items+=@(
    (DashboardItem 'Nouveau preset' 'newPresetName' 'DashboardParameterItem' ($root+'newPresetName/newPresetName') @(660,-160) @(240,60)),
    (DashboardItem 'Update' 'updateSelectedPreset' 'DashboardTriggerItem' '/states/savePresets/processors/updateSelectedPreset/trigger' @(560,-160) @(80,80)),
    (DashboardItem 'Preset a mettre a jour' 'selectedPreset' 'DashboardParameterItem' ($root+'selectedPreset/selectedPreset') @(560,-60) @(300,60)),
    (DashboardItem 'Sauvegarde' 'presetSaveStatus' 'DashboardParameterItem' ($root+'status/status') @(560,10) @(360,55))
)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFull))|Out-Null
[IO.File]::WriteAllText($outputFull,(Json $p),[Text.UTF8Encoding]::new($false))
'PRESET_AUTHORING_READY: '+$entries.Count+' scene/stage update triggers; Save / name / selector / Update / status on Abysses.'
