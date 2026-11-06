param(
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference='Stop'
$sourceFull=(Resolve-Path -LiteralPath $SourcePath).Path
$outputFull=[IO.Path]::GetFullPath($OutputPath)
if($sourceFull -eq $outputFull){throw 'Use a separate output file.'}
$p=[IO.File]::ReadAllText($sourceFull)|ConvertFrom-Json
function Copy-Node($node){$node|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json}
function Put($node,[string]$key,$value){$node|Add-Member -NotePropertyName $key -NotePropertyValue $value -Force}
function Param([string]$key,$value){[pscustomobject]@{controlAddress=$key;value=$value}}
function Key([string]$name){$name=$name -replace '[^\p{L}\p{Nd}_]','';$name.Substring(0,1).ToLowerInvariant()+$name.Substring(1)}
function CV([string]$key){'/customVariables/kinect/variables/'+$key+'/'+$key}
function Condition([string]$address,$reference,[string]$comparison='=='){
    [pscustomobject]@{niceName='From Input Value';type='From Input Value';parameters=@((Param '/inputValue' $address));comparator=[pscustomobject]@{parameters=@((Param '/comparisonFunction' $comparison),(Param '/reference' $reference));hideInEditor=$true}}
}
$group=$p.customVariables.items|Where-Object niceName -eq Kinect
$original=$p.dashboardManager.items|Where-Object niceName -eq Abysses
$bank=$p.states.items|Where-Object shortName -eq kinectEN16
if(!$group -or !$original -or !$bank){throw 'Expected Kinect controls, EN16 bank and Abysses dashboard.'}
if(@($p.dashboardManager.items|Where-Object niceName -eq 'Abysses Kinect').Count){throw 'Abysses Kinect already exists.'}

# Chataigne derives the inner CV container/parameter name from niceName. An
# arbitrary shortName on the CV item does not rename that inner container.
$baselinePath=Join-Path $PSScriptRoot '../../Chataigne/Oxipital Live Kinect.noisette'
$baseline=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $baselinePath))|ConvertFrom-Json
$baselineGroup=$baseline.customVariables.items|Where-Object niceName -eq Kinect
$replacements=@{}
foreach($v in $group.variables.items){
    $old=$v.shortName;if(!$old){$old=Key $v.niceName}
    $key=$v.parameters[0].controlAddress.TrimStart('/')
    $replacements[(CV $old)]=CV $key
    if($old -ne $key){
        $defaults=$baselineGroup.variables.items|Where-Object niceName -eq $v.niceName
        if(!$defaults){throw ('Missing defaults for '+$v.niceName)}
        $v.parameters=@((Copy-Node $defaults.parameters[0]))
        $v.parameters[0].controlAddress='/'+$key
    }
    Put $v 'shortName' $key
}
$json=$p|ConvertTo-Json -Depth 100 -Compress
foreach($oldAddress in $replacements.Keys){$json=$json.Replace(('"'+$oldAddress+'"'),('"'+$replacements[$oldAddress]+'"'))}
$p=$json|ConvertFrom-Json
$group=$p.customVariables.items|Where-Object niceName -eq Kinect
$original=$p.dashboardManager.items|Where-Object niceName -eq Abysses
$bank=$p.states.items|Where-Object shortName -eq kinectEN16
$presetState=$p.states.items|Where-Object {$_.niceName -in @('Preset','Presets')}
$leap=$p.customVariables.items|Where-Object niceName -eq 'Leap Motion'
foreach($preset in $group.presets.items){
    $containers=[pscustomobject]@{}
    foreach($v in $group.variables.items|Where-Object shortName -notin @('kinectEnabled','en16KinectBank')){
        $key=$v.shortName
        $saved=$preset.values.containers.PSObject.Properties[$key].Value
        if(!$saved -or !$saved.parameters){
            $base=$baselineGroup.variables.items|Where-Object niceName -eq $v.niceName
            $saved=[pscustomobject]@{niceName=$v.niceName;owned=$true;parameters=@((Param ('/'+$key) $base.parameters[0].value))}
        }
        Put $containers $key $saved
    }
    # Rebuild the flags lost by the old CV names from the matching Leap preset.
    $action=$presetState.processors.items|Where-Object{
        @($_.consequences.items|Where-Object{ @($_.command.parameters|Where-Object{ $_.controlAddress -eq '/targetPreset' -and $_.value -eq ('/kinect/presets/'+$preset.shortName)}).Count }).Count
    }
    $leapTarget=@($action.consequences.items|ForEach-Object{$_.command.parameters}|Where-Object{ $_.controlAddress -eq '/targetPreset' -and $_.value -is [string] -and $_.value.StartsWith('/leapMotion/presets/') })
    $names=@{forceOrb='Force & Orb';forceOnly='Force only';orbOnly='Orb only';off='Off'}
    if($leapTarget.Count -ne 1){throw 'Cannot resolve Leap preset for Kinect scene'}
    $leapPreset=$leap.presets.items|Where-Object niceName -eq $names[$leapTarget[0].value.Split('/')[-1]]
    foreach($key in @('sendForcesPosition','sendOrbsPosition')){
        $flag=$leapPreset.values.containers.PSObject.Properties[$key].Value
        $value=$false
        if($flag.parameters){$value=[bool]$flag.parameters[0].value}
        $containers.PSObject.Properties[$key].Value.parameters=@((Param ('/'+$key) $value))
    }
    $preset.values.containers=$containers
}

