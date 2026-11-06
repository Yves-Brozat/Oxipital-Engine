param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
if([IO.Path]::GetFullPath($SourcePath) -eq [IO.Path]::GetFullPath($OutputPath)){throw 'Use a separate output file.'}
$p=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
function Clone($n){$n|ConvertTo-Json -Depth 100|ConvertFrom-Json}
function Value($pr,$key,$v){$pr.values.containers.$key.parameters[0].value=$v}
$g1=$p.customVariables.items|Where-Object niceName -eq 'Force 1'
$g2=$p.customVariables.items|Where-Object niceName -eq 'Force 2'
$one=$g1.presets.items|Where-Object niceName -eq Tourbillon
$two=$g2.presets.items|Where-Object niceName -eq Tourbillon
if(!$one -or !$two){throw 'Missing Tourbillon force presets'}
if($g2.presets.items|Where-Object shortName -eq tourbillonBackgroundOff){throw 'Split already installed'}
# Match all shared settings before separating the force components. Retain
# Force 2's supported schema (Force 1 has an extra Linear Direction CV).
foreach($entry in $two.values.containers.PSObject.Properties){
    if($one.values.containers.($entry.Name)){
        $two.values.containers.($entry.Name)=Clone $one.values.containers.($entry.Name)
    }
}
foreach($key in 'radialIntensity','axialIntensity','linearIntensity','orthoradialIntensity','orthoaxialIntensity'){Value $two $key 0.0}
Value $one curlIntensity 0.0
Value $one perlinIntensity 0.0
$off=Clone $two
$off.niceName='Tourbillon Background Off'
$off|Add-Member -NotePropertyName shortName -NotePropertyValue tourbillonBackgroundOff -Force
Value $off intensity 0.0
$g2.presets.items+=@($off)
foreach($action in ($p.states.items|Where-Object niceName -eq Presets).processors.items){
    if($action.niceName -eq 'Tourbillon'){
        $base=$action.consequences.items|Where-Object {($_.command.parameters|Where-Object controlAddress -eq '/targetPreset').value -eq '/force1/presets/tourbillon'}
        $load=Clone $base
        $load.niceName='Force 2 Tourbillon Background'
        ($load.command.parameters|Where-Object controlAddress -eq '/targetPreset').value='/force2/presets/tourbillon'
    }else{
        $load=[pscustomobject]@{niceName='Stop Tourbillon Background';type='Consequence';commandModule='customVariables';commandPath='';commandType='Set Preset';command=[pscustomobject]@{parameters=@([pscustomobject]@{controlAddress='/targetPreset';value='/force2/presets/tourbillonBackgroundOff'});paramLinks=[pscustomobject]@{}}}
    }
    # Start alongside Force 1, before the existing reapply/snapshot trigger.
    $action.consequences.items=@($load)+@($action.consequences.items)
}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),($p|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
'TOURBILLON_SPLIT: brush force 1; independent Curl/Perlin force 2; shared recall duration; background off on other scenes.'
