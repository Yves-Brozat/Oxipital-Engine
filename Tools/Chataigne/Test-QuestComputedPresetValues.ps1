param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$before=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$after=Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8|ConvertFrom-Json
$old=($before.customVariables.items|Where-Object niceName -eq 'Leap Motion').presets.items
$new=($after.customVariables.items|Where-Object niceName -eq 'Leap Motion').presets.items
$count=0
for($i=0;$i -lt $old.Count;$i++){
    if($old[$i].niceName -ne $new[$i].niceName){throw 'Preset order changed'}
    foreach($key in 'questOrbFinal','questForceFinal'){
        $a=$old[$i].values.containers.$key; $b=$new[$i].values.containers.$key
        if(!$a){if($b){throw 'Unexpected computed field'};continue}
        if(($b.parameters|Where-Object controlAddress -eq '/mode').value -ne 'None'){throw "Computed value can still interpolate: $key"}
        # Undo only the permitted change and compare the entire document.
        $b.parameters=@($a.parameters|ConvertTo-Json -Depth 100|ConvertFrom-Json)
        $count++
    }
}
if($count -lt 2){throw 'No computed fields checked'}
if(($before|ConvertTo-Json -Depth 100 -Compress) -cne ($after|ConvertTo-Json -Depth 100 -Compress)){throw 'Unrelated project data changed'}
Write-Output "QUEST_COMPUTED_PRESET_VALUES_PASS: $count fields cannot be recalled; all other project data unchanged."
