param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath,[string]$FocusScriptPath)
$ErrorActionPreference='Stop'
function Json($n){ConvertTo-Json -InputObject $n -Depth 100 -Compress}
function P($key,$value){[pscustomobject]@{controlAddress=$key;value=$value}}
function V($n,$key){($n.parameters|Where-Object controlAddress -eq $key).value}
function Set-P($n,$key,$value){$a=$n.parameters|Where-Object controlAddress -eq $key;if(!$a){throw "Missing $key"};$a.value=$value}
function Set-Command($label,$target,$value){[pscustomobject]@{niceName=$label;type='Consequence';commandModule='generic';commandPath='';commandType='Set Parameter Value';command=[pscustomobject]@{parameters=@((P '/target' $target),(P '/component' 'All'),(P '/operator' 'Equals'),(P '/value' $value));paramLinks=[pscustomobject]@{}}}}
function Trigger-Command($target){[pscustomobject]@{niceName='Afficher le dashboard de la banque';type='Consequence';commandModule='generic';commandPath='';commandType='Trigger a Control';command=[pscustomobject]@{parameters=@((P '/target' $target));paramLinks=[pscustomobject]@{}}}}
if([IO.Path]::GetFullPath($SourcePath) -eq [IO.Path]::GetFullPath($OutputPath)){throw 'Use a separate output.'}
$p=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$state=$p.states.items|Where-Object shortName -eq en16Banks
$kinect=$p.states.items|Where-Object shortName -eq kinectEN16
if(!$state -or !$kinect){throw 'Expected three software banks.'}
$names=@('showEN16Abysses','showEN16Kinect','showEN16Fluides')
foreach($bank in 0..2){
    $action=$state.processors.items|Where-Object shortName -eq "applyBank$bank"
    if(@($action).Count -ne 1){throw 'Missing bank action.'}
    $colors=@($action.consequences.items|Where-Object {(V $_.command '/target') -like '/dashboards/abyssesKinect/dashboard/rotary*/foregroundColor'})
    $commands=@()
    foreach($i in 1..16){
        foreach($side in @('Abysses','Kinect')){$key="en16${side}Button$i";$commands+=@(Set-Command "Clear $side $i" "/customVariables/kinect/variables/$key/$key" 0)}
        $key="fluidButton$i";$commands+=@(Set-Command "Clear Fluides $i" "/customVariables/en16Banks/variables/$key/$key" 0)
    }
    $commands+=@(Set-Command 'Compatibility Kinect bank' '/customVariables/kinect/variables/en16KinectBank/en16KinectBank' ($bank -eq 1))
    $commands+=@(Trigger-Command ('/states/dashboard/processors/'+$names[$bank]+'/trigger'))
    $action.consequences.items=@($commands)+@($colors)
}
# Each bank has a separate RGB MIDI address range and firmware cache. Both
# colors keep refreshing even while inactive; no shared RGB stream or gate.
foreach($i in 0..2){
    $color=@('Red','Green','Blue')[$i]
    $k=$kinect.processors.items|Where-Object shortName -eq ('en16LED'+$color)
    $f=$state.processors.items|Where-Object shortName -eq ('fluidLED'+$color)
    if(!$k -or !$f){throw 'Missing RGB mapping.'}
    foreach($m in @($k,$f)){$m.filters.items=@($m.filters.items|Where-Object niceName -ne 'Software Bank Gate')}
    Set-P $k.outputs.items[0].command '/ccNumber' (116+$i)
    Set-P $f.outputs.items[0].command '/ccNumber' (112+$i)
}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),(Json $p),[Text.UTF8Encoding]::new($false))
if($FocusScriptPath){
    & (Join-Path $PSScriptRoot 'Repair-EN16DashboardForeground.ps1') -SourcePath $OutputPath -OutputPath ($OutputPath+'.foreground.tmp') -FocusScriptPath $FocusScriptPath
    Move-Item -LiteralPath ($OutputPath+'.foreground.tmp') -Destination $OutputPath -Force
}
'EN16_COLORS_AND_DASHBOARDS_REPAIRED: native clear/compatibility/dashboard commands on every bank change; distinct Kinect/Fluides MIDI color channels and caches.'