$rotaries=@('strength','radiusMultiplier','sizeMultiplier','orbRadiusMultiplier','orientationOffsetX','orientationOffsetY','orientationOffsetZ','smoothingSeconds','interactionDepth','maximumRadius','minimumRadius','activationFadeSeconds','forceGroupNumber','orbGroupNumber','unityBrushIndex','minimumAxisDistance')
$rotaryLabels=@('Intensite','Rayon force','Echelle force','Rayon orbe','Rotation X','Rotation Y','Rotation Z','Lissage','Profondeur','Rayon maximum','Rayon minimum','Fondu activation','Groupe force','Groupe orbe','Pinceau Unity','Distance axe')
$buttons=@('brushEnabled','sendForcesPosition','sendOrbsPosition','controlIntensityRadius','controlOrientation','controlOrbRadius','intensityFromHandDistance','invertGestureIntensity','useTargetDepth','showMonitor','showHandOverlay','kinectEnabled')
$buttonLabels=@('Pinceau actif','Position forces','Position orbes','Intensite / rayon','Orientation','Rayon orbe geste','Intensite geste','Inverser geste','Profondeur cible','Moniteur','Overlay mains','Kinect actif')
$mux=$bank.processors.items|Where-Object type -eq Multiplex
$targetList=$mux.containers.lists.items|Where-Object niceName -eq 'Target Kinect Parameters'
if(!$targetList){$targetList=$mux.containers.lists.items|Where-Object niceName -eq 'Target Force 1'}
for($i=0;$i -lt 16;$i++){$targetList.parameters[$i].value=CV $rotaries[$i]}
$physical=($mux.containers.lists.items|Where-Object niceName -eq 'EN16 Button Page 1').parameters.value
if($physical.Count -ne 16){throw 'Expected 16 physical push inputs.'}
$bankAddress=CV 'en16KinectBank'
# The live project may have saved the old unresolved bank condition as false.
# Rebuild it explicitly after resolving the canonical bank address.
foreach($mapping in $mux.containers.processors.items|Where-Object type -eq Mapping){
    foreach($filter in $mapping.filters.items|Where-Object niceName -eq 'Kinect Mode Gate'){
        $filter.conditions.items=@((Condition $bankAddress $true '='))
    }
}

# Gate every existing action that directly reads one of these push buttons,
# including nested Multiplex conditions; other controllers keep their routes.
$script:gated=0
function Gate-HardwareActions($nodes){
    foreach($node in $nodes){
    if($node.type -eq 'Action' -and $node.conditions){
        $text=$node.conditions|ConvertTo-Json -Depth 50 -Compress
        $readsPush=$text.Contains('From Multiplex List') -and $text.Contains('en16ButtonPage1')
        foreach($address in $physical){if($text.Contains($address)){$readsPush=$true}}
        if($readsPush){
            # The bank is an authorization gate, never an alternative trigger.
            # The legacy Launch Start action has one MIDI condition under OR.
            $operator=$node.conditions.parameters|Where-Object controlAddress -eq '/operator'
            if($operator.value -eq 'OR'){
                if(@($node.conditions.items).Count -ne 1){throw ('Cannot append a bank gate to a multi-input OR action: '+$node.niceName)}
                $operator.value='AND'
            }
            Put $node.conditions 'items' (@($node.conditions.items)+@((Condition $bankAddress $false)))
            $script:gated++
        }
    }
    if($node.processors.items){Gate-HardwareActions $node.processors.items}
    if($node.containers.processors.items){Gate-HardwareActions $node.containers.processors.items}
    if($node.states.items){Gate-HardwareActions $node.states.items}
    }
}
Gate-HardwareActions $p.states.items

