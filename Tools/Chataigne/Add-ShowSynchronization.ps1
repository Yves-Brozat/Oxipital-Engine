param(
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [Parameter(Mandatory=$true)][string]$ModuleScriptPath,
    [Parameter(Mandatory=$true)][string]$ModuleDefinitionPath,
    [Parameter(Mandatory=$true)][string]$PatchedScriptPath,
    [Parameter(Mandatory=$true)][string]$PatchedDefinitionPath
)
$ErrorActionPreference='Stop'
function Clone($n){$n|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json}
function Put($n,$k,$v){if($n.PSObject.Properties[$k]){$n.PSObject.Properties[$k].Value=$v}else{$n|Add-Member -NotePropertyName $k -NotePropertyValue $v}}
function Param($n,$k,$v){$x=$n.parameters|Where-Object controlAddress -eq $k;if($x){$x.value=$v}else{Put $n parameters (@($n.parameters)+@([pscustomobject]@{controlAddress=$k;value=$v}))}}
function Short($name){$s=$name -replace '[^a-zA-Z0-9_]','';$s.Substring(0,1).ToLowerInvariant()+$s.Substring(1)}
function SetCommand($target,$value){[pscustomobject]@{niceName='Set Value';type='Consequence';commandModule='generic';commandPath='';commandType='Set Parameter Value';command=[pscustomobject]@{parameters=@([pscustomobject]@{controlAddress='/target';value=$target},[pscustomobject]@{controlAddress='/component';value='All'},[pscustomobject]@{controlAddress='/operator';value='Equals'},[pscustomobject]@{controlAddress='/value';value=$value});paramLinks=[pscustomobject]@{}}}}
$p=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$before=Clone $p.customVariables
$setupRoot='/modules/oxipital/parameters/setup/'
$mode=$setupRoot+'unityEditMode'
$ox=$p.modules.items|Where-Object niceName -eq Oxipital
if($ox.params.containers.setup.parameters|Where-Object controlAddress -eq '/unityEditMode'){throw 'Show synchronization already installed.'}
foreach($pair in @(@('unityEditMode',$false),@('presetApplyDuration',0))){Param $ox.params.containers.setup ('/'+$pair[0]) $pair[1]}
$authoring=[pscustomobject]@{niceName='Unity -> Show Editing';shortName='unityAuthoring';type='State';parameters=@([pscustomobject]@{controlAddress='/active';value=$false});processors=[pscustomobject]@{items=@()}}
$destinations=@{}
function Add-Feedback($cv,$moduleTarget){
    if($destinations.ContainsKey($cv) -or $cv -notmatch '^/customVariables/(orb[12]|force[12])/'){return}
    if($moduleTarget -notmatch '^/modules/oxipital/parameters/(orbGroups|forceGroups)/(orbGroup|forceGroup)([12])/([^/]+)/([^/]+)/baseValue$'){return}
    $kind=$Matches[1];$number=$Matches[3];$section=$Matches[4];$field=$Matches[5]
    $manager=if($kind -eq 'orbGroups'){'Orb_Groups'}else{'Force_Groups'}
    $groupName=if($kind -eq 'orbGroups'){'Orb_Group_'+$number}else{'Force_Group_'+$number}
    $component=if($kind -eq 'orbGroups'){'OrbGroup'}else{'StandardForceGroup'}
    if($section -eq 'transform'){$component='Transform'}
    $pattern=@{linePatternWeight='LineDancePattern/weight';linePatternSpeedWeight='LineDancePattern/speedWeight';circlePatternWeight='CircleDancePattern/weight';circlePatternSpeedWeight='CircleDancePattern/speedWeight';manualPatternWeight='ManualDancePattern/weight'}
    if($pattern.ContainsKey($field)){$split=$pattern[$field].Split('/');$component=$split[0];$field=$split[1]}
    $node=$ox.treeData.CONTENTS.Ballet.CONTENTS.$manager.CONTENTS.$groupName.CONTENTS.$component.CONTENTS.PSObject.Properties[$field]
    if(!$node){Write-Output ('SKIPPED_FEEDBACK: '+$cv);return}
    $input='/modules/oxipital/values'+$node.Value.FULL_PATH
    $destinations[$cv]=$input
    $authoring.processors.items+=@([pscustomobject]@{
        niceName='Read '+$groupName+' '+$field;type='Mapping'
        im=[pscustomobject]@{items=@([pscustomobject]@{niceName='Input Value';type='Input Value';parameters=@([pscustomobject]@{controlAddress='/inputValue';value=$input})})}
        params=[pscustomobject]@{parameters=@([pscustomobject]@{controlAddress='/updateRate';value=5},[pscustomobject]@{controlAddress='/sendOnActivate';value=$true},[pscustomobject]@{controlAddress='/sendOnInputChangeOnly';value=$true})}
        outputs=[pscustomobject]@{items=@([pscustomobject]@{niceName='MappingOutput';type='BaseItem';commandModule='generic';commandPath='';commandType='Set Parameter Value';command=[pscustomobject]@{parameters=@([pscustomobject]@{controlAddress='/target';value=$cv},[pscustomobject]@{controlAddress='/component';value='All'},[pscustomobject]@{controlAddress='/operator';value='Equals'});paramLinks=[pscustomobject]@{value=[pscustomobject]@{linkType=1;mappingValueIndex=0}}}})}
    })
}
foreach($state in $p.states.items|Where-Object niceName -match '^CV (Orb|Force)'){
    foreach($mux in $state.processors.items|Where-Object type -eq Multiplex){
        $lists=$mux.containers.lists.items
        foreach($mapping in $mux.containers.processors.items){
            $output=$mapping.outputs.items[0]
            $targetList=$output.command.paramLinks.target.list
            if($targetList -notmatch 'Oxipital|oxipitalForce'){continue}
            $inputList=($mapping.im.items[0].parameters|Where-Object controlAddress -eq '/inputList').value.TrimStart('/')
            $sourceList=$lists|Where-Object {(Short $_.niceName) -eq $inputList -or $_.shortName -eq $inputList}
            if($inputList -eq 'questFinalValues'){
                $sourceList=$lists|Where-Object niceName -eq $(if($mux.niceName -eq 'Force P3D'){'Force 1 CV'}else{'Orb 1'})
            }
            $targets=$lists|Where-Object {(Short $_.niceName) -eq $targetList -or $_.shortName -eq $targetList}
            for($i=0;$i -lt $sourceList.parameters.Count;$i++){
                Add-Feedback $sourceList.parameters[$i].value $targets.parameters[$i].value
            }
        }
    }
    foreach($mapping in $state.processors.items|Where-Object type -eq Mapping){
        $input=($mapping.im.items[0].parameters|Where-Object controlAddress -eq '/inputValue').value
        $output=($mapping.outputs.items[0].command.parameters|Where-Object controlAddress -eq '/target').value
        Add-Feedback $input $output
    }
}
if($destinations.Count -lt 40){throw 'Too few live feedback routes resolved.'}
$p.states.items+=@($authoring)
$gate=[pscustomobject]@{niceName='Performance Mode';type='Condition';filterParams=[pscustomobject]@{paramLinks=[pscustomobject]@{}};conditions=[pscustomobject]@{items=@([pscustomobject]@{niceName='From Input Value';type='From Input Value';parameters=@([pscustomobject]@{controlAddress='/inputValue';value=$mode});comparator=[pscustomobject]@{parameters=@([pscustomobject]@{controlAddress='/reference';value=$false})}})}}
$kinect=$p.states.items|Where-Object shortName -eq kinectToUnity
foreach($mapping in $kinect.processors.items|Where-Object type -eq Mapping){if(!$mapping.filters){Put $mapping filters ([pscustomobject]@{items=@()})};Put $mapping.filters items (@($mapping.filters.items)+@((Clone $gate)))}
$bank=$p.states.items|Where-Object shortName -eq kinectEN16
$bank.processors.items+=@([pscustomobject]@{niceName='Unity Editing Mode';shortName='unityEditingMode';type='Action';conditions=[pscustomobject]@{items=@([pscustomobject]@{niceName='From Input Value';type='From Input Value';parameters=@([pscustomobject]@{controlAddress='/inputValue';value=$mode});comparator=[pscustomobject]@{parameters=@([pscustomobject]@{controlAddress='/reference';value=$true})}})};consequences=[pscustomobject]@{items=@((SetCommand '/states/unityAuthoring/active' $true),(SetCommand '/modules/oxipital/values/Ballet/Optical_Flow/TwoHandForceBrush/remoteControlEnabled' $false))};consequencesOff=[pscustomobject]@{items=@((SetCommand '/states/unityAuthoring/active' $false))}})
foreach($action in ($p.states.items|Where-Object niceName -eq Presets).processors.items){
    $recalls=@($action.consequences.items|Where-Object {$_.commandType -eq 'Go to preset' -and ($_.command.parameters|Where-Object controlAddress -eq '/targetPreset').value -match '^/(orb|force)'})
    if(!$recalls.Count){continue}
    $duration=0
    foreach($c in $recalls){$v=($c.command.parameters|Where-Object controlAddress -eq '/interpolationTime').value;if($v -gt $duration){$duration=$v}}
    $action.consequences.items+=@((SetCommand ($setupRoot+'presetApplyDuration') $duration),[pscustomobject]@{niceName='Reapply Show Values';type='Consequence';commandModule='generic';commandPath='';commandType='Trigger a Control';command=[pscustomobject]@{parameters=@([pscustomobject]@{controlAddress='/target';value=($setupRoot+'applyCurrentValues')});paramLinks=[pscustomobject]@{}}})
}
$dash=$p.dashboardManager.items|Where-Object niceName -eq 'Abysses Kinect'
$dash.itemManager.items+=@([pscustomobject]@{niceName='Unity Editing Mode';shortName='unityEditingMode';type='DashboardParameterItem';hideInEditor=$true;ghostAddress=$mode;controllable=$mode;parameters=@([pscustomobject]@{controlAddress='/viewUIPosition';value=@(700,60)},[pscustomobject]@{controlAddress='/viewUISize';value=@(190,70)},[pscustomobject]@{controlAddress='/target';value=$mode},[pscustomobject]@{controlAddress='/customText';value='Edition Unity';enabled=$true},[pscustomobject]@{controlAddress='/style';value='Toggle Button'})})
if(($p.customVariables|ConvertTo-Json -Depth 100 -Compress) -cne ($before|ConvertTo-Json -Depth 100 -Compress)){throw 'Existing variables/presets changed.'}
$script=Get-Content -LiteralPath $ModuleScriptPath -Raw
if($script.Contains('function processPresetPushes(')){throw 'Bridge already patched.'}
$helpers=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'ShowSync-Bridge.js') -Raw
foreach($name in @('updateUnityParam','pushAllToUnity')){
    $pattern='(?m)^function '+$name+'\([^\r\n]*\)\s*\{[\s\S]*?^\}'
    if([regex]::Matches($script,$pattern).Count -ne 1){throw ('Expected one bridge function '+$name)}
    $script=[regex]::Replace($script,$pattern,'')
}
$script=[regex]::Replace($script,'(?m)^(function update\(deltaTime\)\s*\{)','$1'+"`r`n`tprocessPresetPushes();",1)
$script=[regex]::Replace($script,'(?m)^(function moduleParameterChanged\(param\)\s*\{)','$1'+"`r`n`tif (handleShowSyncControl(param)) return;",1)
$script=$script.Replace('function updateParam(index, groupName, paramName, sourceParam, parameters, items)', 'function updateParam(index, groupName, paramName, sourceParam, parameters, items, forceSend)')
$script=$script.Replace('function pushAllParameters(items, parameters)', 'function pushAllParameters(items, parameters, forceSend)')
$script=$script.Replace('updateParam(i, itemGroup.niceName, itemParams[k].niceName, null, parameters, items);', 'updateParam(i, itemGroup.niceName, itemParams[k].niceName, null, parameters, items, forceSend);')
$script=$script.Replace('updateUnityParam(managerName, item.niceName, paramPath, finalValue);', 'updateUnityParam(managerName, item.niceName, paramPath, finalValue, forceSend);')
$script='var presetPushAt = -1, presetFinalAt = -1;' + "`r`n"+$script+"`r`n"+$helpers
$definition=Get-Content -LiteralPath $ModuleDefinitionPath -Raw|ConvertFrom-Json
foreach($spec in @(@('Unity Edit Mode','Boolean',$false),@('Apply Current Values','Trigger',$null),@('Preset Apply Duration','Float',0))){
    $node=[pscustomobject]@{type=$spec[1]}
    if($spec[1] -ne 'Trigger'){Put $node default $spec[2]}
    Put $definition.parameters.Setup $spec[0] $node
}
foreach($pair in @(@($OutputPath,($p|ConvertTo-Json -Depth 100 -Compress)),@($PatchedScriptPath,$script),@($PatchedDefinitionPath,($definition|ConvertTo-Json -Depth 100)))){
    $path=[IO.Path]::GetFullPath($pair[0]);[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))|Out-Null;[IO.File]::WriteAllText($path,$pair[1],[Text.UTF8Encoding]::new($false))
}
'SHOW_SYNC_READY: '+$destinations.Count+' live reverse routes at 5 Hz in editing state only; explicit preset resend; authored presets preserved.'
