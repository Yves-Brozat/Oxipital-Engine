param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Assert($ok,$message){if(!$ok){throw $message}}
function Json($n){ConvertTo-Json -InputObject $n -Depth 100 -Compress}
function Value($n,$key){($n.parameters|Where-Object controlAddress -eq $key).value}
function Walk($nodes){foreach($n in $nodes){$n;if($n.processors.items){Walk $n.processors.items};if($n.containers.processors.items){Walk $n.containers.processors.items};if($n.states.items){Walk $n.states.items}}}
$before=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$after=Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8|ConvertFrom-Json
$targets=@(
    '/states/initialisation/processors/launchStart/trigger',
    '/states/conduite/processors/init/trigger',
    '/states/conduite/processors/previous/trigger',
    '/customVariables/kinect/variables/en16KinectBank/en16KinectBank',
    '/states/conduite/processors/conductor/processors/meduse/trigger',
    '/states/conduite/processors/conductor/processors/cascade/trigger',
    '/states/conduite/processors/conductor/processors/tornade/trigger',
    '/states/initialisation/processors/resetCameraPosition/trigger',
    '/states/conduite/processors/conductor/processors/chute/trigger',
    '/states/conduite/processors/conductor/processors/tourbillon/trigger',
    '/states/conduite/processors/conductor/processors/cercle/trigger',
    '/states/initialisation/processors/syncData/trigger',
    '/states/conduite/processors/next/trigger',
    '/states/effects/processors/switchInOutRadial/trigger',
    '/states/effects/processors/180Z/trigger',
    '/states/effects/processors/explosion/trigger'
)
$dashboard=$after.dashboardManager.items|Where-Object niceName -eq Abysses
$actions=@(Walk $after.states.items|Where-Object type -eq Action)
$occupied=@{}
foreach($slot in 1..16){
    $target=$targets[$slot-1]
    $widget=@($dashboard.itemManager.items|Where-Object shortName -eq "abyssesPush$slot")
    Assert ($widget.Count -eq 1) "Missing dashboard slot $slot"
    Assert ((Value $widget[0] '/target') -eq $target -and $widget[0].controllable -eq $target -and $widget[0].ghostAddress -eq $target) "Dashboard target $slot"
    $pos=Json (Value $widget[0] '/viewUIPosition')
    Assert (!$occupied.ContainsKey($pos)) 'Overlapping dashboard buttons';$occupied[$pos]=$true
    Assert ((Value $widget[0] '/customText') -like "$slot *") "Missing slot label $slot"
    $address="/customVariables/kinect/variables/en16AbyssesButton$slot/en16AbyssesButton$slot"
    $listeners=@($actions|Where-Object {@($_.conditions.items|Where-Object {(Value $_ '/inputValue') -eq $address}).Count})
    if($slot -eq 4){Assert ($listeners.Count -eq 0) 'Bank button must remain reserved';continue}
    Assert ($listeners.Count -eq 1) "Slot $slot has stale or duplicate hardware actions"
    $a=$listeners[0]
    Assert ($a.shortName -eq "en16Abysses$slot") "Slot $slot uses an obsolete action"
    Assert ($a.consequences.items.Count -eq 1 -and $a.consequences.items[0].commandType -eq 'Trigger a Control') "Unexpected command bundle for slot $slot"
    Assert ((Value $a.consequences.items[0].command '/target') -eq $target) "Hardware/dashboard disagree for slot $slot"
    Assert ((Value $a.conditions.items[0].comparator '/comparisonFunction') -eq '>' -and (Value $a.conditions.items[0].comparator '/reference') -eq 0) 'Release or cleared bank input could trigger an action'
}
$save=@($dashboard.itemManager.items|Where-Object {(Value $_ '/target') -eq '/states/savePresets/processors/saveNewPreset/trigger'})
Assert ($save.Count -eq 1 -and !$occupied.ContainsKey((Json (Value $save[0] '/viewUIPosition')))) 'Save must remain available outside the numbered grid'
foreach($a in $actions){if(($a.consequences.items|Json) -match '/states/savePresets/processors/saveNewPreset/trigger'){Assert (!(($a.conditions|Json) -match 'en16AbyssesButton')) 'Save is still affiliated with an EN16 button'}}
foreach($removed in @('/states/initialisation/processors/launchOxipital/trigger','/customVariables/leapMotion/variables/sendOrbsPosition/sendOrbsPosition','/states/presets/processors/monteeDesEaux/trigger')){Assert (@($dashboard.itemManager.items|Where-Object {(Value $_ '/target') -eq $removed}).Count -eq 0) 'Removed dashboard item remains'}
$conduite=$after.states.items|Where-Object niceName -eq Conduite
$previous=$conduite.processors.items|Where-Object shortName -eq previous
Assert ((Value $previous.consequences.items[0].command '/target') -eq '/states/conduite/processors/conductor/triggerPrevious') 'Previous must call the native conductor command'
foreach($section in @('customVariables','modules','sequences')){Assert ((Json $before.$section) -ceq (Json $after.$section)) "Changed $section"}
Assert ((Json @($before.dashboardManager.items|Where-Object niceName -ne Abysses)) -ceq (Json @($after.dashboardManager.items|Where-Object niceName -ne Abysses))) 'Other dashboards changed'
$oldConduite=$before.states.items|Where-Object niceName -eq Conduite
foreach($key in @('conductor','init','next')){Assert ((Json ($oldConduite.processors.items|Where-Object shortName -eq $key)) -ceq (Json ($conduite.processors.items|Where-Object shortName -eq $key))) "Existing Conduite control changed: $key"}
# Outside Conduite only complete, old Abysses button condition sets may change.
foreach($state in $before.states.items|Where-Object niceName -ne Conduite){
    foreach($action in @(Walk @($state)|Where-Object type -eq Action)){
        if(@($action.conditions.items|Where-Object {(Value $_ '/inputValue') -match '^/customVariables/kinect/variables/en16AbyssesButton\d+/'}).Count){$action.conditions.items=@()}
    }
}
Assert ((Json @($before.states.items|Where-Object niceName -ne Conduite)) -ceq (Json @($after.states.items|Where-Object niceName -ne Conduite))) 'Manual commands, Kinect isolation, LED logic or bank switch changed'
'ABYSSES_BUTTON_REMAP_PASS: 16 targets/positions, 15 unique hardware routes, reserved Bank, separate Save, native Previous, preserved presets/sequences/Kinect/LEDs.'
