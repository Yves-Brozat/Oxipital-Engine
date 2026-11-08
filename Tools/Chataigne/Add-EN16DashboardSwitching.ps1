param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function P($key,$value){[pscustomobject]@{controlAddress=$key;value=$value}}
function Script-Command{[pscustomobject]@{niceName='Afficher la banque EN16 et activer Chataigne';type='Consequence';commandModule='generic';commandPath='';commandType='Script';command=[pscustomobject]@{script=[pscustomobject]@{parameters=@((P '/filePath' 'scripts/EN16Dashboard.js'))}}}}
function Command($label,$module,$path,$type,$parameters){[pscustomobject]@{niceName=$label;type='Consequence';commandModule=$module;commandPath=$path;commandType=$type;command=[pscustomobject]@{parameters=@($parameters);paramLinks=[pscustomobject]@{}}}}
if([IO.Path]::GetFullPath($SourcePath) -eq [IO.Path]::GetFullPath($OutputPath)){throw 'Use a separate output.'}
$p=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$midi=$p.modules.items|Where-Object niceName -eq EN16
$dashboard=$p.states.items|Where-Object niceName -eq Dashboard
$bank=($p.states.items|Where-Object shortName -eq kinectEN16).processors.items|Where-Object niceName -eq 'Show Active EN16 Bank'
if(!$midi -or !$dashboard -or !$bank -or !($p.modules.items|Where-Object type -eq OS)){throw 'Expected MIDI, Dashboard, OS and bank action.'}
if($dashboard.processors.items|Where-Object shortName -eq showEN16Fluides){throw 'Dashboard switching already installed.'}
if($midi.values.parameters|Where-Object controlAddress -eq '/_16_CC115'){throw 'CC115 is already used; inspect before changing.'}
$midi.values.parameters+=@([pscustomobject]@{niceName='[16] CC115';controlAddress='/_16_CC115';type='MIDI Value';channel=16;pitchOrNumber=115;MIDIType=2;value=0;default=0;minValue=0;maxValue=127;alwaysNotify=$true;customizable=$false;removable=$true;feedbackOnly=$false})
foreach($spec in @(@('showEN16Abysses','/abysses'),@('showEN16Kinect','/abyssesKinect'),@('showEN16Fluides','/abyssesFluides'))){
    $dashboard.processors.items+=@([pscustomobject]@{niceName=$spec[0];shortName=$spec[0];type='Action';consequences=[pscustomobject]@{items=@(
        (Command 'Afficher le dashboard' 'generic' '' 'Select Dashboard' @((P '/dashboard' $spec[1]),(P '/setInClients' $true)))
    )}})
}
foreach($page in @(0,1)){
    $dashboard.processors.items+=@([pscustomobject]@{niceName="EN16 native page $($page+1)";shortName="en16NativePage$page";type='Action';conditions=[pscustomobject]@{items=@([pscustomobject]@{niceName='From Input Value';type='From Input Value';parameters=@((P '/inputValue' '/modules/en16/values/_16_CC115'));comparator=[pscustomobject]@{parameters=@((P '/comparisonFunction' '='),(P '/reference' $page));hideInEditor=$true}})};consequences=[pscustomobject]@{items=@((Script-Command))}})
}
foreach($side in @('consequences','consequencesOff')){
    $bank.$side.items=@($bank.$side.items|Where-Object commandType -ne 'Select Dashboard')+@((Script-Command))
}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),($p|ConvertTo-Json -Depth 100 -Compress),[Text.UTF8Encoding]::new($false))
'EN16_DASHBOARD_SWITCHING_READY: native page CC115 + Kinect bank select dashboard without restoring or focusing the window.'
