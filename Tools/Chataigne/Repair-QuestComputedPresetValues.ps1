param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
if([IO.Path]::GetFullPath($SourcePath) -eq [IO.Path]::GetFullPath($OutputPath)){throw 'Use a separate output file.'}
$p=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$g=$p.customVariables.items|Where-Object niceName -eq 'Leap Motion'
if(!$g){throw 'Missing Leap Motion group'}
$count=0
foreach($preset in $g.presets.items){
    foreach($key in 'questOrbFinal','questForceFinal'){
        $entry=$preset.values.containers.$key
        if(!$entry){continue}
        $mode=$entry.parameters|Where-Object controlAddress -eq '/mode'
        if($mode){$mode.value='None'}else{
            $entry.parameters=@($entry.parameters)+@([pscustomobject]@{controlAddress='/mode';value='None'})
        }
        $count++
    }
}
if($count -lt 2){throw 'No computed Quest positions found'}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),($p|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
Write-Output "QUEST_COMPUTED_PRESET_VALUES_DISABLED: $count entries (Mode None), artistic values preserved."