# Clone dashboard appearance and camera preview, replacing the controls with
# two grids in physical EN16 list order: rotations left, pushes right.
$dashboard=Copy-Node $original
$dashboard.niceName='Abysses Kinect'
Put $dashboard 'shortName' 'abyssesKinect'
$rotaryTemplate=$original.itemManager.items|Where-Object{ @($_.parameters|Where-Object{ $_.controlAddress -eq '/style' -and $_.value -eq 'Rotary Slider' }).Count }|Select-Object -First 1
$toggleTemplate=$original.itemManager.items|Where-Object{ @($_.parameters|Where-Object{ $_.controlAddress -eq '/style' -and $_.value -eq 'Toggle Button' }).Count }|Select-Object -First 1
$triggerTemplate=$original.itemManager.items|Where-Object type -eq DashboardTriggerItem|Select-Object -First 1
function Widget($template,[string]$name,[string]$label,[string]$target,$position,$size){
    $item=Copy-Node $template
    $item.niceName=$name
    Put $item 'ghostAddress' $target
    Put $item 'controllable' $target
    $values=@{'/viewUIPosition'=$position;'/viewUISize'=$size;'/target'=$target;'/customText'=$label;'/textSize'=14;'/readOnly'=$false;'/showLabel'=$true}
    foreach($key in $values.Keys){
        $param=$item.parameters|Where-Object controlAddress -eq $key
        if(!$param){$param=Param $key $values[$key];$item.parameters+=@($param)}else{$param.value=$values[$key]}
        if($key -in @('/customText','/textSize')){Put $param 'enabled' $true}
    }
    return $item
}
$items=@()
for($i=0;$i -lt 16;$i++){
    $col=$i%4;$row=[math]::Floor($i/4)
    $items+=@(Widget $rotaryTemplate ('Rotary '+($i+1)) (($i+1).ToString()+' '+$rotaryLabels[$i]) (CV $rotaries[$i]) @((-460+130*$col),(-340+100*$row)) @(120,85))
}
$actions=@()
for($i=0;$i -lt 16;$i++){
    $col=$i%4;$row=[math]::Floor($i/4)
    $name='Push '+($i+1)
    if($i -lt $buttons.Count){
        $key=$buttons[$i];$target=CV $key
        # The existing Leap flags remain the authority for both position switches.
        if($key -in @('sendForcesPosition','sendOrbsPosition')){$target='/customVariables/leapMotion/variables/'+$key+'/'+$key}
        $items+=@(Widget $toggleTemplate $name (($i+1).ToString()+' '+$buttonLabels[$i]) $target @((150+130*$col),(-340+100*$row)) @(120,85))
        $command=[pscustomobject]@{niceName='Toggle';type='Consequence';commandModule='generic';commandPath='';commandType='Set Parameter Value';command=[pscustomobject]@{parameters=@((Param '/target' $target),(Param '/component' 'All'),(Param '/operator' 'Inverse'));paramLinks=[pscustomobject]@{}}}
    }else{
        $originalTargets=@('/states/initialisation/processors/syncData/trigger','/states/initialisation/processors/resetCameraPosition/trigger','/states/presets/processors/univers/trigger','/states/presets/processors/meduse/trigger')
        $labels=@('Sync Unity','Reset camera','Univers','Meduse')
        $target=$originalTargets[$i-12]
        $items+=@(Widget $triggerTemplate $name (($i+1).ToString()+' '+$labels[$i-12]) $target @((150+130*$col),(-340+100*$row)) @(120,85))
        $command=[pscustomobject]@{niceName='Trigger';type='Consequence';commandModule='generic';commandPath='';commandType='Trigger a Control';command=[pscustomobject]@{parameters=@((Param '/target' $target));paramLinks=[pscustomobject]@{}}}
    }
    $actions+=@([pscustomobject]@{niceName=$name;type='Action';editorIsCollapsed=$true;conditions=[pscustomobject]@{items=@((Condition $physical[$i] 0 '>'),(Condition $bankAddress $true))};consequences=[pscustomobject]@{items=@($command)};consequencesOff=[pscustomobject]@{items=@()}})
}
$bank.processors.items=@($bank.processors.items)+$actions
$items+=@(Widget $toggleTemplate 'Kinect Bank' 'Banque EN16 Kinect' $bankAddress @(-460,-450) @(240,70))
$items+=@(Widget $toggleTemplate 'Kinect Source' 'Controle Kinect actif' (CV 'kinectEnabled') @(-200,-450) @(240,70))
# Preview keeps the same target and native shared-texture settings.
$items+=@($original.itemManager.items|Where-Object type -eq 'Shared Texture'|ForEach-Object{Copy-Node $_})
$dashboard.itemManager.items=$items
$p.dashboardManager.items=@($p.dashboardManager.items)+@($dashboard)
[IO.File]::WriteAllText($outputFull,($p|ConvertTo-Json -Depth 100 -Compress),[Text.UTF8Encoding]::new($false))
"KINECT_DASHBOARD_CREATED: 16 rotaries, 16 pushes, bank selector, preview; $script:gated existing hardware actions gated."
