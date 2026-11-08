param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath,[string]$FocusScriptPath)
$ErrorActionPreference='Stop'
function Json($n){ConvertTo-Json -InputObject $n -Depth 100 -Compress}
function Clone($n){Json $n|ConvertFrom-Json}
function P($key,$value){[pscustomobject]@{controlAddress=$key;value=$value}}
function Put($n,$key,$value){$n|Add-Member -NotePropertyName $key -NotePropertyValue $value -Force}
function V($n,$key){($n.parameters|Where-Object controlAddress -eq $key).value}
function Set-P($n,$key,$value){$a=$n.parameters|Where-Object controlAddress -eq $key;if($a){$a.value=$value}else{Put $n parameters (@($n.parameters)+@((P $key $value)))}}
function Bank-Address{ '/customVariables/en16Banks/variables/bank/bank' }
function Fluid-Address($i){"/customVariables/en16Banks/variables/fluidButton$i/fluidButton$i"}
function Condition($address,$value){[pscustomobject]@{niceName='From Input Value';type='From Input Value';parameters=@((P '/inputValue' $address));comparator=[pscustomobject]@{parameters=@((P '/comparisonFunction' '='),(P '/reference' $value));hideInEditor=$true}}}
function Gate($bank){[pscustomobject]@{niceName='Software Bank Gate';type='Condition';filterParams=[pscustomobject]@{paramLinks=[pscustomobject]@{}};conditions=[pscustomobject]@{items=@((Condition (Bank-Address) $bank))}}}
function Script-Command($operation){[pscustomobject]@{niceName="EN16 banks - $operation";type='Consequence';commandModule='generic';commandPath='';commandType='Script';command=[pscustomobject]@{script=[pscustomobject]@{parameters=@((P '/filePath' 'scripts/EN16Banks.js'));scriptParams=[pscustomobject]@{parameters=@((P '/operation' $operation))}}}}}
function Trigger-Command($target){[pscustomobject]@{niceName='Trigger';type='Consequence';commandModule='generic';commandPath='';commandType='Trigger a Control';command=[pscustomobject]@{parameters=@((P '/target' $target));paramLinks=[pscustomobject]@{}}}}
function Variable($key,$label,$type,$value,$extra){$a=[pscustomobject]@{controlAddress="/$key";value=$value;type=$type;niceName=$label;customizable=$true;removable=$false;feedbackOnly=$false};if($extra){foreach($prop in $extra.Keys){Put $a $prop $extra[$prop]}};$itemType=if($type -eq 'Integer'){'Int Parameter'}else{$type+' Parameter'};[pscustomobject]@{niceName=$label;shortName=$key;type=$itemType;parameters=@($a)}}
if([IO.Path]::GetFullPath($SourcePath) -eq [IO.Path]::GetFullPath($OutputPath)){throw 'Use a separate output.'}
$p=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
if($p.customVariables.items|Where-Object shortName -eq en16Banks){throw 'Three banks already installed.'}
$ks=$p.states.items|Where-Object shortName -eq kinectEN16
$as=$p.states.items|Where-Object niceName -eq 'EN16 -> Oxipital CV'
$fs=$p.states.items|Where-Object niceName -eq 'EN16 -> CV OpticalFluid'
$ds=$p.states.items|Where-Object niceName -eq Dashboard
$kg=$p.customVariables.items|Where-Object niceName -eq Kinect
$fd=$p.dashboardManager.items|Where-Object niceName -eq AbyssesFluides
$am=$as.processors.items|Where-Object type -eq Multiplex
$km=$ks.processors.items|Where-Object type -eq Multiplex
$show=$ks.processors.items|Where-Object niceName -eq 'Show Active EN16 Bank'
$switch=$ks.processors.items|Where-Object shortName -eq switchEN16Bank
if(!$fs -or !$show -or !$am -or !$km -or !$fd){throw 'Missing EN16 bank configuration.'}
$initialBank=if((V ($kg.variables.items|Where-Object shortName -eq en16KinectBank) '/en16KinectBank')){1}else{0}
$group=[pscustomobject]@{niceName='en16Banks';shortName='en16Banks';type='CVGroup';variables=[pscustomobject]@{items=@(
    (Variable 'bank' 'Bank' 'Integer' $initialBank @{minValue=0;maxValue=2;default=0;description='0 Abysses, 1 Kinect, 2 AbyssesFluides'}),
    (Variable 'fluidLEDColor' 'Fluid LED Color' 'Color' @(0,1,1,1) @{description='Global EN16 LED color for AbyssesFluides; excluded from artistic presets.'})
)};presets=[pscustomobject]@{items=@()}}
foreach($i in 1..16){$cv=Variable "fluidButton$i" "Fluid Button $i" 'Integer' 0 @{minValue=0;maxValue=127;default=0;hideInEditor=$true};Put $cv hideInEditor $true;$group.variables.items+=@($cv)}
$p.customVariables.items+=@($group)
# The historical Boolean is kept as compatibility feedback, not bank authority.
($kg.variables.items|Where-Object shortName -eq en16KinectBank).parameters|Where-Object controlAddress -eq '/en16KinectBank'|ForEach-Object {$_.feedbackOnly=$true}
$oldBankAddress='/customVariables/kinect/variables/en16KinectBank/en16KinectBank'
foreach($spec in @(@($am,0),@($km,1))){
    foreach($mapping in $spec[0].containers.processors.items|Where-Object type -eq Mapping){foreach($filter in $mapping.filters.items){foreach($c in $filter.conditions.items){if((V $c '/inputValue') -eq $oldBankAddress){Set-P $c '/inputValue' (Bank-Address);$c.comparator.parameters=@((P '/comparisonFunction' '='),(P '/reference' $spec[1]))}}}}
}
# Replace binary bank changes with a single three-state cycle on the same raw note.
$switch.consequences.items=@((Script-Command 'cycle'))
$ks.processors.items=@($ks.processors.items|Where-Object niceName -ne 'Show Active EN16 Bank')
$ds.processors.items=@($ds.processors.items|Where-Object shortName -notmatch '^en16NativePage[01]$')
$state=[pscustomobject]@{niceName='EN16 Banks';shortName='en16Banks';type='State';parameters=@((P '/active' $true));processors=[pscustomobject]@{items=@()}}
foreach($bank in 0..2){
    $ui=if($bank -eq 1){$show.consequences}else{$show.consequencesOff}
    $colors=@($ui.items|Where-Object {(V $_.command '/target') -like '/dashboards/abyssesKinect/dashboard/rotary*/foregroundColor'})
    $state.processors.items+=@([pscustomobject]@{niceName="Apply Bank $bank";shortName="applyBank$bank";type='Action';conditions=[pscustomobject]@{items=@((Condition (Bank-Address) $bank))};consequences=[pscustomobject]@{items=@((Script-Command 'apply'))+@($colors)}})
}
$p.states.items+=@($state)
# Event-only routing for Fluides, using the identical native-page-1 note list.
$fm=Clone $am;$fm.niceName='Fluides Button Router';Put $fm shortName fluidesButtonRouter
$buttonList=Clone ($am.containers.lists.items|Where-Object niceName -eq 'EN16 Button Page 1')
$physicalList=Clone ($am.containers.lists.items|Where-Object shortName -eq en16PhysicalButtons)
$noteSlots=@{}
foreach($i in 1..16){$noteSlots[$physicalList.parameters[$i-1].value]=$i;$buttonList.parameters[$i-1].value=Fluid-Address $i}
$noteSlots[(V $switch.conditions.items[0] '/inputValue')]=4
$physicalList.parameters[3].value=Fluid-Address 4
$fm.containers.lists.items=@($buttonList,$physicalList)
$router=Clone ($am.containers.processors.items|Where-Object niceName -eq 'Route EN16 Buttons')
$router.filters.items=@((Gate 2));$fm.containers.processors.items=@($router)
$fs.processors.items+=@($fm)
# Move existing Fluides relative rotaries from channel 2 to channel 1, keeping
# their gains, ranges, color components and target CVs unchanged.
foreach($mapping in $fs.processors.items|Where-Object type -eq Mapping){
    $raw=V $mapping.im.items[0] '/inputValue'
    if($raw -like '/modules/en16/values/_2_CC*'){
        $text=(Json $mapping).Replace('/modules/en16/values/_2_','/modules/en16/values/_1_')
        $new=$text|ConvertFrom-Json
        $new.filters.items=@($new.filters.items)+@((Gate 2))
        foreach($flag in @('/sendOnActivate','/sendAfterLoad')){Set-P $new.params $flag $false}
        Set-P $new.params '/sendOnInputChangeOnly' $true
        $name=$mapping.niceName;$fs.processors.items=@($fs.processors.items|ForEach-Object {if($_.niceName -eq $name){$new}else{$_}})
    }
}
foreach($action in $fs.processors.items|Where-Object type -eq Action){foreach($c in $action.conditions.items){
    $raw=V $c '/inputValue'
    if($raw -like '/modules/en16/values/_2_*'){
        $pageOne=$raw.Replace('/_2_','/_1_');$slot=$noteSlots[$pageOne]
        if(!$slot){throw "Unknown Fluides note $raw"}
        if($slot -eq 4){$slot=1} # Display Fluid moves to 1; 4 is always Bank.
        Set-P $c '/inputValue' (Fluid-Address $slot)
        $c.comparator.parameters=@((P '/comparisonFunction' '>'),(P '/reference' 0))
    }
}}
$fs.processors.items+=@([pscustomobject]@{niceName='Launch Fluides';shortName='launchFluides';type='Action';conditions=[pscustomobject]@{items=@([pscustomobject]@{niceName='From Input Value';type='From Input Value';parameters=@((P '/inputValue' (Fluid-Address 5)));comparator=[pscustomobject]@{parameters=@((P '/comparisonFunction' '>'),(P '/reference' 0))}})};consequences=[pscustomobject]@{items=@((Trigger-Command '/states/initialisation/processors/lauchProcessingAbyssesParticles/trigger'))}})
# Existing per-second LED refresh now transmits bank 0/1/2 and the active color.
$resync=$ks.processors.items|Where-Object shortName -eq en16LEDBankResync
Set-P $resync.im.items[0] '/inputValue' (Bank-Address)
$resync.filters.items=@($resync.filters.items|Where-Object type -ne Math)
foreach($color in @('Red','Green','Blue')){
    $map=$ks.processors.items|Where-Object shortName -eq ('en16LED'+$color)
    $fluid=Clone $map;$fluid.niceName='Fluides LED '+$color;Put $fluid shortName ('fluidLED'+$color)
    $fluid=(Json $fluid).Replace('/states/kinectEN16/processors/en16LED','/states/en16Banks/processors/fluidLED')|ConvertFrom-Json
    Set-P $fluid.im.items[0] '/inputValue' '/customVariables/en16Banks/variables/fluidLEDColor/fluidLEDColor'
    $map.filters.items=@($map.filters.items)+@((Gate 1));$fluid.filters.items=@($fluid.filters.items)+@((Gate 2))
    $state.processors.items+=@($fluid)
}
# All three dashboards expose a trigger (one press = next bank), with orange
# background independent of the ordinary encoder/LED bank color.
$bankTarget='/states/kinectEN16/processors/switchEN16Bank/trigger'
$triggerTemplate=($p.dashboardManager.items|Where-Object niceName -eq Abysses).itemManager.items|Where-Object type -eq DashboardTriggerItem|Select-Object -First 1
foreach($dash in $p.dashboardManager.items|Where-Object niceName -in @('Abysses','Abysses Kinect','AbyssesFluides')){
    $widgets=@($dash.itemManager.items|Where-Object {(V $_ '/target') -eq $oldBankAddress})
    if($dash.niceName -eq 'AbyssesFluides'){$w=Clone $triggerTemplate;$w.niceName='Bank Selector';Put $w shortName bankSelector;Set-P $w '/viewUIPosition' @(400,-140);$dash.itemManager.items+=@($w);$widgets=@($w)}
    foreach($w in $widgets){
        $w.type='DashboardTriggerItem';$w.ghostAddress=$bankTarget;$w.controllable=$bankTarget
        Set-P $w '/target' $bankTarget;Set-P $w '/customText' '4 Bank';Set-P $w '/backgroundColor' @(1,0.3921568627,0,1)
        ($w.parameters|Where-Object controlAddress -eq '/backgroundColor')|Add-Member -NotePropertyName enabled -NotePropertyValue $true -Force
        Set-P $w '/viewUISize' @(80,80)
        $w.parameters=@($w.parameters|Where-Object controlAddress -notin @('/style','/toggleImage','/showValue'))
    }
}
$colorTemplate=($p.dashboardManager.items|Where-Object niceName -eq 'Abysses Kinect').itemManager.items|Where-Object shortName -eq kinectLEDColor
$cw=Clone $colorTemplate
if(!$cw){throw 'Missing Kinect color picker template.'}
$cw.niceName='Fluides LED Color';Put $cw shortName fluidesLEDColor
$colorAddress='/customVariables/en16Banks/variables/fluidLEDColor/fluidLEDColor'
$cw.ghostAddress=$colorAddress;$cw.controllable=$colorAddress
Set-P $cw '/target' $colorAddress;Set-P $cw '/customText' 'Couleur LED Fluides';Set-P $cw '/viewUIPosition' @(300,-360)
$fd.itemManager.items+=@($cw)
$labels=@{
    contrast='1 Contrast';brightness='2 Brightness';saturation='3 Saturation';flowScale='4 Flow Scale';timestep='5 Timestep';density='6 Density';velocity='7 Velocity'
    displayFluid='1 Afficher fluide';displayParticles='8 Particules';displaySource='12 Source';cameraMode='16 Camera / couleur'
}
foreach($w in $fd.itemManager.items){$target=V $w '/target';foreach($key in $labels.Keys){if($target -eq "/customVariables/opticalFluid/variables/$key/$key"){Set-P $w '/customText' $labels[$key];($w.parameters|Where-Object controlAddress -eq '/customText')|Add-Member -NotePropertyName enabled -NotePropertyValue $true -Force}}}
# Make freeze and unfreeze visible as well as physically accessible.
foreach($spec in @(@('Freeze','freeze',2,300,60),@('Defreeze','defreeze',3,400,60))){$w=Clone $triggerTemplate;$w.niceName=$spec[0];Put $w shortName $spec[1];$target='/states/en16__CVOpticalFluid/processors/'+$spec[1]+'/trigger';$w.ghostAddress=$target;$w.controllable=$target;Set-P $w '/target' $target;Set-P $w '/customText' ($spec[2].ToString()+' '+$spec[0]);Set-P $w '/viewUIPosition' @($spec[3],$spec[4]);Set-P $w '/viewUISize' @(80,80);$fd.itemManager.items+=@($w)}
# Match the right-hand Fluides button grid to physical EN16 order.
$fluidLayout=@(
    @(1,'Afficher fluide','/customVariables/opticalFluid/variables/displayFluid/displayFluid'),
    @(2,'Freeze','/states/en16__CVOpticalFluid/processors/freeze/trigger'),
    @(3,'Defreeze','/states/en16__CVOpticalFluid/processors/defreeze/trigger'),
    @(4,'Bank',$bankTarget),
    @(5,'Launch','/states/initialisation/processors/lauchProcessingAbyssesParticles/trigger'),
    @(8,'Particules','/customVariables/opticalFluid/variables/displayParticles/displayParticles'),
    @(12,'Source','/customVariables/opticalFluid/variables/displaySource/displaySource'),
    @(13,'Preset','/states/en16__CVOpticalFluid/processors/loadInitPreset/trigger'),
    @(14,'Preset Particle','/states/en16__CVOpticalFluid/processors/loadParticlePreset/trigger'),
    @(15,'Preset Color','/states/en16__CVOpticalFluid/processors/loadCameraColorPreset/trigger'),
    @(16,'Camera / couleur','/customVariables/opticalFluid/variables/cameraMode/cameraMode')
)
foreach($spec in $fluidLayout){$w=$fd.itemManager.items|Where-Object {(V $_ '/target') -eq $spec[2]};if(@($w).Count -ne 1){throw "Missing Fluides widget $($spec[2])"};$i=$spec[0]-1;Set-P $w '/viewUIPosition' @((300+100*($i%4)),(-140+100*[Math]::Floor($i/4)));Set-P $w '/viewUISize' @(80,80);Set-P $w '/customText' ($spec[0].ToString()+' '+$spec[1]);($w.parameters|Where-Object controlAddress -eq '/customText')|Add-Member -NotePropertyName enabled -NotePropertyValue $true -Force}
# The old, disabled Preset 2 is kept separately for manual editing, rather than
# overlapping the active Preset Particle widget at slot 14.
$legacy=$fd.itemManager.items|Where-Object {(V $_ '/target') -eq '/states/en16__CVOpticalFluid/processors/loadLittleVolutePreset/trigger'}
if($legacy){Set-P $legacy '/viewUIPosition' @(500,60)}
$rgb=$fd.itemManager.items|Where-Object {(V $_ '/target') -eq '/customVariables/opticalFluid/variables/brightColor/brightColor'}
Set-P $rgb '/customText' '8 B / 12 R / 16 V'
($rgb.parameters|Where-Object controlAddress -eq '/customText')|Add-Member -NotePropertyName enabled -NotePropertyValue $true -Force
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),(Json $p),[Text.UTF8Encoding]::new($false))
& (Join-Path $PSScriptRoot 'Repair-EN16BankColorsAndDashboards.ps1') -SourcePath $OutputPath -OutputPath ($OutputPath+'.bank-color-fix.tmp') -FocusScriptPath $FocusScriptPath
Move-Item -LiteralPath ($OutputPath+'.bank-color-fix.tmp') -Destination $OutputPath -Force
'EN16_THREE_BANKS_READY: 0 Abysses, 1 Kinect, 2 Fluides; event-only routing, global Fluides LED color, shared orange Bank, preserved artistic presets.'
