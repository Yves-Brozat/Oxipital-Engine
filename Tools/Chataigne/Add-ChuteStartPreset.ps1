param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Json($n){ConvertTo-Json -InputObject $n -Depth 100 -Compress}
function Clone($n){Json $n|ConvertFrom-Json}
if([IO.Path]::GetFullPath($SourcePath) -eq [IO.Path]::GetFullPath($OutputPath)){throw 'Prepare a separate output file.'}
$p=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
foreach($spec in @(@('Force 1','intensity','/intensity'),@('Orb1','dancerIntensity','/dancerIntensity'),@('Kinect','',''))){
    $group=$p.customVariables.items|Where-Object niceName -eq $spec[0]
    $source=$group.presets.items|Where-Object niceName -eq Chute
    if(@($source).Count -ne 1){throw "Missing Chute in $($spec[0])"}
    if($group.presets.items|Where-Object { $_.shortName -eq 'chuteStart' -or $_.niceName -eq 'Chute - Start' }){throw 'Chute Start already exists.'}
    $new=Clone $source
    $new.niceName='Chute - Start'
    if($new.PSObject.Properties['shortName']){$new.shortName='chuteStart'}else{$new|Add-Member -NotePropertyName shortName -NotePropertyValue chuteStart}
    if($spec[1]){
        $intensity=$new.values.containers.PSObject.Properties[$spec[1]].Value.parameters|Where-Object controlAddress -eq $spec[2]
        if(@($intensity).Count -ne 1){throw 'Missing intensity field.'}
        $intensity.value=0
    }
    $group.presets.items+=@($new)
}
# Use the existing Start-preset authoring entries so recall, Update and the
# dashboard selector follow the same native schema as Cascade/Tornade Start.
$tools=$p.customVariables.items|Where-Object shortName -eq presetTools
$selector=($tools.variables.items|Where-Object shortName -eq selectedPreset).parameters|Where-Object controlAddress -eq '/selectedPreset'
$entry=$selector.enumOptions.PSObject.Properties['Cascade - Start'].Value
if(!$entry){throw 'Missing Start preset authoring template.'}
$newEntry=(Json $entry).Replace('cascadeStart','chuteStart').Replace('Cascade - Start','Chute - Start')|ConvertFrom-Json
$selector.enumOptions|Add-Member -NotePropertyName 'Chute - Start' -NotePropertyValue $newEntry
foreach($spec in @(@('Presets','cascadeStart'),@('Save Presets','updatecascadeStart'))){
    $state=$p.states.items|Where-Object niceName -eq $spec[0]
    $template=$state.processors.items|Where-Object shortName -eq $spec[1]
    if(@($template).Count -ne 1){throw "Missing authoring action $($spec[1])"}
    $action=(Json $template).Replace('cascadeStart','chuteStart').Replace('Cascade - Start','Chute - Start')|ConvertFrom-Json
    if($action.conditions.items){throw 'Start authoring action must have no automatic input.'}
    $state.processors.items+=@($action)
}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),(Json $p),[Text.UTF8Encoding]::new($false))
'CHUTE_START_PRESET_READY: Chute clones in Force 1, Orb1 and Kinect; only Force intensity and Orb dancerIntensity set to zero; recall/update/selector installed.'
