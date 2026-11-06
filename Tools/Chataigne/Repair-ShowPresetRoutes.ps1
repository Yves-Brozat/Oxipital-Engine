param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$sourceFull=(Resolve-Path -LiteralPath $SourcePath).Path
$outputFull=[IO.Path]::GetFullPath($OutputPath)
if($sourceFull -eq $outputFull){throw 'Keep the saved session and use a separate output path.'}
$p=[IO.File]::ReadAllText($sourceFull)|ConvertFrom-Json
function Put($node,$key,$value){$node|Add-Member -NotePropertyName $key -NotePropertyValue $value -Force}
function Param($node,$key,$value){$parameter=$node.parameters|Where-Object controlAddress -eq $key;if($parameter){$parameter.value=$value}else{$node.parameters=@($node.parameters)+@([pscustomobject]@{controlAddress=$key;value=$value})}}
$count=0
foreach($state in $p.states.items|Where-Object niceName -match '^CV (Orb|Force)'){
    foreach($mux in $state.processors.items|Where-Object type -eq Multiplex){
        foreach($mapping in $mux.containers.processors.items){
            foreach($output in $mapping.outputs.items){
                $command=$output.command
                if($output.commandType -notin @('Set List Value','Go to List Value','Set Parameter Value','Go to Parameter Value')){continue}
                $changed=$false
                if($output.commandType -in @('Set List Value','Go to List Value')){
                    $target=($command.parameters|Where-Object controlAddress -eq '/target').value
                    if(!$target -or $target -notmatch '/lists/([^/]+)$'){throw 'Expected a local multiplex list target.'}
                    $list=$Matches[1]
                    # Use the same list-linked generic command as the working
                    # float routes, with an explicit current mapping value.
                    $output.commandModule='generic'
                    $output.commandType=if($output.commandType -eq 'Go to List Value'){'Go to Parameter Value'}else{'Set Parameter Value'}
                    $command.parameters=@($command.parameters|Where-Object controlAddress -ne '/target')
                    Put $command.paramLinks target ([pscustomobject]@{linkType=2;list=$list})
                    $changed=$true
                }
                if(!$command.paramLinks.value){
                    Put $command.paramLinks value ([pscustomobject]@{linkType=1;mappingValueIndex=0})
                    $changed=$true
                }
                if(($command.parameters|Where-Object controlAddress -eq '/operator').value -ne 'Equals'){
                    Param $command '/operator' 'Equals';$changed=$true
                }
                if($changed){$count++;'REPAIRED: '+$mux.niceName+' / '+$mapping.niceName}
            }
            if($mux.niceName -eq 'Orb Enum' -and $mapping.niceName -eq 'Orbs to Oxipital'){
                # Shape/render type are authored by Chataigne, never gestures.
                # Reassert them even when reloading a preset whose CV already
                # equals Sphere while Unity was changed locally to Plane.
                Param $mapping.params '/sendOnInputChangeOnly' $false
                Param $mapping.params '/sendOnOutputChangeOnly' $false
                Param $mapping.params '/sendOnActivate' $true
            }
        }
    }
}
if($count -eq 0){throw 'No incomplete preset routes found.'}
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFull))|Out-Null
[IO.File]::WriteAllText($outputFull,($p|ConvertTo-Json -Depth 100 -Compress),[Text.UTF8Encoding]::new($false))
'SHOW_PRESET_ROUTES_READY: '+$count+' outputs repaired; existing preset values and transition times retained.'
