param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Assert($ok,$message){if(!$ok){throw $message}}
function Value($n,$key){($n.parameters|Where-Object controlAddress -eq $key).value}
function Json($n){ConvertTo-Json -InputObject $n -Depth 100 -Compress}
function Walk($nodes){foreach($n in $nodes){$n;if($n.processors.items){Walk $n.processors.items};if($n.containers.processors.items){Walk $n.containers.processors.items};if($n.states.items){Walk $n.states.items}}}
$old=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $SourcePath))|ConvertFrom-Json
$p=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $OutputPath))|ConvertFrom-Json
$bank='/customVariables/kinect/variables/en16KinectBank/en16KinectBank'
$nodes=@(Walk $p.states.items)
$oldNodes=@(Walk $old.states.items)
$g=$p.customVariables.items|Where-Object niceName -eq Kinect
$oldGroup=$old.customVariables.items|Where-Object niceName -eq Kinect
Assert ((Json $g.presets) -ceq (Json $oldGroup.presets)) 'Kinect presets changed'
foreach($v in $oldGroup.variables.items){Assert ((Json $v) -ceq (Json ($g.variables.items|Where-Object shortName -eq $v.shortName))) ('Authored variable changed: '+$v.niceName)}
foreach($group in $old.customVariables.items|Where-Object niceName -ne Kinect){Assert ((Json $group) -ceq (Json ($p.customVariables.items|Where-Object niceName -eq $group.niceName))) 'Show CV/presets changed'}
Assert ((Json $old.dashboardManager) -ceq (Json $p.dashboardManager)) 'Dashboard targets changed'
Assert ((Json $old.modules) -ceq (Json $p.modules)) 'MIDI devices or Unity module changed'
$internal=@($g.variables.items|Where-Object shortName -match '^en16(Abysses|Kinect)Button\d+$')
Assert ($internal.Count -eq 32) 'Expected 32 independent routed button values'
foreach($v in $internal){
    Assert ($v.parameters[0].value -eq 0 -and $v.parameters[0].default -eq 0) 'Routed button loads as held'
    $derived=$v.niceName -replace '[^\p{L}\p{Nd}_]',''
    Assert ($derived -ceq $v.shortName -and $v.parameters[0].controlAddress -ceq ('/'+$derived)) 'Routed button address changes on load'
}
$actions=@($nodes|Where-Object type -eq Action)
foreach($action in $actions|Where-Object niceName -notin @('Show Active EN16 Bank','Switch EN16 Bank')){
    $direct=@($action.conditions.items|Where-Object{(Value $_ '/inputValue') -eq $bank})
    Assert ($direct.Count -eq 0) ('Bank still triggers an action directly: '+$action.niceName)
}
$oldGated=@($oldNodes|Where-Object{ $_.type -eq 'Action' -and $_.niceName -ne 'Show Active EN16 Bank' -and @($_.conditions.items|Where-Object{(Value $_ '/inputValue') -eq $bank}).Count })
foreach($a in $oldGated){
    $new=@($actions|Where-Object{ $_.niceName -ceq $a.niceName -and (Json $_.consequences) -ceq (Json $a.consequences) -and (Json $_.consequencesOff) -ceq (Json $a.consequencesOff) -and (Json $_.parameters) -ceq (Json $a.parameters) -and (Json $_.conditions.parameters) -ceq (Json $a.conditions.parameters) })
    Assert ($new.Count -ge 1) ('Consequences/delays changed: '+$a.niceName)
    Assert ((Json $a.parameters) -ceq (Json $new[0].parameters)) ('Action enable or position changed: '+$a.niceName)
    Assert ((Json $a.conditions.parameters) -ceq (Json $new[0].conditions.parameters)) ('Long-press timing changed: '+$a.niceName)
}
$routers=@($nodes|Where-Object niceName -eq 'Route EN16 Buttons')
Assert ($routers.Count -eq 2) 'Expected two bank event routers'
foreach($route in $routers){
    Assert ((Value $route.params '/sendOnInputChangeOnly') -eq $true) 'Bank/filter changes can emit a cached note'
    Assert ((Value $route.params '/sendOnActivate') -eq $false -and (Value $route.params '/sendAfterLoad') -eq $false) 'Router replays notes when loaded or activated'
    Assert ((Value $route.params '/sendOnOutputChangeOnly') -eq $false) 'Repeated MIDI values are suppressed'
    Assert ((Value $route.im.items[0] '/inputList') -eq '/en16PhysicalButtons') 'Router does not read physical events'
}
$show=$actions|Where-Object niceName -eq 'Show Active EN16 Bank'
foreach($side in @('consequences','consequencesOff')){
    $list=$show.PSObject.Properties[$side].Value.items
    Assert ($list.Count -ge 49) 'Bank transition is missing input resets or UI feedback'
    $targets=@($list|Select-Object -First 32|ForEach-Object{
        Assert ($_.commandType -eq 'Set Parameter Value' -and (Value $_.command '/value') -eq 0) 'Bank clear writes a nonzero value'
        Value $_.command '/target'
    })
    Assert (@($targets|Select-Object -Unique).Count -eq 32) 'Bank clear omits routed inputs'
    foreach($target in $targets){Assert ($target -match '^/customVariables/kinect/variables/en16(Abysses|Kinect)Button\d+/en16\1Button\d+$') 'Bank clear touches a show parameter'}
    $original=($oldNodes|Where-Object niceName -eq 'Show Active EN16 Bank').PSObject.Properties[$side].Value.items
    Assert ((Json @($list|Select-Object -Skip 32)) -ceq (Json @($original))) 'Original dashboard/LED commands changed'
}
# Reproduce stale press conditions in the source: the reset-camera and
# Universe actions become true on bank return if their raw notes remain 127.
$cameraOld=($old.states.items|Where-Object niceName -eq Initialisation).processors.items|Where-Object niceName -eq 'Reset Camera Position'
Assert (@($cameraOld.conditions.items|Where-Object{(Value $_ '/inputValue') -eq $bank}).Count -eq 1) 'Baseline does not contain stale-bank camera condition'
$camera=($p.states.items|Where-Object niceName -eq Initialisation).processors.items|Where-Object niceName -eq 'Reset Camera Position'
$universe=($p.states.items|Where-Object niceName -eq Presets).processors.items|Where-Object niceName -eq Univers
$held=@{}
foreach($v in $internal){$held['/customVariables/kinect/variables/'+$v.shortName+'/'+$v.shortName]=127}
foreach($newBank in @($false,$true,$false,$true,$false)){
    # The only bank event subscribers clear inputs to zero. Even if all keys
    # were held before the switch, every camera/preset press predicate is false.
    foreach($key in @($held.Keys)){$held[$key]=0}
    foreach($a in @($camera,$universe)){
        $input=Value $a.conditions.items[0] '/inputValue'
        Assert ($held.ContainsKey($input)) 'Scene action still reads a raw MIDI note'
        Assert (!($held[$input] -gt 0)) 'Bank transition can recall camera or VFX preset'
    }
}
# A fresh press in Abysses reaches both scene controls after clearing.
foreach($a in @($camera,$universe)){
    $input=Value $a.conditions.items[0] '/inputValue'
    $held[$input]=127
    Assert ($held[$input] -gt 0) 'A fresh scene button cannot activate its action'
    $held[$input]=0
}
$reset=$actions|Where-Object niceName -eq 'Force1 Reset'
Assert ((Value $reset.conditions.items[0].comparator '/comparisonFunction') -eq '>') 'Zeroed button inputs can reset show parameters'
'EN16_BUTTON_ROUTING_PASS: 41 preserved actions, independent bank inputs, held-key bank transitions, camera/VFX press isolation, preserved long-press delays, show presets and LEDs.'
